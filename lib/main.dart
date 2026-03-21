import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';

import 'core/theme/app_theme.dart';
import 'services/openclaw_service.dart';
import 'services/speech_service.dart';
import 'services/tts_service.dart';
import 'services/wake_word_service.dart';
import 'services/settings_service.dart';
import 'bloc/chat/chat_bloc.dart';
import 'bloc/chat/chat_event.dart';
import 'ui/screens/chat_screen.dart';
import 'ui/screens/settings_screen.dart';

// 判断平台
import 'package:flutter/foundation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 设置状态栏样式
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  
  // 请求权限
  await _requestPermissions();
  
  // 初始化设置服务
  final settingsService = SettingsService();
  await settingsService.init();
  
  // 创建服务
  final openClawService = OpenClawService(
    baseUrl: settingsService.baseUrl,
    wsUrl: settingsService.wsUrl,
    agentId: settingsService.agentId,
    model: settingsService.model,
    userId: settingsService.userId,
  );
  final speechService = SpeechService();
  final ttsService = TtsService();
  final wakeWordService = WakeWordService();
  
  // 初始化唤醒词服务
  try {
    await wakeWordService.init();
    debugPrint('唤醒词服务初始化成功');
  } catch (e) {
    debugPrint('唤醒词服务初始化失败: $e');
  }
  
  // 设置全局 settings service (用于新会话)
  globalSettingsService = settingsService;
  
  runApp(VoiceHubApp(
    settingsService: settingsService,
    openClawService: openClawService,
    speechService: speechService,
    ttsService: ttsService,
    wakeWordService: wakeWordService,
  ));
}

Future<void> _requestPermissions() async {
  // 请求麦克风权限
  final micStatus = await Permission.microphone.request();
  if (micStatus.isDenied) {
    debugPrint('麦克风权限被拒绝');
  }
  
  // 请求语音识别权限 (Android)
  final speechStatus = await Permission.speech.request();
  if (speechStatus.isDenied) {
    debugPrint('语音识别权限被拒绝');
  }
  
  // Android: 请求后台权限 (Android 13+)
  if (defaultTargetPlatform == TargetPlatform.android) {
    final notificationStatus = await Permission.notification.request();
    if (notificationStatus.isDenied) {
      debugPrint('通知权限被拒绝');
    }
  }
}

class VoiceHubApp extends StatelessWidget {
  final SettingsService settingsService;
  final OpenClawService openClawService;
  final SpeechService speechService;
  final TtsService ttsService;
  final WakeWordService wakeWordService;
  
  const VoiceHubApp({
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
            wakeWordService: wakeWordService,
          )..add(_Initialize()),
        ),
      ],
      child: MaterialApp(
        title: 'VoiceHub',
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

class _Initialize extends ChatEvent {}
