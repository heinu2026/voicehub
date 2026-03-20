import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/app_config.dart';

class OpenClawService {
  late Dio _dio;
  WebSocketChannel? _wsChannel;
  
  String _baseUrl;
  String _wsUrl;
  
  final _responseController = StreamController<String>.broadcast();
  Stream<String> get onResponse => _responseController.stream;
  
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  
  OpenClawService({
    String? baseUrl,
    String? wsUrl,
  })  : _baseUrl = baseUrl ?? AppConfig.openClawBaseUrl,
        _wsUrl = wsUrl ?? AppConfig.openClawWsUrl {
    _initDio();
  }
  
  void _initDio() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 60),
    ));
  }
  
  /// 更新 URL 配置
  void updateUrls({String? baseUrl, String? wsUrl}) {
    if (baseUrl != null) _baseUrl = baseUrl;
    if (wsUrl != null) _wsUrl = wsUrl;
    _initDio();
  }
  
  /// 发送消息并获取回复 (HTTP)
  Future<String> sendMessage(String text) async {
    try {
      final response = await _dio.post(
        '/api/message',
        data: {
          'message': text,
          'channel': AppConfig.channelName,
        },
      );
      
      final data = response.data;
      
      // 处理不同响应格式
      if (data is Map) {
        return data['reply'] ?? data['message'] ?? data['content'] ?? data.toString();
      }
      return data.toString();
    } on DioException catch (e) {
      throw OpenClawException('请求失败: ${e.message}');
    }
  }
  
  /// 连接 WebSocket (实时对话)
  Future<void> connectWebSocket() async {
    try {
      _wsChannel = WebSocketChannel.connect(
        Uri.parse(_wsUrl),
      );
      
      _wsChannel!.stream.listen(
        (data) {
          try {
            final json = jsonDecode(data as String);
            final content = json['content'] ?? json['reply'] ?? json['message'] ?? '';
            _responseController.add(content);
          } catch (e) {
            _responseController.add(data.toString());
          }
        },
        onError: (error) {
          _isConnected = false;
        },
        onDone: () {
          _isConnected = false;
        },
      );
      
      _isConnected = true;
    } catch (e) {
      _isConnected = false;
      throw OpenClawException('WebSocket 连接失败: $e');
    }
  }
  
  /// 通过 WebSocket 发送消息
  void sendMessageStream(String text) {
    if (_wsChannel == null || !_isConnected) {
      throw OpenClawException('WebSocket 未连接');
    }
    
    _wsChannel!.sink.add(jsonEncode({
      'message': text,
      'channel': AppConfig.channelName,
    }));
  }
  
  /// 断开 WebSocket
  void disconnect() {
    _wsChannel?.sink.close();
    _wsChannel = null;
    _isConnected = false;
  }
  
  void dispose() {
    disconnect();
    _responseController.close();
    _dio.close();
  }
}

class OpenClawException implements Exception {
  final String message;
  OpenClawException(this.message);
  
  @override
  String toString() => message;
}
