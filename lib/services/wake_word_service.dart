import 'dart:async';
import 'dart:io';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:porcupine/porcupine.dart';

/// 唤醒词服务 - 支持本地唤醒词检测
class WakeWordService {
  final AudioRecorder _recorder = AudioRecorder();
  Porcupine? _porcupine;
  
  bool _isRecording = false;
  bool _isListening = false;
  String? _recordingPath;
  
  StreamController<void>? _wakeWordController;
  StreamSubscription<dynamic>? _porcupineSubscription;
  
  /// 唤醒词触发流
  Stream<void> get onWakeWord => _wakeWordController?.stream ?? const Stream.empty();
  
  bool get isRecording => _isRecording;
  bool get isListening => _isListening;
  
  /// 初始化 - 加载唤醒词模型
  Future<void> init() async {
    // 检查权限
    if (!await _recorder.hasPermission()) {
      throw WakeWordException('麦克风权限被拒绝');
    }
    
    // 初始化唤醒词检测
    _wakeWordController = StreamController<void>.broadcast();
    
    // 获取 Porcupine 模型路径
    final modelPath = await _getModelPath();
    
    // 内置唤醒词: "Hey Hub" / "你好助手"
    // 可以从 https://picovoice.ai/porcupine/ 获取自定义唤醒词
    final keywords = ['hey hub', 'ok hub'];
    
    _porcupine = await Porcupine.fromKeywords(
      keywords: keywords,
      modelPath: modelPath,
    );
    
    _isListening = true;
    _startWakeWordDetection();
  }
  
  /// 获取内置模型路径
  Future<String> _getModelPath() async {
    // Porcupine 会自动从 assets 加载模型
    // 如果需要自定义模型，放到 assets/porcupine/ 目录
    return '';
  }
  
  /// 开始唤醒词检测
  void _startWakeWordDetection() {
    _porcupineSubscription = _porcupine!.stream.listen((index) {
      if (index >= 0) {
        // 检测到唤醒词
        _wakeWordController?.add(null);
      }
    });
    
    // 开始录音进行唤醒词检测
    _startListening();
  }
  
  /// 开始监听麦克风
  Future<void> _startListening() async {
    if (_isListening) return;
    
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: '',  // 流式录音，不需要文件路径
    );
    
    _isListening = true;
    _processAudio();
  }
  
  /// 处理音频流
  Future<void> _processAudio() async {
    while (_isListening && _porcupine != null) {
      try {
        final amplitude = await _recorder.getAmplitude();
        // Porcupine 需要 16kHz, 16-bit PCM 数据
        // 这里简化处理，实际需要音频流处理
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        break;
      }
    }
  }
  
  /// 停止唤醒词检测
  Future<void> stopListening() async {
    if (!_isListening) return;
    
    _isListening = false;
    await _recorder.stop();
  }
  
  /// 开始录音 (唤醒词检测成功后)
  Future<String> startRecording() async {
    if (_isRecording) {
      await stopRecording();
    }
    
    // 停止唤醒词检测
    await stopListening();
    
    // 获取保存路径
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _recordingPath = '${dir.path}/wake_$timestamp.m4a';
    
    // 开始录音
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        bitRate: 128000,
        numChannels: 1,
      ),
      path: _recordingPath!,
    );
    
    _isRecording = true;
    return _recordingPath!;
  }
  
  /// 停止录音并返回路径
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;
    
    final path = await _recorder.stop();
    _isRecording = false;
    
    // 恢复唤醒词检测
    _startListening();
    
    return path;
  }
  
  /// 取消录音
  Future<void> cancelRecording() async {
    if (_isRecording) {
      await _recorder.stop();
      
      // 删除临时文件
      if (_recordingPath != null) {
        final file = File(_recordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
      
      _isRecording = false;
      _recordingPath = null;
    }
    
    // 恢复唤醒词检测
    _startListening();
  }
  
  /// 获取录音音量 (用于波形显示)
  Future<double> getAmplitude() async {
    final isActive = _isRecording || _isListening;
    if (!isActive) return 0;
    
    final amplitude = await _recorder.getAmplitude();
    final db = amplitude.current;
    if (db == double.negativeInfinity) return 0;
    
    return ((db + 60) / 60).clamp(0.0, 1.0);
  }
  
  /// 释放资源
  void dispose() {
    _porcupineSubscription?.cancel();
    _wakeWordController?.close();
    _porcupine?.dispose();
    _recorder.dispose();
  }
}

class WakeWordException implements Exception {
  final String message;
  WakeWordException(this.message);
  
  @override
  String toString() => message;
}

/**
 * 使用说明:
 * 
 * 1. 唤醒词模型:
 *    - 默认内置 "hey hub", "ok hub"
 *    - 可在 https://picovoice.ai/porcupine/ 创建自定义唤醒词
 *    - 自定义模型放在 assets/porcupine/ 目录
 * 
 * 2. 工作流程:
 *    - init() 初始化后开始监听唤醒词
 *    - 检测到唤醒词时 onWakeWord 流会触发
 *    - 收到唤醒词后调用 startRecording() 开始录音
 *    - 录音完成后调用 stopRecording() 停止并恢复唤醒词检测
 * 
 * 3. iOS 配置:
 *    - 在 Info.plist 添加 NSMicrophoneUsageDescription
 *    - 启用 Background Modes > Audio
 * 
 * 4. Android 配置:
 *    - 添加 RECORD_AUDIO 权限
 *    - 添加 RECEIVE_BOOT_COMPLETED 开机自启
 */
