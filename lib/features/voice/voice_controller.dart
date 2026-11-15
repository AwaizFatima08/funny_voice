import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:funnyvoice/ads/ad_service.dart';
import 'package:funnyvoice/audio/dsp.dart';
import 'package:funnyvoice/audio/effects.dart';
import 'package:funnyvoice/audio/wav.dart';
import 'package:funnyvoice/core/clock.dart';
import 'package:funnyvoice/features/voice/voice_io.dart';

enum VoicePhase { idle, recording, processing, playing, ready }

enum VoiceProblem { micDenied, tooShort, silent, failed }

@immutable
class VoiceState {
  const VoiceState({
    this.phase = VoicePhase.idle,
    this.effect = VoiceEffect.chipmunk,
    this.hasRecording = false,
    this.level = 0,
    this.elapsed = Duration.zero,
    this.problem,
  });

  final VoicePhase phase;
  final VoiceEffect effect;
  final bool hasRecording;

  /// Microphone loudness 0..1 while recording.
  final double level;
  final Duration elapsed;
  final VoiceProblem? problem;

  bool get busy => phase == VoicePhase.processing;

  VoiceState copyWith({
    VoicePhase? phase,
    VoiceEffect? effect,
    bool? hasRecording,
    double? level,
    Duration? elapsed,
    VoiceProblem? Function()? problem,
  }) => VoiceState(
    phase: phase ?? this.phase,
    effect: effect ?? this.effect,
    hasRecording: hasRecording ?? this.hasRecording,
    level: level ?? this.level,
    elapsed: elapsed ?? this.elapsed,
    problem: problem != null ? problem() : this.problem,
  );
}

/// Record → render the chosen effect → play. Tapping another effect replays the same
/// recording in that voice; rendered voices are cached until the next recording.
class VoiceController extends Notifier<VoiceState> {
  static const maxLength = Duration(seconds: 30);
  static const _minLength = Duration(milliseconds: 400);

  // About -40 dBFS: below this the microphone heard nothing worth changing.
  static const _silence = 0.01;

  final _rendered = <VoiceEffect, String>{};
  Uint8List? _recording;
  StreamSubscription<double>? _levels;
  StreamSubscription<void>? _done;
  Timer? _ticker;
  DateTime _startedAt = DateTime(0);

  // Bumped on every new request so a slow render never plays over a newer choice.
  int _request = 0;

  VoiceRecorder get _recorder => ref.read(recorderProvider);
  VoicePlayer get _player => ref.read(playerProvider);
  VoiceFiles get _files => ref.read(filesProvider);

  @override
  VoiceState build() {
    _done = ref.read(playerProvider).completed.listen((_) => _onPlayed());
    ref.onDispose(() {
      unawaited(_done?.cancel());
      unawaited(_levels?.cancel());
      _ticker?.cancel();
    });
    return const VoiceState();
  }

  Future<void> toggleRecording() =>
      state.phase == VoicePhase.recording ? stopRecording() : startRecording();

  Future<void> startRecording() async {
    if (state.phase == VoicePhase.recording) return;
    _request++;
    await _player.stop();
    if (!await _recorder.requestPermission()) {
      state = state.copyWith(phase: _restingPhase, problem: () => VoiceProblem.micDenied);
      return;
    }
    try {
      await _recorder.start(await _files.path('recording.wav'));
    } on Object catch (e) {
      debugPrint('Record start: $e');
      state = state.copyWith(phase: _restingPhase, problem: () => VoiceProblem.failed);
      return;
    }
    _startedAt = ref.read(clockProvider).now();
    _levels = _recorder.levels.listen((v) => state = state.copyWith(level: v));
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final elapsed = ref.read(clockProvider).now().difference(_startedAt);
      state = state.copyWith(elapsed: elapsed);
      if (elapsed >= maxLength) unawaited(stopRecording());
    });
    state = state.copyWith(
      phase: VoicePhase.recording,
      level: 0,
      elapsed: Duration.zero,
      problem: () => null,
    );
  }

  Future<void> stopRecording() async {
    if (state.phase != VoicePhase.recording) return;
    _ticker?.cancel();
    await _levels?.cancel();
    _levels = null;
    state = state.copyWith(phase: VoicePhase.processing, level: 0);
    try {
      final path = await _recorder.stop();
      final bytes = path == null ? null : await _files.read(path);
      final pcm = bytes == null ? null : decodeWav(bytes);
      if (pcm == null || pcm.duration < _minLength) {
        state = state.copyWith(phase: _restingPhase, problem: () => VoiceProblem.tooShort);
        return;
      }
      if (peakOf(pcm.samples) < _silence) {
        state = state.copyWith(phase: _restingPhase, problem: () => VoiceProblem.silent);
        return;
      }
      _recording = bytes;
      _rendered.clear();
      state = state.copyWith(hasRecording: true);
    } on Object catch (e) {
      debugPrint('Record stop: $e');
      state = state.copyWith(phase: _restingPhase, problem: () => VoiceProblem.failed);
      return;
    }
    await play(state.effect);
  }

  /// Picks [effect]; with a recording, plays it in that voice straight away.
  Future<void> select(VoiceEffect effect) async {
    if (state.phase == VoicePhase.recording) return;
    state = state.copyWith(effect: effect, problem: () => null);
    if (_recording != null) await play(effect);
  }

  Future<void> play(VoiceEffect effect) async {
    final recording = _recording;
    if (recording == null) return;
    final request = ++_request;
    await _player.stop();
    state = state.copyWith(phase: VoicePhase.processing, effect: effect, problem: () => null);
    try {
      final path = await _renderedPath(recording, effect);
      if (request != _request) return;
      await _player.play(path);
      state = state.copyWith(phase: VoicePhase.playing);
    } on Object catch (e) {
      debugPrint('Render ${effect.name}: $e');
      if (request == _request) {
        state = state.copyWith(phase: VoicePhase.ready, problem: () => VoiceProblem.failed);
      }
    }
  }

  Future<void> stopPlayback() async {
    _request++;
    await _player.stop();
    state = state.copyWith(phase: _restingPhase);
  }

  Future<void> share() async {
    final recording = _recording;
    if (recording == null) return;
    final effect = state.effect;
    try {
      final path = await _renderedPath(recording, effect);
      await _files.share(path, 'My ${effect.title} voice, made with Giggle Voice 😂');
    } on Object catch (e) {
      debugPrint('Share: $e');
      state = state.copyWith(problem: () => VoiceProblem.failed);
    }
  }

  void dismissProblem() => state = state.copyWith(problem: () => null);

  Future<void> openSettings() => _recorder.openSettings();

  Future<String> _renderedPath(Uint8List recording, VoiceEffect effect) async {
    final cached = _rendered[effect];
    if (cached != null) return cached;
    final wav = await ref.read(rendererProvider)(recording, effect);
    final path = await _files.path('Giggle Voice - ${effect.title}.wav');
    await _files.write(path, wav);
    // A newer recording may have arrived while rendering.
    if (identical(recording, _recording)) _rendered[effect] = path;
    return path;
  }

  void _onPlayed() {
    if (state.phase != VoicePhase.playing) return;
    state = state.copyWith(phase: VoicePhase.ready);
    unawaited(ref.read(adServiceProvider).showBreakInterstitial());
  }

  VoicePhase get _restingPhase => _recording == null ? VoicePhase.idle : VoicePhase.ready;
}

final NotifierProvider<VoiceController, VoiceState> voiceProvider =
    NotifierProvider<VoiceController, VoiceState>(VoiceController.new);
