import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import 'hero_banner.dart';

/// Native hero carousel: manual swipe, 4-second auto paging, indicator
/// navigation, accessible pause/resume, and motion/visibility aware pausing.
class HeroCarousel extends StatefulWidget {
  const HeroCarousel({
    required this.banners,
    required this.onDestination,
    this.active = true,
    this.interval = const Duration(seconds: 4),
    super.key,
  });

  final List<HomeHeroBanner> banners;
  final ValueChanged<HomeBannerDestination> onDestination;
  final bool active;
  final Duration interval;

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel>
    with WidgetsBindingObserver {
  final PageController _controller = PageController();
  Timer? _timer;
  int _index = 0;
  bool _userPaused = false;
  bool _touching = false;
  bool _focused = false;
  bool _appActive = true;

  bool get _reducedMotion {
    final mq = MediaQuery.maybeOf(context);
    return mq != null && (mq.disableAnimations || mq.accessibleNavigation);
  }

  bool get _routeCurrent => ModalRoute.of(context)?.isCurrent ?? true;

  bool get _shouldRun =>
      mounted &&
      widget.banners.length > 1 &&
      widget.active &&
      _appActive &&
      !_userPaused &&
      !_touching &&
      !_focused &&
      !_reducedMotion &&
      TickerMode.of(context) &&
      _routeCurrent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
    _precacheNext();
  }

