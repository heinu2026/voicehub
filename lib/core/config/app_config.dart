/// 应用配置
class AppConfig {
  // OpenClaw Gateway 地址
  static const String openClawBaseUrl = 'http://192.168.1.x:8000';
  
  // OpenClaw Agent 配置
  static const String defaultAgentId = 'main';  // 默认 Agent
  static const String defaultModel = '';         // 空则使用默认模型
  
  // 唤醒词
  static const String wakeWord = 'Hey OpenClaw';
  
  // 语音识别
  static const String speechLocale = 'zh_CN';
  static const int speechListenSeconds = 30;
  static const int speechPauseSeconds = 3;
  
  // TTS
  static const double ttsSpeechRate = 0.5;
  static const double ttsPitch = 1.0;
  static const double ttsVolume = 1.0;
  
  // 录音
  static const int sampleRate = 16000;
  
  // Channel 标识
  static const String channelName = 'voiceclaw';
}
