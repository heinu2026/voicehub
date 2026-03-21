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
  String _agentId;
  String _model;
  
  final _responseController = StreamController<String>.broadcast();
  Stream<String> get onResponse => _responseController.stream;
  
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  
  OpenClawService({
    String? baseUrl,
    String? wsUrl,
    String? agentId,
    String? model,
  })  : _baseUrl = baseUrl ?? AppConfig.openClawBaseUrl,
        _wsUrl = wsUrl ?? AppConfig.openClawWsUrl,
        _agentId = agentId ?? AppConfig.defaultAgentId,
        _model = model ?? AppConfig.defaultModel {
    _initDio();
  }
  
  void _initDio() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 120),
      headers: {
        'Content-Type': 'application/json',
      },
    ));
  }
  
  /// 更新配置
  void updateConfig({
    String? baseUrl,
    String? wsUrl,
    String? agentId,
    String? model,
  }) {
    if (baseUrl != null) _baseUrl = baseUrl;
    if (wsUrl != null) _wsUrl = wsUrl;
    if (agentId != null) _agentId = agentId;
    if (model != null) _model = model;
    _initDio();
  }
  
  /// 获取请求参数
  Map<String, dynamic> _buildParams([String? message]) {
    final params = <String, dynamic>{
      'channel': AppConfig.channelName,
    };
    
    if (message != null) {
      params['message'] = message;
    }
    
    // 添加 agentId (非默认才传)
    if (_agentId.isNotEmpty && _agentId != AppConfig.defaultAgentId) {
      params['agentId'] = _agentId;
    }
    
    // 添加 model (非空才传)
    if (_model.isNotEmpty) {
      params['model'] = _model;
    }
    
    return params;
  }
  
  /// 发送消息并获取回复 (HTTP API)
  Future<String> sendMessage(String text) async {
    try {
      final response = await _dio.post(
        '/api/message',
        data: _buildParams(text),
      );
      
      final data = response.data;
      
      // 解析响应 - 支持多种格式
      return _parseReply(data);
      
    } on DioException catch (e) {
      throw OpenClawException(_handleDioError(e));
    } catch (e) {
      throw OpenClawException('解析响应失败: $e');
    }
  }
  
  /// 解析回复内容
  String _parseReply(dynamic data) {
    String reply = '';
    
    if (data is Map) {
      if (data.containsKey('reply')) {
        reply = data['reply'] ?? '';
      } else if (data.containsKey('message')) {
        final msg = data['message'];
        reply = msg is Map ? msg['content'] ?? msg.toString() : msg.toString();
      } else if (data.containsKey('content')) {
        reply = data['content'] ?? '';
      } else if (data.containsKey('choices')) {
        final choices = data['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final firstChoice = choices.first;
          if (firstChoice is Map) {
            final msg = firstChoice['message'] ?? firstChoice;
            reply = msg['content'] ?? msg.toString();
          } else {
            reply = firstChoice.toString();
          }
        }
      } else {
        reply = data.toString();
      }
    } else if (data is String) {
      reply = data;
    } else {
      reply = data.toString();
    }
    
    return reply;
  }
  
  /// 处理 Dio 错误
  String _handleDioError(DioException e) {
    if (e.response != null) {
      final errorData = e.response!.data;
      final errorMsg = errorData is Map 
          ? errorData['error'] ?? errorData['message'] ?? errorData.toString()
          : errorData?.toString() ?? '未知错误';
      return 'API 错误: $errorMsg';
    }
    
    if (e.type == DioExceptionType.connectionTimeout) {
      return '连接超时，请检查网络';
    }
    if (e.type == DioExceptionType.receiveTimeout) {
      return '响应超时，AI 可能正在思考';
    }
    if (e.type == DioExceptionType.connectionError) {
      return '无法连接服务器，请检查地址';
    }
    return '请求失败: ${e.message}';
  }
  
  /// 流式响应 (如果 API 支持)
  Stream<String> sendMessageStream(String text) async* {
    try {
      final response = await _dio.post(
        '/api/message/stream',
        data: _buildParams(text),
        options: Options(responseType: ResponseType.stream),
      );
      
      final stream = response.data as Stream<List<int>>;
      
      await for (final chunk in stream) {
        final str = utf8.decode(chunk);
        final lines = str.split('\n');
        
        for (final line in lines) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6);
            if (data == '[DONE]') return;
            
            try {
              final json = jsonDecode(data);
              final content = json['choices']?[0]?['delta']?['content'] 
                  ?? json['content'] 
                  ?? json['delta']?['content']
                  ?? '';
              if (content.isNotEmpty) {
                yield content;
              }
            } catch (_) {
              if (data.isNotEmpty && data != '[DONE]') {
                yield data;
              }
            }
          }
        }
      }
    } on DioException catch (e) {
      throw OpenClawException('流式请求失败: ${_handleDioError(e)}');
    }
  }
  
  /// 连接 WebSocket (实时对话)
  Future<void> connectWebSocket() async {
    try {
      _wsChannel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      
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
        onError: (_) => _isConnected = false,
        onDone: () => _isConnected = false,
      );
      
      _isConnected = true;
    } catch (e) {
      _isConnected = false;
      throw OpenClawException('WebSocket 连接失败: $e');
    }
  }
  
  /// 通过 WebSocket 发送消息
  void sendMessageWs(String text) {
    if (_wsChannel == null || !_isConnected) {
      throw OpenClawException('WebSocket 未连接');
    }
    
    _wsChannel!.sink.add(jsonEncode(_buildParams(text)));
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
