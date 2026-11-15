import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:funnyvoice/ads/ad_ids.dart';
import 'package:funnyvoice/ads/ad_service.dart';
import 'package:funnyvoice/core/clock.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Oppo Reno14 F (CPH2743) and Galaxy Tab S9 FE (SM-X510), as in Rainbow Keys.
const _testDeviceIds = ['E41E9C57CF74F7488344578B3BD4DB0F', '84F0E2335747328B9CBDB93C0D43F4FB'];

/// AdMob implementation. Consent (Google's UMP form) comes first; no ad is
/// requested until the SDK says requests are allowed.
class GoogleAdService implements AdService {
  GoogleAdService(this._clock);

  static const _interstitialGap = Duration(minutes: 3);
  static const _playsPerBreak = 4;

  final Clock _clock;
  final _ready = ValueNotifier<bool>(false);
  DateTime? _lastInterstitial;
  int _plays = 0;
  InterstitialAd? _interstitial;
  bool _started = false;

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    final consent = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        await ConsentForm.loadAndShowConsentFormIfRequired((error) {
          if (error != null) debugPrint('Consent form: ${error.message}');
        });
        consent.complete();
      },
      (error) {
        debugPrint('Consent info: ${error.message}');
        consent.complete();
      },
    );
    await consent.future;
    if (!await ConsentInformation.instance.canRequestAds()) return;
    // Our own phones get labelled test ads even in release builds.
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(testDeviceIds: _testDeviceIds),
    );
    await MobileAds.instance.initialize();
    _ready.value = true;
    _loadInterstitial();
  }

  @override
  Future<bool> privacyChoicesRequired() async {
    final status = await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
    return status == PrivacyOptionsRequirementStatus.required;
  }

  @override
  Future<void> showPrivacyChoices() => ConsentForm.showPrivacyOptionsForm((error) {
    if (error != null) debugPrint('Privacy choices: ${error.message}');
  });

  void _loadInterstitial() {
    unawaited(
      InterstitialAd.load(
        adUnitId: AdIds.interstitial,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) => _interstitial = ad,
          onAdFailedToLoad: (error) => debugPrint('Interstitial: ${error.message}'),
        ),
      ),
    );
  }

  @override
  Widget banner() => ValueListenableBuilder<bool>(
    valueListenable: _ready,
    builder: (context, ready, _) => ready ? const _BannerSlot() : const SizedBox.shrink(),
  );

  @override
  Future<void> showBreakInterstitial() async {
    _plays++;
    final ad = _interstitial;
    final last = _lastInterstitial;
    final now = _clock.now();
    if (ad == null || _plays < _playsPerBreak) return;
    if (last != null && now.difference(last) < _interstitialGap) return;
    _plays = 0;
    _interstitial = null;
    _lastInterstitial = now;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        unawaited(ad.dispose());
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        unawaited(ad.dispose());
        _loadInterstitial();
      },
    );
    await ad.show();
  }
}

class _BannerSlot extends StatefulWidget {
  const _BannerSlot();

  @override
  State<_BannerSlot> createState() => _BannerSlotState();
}

class _BannerSlotState extends State<_BannerSlot> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ad != null) return;
    final width = MediaQuery.sizeOf(context).width.truncate();
    unawaited(_load(width));
  }

  Future<void> _load(int width) async {
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (size == null || !mounted) return;
    final ad = BannerAd(
      adUnitId: AdIds.banner,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('Banner: ${error.message}');
          unawaited(ad.dispose());
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
    unawaited(_ad?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
