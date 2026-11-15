import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:funnyvoice/ads/ad_service.dart';
import 'package:funnyvoice/app.dart';
import 'package:funnyvoice/audio/effects.dart';
import 'package:funnyvoice/audio/wav.dart';
import 'package:funnyvoice/features/voice/voice_controller.dart';
import 'package:funnyvoice/features/voice/voice_io.dart';

class FakeRecorder implements VoiceRecorder {
  bool allowed = true;
  bool recording = false;
  double seconds = 1;
  final levelsCtl = StreamController<double>.broadcast();

  @override
  Future<bool> requestPermission() async => allowed;

  @override
  Future<void> openSettings() async {}

  @override
  Future<void> start(String path) async => recording = true;

  @override
  Stream<double> get levels => levelsCtl.stream;

  @override
  Future<String?> stop() async {
    recording = false;
    return 'recording.wav';
  }
}

class FakePlayer implements VoicePlayer {
  final played = <String>[];
  final doneCtl = StreamController<void>.broadcast();

  @override
  Future<void> play(String path) async => played.add(path);

  @override
  Future<void> stop() async {}

  @override
  Stream<void> get completed => doneCtl.stream;
}

class FakeFiles implements VoiceFiles {
  FakeFiles(this.recorder);

  double amplitude = 0.5;

  final FakeRecorder recorder;
  final written = <String, Uint8List>{};
  final shared = <String>[];

  @override
  Future<String> path(String name) async => name;

  @override
  Future<Uint8List> read(String path) async {
    final n = (recorder.seconds * 8000).round();
    final tone = Float32List.fromList(
      List.generate(n, (i) => amplitude * math.sin(2 * math.pi * 200 * i / 8000)),
    );
    return encodeWav(Pcm(tone, 8000));
  }

  @override
  Future<void> write(String path, Uint8List bytes) async => written[path] = bytes;

  @override
  Future<void> share(String path, String text) async => shared.add(path);
}

class CountingAds extends NoAdService {
  int breaks = 0;

  @override
  Future<void> showBreakInterstitial() async => breaks++;
}

void main() {
  late FakeRecorder recorder;
  late FakePlayer player;
  late FakeFiles files;
  late CountingAds ads;
  late List<VoiceEffect> renders;
  late ProviderContainer c;

  setUp(() {
    recorder = FakeRecorder();
    player = FakePlayer();
    files = FakeFiles(recorder);
    ads = CountingAds();
    renders = [];
    c = ProviderContainer(
      overrides: [
        recorderProvider.overrideWithValue(recorder),
        playerProvider.overrideWithValue(player),
        filesProvider.overrideWithValue(files),
        adServiceProvider.overrideWithValue(ads),
        rendererProvider.overrideWithValue((wav, e) async {
          renders.add(e);
          return wav;
        }),
      ],
    );
    addTearDown(c.dispose);
  });

  VoiceController ctl() => c.read(voiceProvider.notifier);
  VoiceState st() => c.read(voiceProvider);

  test('record, stop, plays the selected effect', () async {
    await ctl().startRecording();
    expect(st().phase, VoicePhase.recording);
    await ctl().stopRecording();
    expect(st().phase, VoicePhase.playing);
    expect(st().hasRecording, isTrue);
    expect(player.played, ['Giggle Voice - Chipmunk.wav']);
  });

  test('switching effects replays and caches renders', () async {
    await ctl().startRecording();
    await ctl().stopRecording();
    await ctl().select(VoiceEffect.robot);
    await ctl().select(VoiceEffect.chipmunk);
    expect(renders, [VoiceEffect.chipmunk, VoiceEffect.robot]);
    expect(player.played.last, 'Giggle Voice - Chipmunk.wav');
    expect(st().effect, VoiceEffect.chipmunk);
  });

  test('a new recording clears the cache', () async {
    await ctl().startRecording();
    await ctl().stopRecording();
    await ctl().startRecording();
    await ctl().stopRecording();
    expect(renders, [VoiceEffect.chipmunk, VoiceEffect.chipmunk]);
  });

  test('denied microphone reports the problem and does not record', () async {
    recorder.allowed = false;
    await ctl().startRecording();
    expect(recorder.recording, isFalse);
    expect(st().problem, VoiceProblem.micDenied);
    expect(st().phase, VoicePhase.idle);
  });

  test('too-short recordings are rejected', () async {
    recorder.seconds = 0.1;
    await ctl().startRecording();
    await ctl().stopRecording();
    expect(st().problem, VoiceProblem.tooShort);
    expect(st().hasRecording, isFalse);
    expect(player.played, isEmpty);
  });

  test('a silent recording is reported, not amplified into hiss', () async {
    files.amplitude = 0.0003;
    await ctl().startRecording();
    await ctl().stopRecording();
    expect(st().problem, VoiceProblem.silent);
    expect(st().hasRecording, isFalse);
    expect(player.played, isEmpty);
  });

  test('finished playback returns to ready and offers an ad break', () async {
    await ctl().startRecording();
    await ctl().stopRecording();
    player.doneCtl.add(null);
    await pumpEventQueue();
    expect(st().phase, VoicePhase.ready);
    expect(ads.breaks, 1);
  });

  test('share sends the rendered file of the current effect', () async {
    await ctl().startRecording();
    await ctl().stopRecording();
    await ctl().select(VoiceEffect.ghost);
    await ctl().share();
    expect(files.shared, ['Giggle Voice - Ghost.wav']);
  });

  testWidgets('home screen shows the mic and all voices', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const GiggleVoiceApp()),
    );
    expect(find.text('Giggle Voice'), findsOneWidget);
    expect(find.text('Tap the mic and say something!'), findsOneWidget);
    expect(find.bySemanticsLabel('Start recording'), findsOneWidget);
    expect(find.text('Chipmunk'), findsOneWidget);
    await tester.drag(find.byType(GridView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text('Reverse'), findsOneWidget);
  });
}
