import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../models/message.dart';
import '../../services/openclaw_service.dart';
import '../../services/speech_service.dart';
import '../../services/settings_service.dart';
import '../../services/tts_service.dart';
import '../../services/wake_word_service.dart';
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

  /// 唤醒词服务（可选，未配置时为 null）
  WakeWordService? _wakeWordService;

  StreamSubscription? _speechResultSubscription;
  StreamSubscription? _speechPartialSubscription;
  StreamSubscription? _speechStatusSubscription;
  StreamSubscription? _speechDecibelSubscription;
  StreamSubscription? _wakeWordStatusSubscription;

  final _uuid = const Uuid();

  /// 确认音效播放器
  final AudioPlayer _dingPlayer = AudioPlayer();

  /// Listening Window 定时器
  Timer? _listeningWindowTimer;

  /// 取消当前 OpenClaw 流式请求
  void cancelOpenClawStream() {
    _openClawService.cancelStream();
  }

  ChatBloc({
    required OpenClawService openClawService,
    required SpeechService speechService,
    required TtsService ttsService,
    required SettingsService settingsService,
    WakeWordService? wakeWordService,
  })  : _openClawService = openClawService,
        _speechService = speechService,
        _ttsService = ttsService,
        _settingsService = settingsService,
        _wakeWordService = wakeWordService,
        super(const ChatState()) {

    on<Initialize>(_onInitialize);
    on<SendTextMessage>(_onSendTextMessage);
    on<StopListening>(_onStopListening);
    on<StopTts>(_onStopTts);
    on<ClearMessages>(_onClearMessages);
    on<NewSession>(_onNewSession);
    on<ConversationListeningResult>(_onConversationListeningResult);
    on<PartialListeningResult>(_onPartialListeningResult);
    on<ListeningStatusChanged>(_onListeningStatusChanged);
    on<VoiceLevelChanged>(_onVoiceLevelChanged);
    on<StartListening>(_onStartListening);
    on<WakeWordDetected>(_onWakeWordDetected);
    on<ToggleWakeWord>(_onToggleWakeWord);
    on<ListeningWindowTimeout>(_onListeningWindowTimeout);
  }

  /// 设置 WakeWordService（可在初始化后注入）
  void setWakeWordService(WakeWordService service) {
    _wakeWordService = service;
  }

  Future<void> _onInitialize(Initialize event, Emitter<ChatState> emit) async {
    await _speechService.init();
    await _ttsService.init();

    // 监听语音识别结果（final - 触发 AI）
    _speechResultSubscription?.cancel();
    _speechResultSubscription = _speechService.onResult.listen((text) {
      if (text.isNotEmpty) {
        add(ConversationListeningResult(text));
      }
    });

    // 监听 partial 结果（实时显示，不触发 AI）
    _speechPartialSubscription?.cancel();
    _speechPartialSubscription = _speechService.onPartial.listen((text) {
      if (text.isNotEmpty) {
        add(PartialListeningResult(text));
      }
    });

    // 监听聆听状态
    _speechStatusSubscription?.cancel();
    _speechStatusSubscription = _speechService.onStatus.listen((isActive) {
      add(ListeningStatusChanged(isActive));
    });

    // 监听音量
    _speechDecibelSubscription?.cancel();
    _speechDecibelSubscription = _speechService.onDecibel.listen((db) {
      final level = ((db + 60) / 60).clamp(0.0, 1.0);
      add(VoiceLevelChanged(level));
    });

    // 初始化唤醒词服务
    await _initWakeWordService(emit);

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

    // Whisper STT 必须可用
    if (!_settingsService.isWhisperConfigured) {
      debugPrint('ChatBloc: Whisper 未配置');
      emit(state.copyWith(
        status: ChatStatus.configRequired,
        errorMessage: '请先配置 Whisper STT 服务器地址',
      ));
      return;
    }

    // 配置 OK，启动语音监听（唤醒词模式或手动模式）
    _speechService.startListening();
    emit(state.copyWith(status: ChatStatus.listening));
  }

  /// 初始化唤醒词服务
  Future<void> _initWakeWordService(Emitter<ChatState> emit) async {
    if (_wakeWordService == null) {
      debugPrint('ChatBloc: 未配置 WakeWordService');
      emit(state.copyWith(isWakeWordEnabled: false, isWakeWordReady: false));
      return;
    }

    try {
      await _wakeWordService!.init();

      // 设置唤醒词检测回调
      _wakeWordService!.setOnWakeWordDetected(() {
        debugPrint('ChatBloc: 收到 WakeWordDetected 事件');
        add(WakeWordDetected());
      });

      // 监听唤醒词服务状态
      _wakeWordStatusSubscription?.cancel();
      _wakeWordStatusSubscription = _wakeWordService!.onStatus.listen((isListening) {
        debugPrint('ChatBloc: WakeWord 监听状态=$isListening');
        emit(state.copyWith(isWakeWordListening: isListening));
      });

      // 尝试加载默认模型
      const modelPath = 'assets/models/claw.pmdl';
      final modelReady = await _wakeWordService!.prepare(modelPath);

      if (modelReady) {
        debugPrint('ChatBloc: WakeWord 模型加载成功');
        emit(state.copyWith(
          isWakeWordEnabled: true,
          isWakeWordReady: true,
        ));

        // 自动开始持续监听
        await _wakeWordService!.startListening();
        emit(state.copyWith(isWakeWordListening: true));
      } else {
        debugPrint('ChatBloc: WakeWord 模型加载失败（文件不存在或无效）');
        debugPrint('ChatBloc: 请按照 assets/models/README.md 训练你的唤醒词模型');
        emit(state.copyWith(
          isWakeWordEnabled: false,
          isWakeWordReady: false,
        ));
      }
    } catch (e) {
      debugPrint('ChatBloc: WakeWordService 初始化失败 $e');
      emit(state.copyWith(isWakeWordEnabled: false, isWakeWordReady: false));
    }
  }

  /// 唤醒词被检测到
  Future<void> _onWakeWordDetected(
      WakeWordDetected event, Emitter<ChatState> emit) async {
    debugPrint('ChatBloc: 唤醒词检测触发！');

    // 1. 停止 WakeWord 持续监听（避免重复触发）
    if (_wakeWordService?.isListening == true) {
      await _wakeWordService!.stopListening();
    }

    // 2. 播放确认音效 "叮"
    try {
      await _playDingSound();
      debugPrint('ChatBloc: 确认音效播放完成');
    } catch (e) {
      debugPrint('ChatBloc: 确认音效播放失败 $e');
    }

    // 3. 重置音量，清空 partial，清除之前状态
    emit(state.copyWith(voiceLevel: 0, partialText: ''));

    // 4. 开始录音（复用 SpeechService 的 VAD 逻辑）
    // 先确保之前的录音已停止
    await _speechService.stop();

    // 5. 告知 UI：进入"唤醒后等待说话"状态
    emit(state.copyWith(status: ChatStatus.listening));

    // 6. 开始录音
    try {
      await _speechService.startListening();
    } catch (e) {
      debugPrint('ChatBloc: 启动语音监听失败 $e');
      // 失败时尝试恢复唤醒词监听
      await _resumeWakeWordListening();
    }
  }

  /// 播放唤醒确认音效
  Future<void> _playDingSound() async {
    try {
      // 优先用内置音效文件
      await _dingPlayer.setSource(AssetSource('audio/ding.mp3'));
      await _dingPlayer.resume();
    } catch (e) {
      // 文件不存在时，用系统提示音（TTS 引擎未初始化前只能这样）
      debugPrint('ChatBloc: 音效文件不存在，跳过: $e');
    }
  }

  /// 恢复唤醒词持续监听
  Future<void> _resumeWakeWordListening() async {
    if (_wakeWordService != null && state.isWakeWordEnabled) {
      await _wakeWordService!.startListening();
    }
  }

  /// 切换唤醒词启用/禁用
  Future<void> _onToggleWakeWord(
      ToggleWakeWord event, Emitter<ChatState> emit) async {
    if (_wakeWordService == null) return;

    final newEnabled = !state.isWakeWordEnabled;

    if (newEnabled) {
      // 启用：先停止语音监听，再启动唤醒词
      await _speechService.stop();
      final ok = await _wakeWordService!.prepare('assets/models/claw.pmdl');
      if (ok) {
        await _wakeWordService!.startListening();
        emit(state.copyWith(
          isWakeWordEnabled: true,
          isWakeWordReady: true,
          isWakeWordListening: true,
          status: ChatStatus.idle,
        ));
      }
    } else {
      // 禁用：停止唤醒词，开始语音监听
      await _wakeWordService!.stopListening();
      await _speechService.startListening();
      emit(state.copyWith(
        isWakeWordEnabled: false,
        isWakeWordListening: false,
        status: ChatStatus.listening,
      ));
    }
  }

  void _onListeningStatusChanged(
      ListeningStatusChanged event, Emitter<ChatState> emit) {
    if (event.isActive) {
      emit(state.copyWith(status: ChatStatus.listening, voiceLevel: 0));
    }
  }

  void _onVoiceLevelChanged(
      VoiceLevelChanged event, Emitter<ChatState> emit) {
    emit(state.copyWith(voiceLevel: event.level));
  }

  /// 从设置页返回后，开始聆听
  void _onStartListening(StartListening event, Emitter<ChatState> emit) {
    debugPrint(
        'ChatBloc: StartListening 触发，当前状态=${state.status}，whisperUrl=${_settingsService.whisperUrl}');

    if (!_settingsService.isWhisperConfigured) {
      debugPrint('ChatBloc: Whisper 未配置');
      emit(state.copyWith(
        status: ChatStatus.configRequired,
        errorMessage: '请先配置 Whisper STT 服务器地址',
      ));
      return;
    }

    _speechService.stop();
    _speechService.startListening();
    emit(state.copyWith(status: ChatStatus.listening, voiceLevel: 0, partialText: ''));
  }

  Future<void> _onSendTextMessage(
      SendTextMessage event, Emitter<ChatState> emit) async {
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
      // 流式模式：边接收 AI 回复边播放 TTS
      final textStream = _openClawService.sendMessageStream(event.text);
      final fullReply = StringBuffer();

      // 先发一条空 assistant 消息，后面逐步更新
      final assistantMessage = Message(
        id: _uuid.v4(),
        content: '',
        role: MessageRole.assistant,
        timestamp: DateTime.now(),
      );

      emit(state.copyWith(
        messages: [...state.messages, assistantMessage],
        status: ChatStatus.speaking,
      ));

      try {
        // 流式 TTS 播放
        await for (final sentence in _ttsService.speakStream(textStream)) {
          // 每播完一句，更新 assistant 消息
          fullReply.write(sentence);
          final updatedMessages = [...state.messages];
          if (updatedMessages.isNotEmpty) {
            updatedMessages[updatedMessages.length - 1] =
                Message(
                  id: assistantMessage.id,
                  content: fullReply.toString(),
                  role: MessageRole.assistant,
                  timestamp: assistantMessage.timestamp,
                );
          }
          emit(state.copyWith(messages: updatedMessages));
        }
      } catch (e) {
        debugPrint('TTS 播放失败: $e');
        // TTS 失败时，保存已收到的文本
        if (fullReply.isNotEmpty) {
          final updatedMessages = [...state.messages];
          if (updatedMessages.isNotEmpty) {
            updatedMessages[updatedMessages.length - 1] =
                Message(
                  id: assistantMessage.id,
                  content: fullReply.toString(),
                  role: MessageRole.assistant,
                  timestamp: assistantMessage.timestamp,
                );
          }
          emit(state.copyWith(messages: updatedMessages));
        }
      }

      // TTS 播完后，进入追问窗口
      emit(state.copyWith(status: ChatStatus.listeningWindow, partialText: ''));
      _startListeningWindowTimer();
      await _speechService.startListening();

    } catch (e) {
      emit(state.copyWith(
        status: ChatStatus.error,
        errorMessage: '获取回复失败: $e',
      ));
    }
  }

  Future<void> _onStopListening(
      StopListening event, Emitter<ChatState> emit) async {
    cancelOpenClawStream();
    await _speechService.stop();
    emit(state.copyWith(status: ChatStatus.idle, voiceLevel: 0, partialText: ''));
    await _resumeWakeWordListening();
  }

  Future<void> _onStopTts(StopTts event, Emitter<ChatState> emit) async {
    cancelOpenClawStream();
    await _ttsService.stop();
    emit(state.copyWith(status: ChatStatus.idle));
  }

  Future<void> _onClearMessages(
      ClearMessages event, Emitter<ChatState> emit) async {
    emit(state.copyWith(messages: [], status: ChatStatus.idle));
  }

  Future<void> _onNewSession(
      NewSession event, Emitter<ChatState> emit) async {
    _openClawService.setUserId(event.newUserId);
    emit(state.copyWith(messages: [], status: ChatStatus.idle));
  }

  Future<void> _onConversationListeningResult(
      ConversationListeningResult event, Emitter<ChatState> emit) async {
    // 取消 Listening Window 计时器，避免超时和结果同时处理
    _cancelListeningWindowTimer();

    final text = event.recognizedText;
    debugPrint('ChatBloc: 收到识别结果 "$text"');

    if (_containsExitKeyword(text)) {
      _cancelListeningWindowTimer();
      cancelOpenClawStream(); // 取消 AI 流
      await _ttsService.stop();
      try {
        await _ttsService.speak('好的，再见！');
      } catch (_) {}
      emit(state.copyWith(status: ChatStatus.idle, partialText: ''));
      await _resumeWakeWordListening();
      return;
    }

    if (text.trim().isEmpty) {
      // 空结果，重新进入 Listening Window
      if (state.status == ChatStatus.listeningWindow) {
        emit(state.copyWith(partialText: ''));
      } else {
        await _resumeWakeWordListening();
      }
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
      partialText: '', // 清空 partial 显示
    ));

    try {
      // 流式：边接收 AI 回复，边播放 TTS
      final textStream = _openClawService.sendMessageStream(text);
      final fullReply = StringBuffer();

      final assistantMessage = Message(
        id: _uuid.v4(),
        content: '',
        role: MessageRole.assistant,
        timestamp: DateTime.now(),
      );

      emit(state.copyWith(
        messages: [...state.messages, assistantMessage],
        status: ChatStatus.speaking,
      ));

      try {
        // 流式 TTS：每播完一句 yield 回来，更新 UI
        await for (final sentence in _ttsService.speakStream(textStream)) {
          fullReply.write(sentence);
          final updatedMessages = [...state.messages];
          if (updatedMessages.isNotEmpty) {
            updatedMessages[updatedMessages.length - 1] =
                Message(
                  id: assistantMessage.id,
                  content: fullReply.toString(),
                  role: MessageRole.assistant,
                  timestamp: assistantMessage.timestamp,
                );
          }
          emit(state.copyWith(messages: updatedMessages));
        }
      } catch (e) {
        debugPrint('TTS 播放失败: $e');
        if (fullReply.isNotEmpty) {
          final updatedMessages = [...state.messages];
          if (updatedMessages.isNotEmpty) {
            updatedMessages[updatedMessages.length - 1] =
                Message(
                  id: assistantMessage.id,
                  content: fullReply.toString(),
                  role: MessageRole.assistant,
                  timestamp: assistantMessage.timestamp,
                );
          }
          emit(state.copyWith(messages: updatedMessages));
        }
      }

      // 播完后进入 Listening Window
      emit(state.copyWith(status: ChatStatus.listeningWindow, partialText: ''));
      _startListeningWindowTimer();
      await _speechService.startListening();

    } catch (e) {
      emit(state.copyWith(
        status: ChatStatus.error,
        errorMessage: '获取回复失败: $e',
      ));
      await _resumeWakeWordListening();
    }
  }

  /// Partial 结果：实时更新 UI 显示，不触发 AI
  void _onPartialListeningResult(
      PartialListeningResult event, Emitter<ChatState> emit) {
    debugPrint('ChatBloc: partial "$event.partialText"');

    // 在 Listening Window 中，重置计时器（用户还在说话）
    if (state.status == ChatStatus.listeningWindow) {
      _startListeningWindowTimer();
    }

    emit(state.copyWith(
      partialText: event.partialText,
      status: ChatStatus.listening,
    ));
  }

  /// Listening Window 超时：回到唤醒词监听
  Future<void> _onListeningWindowTimeout(
      ListeningWindowTimeout event, Emitter<ChatState> emit) async {
    debugPrint('ChatBloc: Listening Window 超时，回到唤醒词监听');
    await _speechService.stop();
    emit(state.copyWith(status: ChatStatus.idle, partialText: ''));
    await _resumeWakeWordListening();
  }

  /// 启动 Listening Window 定时器
  void _startListeningWindowTimer() {
    _cancelListeningWindowTimer();
    final duration = _settingsService.listeningWindowDuration;
    _listeningWindowTimer = Timer(
      Duration(seconds: duration),
      () => add(ListeningWindowTimeout()),
    );
    debugPrint('ChatBloc: Listening Window 计时器启动 (${duration}s)');
  }

  /// 取消 Listening Window 定时器
  void _cancelListeningWindowTimer() {
    _listeningWindowTimer?.cancel();
    _listeningWindowTimer = null;
  }

  bool _containsExitKeyword(String text) {
    final lower = text.toLowerCase();
    return _exitKeywords.any((kw) => lower.contains(kw));
  }

  @override
  Future<void> close() {
    _speechResultSubscription?.cancel();
    _speechPartialSubscription?.cancel();
    _speechStatusSubscription?.cancel();
    _speechDecibelSubscription?.cancel();
    _wakeWordStatusSubscription?.cancel();
    _listeningWindowTimer?.cancel();
    _dingPlayer.dispose();
    _openClawService.dispose();
    _speechService.dispose();
    _ttsService.dispose();
    _wakeWordService?.dispose();
    return super.close();
  }
}
