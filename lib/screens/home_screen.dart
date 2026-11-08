import 'package:flutter/material.dart';

import '../app/app_language.dart';
import '../app/app_theme.dart';
import '../auth/auth_controller.dart';
import '../data/program_area.dart';
import '../helpdesk/helpdesk_api.dart';
import '../helpdesk/helpdesk_common.dart';
import '../helpdesk/submit_request_screen.dart';
import '../home/hero_banner.dart';
import '../home/hero_carousel.dart';
import '../home/home_api.dart';
import '../home/home_controller.dart';
import '../home/home_search_screen.dart';
import '../home/home_sections.dart';
import '../widgets/app_components.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.language,
    required this.onOpenHelpDesk,
    required this.authController,
    required this.onOpenCommunity,
    required this.onOpenProfile,
    this.isActive = true,
    this.api,
    super.key,
  });

  final AppLanguage language;
  final VoidCallback onOpenHelpDesk;
  final AuthController authController;
  final VoidCallback onOpenCommunity;
  final VoidCallback onOpenProfile;
  final bool isActive;
  final HomeApi? api;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeController _controller;
  final _programsKey = GlobalKey();
  bool _showAllPrograms = false;

  @override
  void initState() {
    super.initState();
    _controller = HomeController(
      auth: widget.authController,
      api: widget.api ?? HomeApi(auth: widget.authController.api),
    );
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.isActive) _controller.refresh();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  AuthController get _auth => widget.authController;

  // ---------- Navigation ----------

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HomeSearchScreen(auth: _auth, api: _controller.api),
      ),
    );
  }

  void _openSubmit({String? category}) {
    final user = _auth.user;
    if (!_auth.isAuthenticated || user == null) {
      widget.onOpenProfile();
      return;
    }
    final session = HelpDeskSession(
      api: HelpDeskApi(auth: _auth.api),
      userId: user.id,
      canManage: _auth.permissions.contains('helpdesk:manage'),
      isAgent: _auth.permissions.contains('helpdesk:agent'),
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SubmitRequestScreen(session: session, initialCategory: category),
      ),
    );
  }

  Future<void> _openEmergency() async {
    final proceed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.danger,
                size: 30,
              ),
              const SizedBox(height: 10),
              Text(
                'This is not an emergency response service',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'If anyone is in immediate danger, contact your local emergency '
                'services or go to the nearest hospital first. ORAKZAI.ORG '
                'cannot dispatch help, and requests are reviewed by staff, '
                'which can take time.\n\nFor welfare follow-up after you are '
                'safe, you can send a private emergency assistance request.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                icon: const Icon(Icons.lock_outline_rounded),
                label: Text(
                  _auth.isAuthenticated
                      ? 'Open emergency assistance form'
                      : 'Sign in to send a request',
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
    if (proceed == true && mounted) {
      _openSubmit(category: 'emergency_assistance');
    }
  }

  void _scrollToPrograms() {
    final ctx = _programsKey.currentContext;
    if (ctx == null) return;
    final reduce =
        MediaQuery.of(context).disableAnimations ||
        MediaQuery.of(context).accessibleNavigation;
    Scrollable.ensureVisible(
      ctx,
      duration: reduce ? Duration.zero : const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  void _onBannerDestination(HomeBannerDestination d) {
    switch (d) {
      case HomeBannerDestination.community:
        widget.onOpenCommunity();
      case HomeBannerDestination.helpDesk:
        widget.onOpenHelpDesk();
      case HomeBannerDestination.submitRequest:
        _openSubmit();
      case HomeBannerDestination.emergencyAssistance:
        _openEmergency();
      case HomeBannerDestination.profile:
        widget.onOpenProfile();
      case HomeBannerDestination.programs:
        _scrollToPrograms();
    }
  }

  Future<void> _showProgram(ProgramArea area) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(area.icon, color: AppColors.navy),
        title: Text(area.title),
        content: SingleChildScrollView(
          child: Text(
            '${area.summary}\n\nSource: ${area.source}. This describes a '
            'public program area. Current availability of any specific '
            'service has not been confirmed in the app.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.text;
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final signedIn = _auth.isAuthenticated;
        final firstName = (_auth.user?.fullName ?? '').trim().split(' ').first;
        return SafeArea(
          bottom: false,
          child: RefreshIndicator(
            color: AppColors.navy,
            onRefresh: _controller.refresh,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 720;
                final hPad = wide ? 32.0 : 18.0;
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(hPad, 10, hPad, 32),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _HomeHeader(
                            greeting: signedIn && firstName.isNotEmpty
                                ? 'Welcome back, $firstName'
                                : copy(widget.language, 'homeTitle'),
                            onSearch: _openSearch,
                          ),
                          const SizedBox(height: 14),
                          _SearchField(
                            hint: signedIn
                                ? 'Search posts, announcements, programs'
                                : copy(widget.language, 'search'),
                            onTap: _openSearch,
                          ),
                          const SizedBox(height: 16),
                          HeroCarousel(
                            banners: homeHeroBanners,
                            onDestination: _onBannerDestination,
                            active: widget.isActive,
                          ),
                          const SizedBox(height: 6),
                          _actions(copy),
                          const SizedBox(height: 28),
                          _announcements(signedIn),
                          const SizedBox(height: 24),
                          KeyedSubtree(key: _programsKey, child: _programs()),
                          const SizedBox(height: 24),
                          _statistics(signedIn),
                          const SizedBox(height: 24),
                          _updates(signedIn),
                          const SizedBox(height: 24),
                          const HomeSectionHeader(
                            eyebrow: 'Opportunities',
                            title: 'Openings',
                          ),
                          const HomeStateCard(
                            icon: Icons.work_outline_rounded,
                            title: 'No listings yet',
                            message:
                                'Verified openings appear here once an '
                                'official source is connected.',
                          ),
                          const SizedBox(height: 28),
                          Text(
                            'Figures count records your account can see, not '
                            'worldwide membership. Photos are representative.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _actions(String Function(AppLanguage, String) copy) {
    final signedIn = _auth.isAuthenticated;
    final scale = MediaQuery.textScalerOf(context).scale(10) / 10;
    return LayoutBuilder(
      builder: (context, c) {
        final stack = c.maxWidth < 340 || scale > 1.3;
        final four = !stack && c.maxWidth >= 680;
        HomeActionTile tile(
          IconData icon,
          String title,
          String sub,
          VoidCallback onTap,
          HomeActionTone tone,
        ) => HomeActionTile(
          icon: icon,
          title: title,
          subtitle: sub,
          onTap: onTap,
          tone: tone,
          horizontal: stack,
        );
        final tiles = [
          tile(
            Icons.edit_note_rounded,
            'Submit a request',
            signedIn ? 'Private to authorised staff' : 'Sign in to send',
            _openSubmit,
            HomeActionTone.primary,
          ),
          tile(
            Icons.emergency_outlined,
            copy(widget.language, 'emergency'),
            'What to do first',
            _openEmergency,
            HomeActionTone.urgent,
          ),
          tile(
            Icons.support_agent_outlined,
            'Help Desk',
            'Your requests',
            widget.onOpenHelpDesk,
            HomeActionTone.neutral,
          ),
          tile(
            Icons.people_outline_rounded,
            'Community',
            'Groups and posts',
            widget.onOpenCommunity,
            HomeActionTone.gold,
          ),
        ];
        if (stack) {
          return Column(
            children: [
              for (final t in tiles)
                Padding(padding: const EdgeInsets.only(bottom: 10), child: t),
            ],
          );
        }
        Widget row(List<Widget> ts) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < ts.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: ts[i]),
              ],
            ],
          ),
        );
        if (four) return row(tiles);
        return Column(
          children: [
            row(tiles.sublist(0, 2)),
            const SizedBox(height: 10),
            row(tiles.sublist(2)),
          ],
        );
      },
    );
  }

  Widget _signInGate(String what) => HomeStateCard(
    icon: Icons.lock_outline_rounded,
    tone: HomeNoticeTone.gate,
    title: 'Sign in to see $what',
    message: 'This information is shared with members only.',
    actionLabel: 'Sign in',
    onAction: widget.onOpenProfile,
  );

  Widget _feedSection({
    required String eyebrow,
    required String title,
    required bool signedIn,
    required HomeSection<List<Map<String, dynamic>>> section,
    required String emptyTitle,
    required String emptyMessage,
    required String gateLabel,
  }) {
    final items = section.data ?? const <Map<String, dynamic>>[];
    Widget body;
    if (!signedIn) {
      body = _signInGate(gateLabel);
    } else if (section.error != null && items.isEmpty) {
      body = HomeStateCard(
        icon: Icons.cloud_off_rounded,
        tone: HomeNoticeTone.error,
        title: 'Could not load $gateLabel',
        message: section.error!,
        actionLabel: 'Try again',
        onAction: _controller.refresh,
      );
    } else if (section.loading && section.data == null) {
      body = const HomeSkeleton();
    } else if (items.isEmpty) {
      body = HomeStateCard(
        icon: Icons.inbox_outlined,
        title: emptyTitle,
        message: emptyMessage,
      );
    } else {
      body = Column(
        children: [
          for (final r in items)
            HomeFeedTile(
              key: ValueKey(r['id']),
              record: r,
              onOpen: widget.onOpenCommunity,
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(
          eyebrow: eyebrow,
          title: title,
          actionLabel: signedIn ? 'Open Community' : null,
          onAction: widget.onOpenCommunity,
        ),
        body,
      ],
    );
  }

  Widget _announcements(bool signedIn) => _feedSection(
    eyebrow: 'From the organization',
    title: 'Announcements',
    signedIn: signedIn,
    section: _controller.announcements,
    emptyTitle: 'No announcements yet',
    emptyMessage: 'Official announcements will appear here when posted.',
    gateLabel: 'announcements',
  );

  Widget _updates(bool signedIn) => _feedSection(
    eyebrow: 'Community',
    title: 'Latest updates',
    signedIn: signedIn,
    section: _controller.updates,
    emptyTitle: 'Nothing posted yet',
    emptyMessage: 'Posts you can see in your groups will appear here.',
    gateLabel: 'latest updates',
  );

  Widget _statistics(bool signedIn) {
    final s = _controller.statistics;
    Widget body;
    if (!signedIn) {
      body = _signInGate('your community figures');
    } else if (s.error != null && s.data == null) {
      body = HomeStateCard(
        icon: Icons.cloud_off_rounded,
        tone: HomeNoticeTone.error,
        title: 'Could not load figures',
        message: s.error!,
        actionLabel: 'Try again',
        onAction: _controller.refresh,
      );
    } else if (s.data == null) {
      body = const HomeSkeleton(lines: 1, height: 96);
    } else {
      int v(String k) => (s.data![k] as num?)?.toInt() ?? 0;
      final tiles = [
        HomeStatTile(
          value: v('accessiblePosts'),
          label: 'Visible updates',
          icon: Icons.forum_outlined,
        ),
        HomeStatTile(
          value: v('accessibleAnnouncements'),
          label: 'Announcements',
          icon: Icons.campaign_outlined,
        ),
        HomeStatTile(
          value: v('joinedGroups'),
          label: 'Your groups',
          icon: Icons.groups_outlined,
        ),
      ];
      body = LayoutBuilder(
        builder: (context, c) {
          final perRow =
              c.maxWidth < 300 ||
                  MediaQuery.textScalerOf(context).scale(10) > 16
              ? 1
              : 3;
          final w = ((c.maxWidth - 10 * (perRow - 1)) / perRow).floorToDouble();
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [for (final t in tiles) SizedBox(width: w, child: t)],
          );
        },
      );
      body = Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(20),
        ),
        child: body,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HomeSectionHeader(
          eyebrow: 'From your account',
          title: 'Your community',
        ),
        body,
      ],
    );
  }

  Widget _programs() {
    final areas = _showAllPrograms
        ? publicProgramAreas
        : publicProgramAreas.take(4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HomeSectionHeader(
          eyebrow: 'What we work on',
          title: 'Program areas',
        ),
        Text(
          'Focus areas from the public mission. Tap to read more.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        for (final a in areas)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ProgramAreaCard(area: a, onTap: () => _showProgram(a)),
          ),
        if (publicProgramAreas.length > 4)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () =>
                  setState(() => _showAllPrograms = !_showAllPrograms),
              child: Text(
                _showAllPrograms
                    ? 'Show fewer'
                    : 'Show all ${publicProgramAreas.length} program areas',
              ),
            ),
          ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.hint, required this.onTap});
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Search',
      hint: hint,
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 50),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: AppColors.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    hint,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 14.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.tune_rounded, color: AppColors.navy, size: 19),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Short reference-style header: navy brand mark, eyebrow, greeting, search.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.greeting, required this.onSearch});
  final String greeting;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Image.asset(
              'assets/images/orakzai_emblem.png',
              fit: BoxFit.cover,
              excludeFromSemantics: true,
              errorBuilder: (context, _, _) =>
                  const Icon(Icons.public_rounded, color: AppColors.gold),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ORAKZAI.ORG',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.goldDeep,
                  fontSize: 10.5,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                greeting,
                style: theme.textTheme.titleLarge?.copyWith(fontSize: 20),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.line),
          ),
          child: IconButton(
            tooltip: 'Search',
            onPressed: onSearch,
            icon: const Icon(Icons.search_rounded, color: AppColors.ink),
          ),
        ),
      ],
    );
  }
}
