import 'dart:async';
import 'package:dio/dio.dart';
import '../config/app_config.dart';

class OpenClawService {
  late Dio _dio;
  
  String _baseUrl;
  String _agentId;
  String _model;
  String _userId;
  
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  
  OpenClawService({
    String? baseUrl,
    String? agentId,
    String? model,
    String? userId,
  })  : _baseUrl = baseUrl ?? AppConfig.openClawBaseUrl,
        _agentId = agentId ?? AppConfig.defaultAgentId,
        _model = model ?? AppConfig.defaultModel,
        _userId = userId ?? '' {
    _initDio();
  }
  
  void _initDio() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 120),
      headers: {'Content-Type': 'application/json'},
    ));
  }
  
  /// 更新配置
  void updateConfig({
    String? baseUrl,
    String? agentId,
    String? model,
    String? userId,
  }) {
    if (baseUrl != null) _baseUrl = baseUrl;
    if (agentId != null) _agentId = agentId;
    if (model != null) _model = model;
    if (userId != null) _userId = userId;
    _initDio();
  }
  
  /// 更新 User ID (切换 session)
  void setUserId(String userId) {
    _userId = userId;
  }
  
  /// 构建请求参数
  Map<String, dynamic> _buildParams(String message) {
    final params = <String, dynamic>{
      'message': message,
      'channel': AppConfig.channelName,
      'user': _userId,
    };
    
    if (_agentId.isNotEmpty && _agentId != AppConfig.defaultAgentId) {
      params['agentId'] = _agentId;
    }
    
    if (_model.isNotEmpty) {
      params['model'] = _model;
    }
    
    return params;
  }
  
  /// 发送消息并获取回复
  Future<String> sendMessage(String text) async {
    try {
      _isConnected = true;
      final response = await _dio.post(
        '/api/message',
        data: _buildParams(text),
      );
      
      return _parseReply(response.data);
      
    } on DioException catch (e) {
      _isConnected = false;
      throw OpenClawException(_handleDioError(e));
    } catch (e) {
      _isConnected = false;
      throw OpenClawException('解析响应失败: $e');
    }
  }
  
  /// 解析回复内容
  String _parseReply(dynamic data) {
    if (data is Map) {
      if (data.containsKey('reply')) return data['reply'] ?? '';
      if (data.containsKey('message')) {
        final msg = data['message'];
        return msg is Map ? msg['content'] ?? msg.toString() : msg.toString();
      }
      if (data.containsKey('content')) return data['content'] ?? '';
      if (data.containsKey('choices')) {
        final choices = data['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final firstChoice = choices.first;
          if (firstChoice is Map) {
            final msg = firstChoice['message'] ?? firstChoice;
            return msg['content'] ?? msg.toString();
          }
          return firstChoice.toString();
        }
      }
      return data.toString();
    } else if (data is String) {
      return data;
    }
    return data.toString();
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
    
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return '连接超时，请检查网络';
      case DioExceptionType.receiveTimeout:
        return '响应超时，AI 可能正在思考';
      case DioExceptionType.connectionError:
        return '无法连接服务器，请检查地址';
      default:
        return '请求失败: ${e.message}';
    }
  }
  
  void dispose() {
    _isConnected = false;
    _dio.close();
  }
}

class OpenClawException implements Exception {
  final String message;
  OpenClawException(this.message);
  
  @override
  String toString() => message;
}
