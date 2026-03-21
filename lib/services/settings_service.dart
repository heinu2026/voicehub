import 'package:shared_preferences/shared_preferences.dart';
import '../core/config/app_config.dart';

/// 设置服务 - 管理应用配置
class SettingsService {
  // Keys
  static const String _keyBaseUrl = 'openclaw_base_url';
  static const String _keyWsUrl = 'openclaw_ws_url';
  static const String _keyAgentId = 'openclaw_agent_id';
  static const String _keyModel = 'openclaw_model';
  
  SharedPreferences? _prefs;
  
  /// 初始化
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }
  
  // ========== URL 配置 ==========
  
  /// 获取 OpenClaw Base URL
  String get baseUrl => _prefs?.getString(_keyBaseUrl) ?? AppConfig.defaultBaseUrl;
  
  /// 获取 OpenClaw WebSocket URL  
  String get wsUrl => _prefs?.getString(_keyWsUrl) ?? AppConfig.defaultWsUrl;
  
  /// 保存 OpenClaw Base URL
  Future<bool> setBaseUrl(String url) async {
    return await _prefs?.setString(_keyBaseUrl, url) ?? false;
  }
  
  /// 保存 OpenClaw WebSocket URL
  Future<bool> setWsUrl(String url) async {
    return await _prefs?.setString(_keyWsUrl, url) ?? false;
  }
  
  /// 批量保存 URL
  Future<void> setUrls({required String baseUrl, required String wsUrl}) async {
    await _prefs?.setString(_keyBaseUrl, baseUrl);
    await _prefs?.setString(_keyWsUrl, wsUrl);
  }
  
  // ========== Agent 配置 ==========
  
  /// 获取 Agent ID
  String get agentId => _prefs?.getString(_keyAgentId) ?? AppConfig.defaultAgentId;
  
  /// 获取 Model
  String get model => _prefs?.getString(_keyModel) ?? AppConfig.defaultModel;
  
  /// 保存 Agent ID
  Future<bool> setAgentId(String agentId) async {
    return await _prefs?.setString(_keyAgentId, agentId) ?? false;
  }
  
  /// 保存 Model
  Future<bool> setModel(String model) async {
    return await _prefs?.setString(_keyModel, model) ?? false;
  }
  
  // ========== 工具 ==========
  
  /// 检查是否已配置
  bool get isConfigured {
    final url = baseUrl;
    return url != AppConfig.defaultBaseUrl && url.isNotEmpty && !url.contains('192.168.1.x');
  }
  
  /// 获取完整的 API 请求参数
  Map<String, dynamic> get apiParams {
    final params = <String, dynamic>{
      'channel': AppConfig.channelName,
    };
    
    // 添加 agentId (非默认才传)
    if (agentId.isNotEmpty && agentId != AppConfig.defaultAgentId) {
      params['agentId'] = agentId;
    }
    
    // 添加 model (非空才传)
    if (model.isNotEmpty) {
      params['model'] = model;
    }
    
    return params;
  }
}
