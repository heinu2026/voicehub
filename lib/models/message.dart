import 'package:equatable/equatable.dart';

enum MessageRole { user, assistant, system }

class Message extends Equatable {
  final String id;
  final String content;
  final MessageRole role;
  final DateTime timestamp;
  final bool isVoice;  // 是否是语音输入
  final bool isPlaying;  // TTS 是否正在播放
  
  const Message({
    required this.id,
    required this.content,
    required this.role,
    required this.timestamp,
    this.isVoice = false,
    this.isPlaying = false,
  });
  
  Message copyWith({
    String? id,
    String? content,
    MessageRole? role,
    DateTime? timestamp,
    bool? isVoice,
    bool? isPlaying,
  }) {
    return Message(
      id: id ?? this.id,
      content: content ?? this.content,
      role: role ?? this.role,
      timestamp: timestamp ?? this.timestamp,
      isVoice: isVoice ?? this.isVoice,
      isPlaying: isPlaying ?? this.isPlaying,
    );
  }
  
  @override
  List<Object?> get props => [id, content, role, timestamp, isVoice, isPlaying];
}
