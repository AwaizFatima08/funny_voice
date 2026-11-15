import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:funnyvoice/audio/effects.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';

/// Microphone recording to a WAV file.
abstract interface class VoiceRecorder {
  /// Asks for the microphone permission if needed; false when refused.
  Future<bool> requestPermission();

  /// Opens Android's app settings (after the permission was refused for good).
  Future<void> openSettings();

  Future<void> start(String path);

  /// Input loudness 0..1 while recording.
  Stream<double> get levels;

  /// Stops and returns the file path, or null when nothing was recorded.
  Future<String?> stop();
}

abstract interface class VoicePlayer {
  Future<void> play(String path);
  Future<void> stop();

  /// Fires when a file has played to the end.
  Stream<void> get completed;
}

/// Where recordings and rendered voices live, and how they are shared.
abstract interface class VoiceFiles {
  Future<String> path(String name);
  Future<Uint8List> read(String path);
  Future<void> write(String path, Uint8List bytes);
  Future<void> share(String path, String text);
}

typedef EffectRenderer = Future<Uint8List> Function(Uint8List recording, VoiceEffect effect);

Future<Uint8List> renderInBackground(Uint8List recording, VoiceEffect effect) =>
    Isolate.run(() => renderEffect(recording, effect));

class MicRecorder implements VoiceRecorder {
  static const _settings = MethodChannel('com.homilabs.funnyvoice/settings');

  final _rec = AudioRecorder();

  @override
  Future<bool> requestPermission() => _rec.hasPermission();

  @override
  Future<void> openSettings() => _settings.invokeMethod<void>('openAppSettings');

  @override
  Future<void> start(String path) => _rec.start(
    // 44.1 kHz (the default) is the one rate every Android microphone supports.
    const RecordConfig(encoder: AudioEncoder.wav, numChannels: 1, noiseSuppress: true),
    path: path,
  );

  // dBFS (-160..0) to 0..1, with -45 dB as the floor so quiet speech still moves the meter.
  @override
  Stream<double> get levels => _rec
      .onAmplitudeChanged(const Duration(milliseconds: 80))
      .map((a) => ((a.current + 45) / 45).clamp(0.0, 1.0))
      .map((v) => math.pow(v, 1.5).toDouble());

  @override
  Future<String?> stop() => _rec.stop();
}

class SpeakerPlayer implements VoicePlayer {
  final _player = AudioPlayer();

  @override
  Future<void> play(String path) async {
    await _player.stop();
    await _player.play(DeviceFileSource(path));
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Stream<void> get completed => _player.onPlayerComplete;
}

class TempVoiceFiles implements VoiceFiles {
  @override
  Future<String> path(String name) async =>
      '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}$name';

  @override
  Future<Uint8List> read(String path) => File(path).readAsBytes();

  @override
  Future<void> write(String path, Uint8List bytes) => File(path).writeAsBytes(bytes, flush: true);

  @override
  Future<void> share(String path, String text) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: 'audio/wav')],
        text: text,
      ),
    );
  }
}

final Provider<VoiceRecorder> recorderProvider = Provider<VoiceRecorder>((ref) => MicRecorder());
final Provider<VoicePlayer> playerProvider = Provider<VoicePlayer>((ref) => SpeakerPlayer());
final Provider<VoiceFiles> filesProvider = Provider<VoiceFiles>((ref) => TempVoiceFiles());
final Provider<EffectRenderer> rendererProvider = Provider<EffectRenderer>(
  (ref) => renderInBackground,
);
