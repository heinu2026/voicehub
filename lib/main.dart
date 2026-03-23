import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';

import 'config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'services/openclaw_service.dart';
import 'services/speech_service.dart';
import 'services/whisper_stt_service.dart';
import 'services/tts_service.dart';
import 'services/settings_service.dart';
import 'services/wake_word_service.dart';
import 'bloc/chat/chat_bloc.dart';
import 'bloc/chat/chat_event.dart';
import 'ui/screens/chat_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'package:flutter/foundation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  await _requestPermissions();

  final settingsService = SettingsService();
  await settingsService.init();

  final openClawService = OpenClawService(
    baseUrl: settingsService.baseUrl,
    agentId: settingsService.agentId,
    userId: settingsService.userId,
    authToken: AppConfig.defaultOpenClawToken,
  );

  final whisperSttService = WhisperSttService();
  try {
    final ok = await whisperSttService.init();
    if (ok) {
      whisperSttService.setWhisperUrl(settingsService.whisperWsUrl);
      whisperSttService.setApiKey(settingsService.whisperApiKey);
      whisperSttService.setModel(settingsService.whisperModel);
      debugPrint('Whisper STT 服务初始化成功 (WS): ${settingsService.whisperWsUrl}');
    }
  } catch (e) {
    debugPrint('Whisper STT 服务初始化失败: $e');
  }

  final speechService = SpeechService();
  speechService.setWhisperSttService(whisperSttService);
  speechService.setSettingsService(settingsService);

  final ttsService = TtsService();
  ttsService.setSettingsService(settingsService);

  globalSettingsService = settingsService;

  // 初始化唤醒词服务（可选，模型不存在时自动降级）
  final wakeWordService = WakeWordService();

  runApp(VoiceClawApp(
    settingsService: settingsService,
    openClawService: openClawService,
    speechService: speechService,
    ttsService: ttsService,
    wakeWordService: wakeWordService,
  ));
}

Future<void> _requestPermissions() async {
  final micStatus = await Permission.microphone.request();
  if (micStatus.isDenied) {
    debugPrint('麦克风权限被拒绝');
  }

  final speechStatus = await Permission.speech.request();
  if (speechStatus.isDenied) {
    debugPrint('语音识别权限被拒绝');
  }

  if (defaultTargetPlatform == TargetPlatform.android) {
    final notificationStatus = await Permission.notification.request();
    if (notificationStatus.isDenied) {
      debugPrint('通知权限被拒绝');
    }
  }
}

class VoiceClawApp extends StatelessWidget {
  final SettingsService settingsService;
  final OpenClawService openClawService;
  final SpeechService speechService;
  final TtsService ttsService;
  final WakeWordService wakeWordService;

  const VoiceClawApp({
    super.key,
    required this.settingsService,
    required this.openClawService,
    required this.speechService,
    required this.ttsService,
    required this.wakeWordService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => ChatBloc(
            openClawService: openClawService,
            speechService: speechService,
            ttsService: ttsService,
            settingsService: settingsService,
            wakeWordService: wakeWordService,
          )..add(Initialize()),
        ),
      ],
      child: MaterialApp(
        title: 'VoiceClaw',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const ChatScreen(),
        routes: {
          '/settings': (context) => SettingsScreen(
            settingsService: settingsService,
          ),
        },
      ),
    );
  }
}
