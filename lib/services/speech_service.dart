import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:audio_session/audio_session.dart';
import 'settings_service.dart';
import 'whisper_stt_service.dart';

/// 语音识别服务
///
/// 支持两种模式:
/// 1. 流式模式（推荐）：使用 WhisperSttService 的 WebSocket 流式接口
///    - VAD 在服务器端进行（Silero VAD）
///    - partial 和 final 结果通过 stream 回调返回
/// 2. 旧模式（兼容）：文件录制 + HTTP API
///    - 客户端 VAD（基于分贝检测）
class SpeechService {
  WhisperSttService? _whisperSttService;
  SettingsService? _settingsService;
  bool _isInitialized = false;
  bool _isListening = false;

  FlutterSoundRecorder? _recorder;
  AudioSession? _audioSession;

  // ========== 旧模式（兼容）相关 ==========
  String? _tempPath;
  // 录音状态机
  static const double _speechThreshold = 15.0;
  static const double _silenceThreshold = 0.0;
  static const int _recordDurationAfterSpeech = 5;
  static const int _maxRecordDuration = 60;

  Timer? _silenceTimer;
  Timer? _maxRecordTimer;
  StreamSubscription? _recorderSubscription;
  static const Duration _silenceCheckInterval = Duration(milliseconds: 200);

  bool _isSpeechDetected = false;
  int _silenceSeconds = 0;

  // 流式模式下的 PCM stream 控制器
  StreamController<Uint8List>? _pcmStreamController;

  final _resultController = StreamController<String>.broadcast();
  Stream<String> get onResult => _resultController.stream;

  /// Partial 结果流（转写中，实时显示）
  final _partialController = StreamController<String>.broadcast();
  Stream<String> get onPartial => _partialController.stream;

  final _statusController = StreamController<bool>.broadcast();
  Stream<bool> get onStatus => _statusController.stream;

  final _decibelController = StreamController<double>.broadcast();
  Stream<double> get onDecibel => _decibelController.stream;

  bool get isAvailable => _isInitialized;
  bool get isListening => _isListening;

  void setWhisperSttService(WhisperSttService service) {
    _whisperSttService = service;

    // 转发 WhisperSttService 的 partial 结果
    service.onPartial.listen((text) {
      if (text.isNotEmpty) {
        _partialController.add(text);
      }
    });

    // 转发 WhisperSttService 的 final 结果
    service.onResult.listen((text) {
      if (text.isNotEmpty) {
        _resultController.add(text);
      }
    });
  }

  void setSettingsService(SettingsService settingsService) {
    _settingsService = settingsService;
  }

  Future<bool> init() async {
    if (_isInitialized) return true;
    _recorder ??= FlutterSoundRecorder();
    _isInitialized = true;
    debugPrint('SpeechService: 初始化成功');
    return true;
  }

  /// 开始聆听
  /// 自动选择模式:
  /// - WhisperSttService 支持流式 → 使用流式模式
  /// - 否则使用旧文件模式（向后兼容）
  Future<void> startListening() async {
    if (!_isInitialized) {
      final ok = await init();
      if (!ok) throw SpeechException('语音识别初始化失败');
    }

    if (_isListening) return;

    // 优先使用流式模式
    if (_whisperSttService != null && _whisperSttService!.isUrlConfigured) {
      await _startStreamingMode();
      return;
    }

    // 降级到旧文件模式
    debugPrint('SpeechService: 流式模式不可用，降级到文件模式');
    await _startLegacyMode();
  }

  /// 流式模式：WebSocket 实时流
  Future<void> _startStreamingMode() async {
    _isListening = true;
    _isSpeechDetected = false;
    _silenceSeconds = 0;
    _statusController.add(true);

    try {
      // 配置音频会话
      _audioSession ??= await AudioSession.instance;
      await _audioSession!.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.defaultToSpeaker |
                AVAudioSessionCategoryOptions.allowBluetooth,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ));

      await _audioSession!.setActive(true);
      await _recorder!.openRecorder();

      // PCM 流控制器
      _pcmStreamController = StreamController<Uint8List>();

      // 监听 PCM → 发送给 WhisperSttService
      _pcmStreamController!.stream.listen((pcmData) {
        // WhisperSttService 在流模式下内部处理 WebSocket 发送
        // 这里 PCM 已经在 WhisperSttService.startListening() 里发了
      });

      // 开始录音：16kHz, 16-bit, mono PCM
      await _recorder!.startRecorder(
        toStream: _pcmStreamController!.sink,
        codec: Codec.pcm16,
        sampleRate: 16000,
        numChannels: 1,
      );

      // WhisperSttService 连接并开始流式识别
      final wsConnected = await _whisperSttService!.connect();
      if (!wsConnected) {
        throw SpeechException('WebSocket 连接失败');
      }
      await _whisperSttService!.startListening();

      debugPrint('SpeechService: 流式模式启动成功');

