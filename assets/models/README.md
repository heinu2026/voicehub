# Snowboy 唤醒词模型训练指南

VoiceHub 使用 **Snowboy** (KITT.AI / seasalt-ai) 进行本地唤醒词检测。
唤醒词模型需要自行训练，生成 `.pmdl` 文件放到本目录。

---

## 方案一：使用 seasalt-ai/snowboy Docker 训练（推荐）

### 1. 克隆仓库

```bash
git clone https://github.com/seasalt-ai/snowboy
cd snowboy
```

### 2. 构建 Docker 镜像

```bash
docker build -t snowboy .
```

### 3. 准备音频样本

在宿主机创建模型目录（注意不要在 Docker 容器内创建）：

```bash
mkdir -p ~/snowboy_models/hey_vcl
cd ~/snowboy_models/hey_vcl
```

准备以下 WAV 音频（必须满足 Snowboy 格式要求）：
- **格式**: 16kHz, 16-bit, mono PCM WAV
- **时长**: 1-3 秒
- **内容**: 清晰念出你的唤醒词

创建以下目录结构：

```
~/snowboy_models/hey_vcl/
├── personal/          # 你自己录的样本（正面）
│   ├── 1.wav
│   ├── 2.wav
│   ├── 3.wav
│   └── ...
└── negative/          # 随机其他人声/背景音（负面）
    ├── sample1.wav
    └── ...
```

**音频录制技巧**：
```bash
# 用 ffmpeg 转换格式（如果不是标准 WAV）
ffmpeg -i input.mp3 -ar 16000 -ac 1 -ab 16 -f wav output.wav

# 或用 macOS 音频工具录制
rec -r 16000 -c 1 -b 16 output.wav
```

**要求**：
- `personal/` 至少 3 个样本，越多越准确
- `negative/` 越多越好（>10个），包含不同人的声音和环境音
- 不要在太安静的环境录（Snowboy 需要学会区分噪声）

### 4. 运行训练

```bash
docker run --rm \
  -v ~/snowboy_models:/workspace/models \
  snowboy \
  bash -c "cd /workspace/models/hey_vcl && \
    python3 /snowboy/examples/Python3/generate_pmdl.py \
    personal/*.wav negative/*.wav hey_vcl.pmdl"
```

### 5. 复制模型到 VoiceHub

```bash
cp ~/snowboy_models/hey_vcl/hey_vcl.pmdl \
   /path/to/voicehub/assets/models/hey_voiceclaw.pmdl
```

---

## 方案二：使用通用预训练模型（快速测试）

seasalt-ai/snowboy 仓库自带几个通用模型，可以直接用：

```bash
# 下载预训练模型
curl -L \
  "https://github.com/seasalt-ai/snowboy/raw/master/resources/models/snowboy.pmdl" \
  -o assets/models/snowboy_default.pmdl
```

> ⚠️ 预训练模型识别的是 "Snowboy"，不是你的自定义唤醒词。
> 仅用于开发测试，正式使用请训练自己的模型。

---

## 推荐唤醒词

- **英文**: "Hey VoiceClaw" / "Hey OpenClaw" / "Hey Buddy"
- **中文**: "黑黑" / "小助手" / "嗨助手"（中文唤醒词训练难度更高，建议英文）
- 唤醒词长度 2-4 秒效果最好
- 避免常用词和太短的词（如"喂"、"嗨"容易误触发）

---

## 模型格式说明

- `.pmdl` = Personal Model (个人模型，轻量，专属你训练的唤醒词)
- `.umdl` = Universal Model (通用模型，可识别多个唤醒词)
- VoiceHub 使用 `.pmdl` 格式

---

## 代码中使用

```dart
// 在 ChatBloc 或 App 初始化时：
final wakeWordService = WakeWordService();
await wakeWordService.init();
await wakeWordService.prepare('assets/models/hey_voiceclaw.pmdl');

wakeWordService.setOnWakeWordDetected(() {
  debugPrint('🎉 唤醒词触发！');
  // 开始录音 → STT → AI → TTS
});

await wakeWordService.startListening();
```

---

## 常见问题

### Q: 训练失败？
检查 WAV 文件格式：
```bash
ffprobe your_audio.wav
# 确保: 16000 Hz, 1 channel, 16 bit
```

### Q: 检测不准/误触发？
- 增加 `negative/` 样本数量
- 确保录音环境多样（安静、有背景音、不同距离）
- 调整灵敏度（见下方）

### Q: 调整灵敏度？
Snowboy 的 `sensitivity` 参数（默认 0.5）：
- 值越高越灵敏（也越容易误触发）
- 在 `WakeWordService.detect()` 调用前设置

### Q: iOS 模拟器不支持？
Snowboy 是 C++ 原生库，需要物理设备测试。
```bash
# 真机测试
flutter run -d <your-iphone-device-id>
```
