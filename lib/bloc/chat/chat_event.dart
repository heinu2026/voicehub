import 'package:equatable/equatable.dart';

/// 聊天相关事件
abstract class ChatEvent extends Equatable {
  const ChatEvent();

  @override
  List<Object?> get props => [];
}

/// 初始化事件
class Initialize extends ChatEvent {}

/// 发送文本消息
class SendTextMessage extends ChatEvent {
  final String text;
  const SendTextMessage(this.text);

  @override
  List<Object?> get props => [text];
}

/// 停止聆听
class StopListening extends ChatEvent {}

/// 停止 TTS
class StopTts extends ChatEvent {}

/// 清除消息
class ClearMessages extends ChatEvent {}

/// 新会话
class NewSession extends ChatEvent {
  final String newUserId;
  const NewSession(this.newUserId);

  @override
  List<Object?> get props => [newUserId];
}

/// 聆听结果
class ConversationListeningResult extends ChatEvent {
  final String recognizedText;
  const ConversationListeningResult(this.recognizedText);

  @override
  List<Object?> get props => [recognizedText];
}

/// 聆听状态变化
class ListeningStatusChanged extends ChatEvent {
  final bool isActive;
  const ListeningStatusChanged(this.isActive);

  @override
  List<Object?> get props => [isActive];
}

/// 音量变化
class VoiceLevelChanged extends ChatEvent {
  final double level;
  const VoiceLevelChanged(this.level);

  @override
  List<Object?> get props => [level];
}

/// 从设置页返回，开始聆听
class StartListening extends ChatEvent {}
