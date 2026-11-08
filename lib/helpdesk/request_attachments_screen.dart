import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import 'helpdesk_common.dart';
import 'helpdesk_files.dart';
import 'helpdesk_paged_list.dart';
import 'helpdesk_widgets.dart';

/// Request Attachments: list, open privately, and upload (including retries).
class RequestAttachmentsScreen extends StatefulWidget {
  const RequestAttachmentsScreen({required this.session, required this.requestId, this.status, super.key});
  final HelpDeskSession session;
  final String requestId;
  final String? status;

  @override
  State<RequestAttachmentsScreen> createState() => _RequestAttachmentsScreenState();
}

class _RequestAttachmentsScreenState extends State<RequestAttachmentsScreen> {
  final _listKey = GlobalKey<HdPagedListState>();
  String? _uploading;
  String? _opening;

  Future<void> _upload() async {
    final picked = await hdPickFiles();
    if (!mounted) return;
    if (picked.rejected.isNotEmpty) hdSnack(context, picked.rejected.join('. '), error: true);
    final failed = <String>[];
    for (var i = 0; i < picked.files.length; i++) {
      final f = picked.files[i];
      setState(() => _uploading = 'Uploading ${f.name} (${i + 1} of ${picked.files.length})');
      try {
        await widget.session.api.upload(widget.requestId, f.bytes, f.name);
      } catch (e) {
        failed.add('${f.name}: ${hdError(e)}');
      }
    }
    if (!mounted) return;
    setState(() => _uploading = null);
    if (failed.isNotEmpty) {
      hdSnack(context, '${failed.length} file(s) failed. ${failed.join(' ')}', error: true);
    } else if (picked.files.isNotEmpty) {
      hdSnack(context, '${picked.files.length} file(s) uploaded.');
    }
    _listKey.currentState?.reload();
  }

  Future<void> _open(Map<String, dynamic> file) async {
    setState(() => _opening = hdStr(file['id']));
    try {
      await hdOpenAttachment(widget.session.api, widget.requestId, file);
    } catch (e) {
      if (mounted) hdSnack(context, hdError(e), error: true);
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return HdScaffold(
      title: 'Attachments',
      subtitle: 'Files are downloaded privately to this device and never shared as public links.',
      onRefresh: () async => _listKey.currentState?.reload(),
      children: [
        if (_uploading != null) ...[
          HdNotice(title: 'Uploading', message: _uploading!, icon: Icons.upload_rounded),
          const SizedBox(height: 12),
        ],
        FilledButton.icon(
          onPressed: _uploading != null ? null : _upload,
          icon: const Icon(Icons.upload_file_rounded),
          label: const Text('Upload files (25 MB max each)'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.navy, padding: const EdgeInsets.symmetric(vertical: 14)),
        ),
        const SizedBox(height: 16),
        HdPagedList(
          key: _listKey,
          itemLabel: 'files',
          fetch: (offset, limit) => widget.session.api
              .get('/requests/${widget.requestId}/attachments', query: {'limit': '$limit', 'offset': '$offset'}),
          emptyTitle: 'No files yet',
          emptyMessage: 'Supporting documents and images added to this request will appear here.',
          emptyIcon: Icons.folder_open_outlined,
          itemBuilder: (context, f) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: HdCard(
              onTap: _opening == null ? () => _open(f) : null,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                Icon(hdStr(f['contentType']).startsWith('image/') ? Icons.image_outlined : Icons.description_outlined,
                    color: AppColors.navy),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(hdStr(f['name']), maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                    Text(
                      '${hdBytes(hdInt(f['byteSize']))} - ${hdDate(f['createdAt'])}'
                      '${f['uploadedBy'] == widget.session.userId ? ' - you' : ''}'
                      '${f['messageId'] == null ? '' : ' - in conversation'}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                    ),
                  ]),
                ),
                Text(_opening == hdStr(f['id']) ? 'Opening' : 'Open',
                    style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
      ],
    );
  }
}