      // 兜底：最长录音超时
      _maxRecordTimer?.cancel();
      _maxRecordTimer = Timer(const Duration(seconds: _maxRecordDuration), () {
        if (_isListening) {
          debugPrint('SpeechService: 流式模式超时，停止');
          stop();
        }
      });

    } catch (e) {
      debugPrint('SpeechService: 流式模式启动失败 $e');
      _isListening = false;
      _statusController.add(false);
      await _cleanupRecorder();
    }
  }

  /// 旧文件模式：录制到文件后上传（兼容）
  Future<void> _startLegacyMode() async {
    _isListening = true;
    _isSpeechDetected = false;
    _silenceSeconds = 0;
    _statusController.add(true);

    try {
      final dir = await getTemporaryDirectory();
      _tempPath = '${dir.path}/voice_input.aac';

      final file = File(_tempPath!);
      if (await file.exists()) await file.delete();

      await _recorder!.openRecorder();
      await _recorder!.startRecorder(
        toFile: _tempPath!,
        codec: Codec.aacADTS,
        sampleRate: 44100,
        numChannels: 1,
        bitRate: 128000,
      );

      debugPrint('SpeechService: 录音开始（文件模式）');

      await _recorder!.setSubscriptionDuration(_silenceCheckInterval);
      _recorderSubscription?.cancel();
      _recorderSubscription = _recorder!.onProgress?.listen((e) {
        if (e.decibels != null) {
          _onDecibelSample(e.decibels!);
          _decibelController.add(e.decibels!);
        }
      });

      _maxRecordTimer?.cancel();
      _maxRecordTimer = Timer(const Duration(seconds: _maxRecordDuration), () {
        if (_isListening) {
          debugPrint('SpeechService: 达到最大录音时长 ${_maxRecordDuration}s，强制触发');
          _triggerRecognition();
        }
      });
    } catch (e) {
      debugPrint('SpeechService: 录音启动失败 $e');
      _isListening = false;
      _statusController.add(false);
    }
  }

  void _onDecibelSample(double dbLevel) {
    debugPrint('SpeechService: dBFS=$dbLevel');

    if (dbLevel > _speechThreshold) {
      _isSpeechDetected = true;
      _silenceSeconds = 0;
      _silenceTimer?.cancel();
    } else if (dbLevel < _silenceThreshold) {
      _silenceSeconds++;
      debugPrint('SpeechService: 静音累积 ${_silenceSeconds * 0.2}s');

      if (_isSpeechDetected && _silenceSeconds * 0.2 >= _recordDurationAfterSpeech) {
        debugPrint('SpeechService: 说话后 ${_recordDurationAfterSpeech}s 静音，触发识别');
        _triggerRecognition();
      }
    } else {
      _silenceTimer?.cancel();
    }
  }

  /// 触发识别（旧文件模式专用）
  Future<void> _triggerRecognition() async {
    debugPrint('SpeechService: _triggerRecognition() 开始');
    _recorderSubscription?.cancel();
    _silenceTimer?.cancel();
    _maxRecordTimer?.cancel();
    _isListening = false;
    _statusController.add(false);

    await _recorder!.stopRecorder();
    debugPrint('SpeechService: 录音已停止，准备识别');

    if (!_isSpeechDetected) {
      debugPrint('SpeechService: 未检测到说话，等待手动触发');
      try {
        final file = File(_tempPath!);
        if (await file.exists()) await file.delete();
      } catch (_) {}
      return;
    }

    if (_whisperSttService == null || !_whisperSttService!.isUrlConfigured) {
      debugPrint('SpeechService: Whisper URL 未配置');
      _isSpeechDetected = false;
      return;
    }

    if (_tempPath != null) {
      final file = File(_tempPath!);
      final size = await file.length();
      debugPrint('SpeechService: 录音文件大小 $size bytes');

      if (await file.exists() && size > 100) {
        try {
          // 尝试流式上传（如果 WhisperSttService 支持）
          final text = await _whisperSttService!.transcribe(_tempPath!);
          debugPrint('SpeechService: Whisper 返回 "$text"');
          if (text.isNotEmpty) {
            _resultController.add(text);
          }
        } catch (e) {
          debugPrint('SpeechService: 识别失败 $e');
        }
      }

      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }

    _isSpeechDetected = false;
  }

  /// 停止聆听
  Future<void> stop() async {
    if (!_isListening) return;

    _recorderSubscription?.cancel();
    _silenceTimer?.cancel();
    _maxRecordTimer?.cancel();
    _isListening = false;
    _statusController.add(false);

    // 流式模式：发送 stop 命令
    if (_pcmStreamController != null) {
      await _whisperSttService?.stop();
    }

    await _cleanupRecorder();
    debugPrint('SpeechService: 停止聆听');
  }

  /// 取消聆听
  Future<void> cancel() async {
    if (!_isListening) return;

    _recorderSubscription?.cancel();
    _silenceTimer?.cancel();
    _maxRecordTimer?.cancel();
    _isListening = false;
    _statusController.add(false);

    if (_pcmStreamController != null) {
      await _whisperSttService?.cancel();
    }

    await _cleanupRecorder();
    debugPrint('SpeechService: 取消聆听');
  }

  Future<void> _cleanupRecorder() async {
    try {
      await _recorder?.stopRecorder();
    } catch (_) {}
    try {
      await _recorder?.closeRecorder();
    } catch (_) {}
    try {
      await _audioSession?.setActive(false);
    } catch (_) {}

    _pcmStreamController?.close();
    _pcmStreamController = null;
  }

  Future<void> dispose() async {
    await cancel();
    _resultController.close();
    _partialController.close();
    _statusController.close();
    _decibelController.close();
    debugPrint('SpeechService: 已释放');
  }
}

class SpeechException implements Exception {
  final String message;
  SpeechException(this.message);

  @override
  String toString() => message;
}
