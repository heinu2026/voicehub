import 'package:flutter/material.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsService settingsService;
  
  const SettingsScreen({
    super.key,
    required this.settingsService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _baseUrlController = TextEditingController();
  final _wsUrlController = TextEditingController();
  final _agentIdController = TextEditingController();
  final _modelController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    _baseUrlController.text = widget.settingsService.baseUrl;
    _wsUrlController.text = widget.settingsService.wsUrl;
    _agentIdController.text = widget.settingsService.agentId;
    _modelController.text = widget.settingsService.model;
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    
    // 保存 URL 配置
    await widget.settingsService.setUrls(
      baseUrl: _baseUrlController.text.trim(),
      wsUrl: _wsUrlController.text.trim(),
    );
    
    // 保存 Agent 配置
    await widget.settingsService.setAgentId(_agentIdController.text.trim());
    await widget.settingsService.setModel(_modelController.text.trim());
    
    setState(() => _isSaving = false);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('设置已保存'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _wsUrlController.dispose();
    _agentIdController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // OpenClaw 地址配置
            _buildSectionTitle('OpenClaw 地址'),
            const SizedBox(height: 8),
            Text(
              '确保手机和电脑在同一网络',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _baseUrlController,
              decoration: _inputDecoration(
                label: 'HTTP 地址',
                hint: 'http://192.168.1.x:8000',
                icon: Icons.link,
              ),
            ),
            const SizedBox(height: 12),
            
            TextField(
              controller: _wsUrlController,
              decoration: _inputDecoration(
                label: 'WebSocket 地址',
                hint: 'ws://192.168.1.x:8000',
                icon: Icons.sync_alt,
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Agent 配置
            _buildSectionTitle('Agent 配置'),
            const SizedBox(height: 8),
            Text(
              '可选，留空使用默认 Agent',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _agentIdController,
              decoration: _inputDecoration(
                label: 'Agent ID',
                hint: 'main',
                icon: Icons.smart_toy,
              ),
            ),
            const SizedBox(height: 12),
            
            TextField(
              controller: _modelController,
              decoration: _inputDecoration(
                label: 'Model (可选)',
                hint: '如: gpt-4o',
                icon: Icons.model_training,
              ),
            ),
            
            const SizedBox(height: 32),
            
            // 保存按钮
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('保存', style: TextStyle(fontSize: 16)),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // 提示
            Center(
              child: Text(
                '如何获取 Mac IP?\n终端运行: ifconfig | grep "inet "',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }
  
  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}
