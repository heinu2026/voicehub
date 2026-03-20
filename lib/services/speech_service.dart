import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import '../config/app_config.dart';

class SpeechService {
  final SpeechToText _speech = SpeechToText();
  bool _isAvailable = false;
  bool _isListening = false;
  
  final _resultController = StreamController<String>.broadcast();
  Stream<String> get onResult => _resultController.stream;
  
  final _statusController = StreamController<bool>.broadcast();
  Stream<bool> get onStatus => _statusController.stream;
  
  bool get isAvailable => _isAvailable;
  bool get isListening => _isListening;
  
  /// 初始化语音识别
  Future<bool> init() async {
    _isAvailable = await _speech.initialize(
      onError: (error) {
        _isListening = false;
        _statusController.add(false);
      },
      onStatus: (status) {
        _isListening = status == 'listening';
        _statusController.add(_isListening);
      },
    );
    
    return _isAvailable;
  }
  
  /// 开始监听语音
  Future<void> listen() async {
    if (!_isAvailable) {
      final initialized = await init();
      if (!initialized) {
        throw SpeechException('语音识别不可用');
      }
    }
    
    if (_isListening) {
      return;  // 已经在监听
    }
    
    _isListening = true;
    _statusController.add(true);
    
    await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        if (result.finalResult) {
          _resultController.add(result.recognizedWords);
          _isListening = false;
          _statusController.add(false);
        }
      },
      listenFor: Duration(seconds: AppConfig.speechListenSeconds),
      pauseFor: Duration(seconds: AppConfig.speechPauseSeconds),
      localeId: AppConfig.speechLocale,  // 中文
      cancelOnError: false,
      partialResults: true,
    );
  }
  
  /// 停止监听
  Future<void> stop() async {
    await _speech.stop();
    _isListening = false;
    _statusController.add(false);
  }
  
  /// 取消监听
  Future<void> cancel() async {
    await _speech.cancel();
    _isListening = false;
    _statusController.add(false);
  }
  
  void dispose() {
    _speech.stop();
    _resultController.close();
    _statusController.close();
  }
}

class SpeechException implements Exception {
  final String message;
  SpeechException(this.message);
  
  @override
  String toString() => message;
}
