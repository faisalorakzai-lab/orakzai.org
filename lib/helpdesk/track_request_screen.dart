import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import 'helpdesk_common.dart';
import 'helpdesk_widgets.dart';
import 'request_detail_screen.dart';

/// Track by Reference. Only returns requests the member is authorised to view.
class TrackRequestScreen extends StatefulWidget {
  const TrackRequestScreen({required this.session, super.key});
  final HelpDeskSession session;

  @override
  State<TrackRequestScreen> createState() => _TrackRequestScreenState();
}

class _TrackRequestScreenState extends State<TrackRequestScreen> {
  final _ref = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  Future<void> _track() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final res = await widget.session.api.get('/track/${Uri.encodeComponent(_ref.text.trim().toUpperCase())}');
      if (!mounted) return;
      setState(() => _result = hdRequest(res));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = hdError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return HdScaffold(
      title: 'Track a request',
      subtitle: 'Enter the reference you received when the request was saved.',
      children: [
        Form(
          key: _form,
          child: TextFormField(
            controller: _ref,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(fontFamily: 'monospace', letterSpacing: 1),
            decoration: const InputDecoration(labelText: 'Reference', prefixIcon: Icon(Icons.tag_rounded)),
            onFieldSubmitted: (_) => _track(),
            validator: (v) => (v ?? '').trim().length < 4 ? 'Enter a valid reference.' : null,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _track,
          icon: const Icon(Icons.search_rounded),
          label: Text(_busy ? 'Looking up' : 'Track request'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.navy, padding: const EdgeInsets.symmetric(vertical: 15)),
        ),
        const SizedBox(height: 18),
        if (_busy) const HdSkeleton(rows: 1, height: 110),
        if (_error != null)
          HdNotice(
            title: 'No request found',
            message: '$_error You can only track requests you are authorised to view.',
            icon: Icons.search_off_rounded,
            tone: HdTone.warning,
            action: TextButton(onPressed: _track, child: const Text('Try again')),
          ),
        if (_result != null)
          HdRequestCard(
            request: _result!,
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => RequestDetailScreen(session: widget.session, requestId: hdStr(_result!['id'])))),
          ),
      ],
    );
  }
}
