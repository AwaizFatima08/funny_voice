import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:funnyvoice/ads/ad_service.dart';
import 'package:funnyvoice/ads/google_ad_service.dart';
import 'package:funnyvoice/app.dart';
import 'package:funnyvoice/core/clock.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (kReleaseMode) debugPrint('Unhandled Flutter error: ${details.exception}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled error: $error\n$stack');
    return true;
  };
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final ads = GoogleAdService(const SystemClock());
  runApp(
    ProviderScope(
      overrides: [adServiceProvider.overrideWithValue(ads)],
      child: const GiggleVoiceApp(),
    ),
  );
  unawaited(ads.start());
}
