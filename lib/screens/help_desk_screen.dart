import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import '../helpdesk/help_desk_home_view.dart';
import '../helpdesk/helpdesk_notifications_screen.dart';
import '../helpdesk/helpdesk_api.dart';
import '../helpdesk/helpdesk_common.dart';
import '../helpdesk/helpdesk_widgets.dart';
import '../widgets/app_components.dart';

class HelpDeskScreen extends StatefulWidget {
  const HelpDeskScreen({
    required this.authController,
    required this.onOpenProfile,
    this.api,
    super.key,
  });

  final AuthController authController;
  final VoidCallback onOpenProfile;

  /// Optional injected client (tests only). Production builds its own.
  final HelpDeskApi? api;

  @override
  State<HelpDeskScreen> createState() => _HelpDeskScreenState();
}

class _HelpDeskScreenState extends State<HelpDeskScreen> {
  late final HelpDeskApi _api =
      widget.api ?? HelpDeskApi(auth: widget.authController.api);
  Map<String, dynamic>? _home;
  String? _error;
  bool _loading = false;
  String? _loadedFor;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.authController.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  @override
  void dispose() {
    widget.authController.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    final auth = widget.authController;
    final uid = auth.isAuthenticated ? auth.user!.id : null;
    if (uid == _loadedFor) return;
    _loadedFor = uid;
    _generation++;
    _home = null;
    _error = null;
    if (uid != null) unawaited(_load());
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (!widget.authController.isAuthenticated) return;
    final gen = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.get('/home');
      if (!mounted || gen != _generation) return;
      setState(() => _home = res);
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() => _error = hdError(e));
    } finally {
      if (mounted && gen == _generation) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.authController,
      builder: (context, _) {
        final auth = widget.authController;
        return AppPage(
          title: 'Help Desk',
          subtitle: 'Private assistance from the ORAKZAI.ORG community team.',
          child: _body(auth),
        );
      },
    );
  }

  Widget _body(AuthController auth) {
    if (auth.status == AuthStatus.restoring) {
      return const HdSkeleton(rows: 3, height: 90);
    }
    if (!auth.isAuthenticated) {
      return HdNotice(
        title: 'Sign in to use the Help Desk',
        message:
            'Requests, conversations and documents are private to your account and the staff assigned to help you.',
        icon: Icons.lock_outline_rounded,
        action: FilledButton.icon(
          onPressed: widget.onOpenProfile,
          icon: const Icon(Icons.login_rounded),
          label: const Text('Open account'),
        ),
      );
    }
    if (_home == null) {
      if (_error != null) return HdErrorPanel(message: _error!, onRetry: _load);
      return const HdSkeleton(rows: 3, height: 90);
    }
    final caps = hdMap(_home!['capabilities']);
    final session = HelpDeskSession(
      api: _api,
      userId: auth.user!.id,
      canManage: caps['manage'] == true,
      isAgent: caps['agent'] == true,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_error != null) ...[
          HdErrorPanel(message: _error!, onRetry: _load),
          const SizedBox(height: 12),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.notifications_outlined),
            label: const Text('Help Desk updates'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => HelpDeskNotificationsScreen(session: session),
              ),
            ),
          ),
        ),
        HelpDeskHomeView(session: session, home: _home!, onReload: _load),
      ],
    );
  }
}
