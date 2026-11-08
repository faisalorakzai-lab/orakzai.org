import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import 'helpdesk_common.dart';
import 'helpdesk_content_screen.dart';
import 'helpdesk_widgets.dart';
import 'requests_list_screen.dart';

/// Staff Dashboard. Counts come from real /admin/requests totals per status.
class StaffDashboardScreen extends StatefulWidget {
  const StaffDashboardScreen({required this.session, super.key});
  final HelpDeskSession session;

  @override
  State<StaffDashboardScreen> createState() => _StaffDashboardScreenState();
}

class _StaffDashboardScreenState extends State<StaffDashboardScreen> {
  static const _tracked = ['submitted', 'under_review', 'assigned', 'in_progress', 'waiting_for_member'];
  Map<String, int>? _counts;
  int _all = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _counts = null;
      _error = null;
    });
    try {
      final api = widget.session.api;
      final results = await Future.wait([
        api.get('/admin/requests', query: {'limit': '1', 'offset': '0'}),
        for (final s in _tracked) api.get('/admin/requests', query: {'status': s, 'limit': '1', 'offset': '0'}),
      ]);
      if (!mounted) return;
      setState(() {
        _all = hdInt(results[0]['total']);
        _counts = {for (var i = 0; i < _tracked.length; i++) _tracked[i]: hdInt(results[i + 1]['total'])};
      });
    } catch (e) {
      if (mounted) setState(() => _error = hdError(e));
    }
  }

  Future<void> _openQueue([String? status]) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                RequestsListScreen(session: widget.session, mode: RequestListMode.staffQueue, initialStatus: status)));
    if (mounted) _load();
  }

  Future<void> _newDepartment() async {
    final ok = await hdTextDialog(
      context,
      title: 'New department',
      submitLabel: 'Create',
      fields: const [HdDialogField('Department name', min: 2, max: 100)],
      onSubmit: (v) => widget.session.api.post('/admin/departments', {'name': v[0]}),
    );
    if (ok && mounted) hdSnack(context, 'Department created.');
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return HdScaffold(
      title: 'Staff dashboard',
      subtitle: s.canManage ? 'Manager access: assign, publish and oversee requests.' : 'Agent access: reply and update requests you handle.',
      onRefresh: _load,
      children: [
        if (_error != null)
          HdErrorPanel(message: _error!, onRetry: _load)
        else if (_counts == null)
          const HdSkeleton(rows: 2, height: 90)
        else ...[
          HdCard(
            onTap: () => _openQueue(),
            accent: AppColors.gold,
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('YOUR QUEUE', style: TextStyle(color: AppColors.muted, fontSize: 11, letterSpacing: 1.2)),
                  Text('$_all', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: AppColors.navy)),
                  const Text('requests visible to you', style: TextStyle(color: AppColors.muted)),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.navy),
            ]),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.7,
            children: [
              for (final st in _tracked)
                HdCard(
                  onTap: () => _openQueue(st),
                  accent: hdStatusColor(st),
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('${_counts![st]}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: hdStatusColor(st))),
                    Text(hdStatus(st), style: const TextStyle(color: AppColors.ink, fontSize: 13)),
                  ]),
                ),
            ],
          ),
        ],
        const HdSectionTitle('Tools'),
        _tool(Icons.inbox_outlined, 'Open request queue', 'Filter, search and manage requests', () => _openQueue()),
        if (s.canManage) ...[
          _tool(Icons.quiz_outlined, 'Maintain FAQs', 'Publish answers to common questions',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => HelpDeskContentScreen(session: s, mode: HelpDeskContentMode.faqs)))),
          _tool(Icons.campaign_outlined, 'Post announcements', 'Share important notices with members',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => HelpDeskContentScreen(session: s, mode: HelpDeskContentMode.announcements)))),
          _tool(Icons.apartment_rounded, 'Add department', 'Create a team that requests can be routed to', _newDepartment),
        ],
      ],
    );
  }

  Widget _tool(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return Padding(
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
}
