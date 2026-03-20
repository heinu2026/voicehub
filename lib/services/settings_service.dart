import 'package:shared_preferences/shared_preferences.dart';

/// 设置服务 - 管理应用配置
class SettingsService {
  static const String _keyBaseUrl = 'openclaw_base_url';
  static const String _keyWsUrl = 'openclaw_ws_url';
  
  // 默认值
  static const String defaultBaseUrl = 'http://192.168.1.x:8000';
  static const String defaultWsUrl = 'ws://192.168.1.x:8000';
  
  SharedPreferences? _prefs;
  
  /// 初始化
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }
  
  /// 获取 OpenClaw Base URL
  String get baseUrl => _prefs?.getString(_keyBaseUrl) ?? defaultBaseUrl;
  
  /// 获取 OpenClaw WebSocket URL  
  String get wsUrl => _prefs?.getString(_keyWsUrl) ?? defaultWsUrl;
  
  /// 保存 OpenClaw Base URL
  Future<bool> setBaseUrl(String url) async {
    return await _prefs?.setString(_keyBaseUrl, url) ?? false;
  }
  
  /// 保存 OpenClaw WebSocket URL
  Future<bool> setWsUrl(String url) async {
    return await _prefs?.setString(_keyWsUrl, url) ?? false;
  }
  
  /// 批量保存
  Future<void> setUrls({required String baseUrl, required String wsUrl}) async {
    await _prefs?.setString(_keyBaseUrl, baseUrl);
    await _prefs?.setString(_keyWsUrl, wsUrl);
  }
  
  /// 检查是否已配置
  bool get isConfigured {
    final url = baseUrl;
    return url != defaultBaseUrl && url.isNotEmpty && !url.contains('192.168.1.x');
  }
}
