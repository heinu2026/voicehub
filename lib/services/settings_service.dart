import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../core/config/app_config.dart';

/// 设置服务 - 管理应用配置
class SettingsService {
  // Keys
  static const String _keyBaseUrl = 'openclaw_base_url';
  static const String _keyWsUrl = 'openclaw_ws_url';
  static const String _keyAgentId = 'openclaw_agent_id';
  static const String _keyModel = 'openclaw_model';
  static const String _keyUserId = 'openclaw_user_id';
  
  SharedPreferences? _prefs;
  final _uuid = const Uuid();
  
  /// 初始化
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }
  
  // ========== URL 配置 ==========
  
  String get baseUrl => _prefs?.getString(_keyBaseUrl) ?? AppConfig.defaultBaseUrl;
  String get wsUrl => _prefs?.getString(_keyWsUrl) ?? AppConfig.defaultWsUrl;
  
  Future<bool> setBaseUrl(String url) async {
    return await _prefs?.setString(_keyBaseUrl, url) ?? false;
  }
  
  Future<bool> setWsUrl(String url) async {
    return await _prefs?.setString(_keyWsUrl, url) ?? false;
  }
  
  Future<void> setUrls({required String baseUrl, required String wsUrl}) async {
    await _prefs?.setString(_keyBaseUrl, baseUrl);
    await _prefs?.setString(_keyWsUrl, wsUrl);
  }
  
  // ========== Agent 配置 ==========
  
  String get agentId => _prefs?.getString(_keyAgentId) ?? AppConfig.defaultAgentId;
  String get model => _prefs?.getString(_keyModel) ?? AppConfig.defaultModel;
  
  Future<bool> setAgentId(String agentId) async {
    return await _prefs?.setString(_keyAgentId, agentId) ?? false;
  }
  
  Future<bool> setModel(String model) async {
    return await _prefs?.setString(_keyModel, model) ?? false;
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
  
  // ========== 工具 ==========
  
  bool get isConfigured {
    final url = baseUrl;
    return url != AppConfig.defaultBaseUrl && url.isNotEmpty && !url.contains('192.168.1.x');
  }
}