  @override
  void didUpdateWidget(HeroCarousel old) {
    super.didUpdateWidget(old);
    if (_index >= widget.banners.length) _index = 0;
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    if (!mounted) return;
    // Route coverage changes without notifying; re-check on each tick.
    if (_shouldRun) {
      _timer ??= Timer.periodic(widget.interval, (_) => _tick());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _tick() {
    if (!_shouldRun) {
      _sync();
      return;
    }
    _goTo((_index + 1) % widget.banners.length);
  }

  void _goTo(int page) {
    if (!_controller.hasClients) return;
    if (_reducedMotion) {
      _controller.jumpToPage(page);
    } else {
      _controller.animateToPage(
        page,
        duration: const Duration(milliseconds: 560),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _restart() {
    _timer?.cancel();
    _timer = null;
    _sync();
  }

  void _precacheNext() {
    if (widget.banners.length < 2) return;
    final next = widget.banners[(_index + 1) % widget.banners.length];
    final provider = _providerFor(next);
    if (provider != null) {
      precacheImage(provider, context, onError: (_, _) {});
    }
  }

  ImageProvider? _providerFor(HomeHeroBanner b) {
    final width = (MediaQuery.maybeSizeOf(context)?.width ?? 400) *
        (MediaQuery.maybeDevicePixelRatioOf(context) ?? 2);
    final cacheWidth = math.min(width.round(), 1600);
    if (b.imageAsset != null) {
      return ResizeImage.resizeIfNeeded(
          cacheWidth, null, AssetImage(b.imageAsset!));
    }
    if (b.hasSecureUrl) {
      return ResizeImage.resizeIfNeeded(
          cacheWidth, null, NetworkImage(b.imageUrl!));
    }
    return null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.banners.isEmpty) return const SizedBox.shrink();
    // Keep timer state aligned with TickerMode/route on rebuilds.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = _HeroLayout.measure(
          context: context,
          width: width,
          banners: widget.banners,
        );
        final multiple = widget.banners.length > 1;

        return Center(
         child: SizedBox(
          width: width,
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Focus(
              onFocusChange: (f) {
                _focused = f;
                _restart();
              },
              child: Listener(
                onPointerDown: (_) {
                  _touching = true;
                  _restart();
                },
                onPointerUp: (_) {
                  _touching = false;
                  _restart();
                },
                onPointerCancel: (_) {
                  _touching = false;
                  _restart();
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: SizedBox(
                    height: height,
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: widget.banners.length,
                      onPageChanged: (i) {
                        setState(() => _index = i);
                        _precacheNext();
                      },
                      itemBuilder: (context, i) => _PhotoSlide(
                        banner: widget.banners[i],
                        provider: _providerFor(widget.banners[i]),
                        position: i + 1,
                        total: widget.banners.length,
                        onDestination: widget.onDestination,
                        width: width,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (multiple) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 0,
                      children: [
                        for (var i = 0; i < widget.banners.length; i++)
                          Semantics(
                            button: true,
                            selected: i == _index,
                            label:
                                'Show banner ${i + 1} of ${widget.banners.length}',
                            child: InkResponse(
                              onTap: () {
                                _goTo(i);
                                _restart();
                              },
                              radius: 20,
                              child: SizedBox(
                                width: 48,
                                height: 48,
                                child: Center(
                                  child: AnimatedContainer(
                                    duration: _reducedMotion
                                        ? Duration.zero
                                        : const Duration(milliseconds: 260),
                                    width: i == _index ? 20 : 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: i == _index
                                          ? AppColors.gold
                                          : AppColors.navy
                                              .withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!_reducedMotion)
                    IconButton(
                      tooltip: _userPaused
                          ? 'Resume automatic banners'
                          : 'Pause automatic banners',
                      onPressed: () {
                        setState(() => _userPaused = !_userPaused);
                        _restart();
                      },
                      icon: Icon(
                        _userPaused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                        color: AppColors.navy,
                      ),
                    ),
                ],
              ),
            ],
          ],
          ),
         ),
        );
      },
    );
  }
}

/// Measured hero geometry. Text is laid out with the exact styles, width
/// and text scaler used by [_PhotoSlide], so large fonts grow the card.
class _HeroLayout {
  static const padH = 20.0;
  static const padTop = 20.0;
  static const padBottom = 20.0;

  static TextStyle eyebrowStyle(BuildContext c) =>
      Theme.of(c).textTheme.labelSmall!.copyWith(
          color: AppColors.gold, fontSize: 10.5, letterSpacing: 1.6,
          fontWeight: FontWeight.w800);
  static TextStyle headingStyle(BuildContext c) =>
      Theme.of(c).textTheme.headlineSmall!.copyWith(
          color: AppColors.onDark, fontSize: 25, height: 1.15,
          letterSpacing: -0.5);
  static TextStyle subtitleStyle(BuildContext c) =>
      Theme.of(c).textTheme.bodyMedium!.copyWith(
          color: AppColors.onDark.withValues(alpha: 0.86),
          fontSize: 14, height: 1.4);
  static TextStyle ctaStyle(BuildContext c) =>
      Theme.of(c).textTheme.labelLarge!.copyWith(fontSize: 14);

  static double textWidth(double width) =>
      math.min(width - padH * 2, 460.0);

  static double _h(BuildContext c, String? t, TextStyle s, double w) {
    if (t == null || t.isEmpty) return 0;
    final tp = TextPainter(
      text: TextSpan(text: t, style: s),
      textDirection: Directionality.of(c),
      textScaler: MediaQuery.textScalerOf(c),
    )..layout(maxWidth: math.max(1, w));
    final h = tp.height;
    tp.dispose();
    return h;
  }

  static double measure({
    required BuildContext context,
    required double width,
    required List<HomeHeroBanner> banners,
  }) {
    final textW = textWidth(width);
    var text = 0.0;
    for (final b in banners) {
      var h = _h(context, 'ORAKZAI.ORG', eyebrowStyle(context), textW) + 8;
      h += _h(context, b.heading, headingStyle(context), textW);
      if (b.subtitle != null) {
        h += 6 + _h(context, b.subtitle, subtitleStyle(context), textW);
      }
      if (b.hasCta) {
        // Button: 16px side padding x2, 18px icon, 8px gap.
        final label = _h(context, b.ctaLabel, ctaStyle(context), textW - 60);
        h += 16 + math.max(48.0, label + 24);
      }
      text = math.max(text, h);
    }
    // Photo needs breathing room above the copy; 8px rounding slack.
    final photo = (width * 0.66).clamp(236.0, 380.0);
    return math.max(photo, padTop + 64 + text + padBottom + 8);
  }
}

/// Full-bleed photo slide with native copy over a navy scrim.
class _PhotoSlide extends StatelessWidget {
  const _PhotoSlide({
    required this.banner,
    required this.provider,
    required this.position,
    required this.total,
    required this.onDestination,
    required this.width,
  });

  final HomeHeroBanner banner;
  final ImageProvider? provider;
  final int position;
  final int total;
  final ValueChanged<HomeBannerDestination> onDestination;
  final double width;

  @override
  Widget build(BuildContext context) {
    final textW = _HeroLayout.textWidth(width);
    return Semantics(
      container: true,
      label: 'Banner $position of $total',
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: AppColors.navy),
          if (provider != null)
            Image(
              image: provider!,
              fit: BoxFit.cover,
              alignment: banner.alignment,
              semanticLabel: banner.semanticLabel,
              gaplessPlayback: true,
              frameBuilder: (context, child, frame, sync) =>
                  sync || frame != null
                      ? child
                      : const ColoredBox(color: AppColors.navySoft),
              errorBuilder: (context, _, _) => const _ImageError(),
            )
          else
            const _ImageError(),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x1A071427),
                  Color(0x80071427),
                  Color(0xF2071427),
                ],
                stops: [0.0, 0.42, 1.0],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(_HeroLayout.padH,
                _HeroLayout.padTop, _HeroLayout.padH, _HeroLayout.padBottom),
            child: Align(
              alignment: AlignmentDirectional.bottomStart,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: math.max(1, textW)),
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('ORAKZAI.ORG',
                          style: _HeroLayout.eyebrowStyle(context)),
                      const SizedBox(height: 8),
                      if (banner.heading != null)
                        Text(banner.heading!,
                            style: _HeroLayout.headingStyle(context)),
                      if (banner.subtitle != null) ...[
                        const SizedBox(height: 6),
                        Text(banner.subtitle!,
                            style: _HeroLayout.subtitleStyle(context)),
                      ],
                      if (banner.hasCta) ...[
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => onDestination(banner.destination!),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.gold,
                            foregroundColor: AppColors.navyDeep,
                            minimumSize: const Size(48, 48),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            textStyle: _HeroLayout.ctaStyle(context),
                          ),
                          icon: const Icon(Icons.arrow_forward_rounded,
                              size: 18),
                          label: Text(banner.ctaLabel!),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageError extends StatelessWidget {
  const _ImageError();
  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: AppColors.navySoft,
        child: Align(
          alignment: Alignment(0.8, -0.6),
          child: Icon(Icons.image_not_supported_outlined,
              color: AppColors.gold, size: 30),
        ),
      );
}
