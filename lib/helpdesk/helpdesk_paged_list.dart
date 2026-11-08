import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import 'helpdesk_common.dart';
import 'helpdesk_widgets.dart';

typedef HdPageFetcher = Future<Map<String, dynamic>> Function(int offset, int limit);

/// Paginated list section rendered inside a parent scroll view.
/// Always shows the real total and a load-more control; never silently caps.
class HdPagedList extends StatefulWidget {
  const HdPagedList({
    required this.fetch,
    required this.itemBuilder,
    required this.emptyTitle,
    required this.emptyMessage,
    this.emptyIcon = Icons.inbox_outlined,
    this.pageSize = helpDeskPageSize,
    this.itemLabel = 'items',
    super.key,
  });

  final HdPageFetcher fetch;
  final Widget Function(BuildContext context, Map<String, dynamic> item) itemBuilder;
  final String emptyTitle;
  final String emptyMessage;
  final IconData emptyIcon;
  final int pageSize;
  final String itemLabel;

  @override
  State<HdPagedList> createState() => HdPagedListState();
}

class HdPagedListState extends State<HdPagedList> {
  final List<Map<String, dynamic>> _items = [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _generation = 0;

  List<Map<String, dynamic>> get items => List.unmodifiable(_items);

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final gen = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.fetch(0, widget.pageSize);
      if (!mounted || gen != _generation) return;
      setState(() {
        _items
          ..clear()
          ..addAll(hdItems(res['items']));
        _total = hdInt(res['total']);
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = hdError(e);
        _loading = false;
      });
    }
  }

  Future<void> _more() async {
    final gen = _generation;
    setState(() => _loadingMore = true);
    try {
      final res = await widget.fetch(_items.length, widget.pageSize);
      if (!mounted || gen != _generation) return;
      setState(() {
        _items.addAll(hdItems(res['items']));
        _total = hdInt(res['total']);
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      hdSnack(context, hdError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const HdSkeleton();
    if (_error != null) return HdErrorPanel(message: _error!, onRetry: reload);
    if (_items.isEmpty) {
      return HdEmpty(title: widget.emptyTitle, message: widget.emptyMessage, icon: widget.emptyIcon);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in _items) widget.itemBuilder(context, item),
        const SizedBox(height: 4),
        Text('Showing ${_items.length} of $_total ${widget.itemLabel}',
            textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
        if (_items.length < _total) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _loadingMore ? null : _more,
            child: Text(_loadingMore ? 'Loading' : 'Load more'),
          ),
        ],
      ],
    );
  }
}
