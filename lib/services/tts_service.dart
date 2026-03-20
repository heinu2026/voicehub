import 'package:flutter_tts/flutter_tts.dart';
import '../config/app_config.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;
  bool _isSpeaking = false;
  
  bool get isSpeaking => _isSpeaking;
  
  /// 初始化 TTS
  Future<void> init() async {
    if (_isInitialized) return;
    
    await _tts.setLanguage('zh-CN');
    await _tts.setSpeechRate(AppConfig.ttsSpeechRate);
    await _tts.setPitch(AppConfig.ttsPitch);
    await _tts.setVolume(AppConfig.ttsVolume);
    
    // 设置中文发音人
    await _tts.setVoice({'name': 'zh-cn-x-sf', 'locale': 'zh-CN'});
    
    // 监听状态
    _tts.setStartHandler(() {
      _isSpeaking = true;
    });
    
    _tts.setCompletionHandler(() {
      _isSpeaking = false;
    });
    
    _tts.setCancelHandler(() {
      _isSpeaking = false;
    });
    
    _tts.setErrorHandler((error) {
      _isSpeaking = false;
    });
    
    _isInitialized = true;
  }
  
  /// 播放语音
  Future<void> speak(String text) async {
    if (!_isInitialized) {
      await init();
    }
    
    // 停止当前播放
    if (_isSpeaking) {
      await stop();
    }
    
    await _tts.speak(text);
    _isSpeaking = true;
  }
  
  /// 停止播放
  Future<void> stop() async {
    await _tts.stop();
    _isSpeaking = false;
  }
  
  /// 暂停播放
  Future<void> pause() async {
    await _tts.pause();
    _isSpeaking = false;
  }
  
  void dispose() {
    _tts.stop();
  }
}
