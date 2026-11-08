import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import 'helpdesk_common.dart';
import 'helpdesk_widgets.dart';

/// History: status timeline plus assignment records, paginated.
class RequestHistoryScreen extends StatefulWidget {
  const RequestHistoryScreen({required this.session, required this.requestId, super.key});
  final HelpDeskSession session;
  final String requestId;

  @override
  State<RequestHistoryScreen> createState() => _RequestHistoryScreenState();
}

class _RequestHistoryScreenState extends State<RequestHistoryScreen> {
  final List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _assignments = [];
  int _total = 0;
  bool _loading = true;
  bool _more = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      if (reset) {
        _loading = true;
        _error = null;
      } else {
        _more = true;
      }
    });
    try {
      final res = await widget.session.api.get('/requests/${widget.requestId}/history',
          query: {'limit': '$helpDeskPageSize', 'offset': '${reset ? 0 : _items.length}'});
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(hdItems(res['items']));
        _assignments = hdItems(res['assignments']);
        _total = hdInt(res['total']);
      });
    } catch (e) {
      if (!mounted) return;
      if (reset) {
        setState(() => _error = hdError(e));
      } else {
        hdSnack(context, hdError(e), error: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _more = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return HdScaffold(
      title: 'History',
      subtitle: 'Every status change and assignment on this request.',
      onRefresh: () => _load(reset: true),
      children: [
        if (_loading)
          const HdSkeleton(rows: 4, height: 60)
        else if (_error != null)
          HdErrorPanel(message: _error!, onRetry: () => _load(reset: true))
        else ...[
          const HdSectionTitle('Status timeline'),
          if (_items.isEmpty)
            const HdEmpty(title: 'No changes yet', message: 'Status updates will be recorded here.', icon: Icons.timeline_rounded)
          else
            for (var i = 0; i < _items.length; i++) _timelineRow(_items[i], i == _items.length - 1),
          if (_items.isNotEmpty)
            Text('Showing ${_items.length} of $_total changes',
                textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          if (_items.length < _total)
            OutlinedButton(onPressed: _more ? null : () => _load(), child: Text(_more ? 'Loading' : 'Load more')),
          const HdSectionTitle('Assignments'),
          if (_assignments.isEmpty)
            const HdEmpty(title: 'Not assigned yet', message: 'Assignments to staff and departments appear here.', icon: Icons.assignment_ind_outlined)
          else
            for (final a in _assignments)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: HdCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${hdStr(a['staffName']).isEmpty ? 'Department queue' : hdStr(a['staffName'])}'
                        '${hdStr(a['departmentName']).isEmpty ? '' : ' - ${hdStr(a['departmentName'])}'}',
                        style: Theme.of(context).textTheme.titleMedium),
                    Text('By ${hdStr(a['assignedBy'])} on ${hdDate(a['createdAt'])}',
                        style: Theme.of(context).textTheme.bodyMedium),
                  ]),
                ),
              ),
        ],
      ],
    );
  }

  Widget _timelineRow(Map<String, dynamic> h, bool last) {
    final to = hdStr(h['toStatus']);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 22,
          child: Column(children: [
            const SizedBox(height: 4),
            Container(width: 12, height: 12, decoration: BoxDecoration(color: hdStatusColor(to), shape: BoxShape.circle)),
            if (!last) Expanded(child: Container(width: 2, color: AppColors.line)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (h['fromStatus'] != null) ...[
                  Text(hdStatus(hdStr(h['fromStatus'])), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                  const Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.muted),
                ],
                HdPill.status(to),
              ]),
              const SizedBox(height: 4),
              Text('${hdStr(h['actorName'])} - ${hdDate(h['createdAt'])}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              if (hdStr(h['reason']).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(hdStr(h['reason']), style: const TextStyle(color: AppColors.ink, fontSize: 13.5)),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}
