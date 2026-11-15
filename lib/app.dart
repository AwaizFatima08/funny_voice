import 'package:flutter/material.dart';
import 'package:funnyvoice/features/voice/home_screen.dart';
import 'package:funnyvoice/ui/theme.dart';

class GiggleVoiceApp extends StatelessWidget {
  const GiggleVoiceApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Giggle Voice',
    debugShowCheckedModeBanner: false,
    theme: giggleTheme(),
    home: const HomeScreen(),
  );
}
