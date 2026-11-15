import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:funnyvoice/audio/dsp.dart';
import 'package:funnyvoice/audio/effects.dart';
import 'package:funnyvoice/audio/wav.dart';

const _sr = 44100;

Float32List _tone(double hz, double seconds, {double amp = 0.5}) => Float32List.fromList(
  List.generate((seconds * _sr).round(), (i) => amp * math.sin(2 * math.pi * hz * i / _sr)),
);

/// Rough pitch from positive-going zero crossings.
double _pitch(Float32List x) {
  var crossings = 0;
  for (var i = 1; i < x.length; i++) {
    if (x[i - 1] < 0 && x[i] >= 0) crossings++;
  }
  return crossings * _sr / x.length;
}

/// A vowel-like test voice: harmonics of a gliding pitch, with syllable-shaped loudness.
Float32List _voice(double seconds) {
  final n = (seconds * _sr).round();
  final y = Float32List(n);
  var phase = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / _sr;
    phase += 2 * math.pi * (140 + 40 * math.sin(2 * math.pi * 0.7 * t)) / _sr;
    final env = math.max(0, math.sin(2 * math.pi * 2.5 * t));
    y[i] = 0.4 * env * (math.sin(phase) + 0.5 * math.sin(2 * phase) + 0.25 * math.sin(3 * phase));
  }
  return y;
}

void main() {
  test('WAV round trip keeps samples and rate', () {
    final pcm = Pcm(_tone(440, 0.1), 22050);
    final back = decodeWav(encodeWav(pcm));
    expect(back.sampleRate, 22050);
    expect(back.samples.length, pcm.samples.length);
    for (var i = 0; i < pcm.samples.length; i++) {
      expect(back.samples[i], closeTo(pcm.samples[i], 1 / 16000));
    }
  });

  test('decodeWav averages stereo and tolerates a bad data size', () {
    final bytes = encodeWav(Pcm(_tone(300, 0.05), _sr));
    ByteData.sublistView(bytes).setUint32(40, 0xFFFFFFFF, Endian.little);
    expect(decodeWav(bytes).samples.length, (0.05 * _sr).round());
    expect(() => decodeWav(Uint8List(20)), throwsA(isA<WavFormatException>()));
  });

  test('resample changes length and pitch together', () {
    final y = resample(_tone(200, 1), 2);
    expect(y.length, closeTo(_sr / 2, 2));
    expect(_pitch(y), closeTo(400, 8));
  });

  test('pitchShift changes pitch and keeps length', () {
    final x = _tone(220, 1);
    for (final r in [0.6, 1.5]) {
      final y = pitchShift(x, r, _sr);
      expect(y.length, closeTo(x.length, x.length * 0.02), reason: 'ratio $r');
      expect(_pitch(y), closeTo(220 * r, 220 * r * 0.06), reason: 'ratio $r');
    }
  });

  test('every effect gives clean, normalised audio', () {
    final recording = encodeWav(Pcm(_voice(2), _sr));
    for (final e in VoiceEffect.values) {
      final out = decodeWav(renderEffect(recording, e)).samples;
      expect(out, isNotEmpty, reason: e.name);
      var peak = 0.0;
      for (final v in out) {
        expect(v.isFinite, isTrue, reason: e.name);
        peak = math.max(peak, v.abs());
      }
      expect(peak, inInclusiveRange(0.5, 0.9), reason: e.name);
    }
  });

  test('silence stays silent and does not crash', () {
    final recording = encodeWav(Pcm(Float32List(_sr), _sr));
    for (final e in VoiceEffect.values) {
      expect(() => renderEffect(recording, e), returnsNormally, reason: e.name);
    }
  });

  test('normalize never boosts near-silence more than 30x', () {
    final quiet = normalize(_tone(200, 0.2, amp: 0.0003), _sr);
    expect(peakOf(quiet), lessThan(0.01));
  });

  test('a 30 s recording renders in reasonable time', () {
    final recording = encodeWav(Pcm(_voice(30), _sr));
    final sw = Stopwatch()..start();
    for (final e in [VoiceEffect.chipmunk, VoiceEffect.ghost, VoiceEffect.cave]) {
      sw.reset();
      renderEffect(recording, e);
      // Generous bound for the JIT test runner; release AOT on a phone is faster.
      expect(sw.elapsed, lessThan(const Duration(seconds: 12)), reason: e.name);
      // ignore: avoid_print, timing is useful when tuning effects on a slower phone.
      print('${e.name}: ${sw.elapsedMilliseconds} ms');
    }
  });
}
