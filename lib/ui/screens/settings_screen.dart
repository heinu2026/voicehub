import 'package:flutter/material.dart';
import '../../services/settings_service.dart';
import '../../config/app_config.dart';

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
  final _agentIdController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _whisperUrlController = TextEditingController();
  final _whisperApiKeyController = TextEditingController();
  bool _isSaving = false;
  String _selectedVoiceId = AppConfig.ttsDefaultVoiceId;
  double _ttsSpeed = AppConfig.ttsDefaultSpeed;

  // 可用的 TTS 音色
  static const _voiceOptions = [
    {'id': 'female-shaonv', 'label': '少女音'},
    {'id': 'female-baiyang', 'label': '白羊音'},
    {'id': 'male-qn-qingse', 'label': '男青年清瑟'},
    {'id': 'male-qingse', 'label': '男声清瑟'},
    {'id': 'female-tianmei', 'label': '甜美女声'},
    {'id': 'male-kangrei', 'label': '康宁男声'},
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    _baseUrlController.text = widget.settingsService.baseUrl;
    _agentIdController.text = widget.settingsService.agentId;
    _apiKeyController.text = widget.settingsService.minimaxApiKey;
    _selectedVoiceId = widget.settingsService.ttsVoiceId;
    _ttsSpeed = widget.settingsService.ttsSpeed;
    _whisperUrlController.text = widget.settingsService.whisperUrl;
    _whisperApiKeyController.text = widget.settingsService.whisperApiKey;
  }

  Future<void> _saveSettings() async {
    // 先验证必填项
    final whisperUrl = _whisperUrlController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    if (whisperUrl.isEmpty) {
      _showValidationError('请填写 Whisper 服务器地址');
      return;
    }
    if (!whisperUrl.startsWith('http') && !whisperUrl.startsWith('ws')) {
      _showValidationError('Whisper 地址必须以 http://, https://, ws:// 或 wss:// 开头');
      return;
    }
    if (baseUrl.isEmpty) {
      _showValidationError('请填写 OpenClaw 地址');
      return;
    }
    if (!baseUrl.startsWith('http')) {
      _showValidationError('OpenClaw 地址必须以 http:// 或 https:// 开头');
      return;
    }

    setState(() => _isSaving = true);

    // 必须等 SharedPreferences 写入完成后再导出
    await widget.settingsService.setBaseUrl(baseUrl);
    await widget.settingsService.setAgentId(_agentIdController.text.trim());
    await widget.settingsService.setMinimaxApiKey(apiKey);
    await widget.settingsService.setTtsVoiceId(_selectedVoiceId);
    await widget.settingsService.setTtsSpeed(_ttsSpeed);
    await widget.settingsService.setWhisperUrl(whisperUrl);
    await widget.settingsService.setWhisperApiKey(_whisperApiKeyController.text.trim());

    // 保存后自动导出备份
    final exportPath = await widget.settingsService.exportConfig();
    debugPrint('SettingsScreen: 保存完成，whisperUrl=$whisperUrl, exportPath=$exportPath');

    setState(() => _isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(exportPath != null ? '设置已保存，正在启动...' : '设置已保存，但导出失败'),
          backgroundColor: exportPath != null ? Colors.green : Colors.orange,
        ),
      );
      Navigator.pop(context, true); // 返回 true 表示配置完成
    }
  }

  void _showValidationError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _exportConfig(BuildContext context) async {
    final path = await widget.settingsService.exportConfig();
    if (path != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('配置已导出：$path'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('导出失败'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _importConfig(BuildContext context) async {
    final ok = await widget.settingsService.importConfig();
    if (ok && context.mounted) {
      _loadSettings(); // 重新加载界面值
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('配置已导入，请检查并重新保存'),
          backgroundColor: Colors.green,
        ),
      );
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('未找到配置文件或导入失败'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _agentIdController.dispose();
    _apiKeyController.dispose();
    _whisperUrlController.dispose();
    _whisperApiKeyController.dispose();
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
            // MiniMax TTS 配置
            _buildSectionTitle('🔊 语音合成 (MiniMax TTS)'),
            const SizedBox(height: 8),
            Text(
              '用于 AI 回复的语音播报',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _apiKeyController,
              decoration: _inputDecoration(
                label: 'MiniMax API Key',
                hint: '输入你的 MiniMax API Key',
                icon: Icons.key,
              ),
              obscureText: true,
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              value: _selectedVoiceId,
              decoration: _inputDecoration(
                label: '音色',
                hint: '选择语音音色',
                icon: Icons.record_voice_over,
              ),
              items: _voiceOptions.map((v) {
                return DropdownMenuItem(value: v['id'], child: Text(v['label']!));
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedVoiceId = val);
              },
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                const Icon(Icons.speed, color: Colors.grey),
                const SizedBox(width: 12),
                const Text('语速:', style: TextStyle(fontSize: 16)),
                Expanded(
                  child: Slider(
                    value: _ttsSpeed,
                    min: 0.5,
                    max: 2.0,
                    divisions: 15,
                    label: _ttsSpeed.toStringAsFixed(1),
                    onChanged: (val) => setState(() => _ttsSpeed = val),
                  ),
                ),
                Text(
                  _ttsSpeed.toStringAsFixed(1),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Whisper STT 配置
            _buildSectionTitle('🎤 Whisper STT'),
            const SizedBox(height: 8),
            Text(
              '语音识别服务（OpenAI 兼容 API）',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _whisperUrlController,
              decoration: _inputDecoration(
                label: 'Whisper 服务器地址',
                hint: 'http://192.168.1.x:9001',
                icon: Icons.mic,
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _whisperApiKeyController,
              decoration: _inputDecoration(
                label: 'API Key（可选）',
                hint: '有认证时填写',
                icon: Icons.key,
              ),
              obscureText: true,
            ),

            const SizedBox(height: 32),

            // OpenClaw 地址配置
            _buildSectionTitle('🌐 OpenClaw 地址'),
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
                hint: 'http://192.168.1.x:8080',
                icon: Icons.link,
              ),
            ),

            const SizedBox(height: 32),

            // Agent 配置
            _buildSectionTitle('🤖 Agent 配置'),
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

            const SizedBox(height: 16),

            // 导出/导入配置
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _exportConfig(context),
                    icon: const Icon(Icons.upload, size: 18),
                    label: const Text('导出配置'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _importConfig(context),
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('导入配置'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 提示
            Center(
              child: Text(
                'API Key 获取: platform.minimaxi.com\n如何获取 Mac IP?\n终端运行: ifconfig | grep "inet "',
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
