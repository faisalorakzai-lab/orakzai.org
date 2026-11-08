import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import 'helpdesk_common.dart';
import 'helpdesk_files.dart';
import 'helpdesk_widgets.dart';

/// Request Conversation. Members post to /requests/:id/messages; authorised
/// staff (not the owner) reply via /admin/requests/:id/reply and may request documents.
class RequestConversationScreen extends StatefulWidget {
  const RequestConversationScreen({
    required this.session,
    required this.request,
    this.requestDocuments = false,
    super.key,
  });
  final HelpDeskSession session;
  final Map<String, dynamic> request;
  final bool requestDocuments;

  @override
  State<RequestConversationScreen> createState() => _RequestConversationScreenState();
}

class _RequestConversationScreenState extends State<RequestConversationScreen> {
  final _body = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  final List<Map<String, dynamic>> _selectedFiles = [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _sending = false;
  String? _error;
  String? _sendError;
  late bool _askDocs = widget.requestDocuments;

  String get _id => hdStr(widget.request['id']);
  String get _status => hdStr(widget.request['status']);
  bool get _isOwner => hdStr(widget.request['ownerId']) == widget.session.userId;
  bool get _staffMode => widget.request['canStaffReply'] == true && !_isOwner;
  bool get _open => !helpDeskFinalStatuses.contains(_status);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.session.api
          .get('/requests/$_id/messages', query: {'limit': '$helpDeskPageSize', 'offset': '0'});
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(hdItems(res['items']));
        _total = hdInt(res['total']);
        _loading = false;
      });
      _markRead(hdItems(res['items']));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = hdError(e);
        _loading = false;
      });
    }
  }

  Future<void> _more() async {
    setState(() => _loadingMore = true);
    try {
      final res = await widget.session.api
          .get('/requests/$_id/messages', query: {'limit': '$helpDeskPageSize', 'offset': '${_messages.length}'});
      if (!mounted) return;
      final page = hdItems(res['items']);
      setState(() {
        _messages.addAll(page);
        _total = hdInt(res['total']);
      });
      _markRead(page);
    } catch (e) {
      if (mounted) hdSnack(context, hdError(e), error: true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Marks only received, unread messages that were rendered on screen.
  Future<void> _markRead(List<Map<String, dynamic>> visible) async {
    final ids = visible
        .where((m) => m['read'] != true && hdStr(m['authorId']) != widget.session.userId)
        .map((m) => hdStr(m['id']))
        .take(100)
        .toList();
    if (ids.isEmpty) return;
    try {
      await widget.session.api.post('/requests/$_id/messages/read', {'messageIds': ids});
    } catch (_) {
      // Read receipts are best-effort; the conversation remains usable.
    }
  }

  Future<void> _attach() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.upload_file_rounded),
            title: const Text('Upload a new file'),
            onTap: () => Navigator.pop(ctx, 'upload'),
          ),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Choose from my files on this request'),
            onTap: () => Navigator.pop(ctx, 'existing'),
          ),
        ]),
      ),
    );
    if (choice == 'upload') await _uploadNew();
    if (choice == 'existing') await _chooseExisting();
  }

  Future<void> _uploadNew() async {
    final picked = await hdPickFiles();
    if (!mounted) return;
    if (picked.rejected.isNotEmpty) hdSnack(context, picked.rejected.join('. '), error: true);
    setState(() => _sending = true);
    for (final f in picked.files) {
      try {
        final res = await widget.session.api.upload(_id, f.bytes, f.name);
        final file = hdMap(res['attachment']).isNotEmpty ? hdMap(res['attachment']) : res;
        if (mounted && file['id'] != null) setState(() => _selectedFiles.add(file));
      } catch (e) {
        if (mounted) hdSnack(context, '${f.name} failed: ${hdError(e)}', error: true);
      }
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _chooseExisting() async {
    List<Map<String, dynamic>> mine;
    try {
      final collected = <Map<String, dynamic>>[];
      var offset = 0;
      while (true) {
        final res = await widget.session.api
            .get('/requests/$_id/attachments', query: {'limit': '50', 'offset': '$offset'});
        final page = hdItems(res['items']);
        collected.addAll(page);
        offset += page.length;
        if (page.isEmpty || offset >= hdInt(res['total'])) break;
      }
      mine = collected
          .where((f) => hdStr(f['uploadedBy']) == widget.session.userId && f['messageId'] == null)
          .toList();
    } catch (e) {
      if (mounted) hdSnack(context, hdError(e), error: true);
      return;
    }
    if (!mounted) return;
    final chosen = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SafeArea(
        child: mine.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('You have no unattached files on this request.'),
              )
            : ListView(shrinkWrap: true, children: [
                for (final f in mine)
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(hdStr(f['name'])),
                    subtitle: Text(hdBytes(hdInt(f['byteSize']))),
                    enabled: !_selectedFiles.any((s) => s['id'] == f['id']),
                    onTap: () => Navigator.pop(ctx, f),
                  ),
              ]),
      ),
    );
    if (chosen != null && mounted) setState(() => _selectedFiles.add(chosen));
  }

  Future<void> _send() async {
    final text = _body.text.trim();
    if (text.isEmpty) {
      setState(() => _sendError = 'Write a message before sending.');
      return;
    }
    setState(() {
      _sending = true;
      _sendError = null;
    });
    final payload = <String, dynamic>{
      'body': text,
      'attachmentIds': _selectedFiles.map((f) => hdStr(f['id'])).toList(),
      'requestDocuments': _staffMode && _askDocs,
    };
    try {
      await widget.session.api
          .post(_staffMode ? '/admin/requests/$_id/reply' : '/requests/$_id/messages', payload);
      if (!mounted) return;
      _body.clear();
      setState(() {
        _selectedFiles.clear();
        _askDocs = false;
      });
      await _load();
    } catch (e) {
      if (mounted) setState(() => _sendError = hdError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.navy,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Conversation', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          Text(hdStr(widget.request['reference']),
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppColors.muted)),
        ]),
        actions: [IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: Column(children: [
        Expanded(child: _thread()),
        _composer(),
      ]),
    );
  }

  Widget _thread() {
    if (_loading && _messages.isEmpty) {
      return const Padding(padding: EdgeInsets.all(20), child: HdSkeleton(rows: 4, height: 64));
    }
    if (_error != null && _messages.isEmpty) {
      return Padding(padding: const EdgeInsets.all(20), child: HdErrorPanel(message: _error!, onRetry: _load));
    }
    if (_messages.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: HdEmpty(
          title: 'No messages yet',
          message: 'Messages between you and the help desk team will appear here.',
          icon: Icons.forum_outlined,
        ),
      );
    }
    final hasMore = _messages.length < _total;
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: _messages.length + 1,
      itemBuilder: (context, i) {
        if (i == _messages.length) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(children: [
              Text('${_messages.length} of $_total messages',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              if (hasMore)
                TextButton(
                  onPressed: _loadingMore ? null : _more,
                  child: Text(_loadingMore ? 'Loading' : 'Load earlier messages'),
                ),
            ]),
          );
        }
        return _bubble(_messages[i]);
      },
    );
  }

  Widget _bubble(Map<String, dynamic> m) {
    final mine = hdStr(m['authorId']) == widget.session.userId;
    final staff = m['isStaff'] == true;
    final files = hdItems(m['attachments']);
    final bg = mine ? AppColors.navy : (staff ? AppColors.goldWash : Colors.white);
    final fg = mine ? Colors.white : AppColors.ink;
    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: mine ? null : Border.all(color: AppColors.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            mine ? 'You' : '${hdStr(m['authorName'])}${staff ? ' - Help desk' : ''}',
            style: TextStyle(color: mine ? AppColors.gold : AppColors.navySoft, fontSize: 12, fontWeight: FontWeight.w700),
          ),
          if (m['requestsDocuments'] == true) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: AppColors.dangerWash, borderRadius: BorderRadius.circular(8)),
              child: const Text('Documents requested',
                  style: TextStyle(color: AppColors.danger, fontSize: 11.5, fontWeight: FontWeight.w700)),
            ),
          ],
          const SizedBox(height: 4),
          SelectableText(hdStr(m['body']), style: TextStyle(color: fg, fontSize: 14.5, height: 1.4)),
          for (final f in files)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: InkWell(
                onTap: () async {
                  try {
                    await hdOpenAttachment(widget.session.api, _id, f);
                  } catch (e) {
                    if (mounted) hdSnack(context, hdError(e), error: true);
                  }
                },
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.attach_file_rounded, size: 16, color: mine ? AppColors.gold : AppColors.green),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(hdStr(f['name']),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: mine ? AppColors.gold : AppColors.green,
                            decoration: TextDecoration.underline,
                            fontSize: 13)),
                  ),
                ]),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            '${hdDate(m['createdAt'])}${mine ? (m['read'] == true ? '  -  Read' : '  -  Sent') : ''}',
            style: TextStyle(color: mine ? Colors.white70 : AppColors.muted, fontSize: 11),
          ),
        ]),
      ),
    );
  }

  Widget _composer() {
    if (!_open) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: HdNotice(
            title: 'Conversation closed',
            message: 'This request is ${hdStatus(_status).toLowerCase()}. New messages are not accepted.',
            icon: Icons.lock_outline_rounded,
          ),
        ),
      );
    }
    return Material(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_sendError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(_sendError!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
              ),
            if (_selectedFiles.isNotEmpty)
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final f in _selectedFiles)
                  InputChip(
                    label: Text(hdStr(f['name']), overflow: TextOverflow.ellipsis),
                    onDeleted: () => setState(() => _selectedFiles.remove(f)),
                  ),
              ]),
            if (_staffMode)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _askDocs,
                onChanged: (v) => setState(() => _askDocs = v ?? false),
                title: const Text('Request documents from the member'),
              ),
            Row(children: [
              IconButton(
                tooltip: 'Attach file',
                onPressed: _sending ? null : _attach,
                icon: const Icon(Icons.attach_file_rounded, color: AppColors.navy),
              ),
              Expanded(
                child: TextField(
                  controller: _body,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 5000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: _staffMode ? 'Reply to the member' : 'Write to the help desk',
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: 'Send',
                style: IconButton.styleFrom(backgroundColor: AppColors.navy),
                onPressed: _sending ? null : _send,
                icon: const Icon(Icons.send_rounded),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
