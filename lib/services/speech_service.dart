import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'settings_service.dart';
import 'whisper_stt_service.dart';

/// 语音识别服务 - 录音模式
/// - 检测到声音后固定录音 N 秒
/// - 然后发送识别
/// - 无声音活动时静默等待
class SpeechService {
  WhisperSttService? _whisperSttService;
  SettingsService? _settingsService;
  bool _isInitialized = false;
  bool _isListening = false;
  String? _tempPath;

  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();

  // 录音状态机
  static const double _speechThreshold = 25.0; // 高于此值=说话中
  static const double _silenceThreshold = 10.0; // 低于此值=安静
  static const int _recordDurationAfterSpeech = 5; // 检测到说话后继续录多少秒
  static const int _maxRecordDuration = 60; // 最长录音秒数

  Timer? _silenceTimer;
  Timer? _maxRecordTimer;
  StreamSubscription? _recorderSubscription;
  static const Duration _silenceCheckInterval = Duration(milliseconds: 200);

  bool _isSpeechDetected = false; // 本次录音是否检测到说话
  int _silenceSeconds = 0; // 连续静音秒数

  final _resultController = StreamController<String>.broadcast();
  Stream<String> get onResult => _resultController.stream;

  final _statusController = StreamController<bool>.broadcast();
  Stream<bool> get onStatus => _statusController.stream;

  final _decibelController = StreamController<double>.broadcast();
  Stream<double> get onDecibel => _decibelController.stream;

  bool get isAvailable => _isInitialized;
  bool get isListening => _isListening;

  void setWhisperSttService(WhisperSttService service) {
    _whisperSttService = service;
  }

  void setSettingsService(SettingsService settingsService) {
    _settingsService = settingsService;
  }

  Future<bool> init() async {
    if (_isInitialized) return true;
    await _recorder.openRecorder();
    _isInitialized = true;
    debugPrint('SpeechService: 初始化成功');
    return true;
  }

  /// 开始聆听
  Future<void> startListening() async {
    if (!_isInitialized) {
      final ok = await init();
      if (!ok) throw SpeechException('语音识别初始化失败');
    }

    if (_isListening) return;
    _isListening = true;
    _isSpeechDetected = false;
    _silenceSeconds = 0;
    _statusController.add(true);

    try {
      final dir = await getTemporaryDirectory();
      _tempPath = '${dir.path}/voice_input.aac';

      final file = File(_tempPath!);
      if (await file.exists()) await file.delete();

      await _recorder.startRecorder(
        toFile: _tempPath!,
        codec: Codec.aacADTS,
        sampleRate: 44100,
        numChannels: 1,
        bitRate: 128000,
      );

      debugPrint('SpeechService: 录音开始');

      await _recorder.setSubscriptionDuration(_silenceCheckInterval);
      _recorderSubscription?.cancel();
      _recorderSubscription = _recorder.onProgress?.listen((e) {
        if (e.decibels != null) {
          _onDecibelSample(e.decibels!);
          _decibelController.add(e.decibels!);
        }
      });

      // 最长录音超时
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
      // 说话中
      _isSpeechDetected = true;
      _silenceSeconds = 0;
      _silenceTimer?.cancel();
    } else if (dbLevel < _silenceThreshold) {
      // 安静，累积静音秒数
      _silenceSeconds++;
      debugPrint('SpeechService: 静音累积 ${_silenceSeconds * 0.2}s');

      // 检测到说话后，等待 5 秒静音才触发
      if (_isSpeechDetected && _silenceSeconds * 0.2 >= _recordDurationAfterSpeech) {
        debugPrint('SpeechService: 说话后 ${_recordDurationAfterSpeech}s 静音，触发识别');
        _triggerRecognition();
      }
    } else {
      // 中间地带，重置静音计数但不离谱
      _silenceSeconds = 0;
    }
  }

  Future<void> _triggerRecognition() async {
    _recorderSubscription?.cancel();
    _silenceTimer?.cancel();
    _maxRecordTimer?.cancel();
    _isListening = false;
    _statusController.add(false);

    await _recorder.stopRecorder();

    // 没有检测到说话则跳过识别，静默等待用户手动触发
    if (!_isSpeechDetected) {
      debugPrint('SpeechService: 未检测到说话，等待手动触发');
      try {
        final file = File(_tempPath!);
        if (await file.exists()) await file.delete();
      } catch (_) {}
      return;
    }

    // 检查 Whisper URL
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
          final text = await _whisperSttService!.transcribe(_tempPath!);
          if (text.isNotEmpty) {
            debugPrint('SpeechService: 识别结果 "$text"');
            _resultController.add(text);
          } else {
            debugPrint('SpeechService: Whisper 识别结果为空');
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
    // 完成后不自动重启，等待用户手动触发
  }

  void _startListeningQuiet() {
    Future.delayed(const Duration(milliseconds: 300), () {
      startListening();
    });
  }

  Future<void> stop() async {
    if (!_isListening) return;
    _recorderSubscription?.cancel();
    _silenceTimer?.cancel();
    _maxRecordTimer?.cancel();
    _isListening = false;
    _statusController.add(false);
    await _recorder.stopRecorder();
    debugPrint('SpeechService: 停止聆听');
  }

  Future<void> dispose() async {
    await stop();
    _recorderSubscription?.cancel();
    _maxRecordTimer?.cancel();
    await _recorder.closeRecorder();
    _resultController.close();
    _statusController.close();
    _decibelController.close();
  }
}

class SpeechException implements Exception {
  final String message;
  SpeechException(this.message);

  @override
  String toString() => message;
}
