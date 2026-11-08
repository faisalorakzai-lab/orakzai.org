import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import 'helpdesk_api.dart';
import 'helpdesk_common.dart';
import 'helpdesk_paged_list.dart';
import 'helpdesk_widgets.dart';
import 'request_detail_screen.dart';
import 'request_management_screen.dart';

enum RequestListMode { mine, staffQueue }

/// My Requests (members) or the staff Request queue, with filters and pagination.
class RequestsListScreen extends StatefulWidget {
  const RequestsListScreen({required this.session, this.mode = RequestListMode.mine, this.initialStatus, super.key});
  final HelpDeskSession session;
  final RequestListMode mode;
  final String? initialStatus;

  @override
  State<RequestsListScreen> createState() => _RequestsListScreenState();
}

class _RequestsListScreenState extends State<RequestsListScreen> {
  final _search = TextEditingController();
  final _listKey = GlobalKey<HdPagedListState>();
  late String? _status = widget.initialStatus;
  String? _category;
  String? _priority;
  String _query = '';

  bool get _staff => widget.mode == RequestListMode.staffQueue;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _fetch(int offset, int limit) {
    return widget.session.api.get(_staff ? '/admin/requests' : '/requests', query: {
      'limit': '$limit',
      'offset': '$offset',
      if (_status != null) 'status': _status!,
      if (_category != null) 'category': _category!,
      if (_priority != null) 'priority': _priority!,
      if (_query.isNotEmpty) 'search': _query,
    });
  }

  Widget _dropdown(String label, Map<String, String> options, String? value, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String?>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('All')),
        for (final e in options.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
      ],
      onChanged: onChanged,
    );
  }

  Future<void> _open(Map<String, dynamic> item) async {
    final id = hdStr(item['id']);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _staff
            ? RequestManagementScreen(session: widget.session, requestId: id)
            : RequestDetailScreen(session: widget.session, requestId: id),
      ),
    );
    _listKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final filterKey = '$_status|$_category|$_priority|$_query';
    return HdScaffold(
      title: _staff ? 'Request queue' : 'My requests',
      subtitle: _staff
          ? 'Requests you are authorised to handle.'
          : 'Only requests you submitted appear here.',
      onRefresh: () async => _listKey.currentState?.reload(),
      children: [
        TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search title or reference',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() {
                      _search.clear();
                      _query = '';
                    }),
                  ),
          ),
          onSubmitted: (v) => setState(() => _query = v.trim()),
        ),
        const SizedBox(height: 10),
        _dropdown('Status', HelpDeskApi.statuses, _status, (v) => setState(() => _status = v)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _dropdown('Category', HelpDeskApi.categories, _category, (v) => setState(() => _category = v))),
          const SizedBox(width: 10),
          Expanded(child: _dropdown('Priority', HelpDeskApi.priorities, _priority, (v) => setState(() => _priority = v))),
        ]),
        const SizedBox(height: 16),
        HdPagedList(
          key: _listKey,
          // Rebuild state when filters change.
          fetch: _fetch,
          itemLabel: 'requests',
          emptyTitle: _status == null && _category == null && _priority == null && _query.isEmpty
              ? (_staff ? 'The queue is clear' : 'No requests yet')
              : 'Nothing matches these filters',
          emptyMessage: _staff
              ? 'No requests match. New submissions will appear here.'
              : 'When you submit a request it will be listed here with its status.',
          emptyIcon: Icons.receipt_long_outlined,
          itemBuilder: (context, item) => HdRequestCard(request: item, showAssignee: _staff, onTap: () => _open(item)),
        ),
        // Invisible keyed trigger so filter changes force a refetch.
        _FilterWatcher(value: filterKey, onChanged: () => _listKey.currentState?.reload()),
        if (!_staff) const SizedBox(height: 8),
        if (!_staff)
          const Text('Statistics and lists only include your own records.',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12)),
      ],
    );
  }
}

class _FilterWatcher extends StatefulWidget {
  const _FilterWatcher({required this.value, required this.onChanged});
  final String value;
  final VoidCallback onChanged;

  @override
  State<_FilterWatcher> createState() => _FilterWatcherState();
}

class _FilterWatcherState extends State<_FilterWatcher> {
  @override
  void didUpdateWidget(covariant _FilterWatcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onChanged());
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
