import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Whisper STT 服务（流式 WebSocket 版本）
///
/// 工作流程:
/// 1. connect() 建立 WebSocket 连接
/// 2. feedAudioData() 接收 PCM 数据，实时发送
/// 3. onResult 收到 partial 和 final 识别结果
/// 4. disconnect() 断开连接
///
/// 服务器要求:
/// - ws://<host>:<port>/stream
/// - 接收原始 PCM 二进制，发送 JSON events
///   → {"type": "partial", "text": "..."}
///   → {"type": "final", "text": "..."}
///   → {"type": "done"}
class WhisperSttService {
  WebSocketChannel? _wsChannel;

  StreamSubscription? _wsSubscription;
  StreamSubscription? _pcmSubscription;

  bool _isInitialized = false;
  bool _isListening = false;
  bool _isConnected = false;

  /// 是否在主动监听中（断开后自动重连）
  bool _shouldReconnect = false;

  /// 重连定时器
  Timer? _reconnectTimer;
  static const int _reconnectDelaySeconds = 3;
  static const int _maxReconnectAttempts = 5;
  int _reconnectAttempts = 0;

  /// WebSocket 服务器地址（不含 path）
  String _wsUrl = '';

  /// 音频分块大小（512 samples ≈ 32ms at 16kHz）
  static const int _chunkSize = 512 * 2; // 16-bit = 2 bytes

  /// partial 结果流（实时转写，显示用）
  final _partialController = StreamController<String>.broadcast();
  Stream<String> get onPartial => _partialController.stream;

  /// final 结果流（语音段结束，触发 AI 对话）
  final _resultController = StreamController<String>.broadcast();
  Stream<String> get onResult => _resultController.stream;

  /// 状态流
  final _statusController = StreamController<bool>.broadcast();
  Stream<bool> get onStatus => _statusController.stream;

  /// 连接状态
  final _connectedController = StreamController<bool>.broadcast();
  Stream<bool> get onConnected => _connectedController.stream;

  bool get isAvailable => _isInitialized;
  bool get isListening => _isListening;
  bool get isConnected => _isConnected;
  bool get isUrlConfigured => _wsUrl.isNotEmpty;

  /// 初始化
  Future<bool> init() async {
    if (_isInitialized) return true;
    _isInitialized = true;
    debugPrint('WhisperSttService: 初始化成功');
    return true;
  }

  /// 设置 WebSocket 服务器地址
  /// [url] - 例如 'ws://192.168.1.100:12017'
  void setWhisperUrl(String url) {
    // 确保不包含尾部斜杠
    _wsUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    debugPrint('WhisperSttService: WebSocket URL 设置为 $_wsUrl');
  }

  /// 设置 API Key（流式版本不需要，保留兼容）
  void setApiKey(String key) {
    debugPrint('WhisperSttService: setApiKey 调用（流式版本不需要）');
  }

  /// 设置 Whisper 模型（流式版本不需要，保留兼容）
  void setModel(String model) {
    debugPrint('WhisperSttService: setModel 调用（流式版本不需要）');
  }

  /// 文件转写（兼容旧接口，流式版本直接返回空）
  /// 使用 startListening() 开启流式识别
  Future<String> transcribe(String audioPath) async {
    debugPrint('WhisperSttService: transcribe() 在流式模式下不可用，请使用 startListening()');
    return '';
  }

  /// 连接 WebSocket 服务器
  Future<bool> connect() async {
    if (_wsUrl.isEmpty) {
      debugPrint('WhisperSttService: 未配置 WebSocket URL');
      return false;
    }

    if (_isConnected) {
      debugPrint('WhisperSttService: 已连接');
      return true;
    }

    try {
      final fullUrl = '$_wsUrl/stream';
      final uri = Uri.parse(fullUrl);
      debugPrint('WhisperSttService: 连接 WebSocket $fullUrl...');
      debugPrint('  scheme=${uri.scheme}, host=${uri.host}, port=${uri.port}');

      _wsChannel = WebSocketChannel.connect(uri);

      // 等待连接打开
      await _wsChannel!.ready;

      _isConnected = true;
      _connectedController.add(true);
      debugPrint('WhisperSttService: WebSocket 已连接');

      // 监听服务器消息
      _wsSubscription?.cancel();
      _wsSubscription = _wsChannel!.stream.listen(
        (data) => _handleWsMessage(data),
        onError: (e) {
          debugPrint('WhisperSttService: WebSocket 错误 $e');
          _isConnected = false;
          _connectedController.add(false);
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('WhisperSttService: WebSocket 连接关闭');
          _isConnected = false;
          _connectedController.add(false);
          _scheduleReconnect();
        },
      );

      _reconnectAttempts = 0; // 连接成功，重置重试计数

      // 启动 PCM 发送循环
      _startPcmSendingLoop();

      return true;
    } catch (e, st) {
      debugPrint('WhisperSttService: WebSocket 连接失败: $e');
      debugPrint('  stack: $st');
      _isConnected = false;
      _connectedController.add(false);
      return false;
    }
  }

  /// PCM 数据缓冲区（异步发送）
  final _pcmBuffer = StreamController<Uint8List>();

