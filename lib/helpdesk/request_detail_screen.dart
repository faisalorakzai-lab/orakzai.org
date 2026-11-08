import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import 'helpdesk_common.dart';
import 'helpdesk_widgets.dart';
import 'request_attachments_screen.dart';
import 'request_conversation_screen.dart';
import 'request_history_screen.dart';
import 'request_management_screen.dart';

/// Request Details for the owner (and staff viewing as members).
class RequestDetailScreen extends StatefulWidget {
  const RequestDetailScreen({required this.session, required this.requestId, super.key});
  final HelpDeskSession session;
  final String requestId;

  @override
  State<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends State<RequestDetailScreen> {
  Map<String, dynamic>? _req;
  String? _error;
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.session.api.get('/requests/${widget.requestId}');
      if (!mounted) return;
      setState(() {
        _req = hdRequest(res);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = hdError(e);
        _loading = false;
      });
    }
  }

  Future<void> _reopen() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reopen this request?'),
        content: const Text('Staff will be asked to look at it again. Resolved requests can be reopened within 7 days.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reopen')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _working = true);
    try {
      await widget.session.api.patch('/requests/${widget.requestId}', {'action': 'reopen'});
      if (mounted) hdSnack(context, 'Request reopened.');
      await _load();
    } catch (e) {
      if (mounted) hdSnack(context, hdError(e), error: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _setMuted(bool muted) async {
    final previous = _req!['muted'];
    setState(() => _req!['muted'] = muted);
    try {
      await widget.session.api.patch('/requests/${widget.requestId}/preferences', {'muted': muted});
    } catch (e) {
      if (!mounted) return;
      setState(() => _req!['muted'] = previous);
      hdSnack(context, hdError(e), error: true);
    }
  }

  void _push(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _req == null) {
      return const HdScaffold(title: 'Request', children: [HdSkeleton(rows: 1, height: 140), HdSkeleton(rows: 3, height: 56)]);
    }
    if (_req == null) {
      return HdScaffold(title: 'Request', children: [HdErrorPanel(message: _error ?? 'Unavailable', onRetry: _load)]);
    }
    final r = _req!;
    final status = hdStr(r['status']);
    final geoText = [r['region'], r['district'], r['qoum'], r['village']]
        .where((v) => v != null && v.toString().isNotEmpty)
        .join(', ');
    final contact = r['contact'];
    final canManage = r['canManage'] == true || r['canStaffReply'] == true;
    return HdScaffold(
      title: hdStr(r['title']),
      onRefresh: _load,
      children: [
        Row(children: [
          Text(hdStr(r['reference']),
              style: const TextStyle(fontFamily: 'monospace', color: AppColors.navy, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          const Spacer(),
          HdPill.status(status),
        ]),
        const SizedBox(height: 14),
        if (status == 'waiting_for_member') ...[
          const HdNotice(
            title: 'Staff are waiting for you',
            message: 'Open the conversation to see what information or documents are needed.',
            icon: Icons.mark_chat_unread_outlined,
            tone: HdTone.warning,
          ),
          const SizedBox(height: 12),
        ],
        HdCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            HdKeyValue('Category', hdCategory(hdStr(r['category']))),
            HdKeyValue('Priority', hdPriority(hdStr(r['priority']))),
            HdKeyValue('Department', hdStr(r['departmentName'])),
            HdKeyValue('Handled by', hdStr(r['assignedName']).isEmpty ? 'Not yet assigned' : hdStr(r['assignedName'])),
            HdKeyValue('Location', geoText),
            HdKeyValue('Contact by', switch (hdStr(r['contactPreference'])) {
              'email' => 'Email',
              'phone' => 'Phone',
              _ => 'In the app',
            }),
            if (contact is Map) HdKeyValue('Member contact', contact.values.where((v) => v != null).join(' / ')),
            HdKeyValue('Submitted', hdDate(r['createdAt'])),
            HdKeyValue('Last update', hdDate(r['updatedAt'])),
            if (r['resolvedAt'] != null) HdKeyValue('Resolved', hdDate(r['resolvedAt'])),
          ]),
        ),
        const HdSectionTitle('Description'),
        HdCard(child: SelectableText(hdStr(r['description']), style: Theme.of(context).textTheme.bodyLarge)),
        const HdSectionTitle('Follow up'),
        _action(Icons.forum_outlined, 'Conversation', 'Messages with the help desk team',
            () => _push(RequestConversationScreen(session: widget.session, request: r))),
        _action(Icons.attach_file_rounded, 'Attachments', 'Documents and images on this request',
            () => _push(RequestAttachmentsScreen(session: widget.session, requestId: widget.requestId, status: status))),
        _action(Icons.history_rounded, 'History', 'Status changes and assignments',
            () => _push(RequestHistoryScreen(session: widget.session, requestId: widget.requestId))),
        if (canManage)
          _action(Icons.admin_panel_settings_outlined, 'Manage request', 'Staff tools: status, notes, assignment',
              () => _push(RequestManagementScreen(session: widget.session, requestId: widget.requestId))),
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Mute notifications for this request'),
          subtitle: const Text('You can still open it here at any time.'),
          value: r['muted'] == true,
          onChanged: _setMuted,
        ),
        if (r['canReopen'] == true) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _working ? null : _reopen,
            icon: const Icon(Icons.replay_rounded),
            label: const Text('Reopen request'),
          ),
        ],
      ],
    );
  }

  Widget _action(IconData icon, String title, String subtitle, VoidCallback onTap) {
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
