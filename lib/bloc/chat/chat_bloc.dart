import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../models/message.dart';
import '../../services/openclaw_service.dart';
import '../../services/speech_service.dart';
import '../../services/settings_service.dart';
import '../../services/tts_service.dart';
import '../../services/wake_word_service.dart';
import 'chat_event.dart';
import 'chat_state.dart';

/// 全局 settings service (在新会话时获取新 userId)
SettingsService? globalSettingsService;

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final OpenClawService _openClawService;
  final SpeechService _speechService;
  final TtsService _ttsService;
  final WakeWordService _wakeWordService;
  
  StreamSubscription? _speechSubscription;
  StreamSubscription? _speechStatusSubscription;
  StreamSubscription? _wakeWordSubscription;
  
  final _uuid = const Uuid();
  
  ChatBloc({
    required OpenClawService openClawService,
    required SpeechService speechService,
    required TtsService ttsService,
    required WakeWordService wakeWordService,
  })  : _openClawService = openClawService,
        _speechService = speechService,
        _ttsService = ttsService,
        _wakeWordService = wakeWordService,
        super(const ChatState()) {
    
    // 初始化服务
    on<_Initialize>(_onInitialize);
    
    // 发送文本消息
    on<SendTextMessage>(_onSendTextMessage);
    
    // 开始语音输入
    on<StartVoiceInput>(_onStartVoiceInput);
    
    // 停止语音输入
    on<StopVoiceInput>(_onStopVoiceInput);
    
    // 停止 TTS
    on<StopTts>(_onStopTts);
    
    // 清除消息
    on<ClearMessages>(_onClearMessages);
    
    // 新会话
    on<NewSession>(_onNewSession);
    
    // 监听语音识别结果
    _speechSubscription = _speechService.onResult.listen((text) {
      if (text.isNotEmpty) {
        add(SendTextMessage(text));
      }
    });
    
    // 监听语音状态
    _speechStatusSubscription = _speechService.onStatus.listen((isListening) {
      if (!isListening && state.status == ChatStatus.listening) {
        add(StopVoiceInput());
      }
    });
    
    // 监听唤醒词事件
    _wakeWordSubscription = _wakeWordService.onWakeWord.listen((type) {
      if (type == WakeWordType.newSession) {
        // 新会话唤醒词 - 开启新会话
        add(NewSession(globalSettingsService?.newSession() ?? ''));
      } else {
        // 正常唤醒词 - 开始语音输入
        add(StartVoiceInput());
      }
    });
  }
  
  Future<void> _onInitialize(_Initialize event, Emitter<ChatState> emit) async {
    try {
      // 初始化语音服务
      await _speechService.init();
      await _ttsService.init();
    } catch (e) {
      emit(state.copyWith(
        status: ChatStatus.error,
        errorMessage: '初始化失败: $e',
      ));
    }
  }
  
  Future<void> _onSendTextMessage(SendTextMessage event, Emitter<ChatState> emit) async {
    if (event.text.trim().isEmpty) return;
    
    // 添加用户消息
    final userMessage = Message(
      id: _uuid.v4(),
      content: event.text,
      role: MessageRole.user,
      timestamp: DateTime.now(),
      isVoice: true,
    );
    
    emit(state.copyWith(
      messages: [...state.messages, userMessage],
      status: ChatStatus.processing,
    ));
    
    try {
      // 调用 OpenClaw API
      final reply = await _openClawService.sendMessage(event.text);
      
      // 添加助手消息
      final assistantMessage = Message(
        id: _uuid.v4(),
        content: reply,
        role: MessageRole.assistant,
        timestamp: DateTime.now(),
      );
      
      emit(state.copyWith(
        messages: [...state.messages, assistantMessage],
        status: ChatStatus.idle,
      ));
      
      // 自动播放 TTS
      await _ttsService.speak(reply);
      
    } catch (e) {
      emit(state.copyWith(
        status: ChatStatus.error,
        errorMessage: '获取回复失败: $e',
      ));
    }
  }
  
  Future<void> _onStartVoiceInput(StartVoiceInput event, Emitter<ChatState> emit) async {
    try {
      emit(state.copyWith(
        status: ChatStatus.listening,
        isVoiceInputActive: true,
      ));
      
      await _speechService.listen();
    } catch (e) {
      emit(state.copyWith(
        status: ChatStatus.error,
        errorMessage: '语音识别失败: $e',
        isVoiceInputActive: false,
      ));
    }
  }
  
  Future<void> _onStopVoiceInput(StopVoiceInput event, Emitter<ChatState> emit) async {
    await _speechService.stop();
    
    emit(state.copyWith(
      status: ChatStatus.idle,
      isVoiceInputActive: false,
      voiceLevel: 0,
    ));
  }
  
  Future<void> _onStopTts(StopTts event, Emitter<ChatState> emit) async {
    await _ttsService.stop();
    emit(state.copyWith(status: ChatStatus.idle));
  }
  
  Future<void> _onClearMessages(ClearMessages event, Emitter<ChatState> emit) async {
    emit(state.copyWith(
      messages: [],
      status: ChatStatus.idle,
    ));
  }
  
  Future<void> _onNewSession(NewSession event, Emitter<ChatState> emit) async {
    // 更新 OpenClawService 的 userId
    _openClawService.setUserId(event.newUserId);
    
    // 清空对话记录
    emit(state.copyWith(
      messages: [],
      status: ChatStatus.idle,
    ));
  }
  
  @override
  Future<void> close() {
    _speechSubscription?.cancel();
    _speechStatusSubscription?.cancel();
    _wakeWordSubscription?.cancel();
    _openClawService.dispose();
    _speechService.dispose();
    _ttsService.dispose();
    _wakeWordService.dispose();
    return super.close();
  }
}

class _Initialize extends ChatEvent {}
