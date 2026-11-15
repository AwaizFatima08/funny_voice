import 'dart:typed_data';

import 'package:funnyvoice/audio/dsp.dart';
import 'package:funnyvoice/audio/wav.dart';

/// The voices offered on the home screen, in display order.
enum VoiceEffect {
  chipmunk('Chipmunk', 'Squeaky & speedy', 0xFFFF9F43, '🐿️'),
  helium('Helium', 'Balloon voice', 0xFFFF6B9D, '🎈'),
  giant('Giant', 'Big and booming', 0xFF4DABF7, '🗿'),
  monster('Monster', 'Grrr, scary-cute', 0xFF9775FA, '👹'),
  robot('Robot', 'Beep boop', 0xFF74C0FC, '🤖'),
  alien('Alien', 'Take me to your leader', 0xFF69DB7C, '👽'),
  cave('Echo Cave', 'Echo… echo… echo', 0xFF845EF7, '🦇'),
  underwater('Underwater', 'Blub blub', 0xFF22B8CF, '🐠'),
  radio('Old Radio', 'Crackly broadcast', 0xFFE8590C, '📻'),
  ghost('Ghost', 'Spooky whisper', 0xFFADB5BD, '👻'),
  fast('Fast Talker', 'Super speed', 0xFFFCC419, '🐆'),
  slow('Slow-mo', 'Sleepy and slow', 0xFF94D82D, '🦥'),
  reverse('Reverse', 'Backwards talk', 0xFFF06595, '🔄')
  ;

  const VoiceEffect(this.title, this.tagline, this.color, this.emoji);

  final String title;
  final String tagline;
  final int color;
  final String emoji;

  /// Character art, or null where the effect has none yet.
  String? get image => _images[this];
}

// Approved homidev art (assets/ASSET-REGISTER.md). Giant and Alien keep their emoji until a retry is approved.
const _art = 'assets/images';
const Map<VoiceEffect, String> _images = {
  VoiceEffect.chipmunk: '$_art/20261115-2347-funny-voice-encoder-image-02_raw.png',
  VoiceEffect.helium: '$_art/20261116-0014-funny-voice-encoder-image-01_raw.png',
  VoiceEffect.monster: '$_art/20261115-2358-funny-voice-encoder-image-01_raw.png',
  VoiceEffect.robot: '$_art/20261115-2358-funny-voice-encoder-image-02_raw.png',
  VoiceEffect.cave: '$_art/20261115-2358-funny-voice-encoder-image-05_raw.png',
  VoiceEffect.underwater: '$_art/20261115-2358-funny-voice-encoder-image-03_raw.png',
  VoiceEffect.radio: '$_art/20261116-0014-funny-voice-encoder-image-02_raw.png',
  VoiceEffect.ghost: '$_art/20261116-0014-funny-voice-encoder-image-03_raw.png',
  VoiceEffect.fast: '$_art/20261116-0014-funny-voice-encoder-image-04_raw.png',
  VoiceEffect.slow: '$_art/20261116-0014-funny-voice-encoder-image-05_raw.png',
};

/// Turns a recorded WAV into the [effect]'s WAV. Pure and synchronous, so it can run
/// in a background isolate.
Uint8List renderEffect(Uint8List recordingWav, VoiceEffect effect) {
  final pcm = decodeWav(recordingWav);
  final sr = pcm.sampleRate;
  final voice = trimSilence(pcm.samples, sr);
  return encodeWav(Pcm(normalize(applyEffect(voice, sr, effect), sr), sr));
}

Float32List applyEffect(Float32List x, int sr, VoiceEffect effect) {
  switch (effect) {
    case VoiceEffect.chipmunk:
      return biquad(resample(pitchShift(x, 1.55, sr), 1.12), sr, FilterType.highPass, 150);
    case VoiceEffect.helium:
      return vibrato(pitchShift(x, 1.35, sr), sr, 5.5, 0.6);
    case VoiceEffect.giant:
      final low = resample(pitchShift(x, 0.62, sr), 0.92);
      return reverb(biquad(low, sr, FilterType.lowPass, 3200), sr, room: 0.88, wet: 0.25);
    case VoiceEffect.monster:
      final low = pitchShift(x, 0.55, sr);
      final growl = tremolo(distort(low, 3.5), sr, 28, 0.35);
      return reverb(biquad(growl, sr, FilterType.lowPass, 2800), sr, room: 0.7, wet: 0.18);
    case VoiceEffect.robot:
      final metal = comb(ringMod(x, sr, 55), sr, 9, 0.55);
      return bitCrush(mix(metal, x, gainA: 0.8, gainB: 0.25), 7, 2);
    case VoiceEffect.alien:
      final up = pitchShift(x, 1.22, sr);
      return vibrato(ringMod(up, sr, 420, mix: 0.55), sr, 7, 1.8);
    case VoiceEffect.cave:
      final wet = echo(x, sr, delayMs: 260, feedback: 0.5, wet: 0.7);
      return reverb(wet, sr, room: 0.93, damp: 0.35, wet: 0.45, tailSeconds: 2);
    case VoiceEffect.underwater:
      final muffled = biquad(biquad(x, sr, FilterType.lowPass, 650), sr, FilterType.lowPass, 900);
      return reverb(vibrato(muffled, sr, 2.8, 6), sr, room: 0.75, damp: 0.6, wet: 0.3);
    case VoiceEffect.radio:
      final band = biquad(biquad(x, sr, FilterType.highPass, 450), sr, FilterType.lowPass, 2800);
      return crackle(distort(band, 4), sr, amount: 0.8);
    case VoiceEffect.ghost:
      // Reverse reverb: the echo swells in before each word.
      final swell = reverse(reverb(reverse(x), sr, room: 0.92, wet: 0.7, tailSeconds: 1.2));
      final eerie = tremolo(pitchShift(swell, 0.88, sr), sr, 4, 0.35);
      return reverb(eerie, sr, room: 0.9, damp: 0.4);
    case VoiceEffect.fast:
      return resample(x, 1.8);
    case VoiceEffect.slow:
      return biquad(resample(x, 0.62), sr, FilterType.lowPass, 4000);
    case VoiceEffect.reverse:
      return reverse(x);
  }
}
