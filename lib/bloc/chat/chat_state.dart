import 'package:equatable/equatable.dart';
import '../../models/message.dart';

enum ChatStatus {
  idle,           // 空闲
  listening,      // 正在听语音
  processing,     // 处理中
  speaking,       // 正在播放 TTS
  error,          // 错误
}

class ChatState extends Equatable {
  final List<Message> messages;
  final ChatStatus status;
  final String? errorMessage;
  final bool isVoiceInputActive;  // 语音输入激活
  final double voiceLevel;        // 语音音量 (0-1)
  
  const ChatState({
    this.messages = const [],
    this.status = ChatStatus.idle,
    this.errorMessage,
    this.isVoiceInputActive = false,
    this.voiceLevel = 0,
  });
  
  ChatState copyWith({
    List<Message>? messages,
    ChatStatus? status,
    String? errorMessage,
    bool? isVoiceInputActive,
    double? voiceLevel,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      status: status ?? this.status,
      errorMessage: errorMessage,
      isVoiceInputActive: isVoiceInputActive ?? this.isVoiceInputActive,
      voiceLevel: voiceLevel ?? this.voiceLevel,
    );
  }
  
  @override
  List<Object?> get props => [
    messages,
    status,
    errorMessage,
    isVoiceInputActive,
    voiceLevel,
  ];
}
