import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:dio/dio.dart';

/// Whisper STT 服务
/// - 可配置 whisper 服务器地址
/// - 支持语音活动检测（3秒静音触发识别）
/// - OpenAI 兼容 API 接口
class WhisperSttService {
  Dio? _dio;
  String _whisperUrl = '';
  String? _apiKey;
  String _model = 'large-v3-turbo-q5_0';

  bool _isInitialized = false;
  bool _isListening = false;

  // 音频录制
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  String? _tempPath;

  // 语音活动检测
  Timer? _activityTimer;
  Timer? _silenceTimer;
  StreamSubscription? _recorderSubscription;
  static const Duration _silenceThreshold = Duration(seconds: 3);
  static const Duration _activityCheckInterval = Duration(milliseconds: 200);

  final _resultController = StreamController<String>.broadcast();
  Stream<String> get onResult => _resultController.stream;

  final _statusController = StreamController<bool>.broadcast();
  Stream<bool> get onStatus => _statusController.stream;

  final _listeningController = StreamController<bool>.broadcast();
  Stream<bool> get onListening => _listeningController.stream;

  bool get isAvailable => _isInitialized;
  bool get isListening => _isListening;
  bool get isUrlConfigured => _whisperUrl.isNotEmpty;

  /// 初始化
  Future<bool> init() async {
    if (_isInitialized) return true;

    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 60),
    ));

    await _recorder.openRecorder();

    _isInitialized = true;
    debugPrint('WhisperSttService: 初始化成功');
    return true;
  }

  /// 设置 whisper 服务器地址
  void setWhisperUrl(String url) {
    _whisperUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    debugPrint('WhisperSttService: whisper URL 设置为 $_whisperUrl');
  }

  /// 设置 API Key（可选，用于 HTTP Basic Auth）
  void setApiKey(String key) {
    _apiKey = key;
  }

  /// 设置 Whisper 模型
  void setModel(String model) {
    _model = model;
  }

  /// 开始语音活动监听
  /// 检测到 3 秒静音后自动停止并识别
  Future<void> startListening() async {
    if (!_isInitialized) {
      final ok = await init();
      if (!ok) throw Exception('WhisperSttService 初始化失败');
    }

    if (_isListening) return;
    _isListening = true;
    _statusController.add(true);
    _listeningController.add(true);

    try {
      final dir = await getApplicationDocumentsDirectory();
      _tempPath = '${dir.path}/voice_input.wav';

      // 确保文件不存在
      final file = File(_tempPath!);
      if (await file.exists()) await file.delete();

      await _recorder.startRecorder(
        toFile: _tempPath!,
        codec: Codec.pcm16,
        sampleRate: 16000,
        numChannels: 1,
      );

      debugPrint('WhisperSttService: 开始录音 + 语音活动检测');

      // 设置音量回调
      await _recorder.setSubscriptionDuration(_activityCheckInterval);
      _recorderSubscription?.cancel();
      _recorderSubscription = _recorder.onProgress?.listen((e) {
        if (e.decibels != null) {
          _onDecibelSample(e.decibels!);
        }
      });

      // 兜底：最长录音 30 秒
      Future.delayed(const Duration(seconds: 30), () {
        if (_isListening) {
          debugPrint('WhisperSttService: 超时 30 秒，触发识别');
          _triggerRecognition();
        }
      });
    } catch (e) {
      debugPrint('WhisperSttService: 启动监听失败 $e');
      _isListening = false;
      _statusController.add(false);
      _listeningController.add(false);
    }
  }

  void _onDecibelSample(double dbLevel) {
    // dbLevel > -45 表示有声音活动
    if (dbLevel > -45.0) {
      _silenceTimer?.cancel();
      _silenceTimer = Timer(_silenceThreshold, () {
        if (_isListening) {
          debugPrint('WhisperSttService: 检测到 3 秒静音，触发识别');
          _triggerRecognition();
        }
      });
    }
  }

  /// 触发识别（停止录音 + 发送 API）
  Future<void> _triggerRecognition() async {
    _recorderSubscription?.cancel();
    _silenceTimer?.cancel();
    _isListening = false;
    _listeningController.add(false);

    await _recorder.stopRecorder();

    if (_tempPath != null) {
      final file = File(_tempPath!);
      final size = await file.length();
      debugPrint('WhisperSttService: 录音文件大小 $size bytes，准备上传');

      if (await file.exists() && size > 100) {
        try {
          final text = await _transcribe(_tempPath!);
          if (text.isNotEmpty) {
            debugPrint('WhisperSttService: 识别结果 "$text"');
            _resultController.add(text);
          }
        } catch (e) {
          debugPrint('WhisperSttService: 识别失败 $e');
        }
      } else {
        debugPrint('WhisperSttService: 录音文件无效或太短 ($size bytes)');
      }
    }

    _statusController.add(false);
  }

  /// 仅识别已有音频文件
  Future<String> transcribe(String audioPath) async {
    return _transcribe(audioPath);
  }

  Future<String> _transcribe(String audioPath) async {
    if (_whisperUrl.isEmpty) {
      debugPrint('WhisperSttService: 未配置 whisper URL');
      return '';
    }

    try {
      final file = File(audioPath);
      if (!await file.exists()) {
        debugPrint('WhisperSttService: 音频文件不存在');
        return '';
      }

      final uploadSize = await file.length();
      debugPrint('WhisperSttService: 上传文件 $uploadSize bytes → $_whisperUrl/v1/audio/transcriptions');

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(audioPath, filename: 'voice.wav'),
        'language': 'zh',
      });

      final headers = <String, dynamic>{};
      if (_apiKey != null && _apiKey!.isNotEmpty) {
        headers['Authorization'] = 'Bearer $_apiKey';
      }

      final response = await _dio!.post(
        '$_whisperUrl/v1/audio/transcriptions',
        data: formData,
        options: Options(headers: headers),
      );

      if (response.statusCode == 200 && response.data != null) {
        return response.data['text']?.toString().trim() ?? '';
      }
      return '';
    } catch (e) {
      debugPrint('WhisperSttService: STT 请求失败 $e');
      return '';
    }
  }

  /// 停止监听
  Future<void> stop() async {
    if (!_isListening) return;
    _activityTimer?.cancel();
    _silenceTimer?.cancel();
    _isListening = false;
    _listeningController.add(false);
    _statusController.add(false);
    await _recorder.stopRecorder();
    debugPrint('WhisperSttService: 停止监听');
  }

  /// 取消监听（不触发识别）
  Future<void> cancel() async {
    if (!_isListening) return;
    _activityTimer?.cancel();
    _silenceTimer?.cancel();
    _isListening = false;
    _listeningController.add(false);
    _statusController.add(false);
    await _recorder.stopRecorder();
    debugPrint('WhisperSttService: 取消监听');
  }

  Future<void> dispose() async {
    _activityTimer?.cancel();
    _silenceTimer?.cancel();
    _recorderSubscription?.cancel();
    await _recorder.closeRecorder();
    _resultController.close();
    _statusController.close();
    _listeningController.close();
    _dio?.close();
  }
}
