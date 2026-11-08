import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import 'community_controller.dart';
import 'community_widgets.dart';

class CommunityModerationScreen extends StatefulWidget {
  const CommunityModerationScreen({required this.controller, super.key});
  final CommunityController controller;

  @override
  State<CommunityModerationScreen> createState() =>
      _CommunityModerationScreenState();
}

class _CommunityModerationScreenState extends State<CommunityModerationScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await widget.controller.loadModerationReports();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Moderation review')),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final reports = widget.controller.moderationReports;
          if (_loading) return const Center(child: CircularProgressIndicator());
          if (reports.isEmpty) {
            return const CommunityEmpty(
              title: 'No open reports',
              message: 'New community reports will appear here for authorized moderators.',
              icon: Icons.verified_user_outlined,
            );
          }
          return RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: reports.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final report = reports[index];
                return Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: AppColors.line),
                  ),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.dangerWash,
                      child: Icon(Icons.flag_outlined, color: AppColors.danger),
                    ),
                    title: Text(
                      '${_title(report['targetType'])} report · ${_title(report['category'])}',
                    ),
                    subtitle: Text(
                      '${report['reporterName'] ?? 'Member'} · ${report['createdAt'] ?? ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _openReport(report),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _openReport(Map<String, dynamic> summary) async {
    final id = summary['id'] as String?;
    if (id == null) return;
    final report = await widget.controller.getModerationReport(id);
    if (!mounted || report == null) return;
    final targetType = report['targetType'] as String? ?? '';
    final actions = <String>[
      if (targetType == 'post' || targetType == 'comment' || targetType == 'message') ...[
        'hide_content',
        'restore_content',
        'remove_content',
      ],
      if (targetType == 'group' && widget.controller.canSuspendGroups)
        ...['suspend_group', 'restore_group'],
      if (targetType == 'user' && widget.controller.canRestrictMembers)
        'restrict_member',
    ];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Report details', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                _DetailCard(
                  label: 'Reason',
                  value: '${_title(report['category'])}\n${report['details'] ?? 'No additional details.'}',
                ),
                _DetailCard(
                  label: 'Reported content',
                  value: report['targetSummary'] as String? ??
                      report['contentPreview'] as String? ??
                      'Content details are not available.',
                ),
                _DetailCard(
                  label: 'Review state',
                  value: '${report['status'] ?? 'open'}',
                ),
                const SizedBox(height: 8),
                if (actions.isEmpty)
                  const Text('No action is available for your role.')
                else
                  ...actions.map(
                    (action) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_actionIcon(action)),
                      title: Text(_title(action)),
                      onTap: () async {
                        Navigator.pop(context);
                        await _applyAction(id, action);
                      },
                    ),
                  ),
                if (report['actionHistory'] is List) ...[
                  const Divider(),
                  Text('Action history', style: Theme.of(context).textTheme.titleSmall),
                  ...((report['actionHistory'] as List).whereType<Map>().map(
                        (entry) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_title(entry['action'])),
                          subtitle: Text(entry['reason'] as String? ?? ''),
                        ),
                      )),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _applyAction(String reportId, String action) async {
    final messenger = ScaffoldMessenger.of(context);
    final reason = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_title(action)),
        content: TextField(
          controller: reason,
          autofocus: true,
          maxLines: 3,
          maxLength: 1000,
          decoration: const InputDecoration(
            labelText: 'Reason for this action',
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (reason.text.trim().length >= 5) {
                Navigator.pop(context, reason.text.trim());
              }
            },
            child: const Text('Apply action'),
          ),
        ],
      ),
    );
    reason.dispose();
    if (value == null || value.length < 5) return;
    await widget.controller.applyModerationAction(reportId, action, value);
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(widget.controller.error ?? 'Moderation action saved.')),
    );
  }

  IconData _actionIcon(String action) => switch (action) {
    'hide_content' => Icons.visibility_off_outlined,
    'restore_content' => Icons.visibility_outlined,
    'remove_content' => Icons.delete_outline_rounded,
    'suspend_group' => Icons.pause_circle_outline_rounded,
    'restore_group' => Icons.play_circle_outline_rounded,
    'restrict_member' => Icons.person_off_outlined,
    _ => Icons.shield_outlined,
  };

  String _title(Object? raw) {
    final text = (raw as String? ?? 'community').replaceAll('_', ' ');
    return text
        .split(' ')
        .map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(value),
          ],
        ),
      ),
    );
  }
}
