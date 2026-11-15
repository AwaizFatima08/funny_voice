# Giggle Voice (HomiLabs): project notes

Flutter Android app: tap the mic, talk, and hear yourself back in one of 13 funny voices (Chipmunk, Helium, Giant,
Monster, Robot, Alien, Echo Cave, Underwater, Old Radio, Ghost, Fast Talker, Slow-mo, Reverse). Package
`com.homilabs.funnyvoice` (locked after the first Play upload), Dart package `funnyvoice`, launcher name "Giggle
Voice". General audience (13+), Homi's choice 15 Nov 2026. Started 15 Nov 2026.

## Locations
- Code: `/mnt/storage/projects/Tools/funny_voice_encoder` · GitHub `AwaizFatima08/funny_voice` (PUBLIC: no secrets)
- Local backup: `/mnt/storage/project_backups/Tools/funny_voice_encoder_backup` via `bash scripts/backup.sh`
- Site: slug `gigglevoice` on https://tools.homilabs.org (privacy#gigglevoice, terms#gigglevoice). Blocks in
  `/mnt/storage/projects/homilabs_tools/tools/gigglevoice_*.block`, applied by `tools/add_gigglevoice.py`
  (run it on pages fetched from the live site, never overwrite live pages with local copies).

## How it works
- Recording: `record` package, WAV 44.1 kHz mono, max 30 s (`lib/features/voice/voice_io.dart`).
- Effects: pure Dart DSP in `lib/audio/` (WSOLA pitch shift, biquads, Freeverb-style reverb, echo, ring mod…),
  rendered in a background isolate and cached per recording. Nothing leaves the phone; no INTERNET use except ads.
- Near-silent recordings are refused (peak < 0.01) and normalise gain is capped at 30x, so hiss is never blown up.
- Graphics: Z-Image on homidev (asset pipeline, see ~/.claude/homidev.md); emoji stand in until approved art lands.

## Ads
AdMob homilabs.smc@gmail.com: app `~1712106601`, `gigglevoice_home_banner`, `gigglevoice_break_interstitial`
(ids in `config/admob.json`). Banner at the bottom of home; interstitial after every 4th finished playback, at
most every 3 min, never while recording. UMP consent first; EU message "Giggle Voice consent" published 16 Nov 2026.
Debug builds use Google test units; `bash scripts/check-release-ad-ids.sh` must pass before a release build.
Oppo CPH2743 and Tab S9 FE are registered test devices.

## Release
- Upload key `.secrets/gigglevoice-upload.keystore` (gitignored; password in
  `.secrets/gigglevoice-upload-keystore-credentials.txt`; `android/key.properties` points at it). Losing it blocks
  Play updates; the local backup copies `.secrets/`.
- Build: `jobq run --name gigglevoice-release-aab -- bash -c 'flutter build appbundle --release --obfuscate
  --split-debug-info=build/symbols && cd android && ./gradlew --stop'`, then copy to `releases/v<version>-<build>/`.
- Emulator: AVD `gigglevoice_api35` (port 5592) in `/mnt/storage/projects/android-avd`, always through `jobq`.
  Its mic records silence, so real voice checks need a phone.

## Gate before commit
```
dart format --set-exit-if-changed lib test
flutter analyze
flutter test
```
