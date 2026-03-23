import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:audio_session/audio_session.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_snowboy/flutter_snowboy.dart';

/// Snowboy 唤醒词检测服务
///
/// 工作流程:
/// 1. init() + prepare() 初始化并加载 .pmdl 模型
/// 2. startListening() 开始持续监听麦克风
/// 3. 检测到唤醒词 → _onWakeWordDetected 回调触发
/// 4. stopListening() 停止监听
///
/// 音频格式: 16kHz, 16-bit, mono PCM
class WakeWordService {
  Snowboy? _detector;
  FlutterSoundRecorder? _recorder;

  /// PCM 原始数据流控制器
  StreamController<Uint8List>? _pcmStreamController;
  StreamSubscription<Uint8List>? _pcmSubscription;

  AudioSession? _audioSession;

  bool _isInitialized = false;
  bool _isListening = false;

  /// 模型绝对路径
  String? _modelPath;

  /// 唤醒词检测回调
  VoidCallback? _onWakeWordDetected;

  final _statusController = StreamController<bool>.broadcast();
  Stream<bool> get onStatus => _statusController.stream;

  bool get isInitialized => _isInitialized;
  bool get isListening => _isListening;

  /// 设置唤醒词检测回调
  void setOnWakeWordDetected(VoidCallback callback) {
    _onWakeWordDetected = callback;
  }

  /// 初始化
  Future<void> init() async {
    if (_isInitialized) return;

    _detector ??= Snowboy();
    _recorder ??= FlutterSoundRecorder();

    // 配置音频会话（iOS/Android 独占麦克风）
    _audioSession ??= await AudioSession.instance;
    await _audioSession!.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker |
          AVAudioSessionCategoryOptions.allowBluetooth,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
      avAudioSessionRouteSharingPolicy:
          AVAudioSessionRouteSharingPolicy.defaultPolicy,
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        flags: AndroidAudioFlags.none,
        usage: AndroidAudioUsage.voiceCommunication,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));

    _isInitialized = true;
    debugPrint('WakeWordService: 初始化完成');
  }

  /// 准备模型文件
  /// [modelAssetPath] - assets 中的模型路径，如 'assets/models/hey_voiceclaw.pmdl'
  Future<bool> prepare(String modelAssetPath) async {
    if (!_isInitialized) await init();

    try {
      final modelFile = await _copyAssetToTempFile(modelAssetPath);
      _modelPath = modelFile.path;

      debugPrint('WakeWordService: 加载模型 $_modelPath');

      final success = await _detector!.prepare(
        _modelPath!,
        sensitivity: 0.5,
        audioGain: 1.0,
        applyFrontend: true,
      );

      if (!success) {
        debugPrint('WakeWordService: 模型加载失败');
        return false;
      }

      _detector!.hotwordHandler = _onWakeWordDetected;
      debugPrint('WakeWordService: 模型准备完成');
      return true;

    } catch (e) {
      debugPrint('WakeWordService: prepare 失败 $e');
      return false;
    }
  }

  /// 开始持续监听
  /// 使用 FlutterSound 流式接口，将 PCM 数据实时送入 Snowboy 检测
  Future<void> startListening() async {
    if (!_isInitialized || _detector == null) {
      debugPrint('WakeWordService: 未初始化，请先调用 prepare()');
      return;
    }

    if (_isListening) return;

    if (_modelPath == null) {
      debugPrint('WakeWordService: 未加载模型');
      return;
    }

    try {
      await _audioSession!.setActive(true);
      await _recorder!.openRecorder();

      // PCM Uint8List 流控制器
      _pcmStreamController = StreamController<Uint8List>();

      // 监听 PCM 数据 → 送入 Snowboy
      _pcmSubscription?.cancel();
      _pcmSubscription = _pcmStreamController!.stream.listen((pcmData) {
        _detector!.detect(pcmData);
      });

      // 开始录音：16kHz, 16-bit, mono PCM
      // 新版 flutter_sound 直接输出 Uint8List
      await _recorder!.startRecorder(
        toStream: _pcmStreamController!.sink,
        codec: Codec.pcm16,
        sampleRate: 16000,
        numChannels: 1,
      );

      _isListening = true;
      _statusController.add(true);
      debugPrint('WakeWordService: 开始持续监听...');

    } catch (e) {
      debugPrint('WakeWordService: 启动监听失败 $e');
      _isListening = false;
      _statusController.add(false);
      await _cleanup();
    }
  }

  /// 停止监听
  Future<void> stopListening() async {
    if (!_isListening) return;

    try {
      await _recorder?.stopRecorder();
    } catch (e) {
      debugPrint('WakeWordService: 停止录音器失败 $e');
    }

    await _cleanup();

    _isListening = false;
    _statusController.add(false);
    debugPrint('WakeWordService: 停止监听');
  }

  Future<void> _cleanup() async {
    await _pcmSubscription?.cancel();
    _pcmSubscription = null;

    await _pcmStreamController?.close();
    _pcmStreamController = null;

    try {
      await _recorder?.closeRecorder();
    } catch (_) {}

    try {
      await _audioSession?.setActive(false);
    } catch (_) {}
  }

  /// 释放资源
  Future<void> dispose() async {
    await stopListening();
    _statusController.close();
    await _detector?.purge();
    debugPrint('WakeWordService: 已释放');
  }

  /// 将 assets 中的文件复制到临时目录
  Future<File> _copyAssetToTempFile(String assetPath) async {
    final byteData = await rootBundle.load(assetPath);
    final tempDir = await getTemporaryDirectory();
    final fileName = p.basename(assetPath);
    final outFile = File(p.join(tempDir.path, fileName));
    await outFile.writeAsBytes(
      byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
    );
    debugPrint('WakeWordService: 模型已复制到 ${outFile.path}');
    return outFile;
  }
}
