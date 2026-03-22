import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../models/message.dart';
import '../../services/openclaw_service.dart';
import '../../services/speech_service.dart';
import '../../services/settings_service.dart';
import '../../services/tts_service.dart';
import 'chat_event.dart';
import 'chat_state.dart';

/// 全局 settings service
SettingsService? globalSettingsService;

/// 退出关键词
const _exitKeywords = ['退出', '停止', '再见', 'end', 'exit', 'stop', 'quit'];

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final OpenClawService _openClawService;
  final SpeechService _speechService;
  final TtsService _ttsService;
  final SettingsService _settingsService;

  StreamSubscription? _speechResultSubscription;
  StreamSubscription? _speechStatusSubscription;
  StreamSubscription? _speechDecibelSubscription;

  final _uuid = const Uuid();

  ChatBloc({
    required OpenClawService openClawService,
    required SpeechService speechService,
    required TtsService ttsService,
    required SettingsService settingsService,
  })  : _openClawService = openClawService,
        _speechService = speechService,
        _ttsService = ttsService,
        _settingsService = settingsService,
        super(const ChatState()) {

    on<Initialize>(_onInitialize);
    on<SendTextMessage>(_onSendTextMessage);
    on<StopListening>(_onStopListening);
    on<StopTts>(_onStopTts);
    on<ClearMessages>(_onClearMessages);
    on<NewSession>(_onNewSession);
    on<ConversationListeningResult>(_onConversationListeningResult);
    on<ListeningStatusChanged>(_onListeningStatusChanged);
    on<VoiceLevelChanged>(_onVoiceLevelChanged);
    on<StartListening>(_onStartListening);
  }

  Future<void> _onInitialize(Initialize event, Emitter<ChatState> emit) async {
    await _speechService.init();
    await _ttsService.init();

    // 监听语音识别结果
    _speechResultSubscription?.cancel();
    _speechResultSubscription = _speechService.onResult.listen((text) {
      if (text.isNotEmpty) {
        add(ConversationListeningResult(text));
      }
    });

    // 监听聆听状态 → 用事件而非直接 emit
    _speechStatusSubscription?.cancel();
    _speechStatusSubscription = _speechService.onStatus.listen((isActive) {
      add(ListeningStatusChanged(isActive));
    });

    // 监听音量 → 用事件而非直接 emit
    _speechDecibelSubscription?.cancel();
    _speechDecibelSubscription = _speechService.onDecibel.listen((db) {
      final level = ((db + 60) / 60).clamp(0.0, 1.0);
      add(VoiceLevelChanged(level));
    });

    // 检测配置
    if (!_settingsService.isAllConfigured) {
      final missing = _settingsService.missingConfigItems;
      debugPrint('ChatBloc: 配置不完整，缺少 $missing');
      emit(state.copyWith(
        status: ChatStatus.configRequired,
        errorMessage: '请先配置：${missing.join("、")}',
      ));
      return;
    }

    // Whisper STT 必须可用（显式配置或从 baseUrl 派生）
    if (!_settingsService.isWhisperConfigured) {
      debugPrint('ChatBloc: Whisper 未配置');
      emit(state.copyWith(
        status: ChatStatus.configRequired,
        errorMessage: '请先配置 Whisper STT 服务器地址',
      ));
      return;
    }

    // 配置 OK，立即开始聆听
    _speechService.startListening();
    emit(state.copyWith(status: ChatStatus.listening));
  }

  void _onListeningStatusChanged(ListeningStatusChanged event, Emitter<ChatState> emit) {
    if (event.isActive) {
      emit(state.copyWith(status: ChatStatus.listening, voiceLevel: 0));
    }
  }

  void _onVoiceLevelChanged(VoiceLevelChanged event, Emitter<ChatState> emit) {
    emit(state.copyWith(voiceLevel: event.level));
  }

  /// 从设置页返回后，直接开始聆听
  void _onStartListening(StartListening event, Emitter<ChatState> emit) {
    debugPrint('ChatBloc: StartListening 触发，当前状态=${state.status}，whisperUrl=${_settingsService.whisperUrl}');

    // Whisper STT 必须可用
    if (!_settingsService.isWhisperConfigured) {
      debugPrint('ChatBloc: Whisper 未配置');
      emit(state.copyWith(
        status: ChatStatus.configRequired,
        errorMessage: '请先配置 Whisper STT 服务器地址',
      ));
      return;
    }

    // 先停止当前录音（防止重复）
    _speechService.stop();
    // 重新开始聆听
    _speechService.startListening();
    emit(state.copyWith(status: ChatStatus.listening, voiceLevel: 0));
  }

  Future<void> _onSendTextMessage(SendTextMessage event, Emitter<ChatState> emit) async {
    if (event.text.trim().isEmpty) return;

    if (_containsExitKeyword(event.text)) {
      add(StopListening());
      return;
    }

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
      final reply = await _openClawService.sendMessage(event.text);

      final assistantMessage = Message(
        id: _uuid.v4(),
        content: reply,
        role: MessageRole.assistant,
        timestamp: DateTime.now(),
      );

      emit(state.copyWith(
        messages: [...state.messages, assistantMessage],
        status: ChatStatus.speaking,
      ));

      try {
        await _ttsService.speak(reply);
      } catch (e) {
        debugPrint('TTS 播放失败: $e');
      }

      // TTS 播完后进入空闲，等待用户手动触发下一轮
      emit(state.copyWith(status: ChatStatus.idle));

    } catch (e) {
      emit(state.copyWith(
        status: ChatStatus.error,
        errorMessage: '获取回复失败: $e',
      ));
    }
  }

  Future<void> _onStopListening(StopListening event, Emitter<ChatState> emit) async {
    await _speechService.stop();
    emit(state.copyWith(status: ChatStatus.idle, voiceLevel: 0));
  }

  Future<void> _onStopTts(StopTts event, Emitter<ChatState> emit) async {
    await _ttsService.stop();
    emit(state.copyWith(status: ChatStatus.idle));
  }

  Future<void> _onClearMessages(ClearMessages event, Emitter<ChatState> emit) async {
    emit(state.copyWith(messages: [], status: ChatStatus.idle));
  }

  Future<void> _onNewSession(NewSession event, Emitter<ChatState> emit) async {
    _openClawService.setUserId(event.newUserId);
    emit(state.copyWith(messages: [], status: ChatStatus.idle));
  }

  Future<void> _onConversationListeningResult(
      ConversationListeningResult event, Emitter<ChatState> emit) async {
    final text = event.recognizedText;
    debugPrint('ChatBloc: 收到识别结果 "$text"');

    if (_containsExitKeyword(text)) {
      try {
        await _ttsService.speak('好的，再见！');
      } catch (_) {}
      return;
    }

    if (text.trim().isEmpty) {
      // 空结果，不重启，等待用户手动触发
      return;
    }

    final userMessage = Message(
      id: _uuid.v4(),
      content: text,
      role: MessageRole.user,
      timestamp: DateTime.now(),
      isVoice: true,
    );

    emit(state.copyWith(
      messages: [...state.messages, userMessage],
      status: ChatStatus.processing,
    ));

    try {
      final reply = await _openClawService.sendMessage(text);

      final assistantMessage = Message(
        id: _uuid.v4(),
        content: reply,
        role: MessageRole.assistant,
        timestamp: DateTime.now(),
      );

      emit(state.copyWith(
        messages: [...state.messages, assistantMessage],
        status: ChatStatus.speaking,
      ));

      try {
        await _ttsService.speak(reply);
      } catch (e) {
        debugPrint('TTS 播放失败: $e');
      }

      // 播完后进入空闲，等待用户手动触发下一轮
      emit(state.copyWith(status: ChatStatus.idle));

    } catch (e) {
      emit(state.copyWith(
        status: ChatStatus.error,
        errorMessage: '获取回复失败: $e',
      ));
      // 错误后不自动重启，等待用户操作
    }
  }

  bool _containsExitKeyword(String text) {
    final lower = text.toLowerCase();
    return _exitKeywords.any((kw) => lower.contains(kw));
  }

  @override
  Future<void> close() {
    _speechResultSubscription?.cancel();
    _speechStatusSubscription?.cancel();
    _speechDecibelSubscription?.cancel();
    _openClawService.dispose();
    _speechService.dispose();
    _ttsService.dispose();
    return super.close();
  }
}
