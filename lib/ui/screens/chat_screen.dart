import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../bloc/chat/chat_bloc.dart';
import '../../bloc/chat/chat_event.dart';
import '../../bloc/chat/chat_state.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/message_bubble.dart';
import '../widgets/voice_button.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VoiceHub'),
        actions: [
          // 新会话按钮
          IconButton(
            icon: const Icon(Icons.add_comment),
            tooltip: '新会话',
            onPressed: () {
              _showNewSessionDialog(context);
            },
          ),
          // 设置按钮
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.pushNamed(context, '/settings');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 对话列表
          Expanded(
            child: BlocBuilder<ChatBloc, ChatState>(
              builder: (context, state) {
                if (state.messages.isEmpty) {
                  return _buildEmptyState();
                }
                
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  reverse: false,
                  itemCount: state.messages.length,
                  itemBuilder: (context, index) {
                    final message = state.messages[index];
                    return MessageBubble(message: message);
                  },
                );
              },
            ),
          ),
          
          // 状态指示
          BlocBuilder<ChatBloc, ChatState>(
            builder: (context, state) {
              return _buildStatusBar(state);
            },
          ),
          
          // 底部控制栏
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // 文字输入框
                  BlocBuilder<ChatBloc, ChatState>(
                    builder: (context, state) {
                      return TextField(
                        decoration: InputDecoration(
                          hintText: '输入消息...',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.send),
                            onPressed: () {
                              // TODO: 发送文字
                            },
                          ),
                        ),
                        onSubmitted: (text) {
                          if (text.trim().isNotEmpty) {
                            context.read<ChatBloc>().add(SendTextMessage(text));
                          }
                        },
                      );
                    },
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // 语音按钮
                  BlocBuilder<ChatBloc, ChatState>(
                    builder: (context, state) {
                      return Column(
                        children: [
                          VoiceButton(
                            isListening: state.status == ChatStatus.listening,
                            voiceLevel: state.voiceLevel,
                            onPressed: () {
                              if (state.status == ChatStatus.listening) {
                                context.read<ChatBloc>().add(StopVoiceInput());
                              } else {
                                context.read<ChatBloc>().add(StartVoiceInput());
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            state.status == ChatStatus.listening
                                ? '正在聆听...'
                                : '按住说话',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.mic,
            size: 80,
            color: AppTheme.primaryColor.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '你好！我是 VoiceHub',
            style: TextStyle(
              fontSize: 20,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击麦克风开始对话',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatusBar(ChatState state) {
    String statusText = '';
    Color statusColor = Colors.transparent;
    
    switch (state.status) {
      case ChatStatus.idle:
        return const SizedBox.shrink();
      case ChatStatus.listening:
        statusText = '🎤 正在聆听...';
        statusColor = AppTheme.successColor;
        break;
      case ChatStatus.processing:
        statusText = '⏳ 思考中...';
        statusColor = AppTheme.secondaryColor;
        break;
      case ChatStatus.speaking:
        statusText = '🔊 播放语音...';
        statusColor = AppTheme.primaryColor;
        break;
      case ChatStatus.error:
        statusText = '❌ ${state.errorMessage ?? "错误"}';
        statusColor = AppTheme.errorColor;
        break;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: statusColor.withOpacity(0.2),
      child: Row(
        children: [
          if (state.status == ChatStatus.processing)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
          if (state.status != ChatStatus.processing)
            const SizedBox(width: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 14,
              ),
            ),
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
        content: const Text(
          '开启新会话将：\n'
          '• 清空当前对话记录\n'
          '• 开始全新的对话\n'
          '• 保留所有设置',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              // 生成新的 userId
              final newUserId = await globalSettingsService?.newSession() ?? '';
              
              if (context.mounted) {
                context.read<ChatBloc>().add(NewSession(newUserId));
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已开启新会话')),
                );
              }
            },
            child: const Text('开启新会话'),
          ),
        ],
      ),
    );
  }
}
