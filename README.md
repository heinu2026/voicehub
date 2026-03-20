# VoiceHub 🗣️

> 语音唤醒 AI 助手 - Flutter 版 (iOS/Android)

## 功能特性

- 🎤 **语音唤醒** - 按住说话，松开结束
- 🤖 **AI 对话** - 连接 OpenClaw 获取智能回复
- 🔊 **语音回复** - TTS 自动朗读回复
- 💬 **文字输入** - 支持键盘输入
- 🌙 **深色主题** - 护眼模式

## 快速开始

### 1. 克隆项目

```bash
git clone https://github.com/heinu2026/voicehub.git
cd voicehub
```

### 2. 安装依赖

```bash
flutter pub get
```

### 3. 配置 OpenClaw 地址

编辑 `lib/core/config/app_config.dart`:

```dart
static const String openClawBaseUrl = 'http://你的Mac-IP:8000';
static const String openClawWsUrl = 'ws://你的Mac-IP:8000';
```

### 4. 运行

```bash
# iOS
flutter run -d iphone

# Android
flutter run -d android
```

## 权限配置

### iOS (ios/Runner/Info.plist)

添加:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>VoiceHub 需要麦克风权限来接收语音输入</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>VoiceHub 需要语音识别权限来转录您的语音</string>
```

### Android (android/app/src/main/AndroidManifest.xml)

添加:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.INTERNET"/>
```

## 项目结构

```
lib/
├── main.dart                    # 入口
├── core/
│   ├── config/app_config.dart   # 配置
│   └── theme/app_theme.dart    # 主题
├── services/
│   ├── openclaw_service.dart   # OpenClaw API
│   ├── speech_service.dart     # 语音识别
│   ├── tts_service.dart        # 语音合成
│   └── wake_word_service.dart  # 唤醒/录音
├── bloc/
│   └── chat/                   # 状态管理
├── models/
│   └── message.dart            # 消息模型
└── ui/
    ├── screens/chat_screen.dart
    └── widgets/
        ├── voice_button.dart
        └── message_bubble.dart
```

## 工作流程

```
用户按下按钮
    ↓
🎤 语音识别 (Speech-to-Text)
    ↓
📝 文本 → OpenClaw API
    ↓
🤖 AI 处理 → 获取回复
    ↓
🔊 TTS 语音合成 → 朗读回复
```

## 进阶功能

### 语音唤醒 (Wake Word)

真正的本地唤醒词需要集成 **Porcupine**:

1. 添加依赖: `porcupine_flutter`
2. 在原生项目中配置 Porcupine 库
3. 训练自定义唤醒词

当前版本使用 **"按键唤醒"** 方案。

### 自定义 TTS

修改 `lib/services/tts_service.dart` 使用更强的 TTS 服务:

- ElevenLabs (效果好)
- Azure TTS
- 阿里云 TTS

## TODO

- [ ] 本地唤醒词 (Porcupine)
- [ ] 对话历史本地存储
- [ ] 多语言支持
- [ ] 离线模式

## License

MIT
