import 'dart:async';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

/// 录音服务 - 用于捕获唤醒词后的语音
class WakeWordService {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  
  String? _recordingPath;
  
  bool get isRecording => _isRecording;
  
  /// 初始化
  Future<void> init() async {
    // 检查权限
    if (!await _recorder.hasPermission()) {
      throw WakeWordException('麦克风权限被拒绝');
    }
  }
  
  /// 开始录音
  Future<String> startRecording() async {
    if (_isRecording) {
      await stopRecording();
    }
    
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
  }
  
  /// 获取录音音量 (用于波形显示)
  Future<double> getAmplitude() async {
    if (!_isRecording) return 0;
    
    final amplitude = await _recorder.getAmplitude();
    // 将 dB 转换为 0-1 范围
    final db = amplitude.current;
    if (db == double.negativeInfinity) return 0;
    
    // 假设范围是 -60dB 到 0dB
    return ((db + 60) / 60).clamp(0.0, 1.0);
  }
  
  void dispose() {
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
 * 注意: 真正的本地唤醒词 (Wake Word) 检测需要:
 * 
 * 1. Porcupine (Picovoice)
 *    - 需要 native 库支持
 *    - 可以自定义唤醒词
 *    - 离线、低功耗
 * 
 * 2. 集成方式:
 *    - Flutter 端: 使用 porcupine_flutter 包
 *    - 原生端: 在 iOS/Android 项目中集成 Porcupine 库
 * 
 * 3. 简化方案:
 *    - 使用 "按下说话" 按钮替代
 *    - 或使用语音助手触发 (Hey Siri / 小爱同学)
 */
