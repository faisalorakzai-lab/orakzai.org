import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import 'category_selection_screen.dart';
import 'helpdesk_api.dart';
import 'helpdesk_common.dart';
import 'helpdesk_files.dart';
import 'helpdesk_widgets.dart';
import 'request_attachments_screen.dart';
import 'request_detail_screen.dart';

typedef HdFilePicker = Future<HdPickResult> Function();

/// Submit Request. Creates the request first, then uploads files to it.
class SubmitRequestScreen extends StatefulWidget {
  const SubmitRequestScreen({required this.session, this.initialCategory, this.pickFiles, super.key});
  final HelpDeskSession session;
  final String? initialCategory;
  final HdFilePicker? pickFiles;

  @override
  State<SubmitRequestScreen> createState() => _SubmitRequestScreenState();
}

class _SubmitRequestScreenState extends State<SubmitRequestScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _region = TextEditingController();
  final _district = TextEditingController();
  final _qoum = TextEditingController();
  final _village = TextEditingController();
  late String _category = widget.initialCategory ?? 'general_inquiry';
  String _priority = 'normal';
  String _contact = 'in_app';
  final List<HdPickedFile> _files = [];
  bool _busy = false;
  String? _error;

  Map<String, dynamic>? _created;
  final List<HdPickedFile> _failed = [];
  String? _uploadProgress;

  @override
  void dispose() {
    for (final c in [_title, _description, _region, _district, _qoum, _village]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _chooseCategory() async {
    final picked = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => CategorySelectionScreen(selected: _category)));
    if (picked != null) setState(() => _category = picked);
  }

  Future<void> _addFiles() async {
    final result = await (widget.pickFiles ?? hdPickFiles)();
    if (!mounted) return;
    setState(() => _files.addAll(result.files));
    if (result.rejected.isNotEmpty) hdSnack(context, result.rejected.join('. '), error: true);
  }

  Future<void> _submit() async {
    if (_busy || _created != null) return;
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = <String, dynamic>{
      'title': _title.text.trim(),
      'category': _category,
      'description': _description.text.trim(),
      'priority': _priority,
      'region': _region.text.trim(),
      'contactPreference': _contact,
      if (_district.text.trim().isNotEmpty) 'district': _district.text.trim(),
      if (_qoum.text.trim().isNotEmpty) 'qoum': _qoum.text.trim(),
      if (_village.text.trim().isNotEmpty) 'village': _village.text.trim(),
    };
    try {
      final res = await widget.session.api.post('/requests', body);
      if (!mounted) return;
      setState(() => _created = hdRequest(res));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = hdError(e);
      });
      return;
    }
    await _uploadAll(List.of(_files));
  }

  Future<void> _uploadAll(List<HdPickedFile> files) async {
    final id = hdStr(_created!['id']);
    final failed = <HdPickedFile>[];
    for (var i = 0; i < files.length; i++) {
      setState(() => _uploadProgress = 'Uploading file ${i + 1} of ${files.length}');
      try {
        await widget.session.api.upload(id, files[i].bytes, files[i].name);
      } catch (_) {
        failed.add(files[i]);
      }
    }
    if (!mounted) return;
    setState(() {
      _failed
        ..clear()
        ..addAll(failed);
      _uploadProgress = null;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_created != null) return _result();
    final emergency = _category == 'emergency_assistance';
    return HdScaffold(
      title: 'Submit a request',
      subtitle: 'Only you and authorised ORAKZAI.ORG staff can see what you share here.',
      children: [
        if (emergency) ...[
          const HdNotice(
            title: 'This is not an emergency response service',
            message:
                'If anyone is in immediate danger, contact local emergency services or the nearest hospital first. This form is for welfare follow-up and can take time to be reviewed.',
            icon: Icons.warning_amber_rounded,
            tone: HdTone.danger,
          ),
          const SizedBox(height: 16),
        ],
        if (_error != null) ...[
          HdNotice(title: 'Your request was not saved', message: _error!, icon: Icons.error_outline_rounded, tone: HdTone.danger),
          const SizedBox(height: 16),
        ],
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const HdSectionTitle('Category'),
              HdCard(
                onTap: _chooseCategory,
                child: Row(children: [
                  Icon(helpDeskCategoryIcons[_category], color: AppColors.navy),
                  const SizedBox(width: 12),
                  Expanded(child: Text(hdCategory(_category), style: Theme.of(context).textTheme.titleMedium)),
                  const Text('Change', style: TextStyle(color: AppColors.green, fontWeight: FontWeight.w700)),
                ]),
              ),
              const HdSectionTitle('Your request'),
              TextFormField(
                key: const Key('hd-title'),
                controller: _title,
                maxLength: 160,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Short title'),
                validator: (v) => (v ?? '').trim().length < 5 ? 'Enter at least 5 characters.' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('hd-description'),
                controller: _description,
                maxLength: 10000,
                minLines: 5,
                maxLines: 10,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Describe what you need', alignLabelWithHint: true),
                validator: (v) => (v ?? '').trim().length < 20 ? 'Enter at least 20 characters so staff understand.' : null,
              ),
              const HdSectionTitle('Priority'),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  for (final p in HelpDeskApi.priorities.entries)
                    ButtonSegment(value: p.key, label: Text(p.value, style: const TextStyle(fontSize: 12.5))),
                ],
                selected: {_priority},
                onSelectionChanged: (s) => setState(() => _priority = s.first),
              ),
              const HdSectionTitle('Where you are'),
              TextFormField(
                key: const Key('hd-region'),
                controller: _region,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Region (required)'),
                validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your region (at least 2 characters).' : null,
              ),
              const SizedBox(height: 4),
              for (final (label, ctrl) in [('District', _district), ('Qoum', _qoum), ('Village', _village)]) ...[
                TextFormField(
                  controller: ctrl,
                  maxLength: 100,
                  decoration: InputDecoration(labelText: '$label (optional)'),
                ),
                const SizedBox(height: 4),
              ],
              const HdSectionTitle('How should we reach you?'),
              Wrap(
                spacing: 8,
                children: [
                  for (final (key, label) in [('in_app', 'In the app'), ('email', 'Email'), ('phone', 'Phone')])
                    ChoiceChip(
                      label: Text(label),
                      selected: _contact == key,
                      selectedColor: AppColors.goldWash,
                      onSelected: (_) => setState(() => _contact = key),
                    ),
                ],
              ),
              const HdSectionTitle('Supporting documents'),
              Text('Images, PDF, DOCX or text. Up to 25 MB each.', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              for (final f in _files)
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.line)),
                  child: ListTile(
                    leading: const Icon(Icons.description_outlined, color: AppColors.navy),
                    title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(hdBytes(f.bytes.length)),
                    trailing: IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: _busy ? null : () => setState(() => _files.remove(f)),
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _addFiles,
                icon: const Icon(Icons.attach_file_rounded),
                label: const Text('Add files'),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                key: const Key('hd-submit'),
                onPressed: _busy ? null : _submit,
                icon: const Icon(Icons.lock_outline_rounded),
                label: Text(_busy ? 'Sending securely' : 'Submit request'),
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy, padding: const EdgeInsets.symmetric(vertical: 15)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _result() {
    final req = _created!;
    final id = hdStr(req['id']);
    final partial = _failed.isNotEmpty;
    return HdScaffold(
      title: partial ? 'Request saved, files need attention' : 'Request received',
      subtitle: 'Keep this reference to track your request.',
      children: [
        HdCard(
          accent: AppColors.gold,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('REFERENCE', style: TextStyle(color: AppColors.muted, fontSize: 11, letterSpacing: 1.2)),
            const SizedBox(height: 4),
            SelectableText(hdStr(req['reference']),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.navy)),
            const SizedBox(height: 8),
            Text(hdStr(req['title']), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            HdPill.status(hdStr(req['status'])),
          ]),
        ),
        const SizedBox(height: 14),
        if (_uploadProgress != null)
          HdNotice(title: 'Attaching files', message: _uploadProgress!, icon: Icons.upload_rounded)
        else if (partial)
          HdNotice(
            title: 'Your request was saved, but ${_failed.length} file(s) failed to upload',
            message: '${_failed.map((f) => f.name).join(', ')}. Do not submit again; retry here or add them later from Attachments.',
            icon: Icons.error_outline_rounded,
            tone: HdTone.warning,
            action: Wrap(spacing: 8, children: [
              TextButton.icon(
                onPressed: () {
                  setState(() => _busy = true);
                  _uploadAll(List.of(_failed));
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry failed files'),
              ),
              TextButton(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => RequestAttachmentsScreen(session: widget.session, requestId: id))),
                child: const Text('Open attachments'),
              ),
            ]),
          )
        else
          HdNotice(
            title: 'Sent privately',
            message: _files.isEmpty
                ? 'Staff will review your request. You will see updates in My Requests.'
                : 'Your request and ${_files.length} file(s) were saved. Staff will review them.',
            icon: Icons.verified_outlined,
            tone: HdTone.success,
          ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _uploadProgress != null
              ? null
              : () => Navigator.pushReplacement(context,
                  MaterialPageRoute(builder: (_) => RequestDetailScreen(session: widget.session, requestId: id))),
          style: FilledButton.styleFrom(backgroundColor: AppColors.navy, padding: const EdgeInsets.symmetric(vertical: 15)),
          child: const Text('View request'),
        ),
      ],
    );
  }
}
