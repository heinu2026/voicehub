import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import 'settings_service.dart';

/// TTS 服务 - 使用 Minimax T2A API
///
/// 支持两种模式:
/// 1. 普通模式: speak(text) → 完整音频 → 播放
/// 2. 流式模式: speakStream(textStream) → 边合成边播放（Siri 级体验）
class TtsService {
  AudioPlayer? _player;
  Dio? _dio;
  SettingsService? _settingsService;
  bool _isInitialized = false;
  bool _isSpeaking = false;

  /// 句子结束标点（用于句子边界检测）
  static const _sentenceEndChars = '。！？.!?；;';

  /// 当前播放队列（流式模式下）
  Uint8List? _streamingBuffer;
  bool _isStreamingTTS = false;

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

  /// 播放语音（普通模式）
  Future<void> speak(String text) async {
    if (!_isInitialized) await init();
    if (text.trim().isEmpty) return;

    final apiKey = _settingsService?.minimaxApiKey ?? '';
    if (apiKey.isEmpty) {
      throw TtsException('未配置 MiniMax API Key');
    }

    if (_isSpeaking) await stop();

    _isSpeaking = true;

    try {
      final voiceId = _settingsService?.ttsVoiceId ?? AppConfig.ttsDefaultVoiceId;
      final speed = _settingsService?.ttsSpeed ?? AppConfig.ttsDefaultSpeed;

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

  /// 流式播放语音（Siri 模式）
  ///
  /// 接收文本流，检测句子边界，实时 TTS 合成并播放。
  /// 流程: text chunks → 拼接 → 按句子分段 → MiniMax TTS → 播放音频块
  ///
  /// [textStream] - AI 回复的文本流
  /// 返回: 播放的句子列表
  Stream<String> speakStream(Stream<String> textStream) async* {
    if (!_isInitialized) await init();

    final apiKey = _settingsService?.minimaxApiKey ?? '';
    if (apiKey.isEmpty) {
      throw TtsException('未配置 MiniMax API Key');
    }

    if (_isSpeaking) await stop();

    _isSpeaking = true;
    _isStreamingTTS = true;

    String buffer = '';

    try {
      await for (final chunk in textStream) {
        if (!_isStreamingTTS) break;

        buffer += chunk;
        debugPrint('TtsService: 流式接收 chunk "${chunk.substring(0, chunk.length.clamp(0, 20))}..."');

        // 检测完整句子并播放
        final sentences = _extractCompleteSentences(buffer);
        for (final sentence in sentences) {
          if (sentence.trim().isEmpty) continue;
          if (!_isStreamingTTS) break;

          debugPrint('TtsService: 流式播放句子: "$sentence"');

          // 边播放边 yield，让调用者知道播了哪句
          yield sentence;

          try {
            await _speakSentence(sentence, apiKey);
          } catch (e) {
            debugPrint('TtsService: 单句 TTS 失败 $e，继续下一句');
          }
        }

        // 保留不完整的尾部
        buffer = sentences.isNotEmpty ? buffer.substring(
          buffer.indexOf(sentences.last) + sentences.last.length
        ) : buffer;
      }

      // 播放剩余内容（最后一段不完整句子）
      if (buffer.trim().isNotEmpty && _isStreamingTTS) {
        yield buffer;
        try {
          await _speakSentence(buffer, apiKey);
        } catch (e) {
          debugPrint('TtsService: 尾部 TTS 失败 $e');
        }
      }

    } finally {
      _isSpeaking = false;
      _isStreamingTTS = false;
    }
  }

  /// 从文本中提取完整的句子（以句末标点结尾）
  List<String> _extractCompleteSentences(String text) {
    if (text.isEmpty) return [];

    final sentences = <String>[];
    final sb = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      sb.write(text[i]);
      if (_sentenceEndChars.contains(text[i])) {
        sentences.add(sb.toString().trim());
        sb.clear();
      }
    }

    return sentences;
  }

  /// 播放单个句子的 TTS
  Future<void> _speakSentence(String sentence, String apiKey) async {
    if (sentence.trim().isEmpty) return;

    final voiceId = _settingsService?.ttsVoiceId ?? AppConfig.ttsDefaultVoiceId;
    final speed = _settingsService?.ttsSpeed ?? AppConfig.ttsDefaultSpeed;

    final response = await _dio!.post(
      '${AppConfig.ttsBaseUrl}/v1/t2a_v2',
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        responseType: ResponseType.plain,
      ),
      data: {
        'model': AppConfig.ttsModel,
        'text': sentence,
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
    if (data == null || data['data'] == null) return;

    final status = data['data']['status'];
    if (status != 2) return;

    final hexAudio = data['data']['audio'] as String;
    final audioBytes = _hexToBytes(hexAudio);

    // 播放音频块
    await _player!.setSourceBytes(audioBytes);
    await _player!.resume();

    // 等待当前句子播放完成，再继续下一句（保证顺序）
    final completer = Completer<void>();
    late StreamSubscription subscription;
    subscription = _player!.onPlayerComplete.listen((_) {
      subscription.cancel();
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;
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
    _isStreamingTTS = false;
    await _player?.stop();
    _isSpeaking = false;
  }

  /// 暂停播放
  Future<void> pause() async {
    await _player?.pause();
    _isSpeaking = false;
  }

  void dispose() {
    _isStreamingTTS = false;
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
