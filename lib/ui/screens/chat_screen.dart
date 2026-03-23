import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/chat/chat_bloc.dart';
import '../../bloc/chat/chat_event.dart';
import '../../bloc/chat/chat_state.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VoiceClaw'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment),
            tooltip: '新会话',
            onPressed: () => _showNewSessionDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          // 状态栏
          BlocBuilder<ChatBloc, ChatState>(
            builder: (context, state) => _buildStatusBar(context, state),
          ),

          // 对话列表
          Expanded(
            child: BlocBuilder<ChatBloc, ChatState>(
              builder: (context, state) {
                if (state.messages.isEmpty) {
                  return _buildEmptyState(context, state);
                }

                return Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        itemCount: state.messages.length,
                        itemBuilder: (context, index) {
                          final message = state.messages[index];
                          return MessageBubble(message: message);
                        },
                      ),
                    ),
                    // 空闲时显示"开始说话"按钮
                    if (state.status == ChatStatus.idle)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              context.read<ChatBloc>().add(StartListening());
                            },
                            icon: const Icon(Icons.mic),
                            label: const Text('开始说话'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ChatState state) {
    // 配置不完整时显示引导页
    if (state.status == ChatStatus.configRequired) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.settings_input_antenna, size: 80, color: AppTheme.primaryColor.withOpacity(0.5)),
              const SizedBox(height: 24),
              Text(
                '请先完成配置',
                style: TextStyle(fontSize: 22, color: Colors.white.withOpacity(0.9)),
              ),
              const SizedBox(height: 12),
              Text(
                state.errorMessage ?? '配置不完整',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.6)),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () async {
                  // 跳转到设置页
                  await Navigator.pushNamed(context, '/settings');
                  // 返回后直接开始聆听
                  if (context.mounted) {
                    context.read<ChatBloc>().add(StartListening());
                  }
                },
                icon: const Icon(Icons.settings),
                label: const Text('去设置'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    String hint;
    IconData icon;

    switch (state.status) {
      case ChatStatus.listening:
        hint = '正在聆听...\n说完话等 3 秒自动识别';
        icon = Icons.mic;
        break;
      case ChatStatus.processing:
        hint = '思考中...';
        icon = Icons.psychology;
        break;
      case ChatStatus.speaking:
        hint = '播放语音...';
        icon = Icons.volume_up;
        break;
      case ChatStatus.idle:
        hint = '正在连接...';
        icon = Icons.hourglass_empty;
        break;
      default:
        hint = '初始化中...';
        icon = Icons.mic_off;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: AppTheme.primaryColor.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(
            '你好！我是 VoiceClaw',
            style: TextStyle(fontSize: 20, color: Colors.white.withOpacity(0.8)),
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context, ChatState state) {
    String statusText;
    Color statusColor;
    bool showSpinner = false;

    switch (state.status) {
      case ChatStatus.idle:
        statusText = '● 等待连接';
        statusColor = Colors.grey;
        break;
      case ChatStatus.listening:
        statusText = '🎤 聆听中（说完等 3 秒）';
        statusColor = AppTheme.successColor;
        break;
      case ChatStatus.processing:
        statusText = '⏳ AI 思考中...';
        statusColor = AppTheme.secondaryColor;
        showSpinner = true;
        break;
      case ChatStatus.speaking:
        statusText = '🔊 播放语音...';
        statusColor = AppTheme.primaryColor;
        break;
      case ChatStatus.configRequired:
        statusText = '⚠️ 请先配置';
        statusColor = Colors.orange;
        break;
      case ChatStatus.error:
        statusText = '❌ ${state.errorMessage ?? "错误"}';
        statusColor = AppTheme.errorColor;
        break;
    }

    // 唤醒词状态指示
    String? wakeWordHint;
    if (state.isWakeWordReady && state.isWakeWordEnabled) {
      wakeWordHint = ' 🪄 唤醒词已开启';
    } else if (!state.isWakeWordReady) {
      wakeWordHint = ' ⚠️ 唤醒词未配置';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: statusColor.withOpacity(0.2),
      child: Row(
        children: [
          if (showSpinner)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          else
            const SizedBox(width: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(statusText, style: TextStyle(color: statusColor, fontSize: 14)),
                if (wakeWordHint != null)
                  Text(
                    wakeWordHint,
                    style: TextStyle(
                      color: statusColor.withOpacity(0.7),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          // 唤醒词切换按钮
          if (state.isWakeWordReady)
            IconButton(
              icon: Icon(
                state.isWakeWordEnabled ? Icons.toggle_on : Icons.toggle_off,
                color: state.isWakeWordEnabled ? AppTheme.successColor : Colors.grey,
              ),
              onPressed: () {
                context.read<ChatBloc>().add(ToggleWakeWord());
              },
              tooltip: state.isWakeWordEnabled ? '关闭唤醒词' : '开启唤醒词',
            ),
        ],
      ),
    );
  }

  void _showNewSessionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新会话'),
        content: const Text('开启新会话将清空当前对话记录。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              final newUserId = await globalSettingsService?.newSession() ?? '';
              if (context.mounted) {
                context.read<ChatBloc>().add(NewSession(newUserId));
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('开启新会话'),
          ),
        ],
      ),
    );
  }
}
