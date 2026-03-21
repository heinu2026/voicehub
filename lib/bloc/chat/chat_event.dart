import 'package:equatable/equatable.dart';

abstract class ChatEvent extends Equatable {
  const ChatEvent();
  
  @override
  List<Object?> get props => [];
}

/// 发送文本消息
class SendTextMessage extends ChatEvent {
  final String text;
  
  const SendTextMessage(this.text);
  
  @override
  List<Object?> get props => [text];
}

/// 发送语音消息
class SendVoiceMessage extends ChatEvent {
  final String audioPath;
  
  const SendVoiceMessage(this.audioPath);
  
  @override
  List<Object?> get props => [audioPath];
}

/// 开始语音输入
class StartVoiceInput extends ChatEvent {}

/// 停止语音输入
class StopVoiceInput extends ChatEvent {}

/// 开始语音唤醒监听
class StartWakeWord extends ChatEvent {}

/// 停止语音唤醒监听
class StopWakeWord extends ChatEvent {}

/// 清除对话历史
class ClearMessages extends ChatEvent {}

/// 停止 TTS 播放
class StopTts extends ChatEvent {}

/// 新会话 (切换 session)
class NewSession extends ChatEvent {
  final String newUserId;
  
  const NewSession(this.newUserId);
  
  @override
  List<Object?> get props => [newUserId];
}
