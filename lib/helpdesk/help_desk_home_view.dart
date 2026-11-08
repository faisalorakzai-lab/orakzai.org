import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import 'helpdesk_common.dart';
import 'helpdesk_content_screen.dart';
import 'helpdesk_widgets.dart';
import 'requests_list_screen.dart';
import 'staff_dashboard_screen.dart';
import 'submit_request_screen.dart';
import 'category_selection_screen.dart';
import 'track_request_screen.dart';

/// Help Desk Home content for a signed-in member.
class HelpDeskHomeView extends StatefulWidget {
  const HelpDeskHomeView({required this.session, required this.home, required this.onReload, super.key});
  final HelpDeskSession session;
  final Map<String, dynamic> home;
  final Future<void> Function() onReload;

  @override
  State<HelpDeskHomeView> createState() => _HelpDeskHomeViewState();
}

class _HelpDeskHomeViewState extends State<HelpDeskHomeView> {
  late bool _notify = widget.home['notificationsEnabled'] == true;
  bool _savingPref = false;

  @override
  void didUpdateWidget(covariant HelpDeskHomeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_savingPref) _notify = widget.home['notificationsEnabled'] == true;
  }

  Future<void> _go(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) widget.onReload();
  }

  Future<void> _newRequest() async {
    final category = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => const CategorySelectionScreen()));
    if (category == null || !mounted) return;
    await _go(SubmitRequestScreen(session: widget.session, initialCategory: category));
  }

  Future<void> _toggle(bool value) async {
    setState(() {
      _notify = value;
      _savingPref = true;
    });
    try {
      await widget.session.api.patch('/preferences', {'enabled': value});
    } catch (e) {
      if (!mounted) return;
      setState(() => _notify = !value);
      hdSnack(context, hdError(e), error: true);
    } finally {
      if (mounted) setState(() => _savingPref = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = hdMap(widget.home['stats']);
    final s = widget.session;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(22)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.lock_outline_rounded, color: AppColors.gold, size: 18),
              SizedBox(width: 8),
              Text('YOUR REQUESTS', style: TextStyle(color: AppColors.gold, fontSize: 11, letterSpacing: 1.3, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              _stat('Total', stats['total']),
              _stat('Pending', stats['pending']),
              _stat('In progress', stats['inProgress']),
              _stat('Resolved', stats['resolved']),
            ]),
            const SizedBox(height: 12),
            const Text('Private to you and authorised help desk staff.',
                style: TextStyle(color: Colors.white70, fontSize: 12.5)),
          ]),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _newRequest,
          icon: const Icon(Icons.edit_note_rounded),
          label: const Text('Submit new request'),
          style: FilledButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.navy,
              padding: const EdgeInsets.symmetric(vertical: 15)),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _go(RequestsListScreen(session: s)),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('My requests'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _go(TrackRequestScreen(session: s)),
              icon: const Icon(Icons.manage_search_rounded),
              label: const Text('Track application'),
            ),
          ),
        ]),
        const HdSectionTitle('Get help with'),
        _shortcutGrid(context),
        const SizedBox(height: 8),
        const HdSectionTitle('Stay informed'),
        _row(Icons.campaign_outlined, 'Important announcements', 'Notices from the help desk team',
            () => _go(HelpDeskContentScreen(session: s, mode: HelpDeskContentMode.announcements))),
        _row(Icons.quiz_outlined, 'FAQ', 'Answers to common questions',
            () => _go(HelpDeskContentScreen(session: s, mode: HelpDeskContentMode.faqs))),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Help desk notifications'),
          subtitle: const Text('Updates when staff reply or change a request status.'),
          value: _notify,
          onChanged: _savingPref ? null : _toggle,
        ),
        if (s.isStaff) ...[
          const HdSectionTitle('Staff'),
          _row(Icons.space_dashboard_outlined, 'Staff dashboard', s.canManage ? 'Queue, assignment and publishing' : 'Your request queue',
              () => _go(StaffDashboardScreen(session: s))),
        ],
        const SizedBox(height: 14),
        const HdNotice(
          title: 'Not an emergency service',
          message: 'For immediate danger, contact local emergency services or the nearest hospital first.',
          icon: Icons.warning_amber_rounded,
          tone: HdTone.danger,
        ),
      ],
    );
  }

  Widget _stat(String label, Object? value) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${hdInt(value)}', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
        ]),
      );

  Widget _shortcutGrid(BuildContext context) {
    final items = <(IconData, String, String, bool)>[
      (Icons.report_outlined, 'Complaints', 'complaints', false),
      (Icons.help_outline_rounded, 'General support', 'general_inquiry', false),
      (Icons.build_circle_outlined, 'Technical support', 'technical_support', false),
      (Icons.volunteer_activism_outlined, 'Community assistance', 'social_welfare', false),
      (Icons.warning_amber_rounded, 'Emergency assistance', 'emergency_assistance', true),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final (icon, label, category, urgent) in items)
          SizedBox(
            width: (MediaQuery.sizeOf(context).width - 50) / 2,
            child: HdCard(
              onTap: () => _go(SubmitRequestScreen(session: widget.session, initialCategory: category)),
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, color: urgent ? AppColors.danger : AppColors.navy),
                const SizedBox(height: 10),
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
              ]),
            ),
          ),
      ],
    );
  }

  Widget _row(IconData icon, String title, String subtitle, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: HdCard(
          onTap: onTap,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Icon(icon, color: AppColors.navy),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ]),
        ),
      );
}
