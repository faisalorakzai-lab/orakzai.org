import 'package:flutter/widgets.dart';

/// Where a hero banner call-to-action leads inside the native app.
enum HomeBannerDestination {
  community,
  helpDesk,
  submitRequest,
  emergencyAssistance,
  profile,
  programs,
}

/// Immutable hero banner. Provide either [imageAsset] or an HTTPS [imageUrl].
@immutable
class HomeHeroBanner {
  const HomeHeroBanner({
    required this.id,
    required this.semanticLabel,
    this.heading,
    this.subtitle,
    this.ctaLabel,
    this.destination,
    this.imageAsset,
    this.imageUrl,
    this.alignment = Alignment.center,
    this.isPlaceholder = false,
    this.fit = BoxFit.cover,
    this.aspectRatio,
  }) : assert(
         imageUrl == null || imageAsset == null,
         'Use either imageAsset or imageUrl, not both.',
       ),
       assert(aspectRatio == null || aspectRatio > 0);

  final String id;
  final String? heading;
  final String? subtitle;
  final String? ctaLabel;
  final HomeBannerDestination? destination;
  final String? imageAsset;

  /// Must be HTTPS; non-HTTPS URLs are ignored and the fallback is shown.
  final String? imageUrl;
  final Alignment alignment;

  /// Accessible description of the artwork.
  final String semanticLabel;

  /// True while approved artwork is still pending.
  final bool isPlaceholder;

  /// How the artwork fills its frame. Use [BoxFit.contain] for posters with
  /// baked-in typography so nothing is cropped.
  final BoxFit fit;

  /// When set (e.g. 1.0 for square posters) the artwork is shown at this
  /// ratio with any CTA placed below the image, never over it.
  final double? aspectRatio;

  bool get isPoster => aspectRatio != null;

  bool get hasSecureUrl =>
      imageUrl != null && Uri.tryParse(imageUrl!)?.scheme == 'https';

  bool get hasCta => ctaLabel != null && destination != null;
}

/// Home hero slides: clean, text-free representative stock photography with
/// all writing rendered natively. Photos illustrate themes only; they are not
/// documented organization activities or actual Orakzai places.
const homeHeroBanners = <HomeHeroBanner>[
  HomeHeroBanner(
    id: 'community',
    heading: 'Together, wherever we live.',
    subtitle: 'One network for Orakzai families at home and abroad.',
    imageAsset: 'assets/images/home_photos/community.jpg',
    alignment: Alignment(0, -0.2),
    semanticLabel: 'Representative photo: hands joined together over a table',
    ctaLabel: 'Open Community',
    destination: HomeBannerDestination.community,
  ),
  HomeHeroBanner(
    id: 'education',
    heading: 'Education opens doors.',
    subtitle: 'Learning and opportunity are core program areas.',
    imageAsset: 'assets/images/home_photos/education.jpg',
    semanticLabel: 'Representative photo: a person studying',
    ctaLabel: 'Read program areas',
    destination: HomeBannerDestination.programs,
  ),
  HomeHeroBanner(
    id: 'care',
    heading: 'Support, asked for privately.',
    subtitle: 'Requests are reviewed by authorised staff.',
    imageAsset: 'assets/images/home_photos/care.jpg',
    semanticLabel: 'Representative photo: a doctor in consultation',
    ctaLabel: 'Open Help Desk',
    destination: HomeBannerDestination.helpDesk,
  ),
  HomeHeroBanner(
    id: 'opportunities',
    heading: 'Building what comes next.',
    subtitle: 'Community development for the next generation.',
    imageAsset: 'assets/images/home_photos/opportunities.jpg',
    semanticLabel: 'Representative photo: a team planning together',
    ctaLabel: 'Read program areas',
    destination: HomeBannerDestination.programs,
  ),
  HomeHeroBanner(
    id: 'heritage',
    heading: 'Shared roots. Shared future.',
    subtitle: 'Stay connected to the people who share your story.',
    imageAsset: 'assets/images/home_photos/heritage.jpg',
    alignment: Alignment(0, 0.2),
    semanticLabel: 'Representative photo: a mountain landscape',
    ctaLabel: 'Open Community',
    destination: HomeBannerDestination.community,
  ),
];

/// Reusable placeholder set for future slots whose artwork is missing.
/// Placeholders use only the official emblem and describe real app features.
const homePlaceholderBanners = <HomeHeroBanner>[
  HomeHeroBanner(
    id: 'placeholder-community',
    heading: 'A home for the Orakzai community, wherever you live',
    subtitle: 'Temporary banner. Approved artwork is pending.',
    ctaLabel: 'Open Community',
    destination: HomeBannerDestination.community,
    imageAsset: 'assets/images/orakzai_emblem.png',
    semanticLabel: 'Temporary placeholder banner with the ORAKZAI.ORG emblem',
    isPlaceholder: true,
  ),
  HomeHeroBanner(
    id: 'placeholder-help',
    heading: 'Ask for support privately',
    subtitle: 'Temporary banner. Requests are reviewed by authorised staff.',
    ctaLabel: 'Submit a request',
    destination: HomeBannerDestination.submitRequest,
    imageAsset: 'assets/images/orakzai_emblem.png',
    alignment: Alignment.topCenter,
    semanticLabel: 'Temporary placeholder banner with the ORAKZAI.ORG emblem',
    isPlaceholder: true,
  ),
  HomeHeroBanner(
    id: 'placeholder-programs',
    heading: 'Program areas from our public mission',
    subtitle: 'Temporary banner. Artwork pending approval.',
    ctaLabel: 'Read program areas',
    destination: HomeBannerDestination.programs,
    imageAsset: 'assets/images/orakzai_emblem.png',
    alignment: Alignment.bottomCenter,
    semanticLabel: 'Temporary placeholder banner with the ORAKZAI.ORG emblem',
    isPlaceholder: true,
  ),
  HomeHeroBanner(
    id: 'placeholder-profile',
    heading: 'Your account, your language',
    subtitle: 'Temporary banner. Artwork pending approval.',
    ctaLabel: 'Open Profile',
    destination: HomeBannerDestination.profile,
    imageAsset: 'assets/images/orakzai_emblem.png',
    semanticLabel: 'Temporary placeholder banner with the ORAKZAI.ORG emblem',
    isPlaceholder: true,
  ),
];
