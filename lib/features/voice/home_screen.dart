import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:funnyvoice/ads/ad_service.dart';
import 'package:funnyvoice/audio/effects.dart';
import 'package:funnyvoice/features/voice/voice_controller.dart';
import 'package:funnyvoice/ui/art.dart';
import 'package:funnyvoice/ui/theme.dart';
import 'package:url_launcher/url_launcher.dart';

const _privacyUrl = 'https://tools.homilabs.org/privacy#gigglevoice';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(voiceProvider.select((s) => s.problem), (_, problem) {
      if (problem != null) _showProblem(context, ref, problem);
    });
    return Scaffold(
      body: DecoratedBox(
        decoration: giggleBackdrop,
        child: SafeArea(
          child: Column(
            children: [
              const _Header(),
              const _RecordPanel(),
              const _Controls(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Row(
                  children: [
                    Text(
                      'Pick a voice',
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    Text(
                      '${VoiceEffect.values.length} voices',
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ],
                ),
              ),
              const Expanded(child: _EffectGrid()),
              ref.watch(adServiceProvider).banner(),
            ],
          ),
        ),
      ),
    );
  }

  void _showProblem(BuildContext context, WidgetRef ref, VoiceProblem problem) {
    final controller = ref.read(voiceProvider.notifier);
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    final (text, action) = switch (problem) {
      VoiceProblem.micDenied => (
        'Giggle Voice needs the microphone to hear you.',
        SnackBarAction(label: 'Settings', onPressed: () => unawaited(controller.openSettings())),
      ),
      VoiceProblem.tooShort => (
        'That was too short. Hold on a bit longer and say something!',
        null,
      ),
      VoiceProblem.silent => (
        "We couldn't hear you. Speak a little louder, close to the mic.",
        null,
      ),
      VoiceProblem.failed => ('Something went wrong. Please try again.', null),
    };
    messenger.showSnackBar(SnackBar(content: Text(text), action: action));
    controller.dismissProblem();
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
      child: Row(
        children: [
          ClipOval(
            child: SizedBox.square(
              dimension: 52,
              child: heroArt != null
                  ? Image.asset(heroArt!, fit: BoxFit.cover)
                  : const ColoredBox(
                      color: GiggleColors.violet,
                      child: Center(child: Text('🎤', style: TextStyle(fontSize: 28))),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Giggle Voice',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const Text('Talk. Laugh. Repeat.', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          const _Menu(),
        ],
      ),
    );
  }
}

enum _MenuItem { privacyChoices, privacyPolicy, about }

class _Menu extends ConsumerWidget {
  const _Menu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showChoices = ref.watch(privacyChoicesRequiredProvider).value ?? false;
    return PopupMenuButton<_MenuItem>(
      tooltip: 'Menu',
      icon: const Icon(Icons.more_vert),
      onSelected: (item) async {
        switch (item) {
          case _MenuItem.privacyChoices:
            await ref.read(adServiceProvider).showPrivacyChoices();
          case _MenuItem.privacyPolicy:
            await launchUrl(Uri.parse(_privacyUrl), mode: LaunchMode.externalApplication);
          case _MenuItem.about:
            if (!context.mounted) return;
            showAboutDialog(
              context: context,
              applicationName: 'Giggle Voice',
              applicationVersion: '1.0.0',
              applicationLegalese:
                  '© 2026 HomiLabs\n\nYour voice is changed on your phone and never uploaded. '
                  'Ads are by Google AdMob.',
            );
        }
      },
      itemBuilder: (_) => [
        if (showChoices)
          const PopupMenuItem(value: _MenuItem.privacyChoices, child: Text('Privacy choices')),
        const PopupMenuItem(value: _MenuItem.privacyPolicy, child: Text('Privacy policy')),
        const PopupMenuItem(value: _MenuItem.about, child: Text('About')),
      ],
    );
  }
}

class _RecordPanel extends ConsumerWidget {
  const _RecordPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(voiceProvider);
    final recording = s.phase == VoicePhase.recording;
    final status = switch (s.phase) {
      VoicePhase.idle => 'Tap the mic and say something!',
      VoicePhase.recording =>
        'Listening…  ${_clock(s.elapsed)} / ${_clock(VoiceController.maxLength)}',
      VoicePhase.processing => 'Making it funny…',
      VoicePhase.playing => '${s.effect.emoji}  Playing ${s.effect.title}',
      VoicePhase.ready => 'Tap a voice to hear it again',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          _MicButton(
            recording: recording,
            level: s.level,
            progress: s.elapsed.inMilliseconds / VoiceController.maxLength.inMilliseconds,
            busy: s.busy,
            onTap: s.busy
                ? null
                : () {
                    unawaited(HapticFeedback.mediumImpact());
                    unawaited(ref.read(voiceProvider.notifier).toggleRecording());
                  },
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              status,
              key: ValueKey(status.split(' ').first + s.phase.name),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  static String _clock(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.recording,
    required this.level,
    required this.progress,
    required this.busy,
    required this.onTap,
  });

  final bool recording;
  final double level;
  final double progress;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const size = 150.0;
    final glow = recording ? 18 + 40 * level : 14.0;
    return Semantics(
      button: true,
      label: recording ? 'Stop recording' : 'Start recording',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox.square(
          dimension: size + 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (recording)
                SizedBox.square(
                  dimension: size + 26,
                  child: CircularProgressIndicator(
                    value: progress.clamp(0, 1),
                    strokeWidth: 6,
                    color: GiggleColors.sun,
                    backgroundColor: Colors.white12,
                  ),
                ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: recording
                        ? const [GiggleColors.coral, Color(0xFFE03131)]
                        : const [Color(0xFFB197FC), GiggleColors.violet],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (recording ? GiggleColors.coral : GiggleColors.violet).withValues(
                        alpha: 0.6,
                      ),
                      blurRadius: glow,
                      spreadRadius: recording ? 4 + 10 * level : 2,
                    ),
                  ],
                ),
                child: busy
                    ? const Padding(
                        padding: EdgeInsets.all(48),
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 5),
                      )
                    : Icon(
                        recording ? Icons.stop_rounded : Icons.mic_rounded,
                        size: 72,
                        color: Colors.white,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(voiceProvider);
    final c = ref.read(voiceProvider.notifier);
    final usable = s.hasRecording && s.phase != VoicePhase.recording && !s.busy;
    final playing = s.phase == VoicePhase.playing;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _RoundAction(
          icon: playing ? Icons.stop_circle_outlined : Icons.replay_rounded,
          label: playing ? 'Stop' : 'Replay',
          onTap: usable ? () => unawaited(playing ? c.stopPlayback() : c.play(s.effect)) : null,
        ),
        const SizedBox(width: 28),
        _RoundAction(
          icon: Icons.share_rounded,
          label: 'Share',
          onTap: usable ? () => unawaited(c.share()) : null,
        ),
      ],
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: Material(
        color: GiggleColors.card,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EffectGrid extends ConsumerWidget {
  const _EffectGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(voiceProvider);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 130,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.82,
      ),
      itemCount: VoiceEffect.values.length,
      itemBuilder: (context, i) {
        final e = VoiceEffect.values[i];
        return _EffectCard(
          effect: e,
          selected: e == s.effect,
          playing: e == s.effect && s.phase == VoicePhase.playing,
          enabled: s.phase != VoicePhase.recording,
          onTap: () {
            unawaited(HapticFeedback.selectionClick());
            unawaited(ref.read(voiceProvider.notifier).select(e));
          },
        );
      },
    );
  }
}

class _EffectCard extends StatelessWidget {
  const _EffectCard({
    required this.effect,
    required this.selected,
    required this.playing,
    required this.enabled,
    required this.onTap,
  });

  final VoiceEffect effect;
  final bool selected;
  final bool playing;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(effect.color);
    final image = effect.image;
    return Semantics(
      button: true,
      selected: selected,
      label: '${effect.title} voice',
      child: AnimatedScale(
        scale: playing ? 1.05 : 1,
        duration: const Duration(milliseconds: 200),
        child: Material(
          color: selected ? color.withValues(alpha: 0.28) : GiggleColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: selected ? color : Colors.transparent, width: 2.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: 0.35),
                        ),
                        child: ClipOval(
                          child: image != null
                              ? Image.asset(image, fit: BoxFit.cover)
                              : Center(
                                  child: Text(effect.emoji, style: const TextStyle(fontSize: 38)),
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    effect.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    effect.tagline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.white60),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
