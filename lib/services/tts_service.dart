import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import '../config/app_config.dart';
import 'settings_service.dart';

/// TTS 服务 - 使用 Minimax T2A API
class TtsService {
  AudioPlayer? _player;
  Dio? _dio;
  SettingsService? _settingsService;
  bool _isInitialized = false;
  bool _isSpeaking = false;

  bool get isSpeaking => _isSpeaking;

  /// 注入 SettingsService 以获取 API Key
  void setSettingsService(SettingsService settingsService) {
    _settingsService = settingsService;
  }

  /// 初始化
  Future<void> init() async {
    if (_isInitialized) return;

    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ));

    _player = AudioPlayer();
    _player!.onPlayerComplete.listen((_) {
      _isSpeaking = false;
    });

    _isInitialized = true;
  }

  /// 播放语音
  Future<void> speak(String text) async {
    if (!_isInitialized) {
      await init();
    }

    final apiKey = _settingsService?.minimaxApiKey ?? '';
    if (apiKey.isEmpty) {
      throw TtsException('未配置 MiniMax API Key，请在设置中填写');
    }

    // 停止当前播放
    if (_isSpeaking) {
      await stop();
    }

    _isSpeaking = true;

    try {
      final voiceId = _settingsService?.ttsVoiceId ?? AppConfig.ttsDefaultVoiceId;
      final speed = _settingsService?.ttsSpeed ?? AppConfig.ttsDefaultSpeed;

      // 调用 Minimax T2A API
      final response = await _dio!.post(
        '${AppConfig.ttsBaseUrl}/v1/t2a_v2',
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'model': AppConfig.ttsModel,
          'text': text,
          'stream': false,
          'voice_setting': {
            'voice_id': voiceId,
            'speed': speed,
            'vol': AppConfig.ttsDefaultVol,
            'pitch': AppConfig.ttsDefaultPitch,
          },
          'audio_setting': {
            'sample_rate': AppConfig.ttsSampleRate,
            'bitrate': AppConfig.ttsBitrate,
            'format': AppConfig.ttsFormat,
            'channel': 1,
          },
        },
      );

      final data = response.data;
      if (data == null || data['data'] == null) {
        throw TtsException('TTS 响应格式错误');
      }

      final status = data['data']['status'];
      if (status != 2) {
        throw TtsException('TTS 生成失败: status=$status');
      }

      // 解码 hex 音频并播放
      final hexAudio = data['data']['audio'] as String;
      final audioBytes = _hexToBytes(hexAudio);

      await _player!.setSourceBytes(audioBytes);
      await _player!.resume();

    } catch (e) {
      _isSpeaking = false;
      if (e is TtsException) rethrow;
      throw TtsException('TTS 请求失败: $e');
    }
  }

  Uint8List _hexToBytes(String hex) {
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(result);
  }

  /// 停止播放
  Future<void> stop() async {
    await _player?.stop();
    _isSpeaking = false;
  }

  /// 暂停播放
  Future<void> pause() async {
    await _player?.pause();
    _isSpeaking = false;
  }

  void dispose() {
    _player?.dispose();
    _dio?.close();
  }
}

class TtsException implements Exception {
  final String message;
  TtsException(this.message);

  @override
  String toString() => message;
}
