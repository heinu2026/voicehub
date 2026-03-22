/// 应用配置
class AppConfig {
  // OpenClaw 服务地址
  static const String defaultBaseUrl = 'http://192.168.1.100:8080';
  static const String openClawBaseUrl = 'http://192.168.1.100:8080';

  // OpenClaw 认证 Token（Bearer Token）
  // TODO: 上线前建议移到设置页或环境变量
  static const String defaultOpenClawToken = 'e9cec475b8d31abb40a4ec3c92b873c79e41174f09dd0bdc';

  // STT 服务端口（OpenClaw 网关本地端口）
  static const int sttPort = 8080;

  // 渠道名称
  static const String channelName = 'voiceclaw';

  // 默认 Agent
  static const String defaultAgentId = 'main';
  static const String defaultModel = '';

  // 语音识别配置
  static const int speechListenSeconds = 30;
  static const int speechPauseSeconds = 3;
  static const String speechLocale = 'zh_CN';

  // ========== Minimax TTS 配置 ==========
  // TTS API endpoint
  static const String ttsBaseUrl = 'https://api.minimaxi.com';
  static const String ttsModel = 'speech-02-hd';  // 高质量中文语音
  static const String ttsDefaultVoiceId = 'female-shaonv';
  static const double ttsDefaultSpeed = 1.0;
  static const double ttsDefaultPitch = 0.0;
  static const double ttsDefaultVol = 1.0;
  static const int ttsSampleRate = 32000;
  static const int ttsBitrate = 128000;
  static const String ttsFormat = 'mp3';

  // TTS 语速
  static const double ttsSpeechRate = 1.0;

  // 唤醒词配置
  static const String wakeWord = 'hey claw';

  // ========== Whisper STT 配置 ==========
  // Whisper 服务器地址（自部署 whisper-server）
  // 例如: http://192.168.1.100:9001
  static const String defaultWhisperUrl = '';

  // Whisper API Key（可选）
  static const String defaultWhisperApiKey = '';

  // Whisper STT 模型
  static const String defaultWhisperModel = 'large-v3-turbo-q5_0';

  // 语音活动检测参数
  static const int silenceSeconds = 3;      // 静音多少秒触发识别
  static const int maxRecordSeconds = 30;    // 最大录音时长
}
