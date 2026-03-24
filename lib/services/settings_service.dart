import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../config/app_config.dart';

/// 设置服务 - 管理应用配置
/// 支持导出/导入配置文件，重装后可以恢复
class SettingsService {
  // Keys
  static const String _keyBaseUrl = 'openclaw_base_url';
  static const String _keyAgentId = 'openclaw_agent_id';
  static const String _keyUserId = 'openclaw_user_id';
  static const String _keyMinimaxApiKey = 'minimax_api_key';
  static const String _keyTtsVoiceId = 'tts_voice_id';
  static const String _keyTtsSpeed = 'tts_speed';
  static const String _keyWhisperUrl = 'whisper_url';
  static const String _keyWhisperApiKey = 'whisper_api_key';
  static const String _keyWhisperModel = 'whisper_model';
  static const String _keyListeningWindowDuration = 'listening_window_duration';

  SharedPreferences? _prefs;
  final _uuid = const Uuid();

  /// 配置文件路径（存放在应用私有目录，重装会丢失）
  String? _configFilePath;

  /// 初始化
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    // 尝试自动导入已存在的配置文件
    await _tryAutoImport();
  }

  /// 获取配置文件的路径（Downloads 目录，重装后保留）
  Future<String> get configFilePath async {
    if (_configFilePath != null) return _configFilePath!;
    try {
      // 使用 Downloads 目录，重装后不会被删除
      final dir = await getExternalStorageDirectory();
      if (dir != null) {
        // 使用实际目录路径，不要硬编码
        _configFilePath = '${dir.path}/voiceclaw_config.json';
      } else {
        // fallback 到应用文档目录
        final fallback = await getApplicationDocumentsDirectory();
        _configFilePath = '${fallback.path}/voiceclaw_config.json';
      }
    } catch (e) {
      // 最后 fallback 到应用文档目录
      final fallback = await getApplicationDocumentsDirectory();
      _configFilePath = '${fallback.path}/voiceclaw_config.json';
    }
    return _configFilePath!;
  }

  /// 导出配置到文件
  Future<String?> exportConfig() async {
    try {
      final path = await configFilePath;
      final config = {
        'version': 1,
        'baseUrl': baseUrl,
        'agentId': agentId,
        'userId': userId,
        'minimaxApiKey': minimaxApiKey,
        'ttsVoiceId': ttsVoiceId,
        'ttsSpeed': ttsSpeed,
        'whisperUrl': whisperUrl,
        'whisperApiKey': whisperApiKey,
        'whisperModel': whisperModel,
      };
      final file = File(path);
      await file.writeAsString(jsonEncode(config), flush: true);
      debugPrint('SettingsService: 配置已导出到 $path, whisperUrl=$whisperUrl');
      return path;
    } catch (e, st) {
      debugPrint('SettingsService: 导出失败 $e $st');
      return null;
    }
  }

  /// 从文件导入配置
  Future<bool> importConfig() async {
    try {
      final path = await configFilePath;
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('SettingsService: 配置文件不存在');
        return false;
      }
      final content = await file.readAsString();
      final config = jsonDecode(content) as Map<String, dynamic>;

      await setBaseUrl(config['baseUrl'] ?? '');
      await setAgentId(config['agentId'] ?? '');
      // userId: 旧版配置可能没有，有则用之，空则生成新的
      final importedUserId = config['userId'];
      await _prefs?.setString(_keyUserId, (importedUserId != null && importedUserId.toString().isNotEmpty) ? importedUserId.toString() : _uuid.v4());
      await setMinimaxApiKey(config['minimaxApiKey'] ?? '');
      await setTtsVoiceId(config['ttsVoiceId'] ?? AppConfig.ttsDefaultVoiceId);
      await setTtsSpeed((config['ttsSpeed'] ?? 1.0).toDouble());
      await setWhisperUrl(config['whisperUrl'] ?? '');
      await setWhisperApiKey(config['whisperApiKey'] ?? '');
      await setWhisperModel(config['whisperModel'] ?? AppConfig.defaultWhisperModel);

      debugPrint('SettingsService: 配置导入成功');
      return true;
    } catch (e) {
      debugPrint('SettingsService: 导入失败 $e');
      return false;
    }
  }

  /// 启动时自动尝试导入
  Future<void> _tryAutoImport() async {
    try {
      final path = await configFilePath;
      final file = File(path);
      final exists = await file.exists();
      debugPrint('SettingsService: 检查配置文件 $path, 存在=$exists');
      if (exists) {
        debugPrint('SettingsService: 发现配置文件，自动导入');
        final ok = await importConfig();
        debugPrint('SettingsService: 导入结果=$ok, whisperUrl=${whisperUrl}');
      } else {
        debugPrint('SettingsService: 配置文件不存在');
      }
    } catch (e, st) {
      debugPrint('SettingsService: 自动导入失败 $e $st');
    }
  }

  /// 获取导出文件路径（供外部分享）
  Future<String?> getExportPath() async {
    try {
      final path = await configFilePath;
      if (await File(path).exists()) {
        return path;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
  
  // ========== URL 配置 ==========
  
  String get baseUrl => _prefs?.getString(_keyBaseUrl) ?? AppConfig.defaultBaseUrl;
  
  Future<bool> setBaseUrl(String url) async {
    return await _prefs?.setString(_keyBaseUrl, url) ?? false;
  }
  
  // ========== Agent 配置 ==========
  
  String get agentId => _prefs?.getString(_keyAgentId) ?? AppConfig.defaultAgentId;
  
  Future<bool> setAgentId(String agentId) async {
    return await _prefs?.setString(_keyAgentId, agentId) ?? false;
  }
  
  
  // ========== Session / User 配置 ==========
  
  /// 获取 User ID (用于 session 保持)
  /// 首次生成，后续复用
  String get userId {
    var id = _prefs?.getString(_keyUserId);
    if (id == null || id.isEmpty) {
      id = _uuid.v4();
      _prefs?.setString(_keyUserId, id);
    }
    return id;
  }
  
  /// 生成新的 User ID (开启新 session)
  Future<String> newSession() async {
    final newId = _uuid.v4();
    await _prefs?.setString(_keyUserId, newId);
    return newId;
  }
  
  // ========== Minimax TTS 配置 ==========

  String get minimaxApiKey => _prefs?.getString(_keyMinimaxApiKey) ?? '';
  String get ttsVoiceId => _prefs?.getString(_keyTtsVoiceId) ?? AppConfig.ttsDefaultVoiceId;
  double get ttsSpeed => _prefs?.getDouble(_keyTtsSpeed) ?? AppConfig.ttsDefaultSpeed;

  Future<bool> setMinimaxApiKey(String key) async {
    return await _prefs?.setString(_keyMinimaxApiKey, key) ?? false;
  }

  Future<bool> setTtsVoiceId(String voiceId) async {
    return await _prefs?.setString(_keyTtsVoiceId, voiceId) ?? false;
  }

  Future<bool> setTtsSpeed(double speed) async {
    return await _prefs?.setDouble(_keyTtsSpeed, speed) ?? false;
  }

  // ========== Whisper STT 配置 ==========

  String get whisperApiKey => _prefs?.getString(_keyWhisperApiKey) ?? AppConfig.defaultWhisperApiKey;
  String get whisperModel => _prefs?.getString(_keyWhisperModel) ?? AppConfig.defaultWhisperModel;

  Future<bool> setWhisperUrl(String url) async {
    return await _prefs?.setString(_keyWhisperUrl, url) ?? false;
  }

  Future<bool> setWhisperApiKey(String key) async {
    return await _prefs?.setString(_keyWhisperApiKey, key) ?? false;
  }

  Future<bool> setWhisperModel(String model) async {
    return await _prefs?.setString(_keyWhisperModel, model) ?? false;
  }

  // ========== 工具 ==========
  
  bool get isConfigured {
    final url = baseUrl;
    return url != AppConfig.defaultBaseUrl && url.isNotEmpty && !url.contains('192.168.1.x');
  }

  /// Whisper URL - 必须显式配置（HTTP URL，用户在设置中填写）
  String get whisperUrl {
    return _prefs?.getString(_keyWhisperUrl) ?? '';
  }

  /// Whisper WebSocket URL（自动从 whisperUrl 转换 http:// → ws://）
  String get whisperWsUrl {
    final url = whisperUrl;
    if (url.isEmpty) return '';
    // 如果已经是 ws:// 或 wss://，直接返回
    if (url.startsWith('ws://') || url.startsWith('wss://')) return url;
    // 自动转换 http:// → ws://, https:// → wss://
    return url.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');
  }

  bool get isWhisperConfigured {
    return whisperUrl.isNotEmpty;
  }

  /// 检查 MiniMax TTS 是否已配置
  bool get isTtsConfigured {
    return minimaxApiKey.isNotEmpty;
  }

  /// 检查 OpenClaw 是否已配置
  bool get isOpenClawConfigured {
    return baseUrl.isNotEmpty && baseUrl.startsWith('http');
  }

  /// 检查所有核心配置是否完整
  bool get isAllConfigured {
    return isOpenClawConfigured;
  }

  /// 获取未配置项列表
  List<String> get missingConfigItems {
    final missing = <String>[];
    if (!isOpenClawConfigured) missing.add('OpenClaw 地址');
    return missing;
  }

  // ========== Listening Window 配置 ==========

  /// Listening Window 持续时间（秒），默认 20 秒
  int get listeningWindowDuration =>
      _prefs?.getInt(_keyListeningWindowDuration) ?? 20;

  Future<bool> setListeningWindowDuration(int seconds) async {
    return await _prefs?.setInt(_keyListeningWindowDuration, seconds) ?? false;
  }
}