  /// 异步 PCM 发送任务
  void _startPcmSendingLoop() {
    _pcmSubscription?.cancel();
    _pcmSubscription = _pcmBuffer.stream.listen((pcmData) {
      if (_isConnected && _wsChannel != null) {
        try {
          _wsChannel!.sink.add(pcmData);
        } catch (e) {
          debugPrint('WhisperSttService: 发送 PCM 失败 $e');
        }
      }
    });
  }

  /// 接收 PCM 数据（由 SpeechService 调用）
  void feedAudioData(Uint8List pcmData) {
    if (!_isConnected) {
      debugPrint('WhisperSttService: WebSocket 未连接，丢弃 PCM 数据');
      return;
    }
    _pcmBuffer.add(pcmData);
  }

  /// 处理 WebSocket 消息
  void _handleWsMessage(dynamic data) {
    if (data is String) {
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final type = json['type'] as String?;
        final text = json['text'] as String? ?? '';

        switch (type) {
          case 'partial':
            // 中间结果，实时显示
            debugPrint('WhisperSttService: partial "$text"');
            _partialController.add(text);
            break;
          case 'final':
            // 最终结果，触发对话
            debugPrint('WhisperSttService: final "$text"');
            _resultController.add(text);
            break;
          case 'done':
            // 转写完成
            debugPrint('WhisperSttService: done');
            break;
          case 'error':
            debugPrint('WhisperSttService: 服务器错误 $text');
            break;
          default:
            debugPrint('WhisperSttService: 未知消息类型 $type: $text');
        }
      } catch (e) {
        debugPrint('WhisperSttService: 消息解析失败 $e');
      }
    }
  }

  /// 开始流式录音（由 SpeechService 调用）
  /// 录音逻辑在 SpeechService，这里只设置状态
  Future<void> startListening() async {
    if (!_isInitialized) {
      final ok = await init();
      if (!ok) throw Exception('WhisperSttService 初始化失败');
    }

    if (_isListening) return;

    // 允许自动重连
    _shouldReconnect = true;

    // 先确保已连接
    if (!_isConnected) {
      final ok = await connect();
      if (!ok) throw Exception('WebSocket 连接失败');
    }

    _isListening = true;
    _statusController.add(true);
    debugPrint('WhisperSttService: 开始接收音频数据...');
  }

  /// 停止监听
  /// 发送 stop 命令，通知服务器强制触发当前语音段转写
  Future<void> stop() async {
    if (!_isListening) return;
    _shouldReconnect = false;
    _reconnectTimer?.cancel();

    // 发送 stop 命令
    if (_isConnected && _wsChannel != null) {
      try {
        _wsChannel!.sink.add(jsonEncode({"type": "stop"}));
      } catch (_) {}
    }

    _isListening = false;
    _statusController.add(false);
    debugPrint('WhisperSttService: 停止监听');
  }

  /// 取消监听（不触发转写）
  Future<void> cancel() async {
    if (!_isListening) return;
    _shouldReconnect = false;
    _reconnectTimer?.cancel();

    // 发送 cancel（服务器可忽略）
    if (_isConnected && _wsChannel != null) {
      try {
        _wsChannel!.sink.add(jsonEncode({"type": "cancel"}));
      } catch (_) {}
    }

    _isListening = false;
    _statusController.add(false);
    debugPrint('WhisperSttService: 取消监听');
  }

  /// 断开 WebSocket 连接
  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _pcmSubscription?.cancel();
    _pcmSubscription = null;
    _wsSubscription?.cancel();
    _wsSubscription = null;

    if (_wsChannel != null) {
      await _wsChannel!.sink.close();
      _wsChannel = null;
    }

    _isConnected = false;
    _connectedController.add(false);
  }

  /// 调度自动重连
  void _scheduleReconnect() {
    if (!_shouldReconnect) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('WhisperSttService: 重连次数已达上限 ($_maxReconnectAttempts)，放弃');
      _shouldReconnect = false;
      return;
    }
    if (_wsUrl.isEmpty) return;

    _reconnectAttempts++;
    final delay = _reconnectDelaySeconds * _reconnectAttempts; // 递增延迟

    debugPrint('WhisperSttService: $_reconnectDelaySeconds 秒后尝试重连 ($_reconnectAttempts/$_maxReconnectAttempts)...');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      _attemptReconnect();
    });
  }

  /// 执行重连
  Future<void> _attemptReconnect() async {
    if (!_shouldReconnect) return;

    debugPrint('WhisperSttService: 正在重连...');
    try {
      final ok = await connect();
      if (ok && _isListening) {
        // 重连成功后重新开始监听
        await startListening();
        debugPrint('WhisperSttService: 重连成功！');
      } else {
        _scheduleReconnect();
      }
    } catch (e) {
      debugPrint('WhisperSttService: 重连失败 $e');
      _scheduleReconnect();
    }
  }

  Future<void> dispose() async {
    await cancel();
    await disconnect();
    _pcmSubscription?.cancel();
    _pcmBuffer.close();
    _partialController.close();
    _resultController.close();
    _statusController.close();
    _connectedController.close();
    debugPrint('WhisperSttService: 已释放');
  }
}
