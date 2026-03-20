import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';

import 'core/theme/app_theme.dart';
import 'services/openclaw_service.dart';
import 'services/speech_service.dart';
import 'services/tts_service.dart';
import 'bloc/chat/chat_bloc.dart';
import 'bloc/chat/chat_event.dart';
import 'ui/screens/chat_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 设置状态栏样式
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  
  // 请求权限
  await _requestPermissions();
  
  // 创建服务
  final openClawService = OpenClawService();
  final speechService = SpeechService();
  final ttsService = TtsService();
  
  runApp(VoiceHubApp(
    openClawService: openClawService,
    speechService: speechService,
    ttsService: ttsService,
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
}

class VoiceHubApp extends StatelessWidget {
  final OpenClawService openClawService;
  final SpeechService speechService;
  final TtsService ttsService;
  
  const VoiceHubApp({
    super.key,
    required this.openClawService,
    required this.speechService,
    required this.ttsService,
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
          )..add(_Initialize()),
        ),
      ],
      child: MaterialApp(
        title: 'VoiceHub',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const ChatScreen(),
      ),
    );
  }
}

class _Initialize extends ChatEvent {}
