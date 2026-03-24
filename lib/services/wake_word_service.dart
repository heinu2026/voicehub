import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_snowboy/flutter_snowboy.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:audio_session/audio_session.dart';

/// 唤醒词检测服务
///
/// 使用 Snowboy 进行本地唤醒词检测，支持离线和低延迟
///
/// 工作流程:
/// 1. init() 初始化 Snowboy 检测器
/// 2. prepare(modelAssetPath) 加载唤醒词模型
/// 3. startListening() 开始持续监听
/// 4. 检测到唤醒词后，调用 onWakeWordDetected 回调
///
/// 注意: 需要麦克风权限
class WakeWordService {
  Snowboy? _detector;
  bool _isInitialized = false;
  bool _isListening = false;

  FlutterSoundRecorder? _recorder;
  AudioSession? _audioSession;
  StreamSubscription? _recorderSubscription;
  StreamController<Uint8List>? _pcmStreamController;

  /// 唤醒词检测回调
  VoidCallback? _onWakeWordDetected;

  final _statusController = StreamController<bool>.broadcast();

  bool get isInitialized => _isInitialized;
  bool get isListening => _isListening;
  Stream<bool> get onStatus => _statusController.stream;

  /// 设置唤醒词检测回调
  void setOnWakeWordDetected(VoidCallback callback) {
    _onWakeWordDetected = callback;
  }

  /// 初始化 Snowboy 检测器
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      _detector = Snowboy();
      _isInitialized = true;
      debugPrint('WakeWordService: Snowboy 初始化成功');
    } catch (e) {
      debugPrint('WakeWordService: 初始化失败 $e');
    }
  }

  /// 准备模型（从 assets 加载到临时目录）
  Future<bool> prepare(String modelAssetPath) async {
    if (!_isInitialized) await init();
    if (!_isInitialized || _detector == null) return false;

    try {
      // 从 assets 复制模型文件到临时目录（Snowboy 需要文件路径）
      final byteData = await rootBundle.load(modelAssetPath);
      final tempDir = Directory.systemTemp;
      final fileName = modelAssetPath.split('/').last;
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(byteData.buffer.asUint8List());

      // 设置唤醒词回调
      _detector!.hotwordHandler = () {
        debugPrint('WakeWordService: ✅ 检测到唤醒词！');
        _onWakeWordDetected?.call();
      };

      // 初始化检测器
      final result = await _detector!.prepare(tempFile.path);
      if (!result) {
        debugPrint('WakeWordService: 模型加载失败');
        return false;
      }

      debugPrint('WakeWordService: 模型加载成功: $modelAssetPath');
      return true;
    } catch (e) {
      debugPrint('WakeWordService: 模型加载失败 $e');
      return false;
    }
  }

  /// 开始持续监听唤醒词
  Future<void> startListening() async {
    if (!_isInitialized) {
      await init();
      if (!_isInitialized) return;
    }

    if (_isListening) return;

    // 初始化录音器
    _recorder ??= FlutterSoundRecorder();

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

      // 监听 PCM 数据并进行唤醒词检测
      _recorderSubscription = _pcmStreamController!.stream.listen((pcmData) {
        _detectHotword(pcmData);
      });

      // 开始录音：16kHz, 16-bit, mono PCM（Snowboy 要求）
      await _recorder!.startRecorder(
        toStream: _pcmStreamController!.sink,
        codec: Codec.pcm16,
        sampleRate: 16000,
        numChannels: 1,
      );

      _isListening = true;
      _statusController.add(true);
      debugPrint('WakeWordService: 开始监听唤醒词');
    } catch (e) {
      debugPrint('WakeWordService: 启动录音失败 $e');
      await _cleanupRecorder();
    }
  }

  /// 使用 Snowboy 检测唤醒词
  void _detectHotword(Uint8List pcmData) {
    if (_detector == null || !_isListening) return;

    // detect 是异步的，但我们不在这里 await，以保持实时处理
    _detector!.detect(pcmData).catchError((e) {
      debugPrint('WakeWordService: 检测失败 $e');
    });
  }

  /// 停止监听
  Future<void> stopListening() async {
    if (!_isListening) return;

    _isListening = false;
    await _cleanupRecorder();
    _statusController.add(false);
    debugPrint('WakeWordService: 停止监听');
  }

  Future<void> _cleanupRecorder() async {
    _recorderSubscription?.cancel();
    _recorderSubscription = null;

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

  /// 释放资源
  Future<void> dispose() async {
    await stopListening();
    await _statusController.close();
    await _detector?.purge();
    _detector = null;
    _isInitialized = false;
    debugPrint('WakeWordService: 已释放');
  }
}
