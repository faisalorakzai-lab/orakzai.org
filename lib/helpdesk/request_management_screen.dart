import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import 'assignment_screen.dart';
import 'helpdesk_common.dart';
import 'helpdesk_paged_list.dart';
import 'helpdesk_widgets.dart';
import 'request_attachments_screen.dart';
import 'request_conversation_screen.dart';
import 'request_detail_screen.dart';
import 'request_history_screen.dart';

/// Request Management (staff only): status, resolve/close, assignment,
/// replies, document requests, internal notes and history.
class RequestManagementScreen extends StatefulWidget {
  const RequestManagementScreen({required this.session, required this.requestId, super.key});
  final HelpDeskSession session;
  final String requestId;

  @override
  State<RequestManagementScreen> createState() => _RequestManagementScreenState();
}

class _RequestManagementScreenState extends State<RequestManagementScreen> {
  final _notesKey = GlobalKey<HdPagedListState>();
  Map<String, dynamic>? _req;
  bool _loading = true;
  String? _error;
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
      setState(() => _req = hdRequest(res));
    } catch (e) {
      if (mounted) setState(() => _error = hdError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _authorized => _req?['canManage'] == true || _req?['canStaffReply'] == true;

  List<String> _allowed() {
    final status = hdStr(_req!['status']);
    final list = List<String>.from(helpDeskTransitions[status] ?? const []);
    if (status == 'resolved') {
      final resolved = hdParseDate(_req!['resolvedAt']);
      if (resolved == null || DateTime.now().difference(resolved).inDays >= 7) list.remove('in_progress');
    }
    return list;
  }

  Future<void> _changeStatus([String? preset]) async {
    final allowed = _allowed();
    if (allowed.isEmpty) return;
    var target = preset ?? allowed.first;
    final reason = TextEditingController();
    String? error;
    var busy = false;
    final changed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Change status'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: target,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'New status'),
                items: [for (final s in allowed) DropdownMenuItem(value: s, child: Text(hdStatus(s)))],
                onChanged: (v) => setLocal(() => target = v ?? target),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: reason,
                maxLines: 3,
                maxLength: 1000,
                decoration: const InputDecoration(labelText: 'Reason (shared in history)'),
              ),
              if (error != null) Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ]),
          ),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setLocal(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await widget.session.api.patch('/admin/requests/${widget.requestId}/status',
                            {'status': target, 'reason': reason.text.trim()});
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setLocal(() {
                          busy = false;
                          error = hdError(e);
                        });
                      }
                    },
              child: Text(busy ? 'Saving' : 'Update'),
            ),
          ],
        ),
      ),
    );
    reason.dispose();
    if (changed == true) {
      if (mounted) hdSnack(context, 'Status updated to ${hdStatus(target)}.');
      _load();
    }
  }

  Future<void> _addNote() async {
    final ok = await hdTextDialog(
      context,
      title: 'Internal note',
      submitLabel: 'Add note',
      fields: const [HdDialogField('Note (staff only)', max: 5000, maxLines: 5)],
      onSubmit: (v) => widget.session.api.post('/admin/requests/${widget.requestId}/notes', {'body': v[0]}),
    );
    if (ok) _notesKey.currentState?.reload();
  }

  Future<void> _push(Widget page) async {
    setState(() => _working = true);
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (!mounted) return;
    setState(() => _working = false);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _req == null) {
      return const HdScaffold(title: 'Manage request', children: [HdSkeleton(rows: 4, height: 70)]);
    }
    if (_req == null) {
      return HdScaffold(title: 'Manage request', children: [HdErrorPanel(message: _error ?? 'Unavailable', onRetry: _load)]);
    }
    final r = _req!;
    if (!_authorized) {
      return HdScaffold(title: 'Manage request', children: [
        const HdNotice(
          title: 'Staff access required',
          message: 'You are not authorised to manage this request.',
          icon: Icons.lock_outline_rounded,
          tone: HdTone.warning,
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => Navigator.pushReplacement(context,
              MaterialPageRoute(builder: (_) => RequestDetailScreen(session: widget.session, requestId: widget.requestId))),
          child: const Text('Open as member view'),
        ),
      ]);
    }
    final status = hdStr(r['status']);
    final allowed = _allowed();
    final canManage = r['canManage'] == true;
    final canReply = r['canStaffReply'] == true && hdStr(r['ownerId']) != widget.session.userId;
    return HdScaffold(
      title: hdStr(r['title']),
      subtitle: 'Staff workspace. Internal notes are never shown to the member.',
      onRefresh: _load,
      children: [
        HdCard(
          accent: hdStatusColor(status),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(hdStr(r['reference']), style: const TextStyle(fontFamily: 'monospace', color: AppColors.navy, fontWeight: FontWeight.w700)),
              const Spacer(),
              HdPill.status(status),
            ]),
            const SizedBox(height: 8),
            HdKeyValue('Category', hdCategory(hdStr(r['category']))),
            HdKeyValue('Priority', hdPriority(hdStr(r['priority']))),
            HdKeyValue('Assigned to', hdStr(r['assignedName']).isEmpty ? 'Unassigned' : hdStr(r['assignedName'])),
            HdKeyValue('Department', hdStr(r['departmentName'])),
            if (r['contact'] is Map) HdKeyValue('Member contact', (r['contact'] as Map).values.where((v) => v != null).join(' / ')),
            HdKeyValue('Submitted', hdDate(r['createdAt'])),
          ]),
        ),
        const HdSectionTitle('Description'),
        HdCard(child: SelectableText(hdStr(r['description']), style: Theme.of(context).textTheme.bodyLarge)),
        const HdSectionTitle('Actions'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: allowed.isEmpty || _working ? null : () => _changeStatus(),
            icon: const Icon(Icons.swap_horiz_rounded),
            label: const Text('Change status'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
          ),
          if (allowed.contains('resolved'))
            OutlinedButton.icon(
              onPressed: () => _changeStatus('resolved'),
              icon: const Icon(Icons.task_alt_rounded),
              label: const Text('Resolve'),
            ),
          if (allowed.contains('closed'))
            OutlinedButton.icon(
              onPressed: () => _changeStatus('closed'),
              icon: const Icon(Icons.archive_outlined),
              label: const Text('Close'),
            ),
          if (canManage)
            OutlinedButton.icon(
              onPressed: () => _push(AssignmentScreen(session: widget.session, request: r)),
              icon: const Icon(Icons.assignment_ind_outlined),
              label: Text(hdStr(r['assignedTo']).isEmpty ? 'Assign' : 'Reassign'),
            ),
          if (canReply && !helpDeskFinalStatuses.contains(status)) ...[
            OutlinedButton.icon(
              onPressed: () => _push(RequestConversationScreen(session: widget.session, request: r)),
              icon: const Icon(Icons.reply_rounded),
              label: const Text('Reply'),
            ),
            OutlinedButton.icon(
              onPressed: () => _push(RequestConversationScreen(session: widget.session, request: r, requestDocuments: true)),
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Request documents'),
            ),
          ] else
            OutlinedButton.icon(
              onPressed: () => _push(RequestConversationScreen(session: widget.session, request: r)),
              icon: const Icon(Icons.forum_outlined),
              label: const Text('Conversation'),
            ),
          OutlinedButton.icon(
            onPressed: () => _push(RequestAttachmentsScreen(session: widget.session, requestId: widget.requestId, status: status)),
            icon: const Icon(Icons.attach_file_rounded),
            label: const Text('Attachments'),
          ),
          OutlinedButton.icon(
            onPressed: () => _push(RequestHistoryScreen(session: widget.session, requestId: widget.requestId)),
            icon: const Icon(Icons.history_rounded),
            label: const Text('History'),
          ),
        ]),
        if (allowed.isEmpty) ...[
          const SizedBox(height: 10),
          const Text('This request is closed. No further status changes are possible.',
              style: TextStyle(color: AppColors.muted, fontSize: 13)),
        ],
        HdSectionTitle('Internal notes',
            trailing: TextButton.icon(onPressed: _addNote, icon: const Icon(Icons.add_rounded), label: const Text('Add'))),
        HdPagedList(
          key: _notesKey,
          itemLabel: 'notes',
          fetch: (offset, limit) => widget.session.api
              .get('/admin/requests/${widget.requestId}/notes', query: {'limit': '$limit', 'offset': '$offset'}),
          emptyTitle: 'No internal notes',
          emptyMessage: 'Notes help staff coordinate. Members never see them.',
          emptyIcon: Icons.sticky_note_2_outlined,
          itemBuilder: (context, n) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.goldWash,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(hdStr(n['body']), style: const TextStyle(color: AppColors.ink, height: 1.4)),
                const SizedBox(height: 6),
                Text('${hdStr(n['authorName'])} - ${hdDate(n['createdAt'])}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ]),
            ),
          ),
        ),
      ],
    );
  }
}
