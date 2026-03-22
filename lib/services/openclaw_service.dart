import 'dart:async';
import 'package:dio/dio.dart';
import '../config/app_config.dart';

class OpenClawService {
  late Dio _dio;

  String _baseUrl;
  String _agentId;
  String _model;
  String _userId;
  String _authToken;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  OpenClawService({
    String? baseUrl,
    String? agentId,
    String? model,
    String? userId,
    String? authToken,
  })  : _baseUrl = baseUrl ?? AppConfig.openClawBaseUrl,
        _agentId = agentId ?? AppConfig.defaultAgentId,
        _model = model ?? AppConfig.defaultModel,
        _userId = userId ?? '',
        _authToken = authToken ?? '' {
    _initDio();
  }

  void _initDio() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 120),
      headers: {
        'Content-Type': 'application/json',
        if (_authToken.isNotEmpty) 'Authorization': 'Bearer $_authToken',
      },
    ));
  }

  /// 更新配置
  void updateConfig({
    String? baseUrl,
    String? agentId,
    String? model,
    String? userId,
    String? authToken,
  }) {
    if (baseUrl != null) _baseUrl = baseUrl;
    if (agentId != null) _agentId = agentId;
    if (model != null) _model = model;
    if (userId != null) _userId = userId;
    if (authToken != null) _authToken = authToken;
    _initDio();
  }

  /// 更新 User ID (切换 session)
  void setUserId(String userId) {
    _userId = userId;
  }

  /// 发送消息并获取回复
  /// 使用 OpenResponses API: POST /v1/responses
  Future<String> sendMessage(String text) async {
    try {
      _isConnected = true;

      // model 格式: openclaw:<agentId>
      final modelStr = _agentId.isNotEmpty
          ? 'openclaw:$_agentId'
          : 'openclaw';

      final response = await _dio.post(
        '/v1/responses',
        data: {
          'model': modelStr,
          'input': text,
          if (_userId.isNotEmpty) 'user': _userId,
        },
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

  /// 解析 OpenResponses API 响应
  String _parseReply(dynamic data) {
    if (data is Map) {
      // OpenResponses 格式：output 数组
      if (data.containsKey('output')) {
        final output = data['output'] as List?;
        if (output != null && output.isNotEmpty) {
          for (final item in output) {
            if (item is Map) {
              // text 输出
              if (item['type'] == 'message' || item['type'] == 'text') {
                final content = item['content'];
                if (content is List) {
                  for (final c in content) {
                    if (c is Map && c['type'] == 'output_text') {
                      return c['text'] ?? '';
                    }
                  }
                }
                final text = item['content'] ?? item['text'];
                if (text is String) return text;
              }
              // reasoning 输出（可能包含思考内容）
              if (item['type'] == 'reasoning') {
                final text = item['content'] ?? item['text'] ?? item['summary'];
                if (text is String && text.isNotEmpty) return text;
              }
            }
            if (item is String) return item;
          }
        }
      }
      // 兼容旧格式
      if (data.containsKey('reply')) return data['reply'] ?? '';
      if (data.containsKey('content')) return data['content'] ?? '';
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
