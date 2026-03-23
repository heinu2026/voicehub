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

  /// SSE 流式响应控制器
  StreamController<String>? _streamController;
  CancelToken? _currentCancelToken;

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

  void setUserId(String userId) {
    _userId = userId;
  }

  /// 发送消息并获取回复（非流式）
  Future<String> sendMessage(String text) async {
    try {
      _isConnected = true;
      final modelStr =
          _agentId.isNotEmpty ? 'openclaw:$_agentId' : 'openclaw';

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

  /// 发送消息并获取流式回复（SSE）
  ///
  /// 返回 text chunks 的 Stream，每个 chunk 是 AI 回复的文本片段。
  /// 可用于边生成边 TTS 播放，实现 Siri 级延迟。
  Stream<String> sendMessageStream(String text) {
    _streamController?.close();
    _streamController = StreamController<String>.broadcast();
    _currentCancelToken?.cancel();
    _currentCancelToken = CancelToken();

    _fetchStreamingResponse(text);

    return _streamController!.stream;
  }

  Future<void> _fetchStreamingResponse(String text) async {
    try {
      _isConnected = true;
      final modelStr =
          _agentId.isNotEmpty ? 'openclaw:$_agentId' : 'openclaw';

      final response = await _dio.post<ResponseBody>(
        '/v1/responses',
        data: {
          'model': modelStr,
          'input': text,
          if (_userId.isNotEmpty) 'user': _userId,
        },
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Accept': 'text/event-stream',
            if (_authToken.isNotEmpty)
              'Authorization': 'Bearer $_authToken',
          },
        ),
        cancelToken: _currentCancelToken,
      );

      final stream = response.data!.stream;
      String buffer = '';

      await for (final chunk in stream) {
        if (_streamController == null || _streamController!.isClosed) break;

        buffer += String.fromCharCodes(chunk);

        while (buffer.contains('\n')) {
          final lineEnd = buffer.indexOf('\n');
          final line = buffer.substring(0, lineEnd).trim();
          buffer = buffer.substring(lineEnd + 1);

          if (line.startsWith('data: ')) {
            final data = line.substring(6);

            if (data == '[DONE]') {
              _streamController?.close();
              return;
            }

            final parsed = _parseSseChunk(data);
            if (parsed != null && parsed.isNotEmpty) {
              if (!_streamController!.isClosed) {
                _streamController!.add(parsed);
              }
            }
          }
        }
      }

      _streamController?.close();
    } on DioException catch (e) {
      _isConnected = false;
      if (!_streamController!.isClosed) {
        _streamController!.addError(OpenClawException(_handleDioError(e)));
        _streamController!.close();
      }
    } catch (e) {
      _isConnected = false;
      if (!_streamController!.isClosed) {
        _streamController!.addError(OpenClawException('流式响应失败: $e'));
        _streamController!.close();
      }
    }
  }

  /// 解析 SSE data chunk，提取文本内容
  String? _parseSseChunk(String data) {
    try {
      if (data.startsWith('{')) {
        // JSON: {"type": "content_delta", "content": "..."}
        final contentMatch =
            RegExp(r'"content":\s*"([^"]*)"').firstMatch(data);
        if (contentMatch != null) return _unescapeJson(contentMatch.group(1)!);

        final deltaMatch =
            RegExp(r'"content_delta":\s*"([^"]*)"').firstMatch(data);
        if (deltaMatch != null) return _unescapeJson(deltaMatch.group(1)!);

        final textMatch = RegExp(r'"text":\s*"([^"]*)"').firstMatch(data);
        if (textMatch != null) return _unescapeJson(textMatch.group(1)!);

        final textDeltaMatch =
            RegExp(r'"text_delta":\s*"([^"]*)"').firstMatch(data);
        if (textDeltaMatch != null)
          return _unescapeJson(textDeltaMatch.group(1)!);
      } else if (!data.startsWith('{')) {
        // 纯文本片段
        return data;
      }
    } catch (_) {}
    return null;
  }

  /// JSON 字符串转义还原
  String _unescapeJson(String s) {
    return s
        .replaceAll(r'\"', '"')
        .replaceAll(r'\\', '\\')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\t', '\t');
  }

  /// 取消当前流式请求
  void cancelStream() {
    _currentCancelToken?.cancel();
    _streamController?.close();
  }

  String _parseReply(dynamic data) {
    if (data is Map) {
      if (data.containsKey('output')) {
        final output = data['output'] as List?;
        if (output != null && output.isNotEmpty) {
          for (final item in output) {
            if (item is Map) {
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
              if (item['type'] == 'reasoning') {
                final text =
                    item['content'] ?? item['text'] ?? item['summary'];
                if (text is String && text.isNotEmpty) return text;
              }
            }
            if (item is String) return item;
          }
        }
      }
      if (data.containsKey('reply')) return data['reply'] ?? '';
      if (data.containsKey('content')) return data['content'] ?? '';
      return data.toString();
    } else if (data is String) {
      return data;
    }
    return data.toString();
  }

  String _handleDioError(DioException e) {
    if (e.response != null) {
      final errorData = e.response!.data;
      final errorMsg = errorData is Map
          ? errorData['error'] ??
              errorData['message'] ??
              errorData.toString()
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
    _streamController?.close();
    _currentCancelToken?.cancel();
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
