import 'package:equatable/equatable.dart';
import '../../models/message.dart';

enum ChatStatus {
  idle,             // 空闲（回到唤醒词监听）
  listening,        // 正在听语音（唤醒词触发后 or Listening Window）
  processing,       // 处理中（AI 思考）
  speaking,         // 正在播放 TTS
  listeningWindow,   // Listening Window：AI 回复后，等待追问
  configRequired,   // 等待配置
  error,            // 错误
}

class ChatState extends Equatable {
  final List<Message> messages;
  final ChatStatus status;
  final String? errorMessage;
  final bool isVoiceInputActive;
  final double voiceLevel;
  final bool isWakeWordEnabled;
  final bool isWakeWordReady;
  final bool isWakeWordListening;
  final String partialText;

  const ChatState({
    this.messages = const [],
    this.status = ChatStatus.idle,
    this.errorMessage,
    this.isVoiceInputActive = false,
    this.voiceLevel = 0,
    this.isWakeWordEnabled = false,
    this.isWakeWordReady = false,
    this.isWakeWordListening = false,
    this.partialText = '',
  });

  ChatState copyWith({
    List<Message>? messages,
    ChatStatus? status,
    String? errorMessage,
    bool? isVoiceInputActive,
    double? voiceLevel,
    bool? isWakeWordEnabled,
    bool? isWakeWordReady,
    bool? isWakeWordListening,
    String? partialText,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      status: status ?? this.status,
      errorMessage: errorMessage,
      isVoiceInputActive: isVoiceInputActive ?? this.isVoiceInputActive,
      voiceLevel: voiceLevel ?? this.voiceLevel,
      isWakeWordEnabled: isWakeWordEnabled ?? this.isWakeWordEnabled,
      isWakeWordReady: isWakeWordReady ?? this.isWakeWordReady,
      isWakeWordListening: isWakeWordListening ?? this.isWakeWordListening,
      partialText: partialText ?? this.partialText,
    );
  }

  @override
  List<Object?> get props => [
    messages,
    status,
    errorMessage,
    isVoiceInputActive,
    voiceLevel,
    isWakeWordEnabled,
    isWakeWordReady,
    isWakeWordListening,
    partialText,
  ];
}
