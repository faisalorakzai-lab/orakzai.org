import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import 'helpdesk_common.dart';
import 'helpdesk_widgets.dart';

/// Assignment and reassignment. Only reachable when the request reports canManage.
class AssignmentScreen extends StatefulWidget {
  const AssignmentScreen({required this.session, required this.request, super.key});
  final HelpDeskSession session;
  final Map<String, dynamic> request;

  @override
  State<AssignmentScreen> createState() => _AssignmentScreenState();
}

class _AssignmentScreenState extends State<AssignmentScreen> {
  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> _departments = [];
  late String? _staffId = hdStr(widget.request['assignedTo']).isEmpty ? null : hdStr(widget.request['assignedTo']);
  late String? _deptId = hdStr(widget.request['departmentId']).isEmpty ? null : hdStr(widget.request['departmentId']);
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _list(Map<String, dynamic> res, String key) =>
      hdItems(res['items']).isNotEmpty ? hdItems(res['items']) : hdItems(res[key]);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.session.api.get('/admin/staff'),
        widget.session.api.get('/departments'),
      ]);
      if (!mounted) return;
      final owner = hdStr(widget.request['ownerId']);
      setState(() {
        _staff = _list(results[0], 'staff').where((s) => hdStr(s['id']) != owner).toList();
        _departments = _list(results[1], 'departments');
        if (!_staff.any((s) => hdStr(s['id']) == _staffId)) _staffId = null;
        if (!_departments.any((d) => hdStr(d['id']) == _deptId)) _deptId = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = hdError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addDepartment() async {
    final ok = await hdTextDialog(
      context,
      title: 'New department',
      submitLabel: 'Create',
      fields: const [HdDialogField('Department name', min: 2, max: 100)],
      onSubmit: (v) => widget.session.api.post('/admin/departments', {'name': v[0]}),
    );
    if (ok) _load();
  }

  Future<void> _save() async {
    if (_staffId == null && _deptId == null) {
      setState(() => _saveError = 'Choose a staff member or a department.');
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.session.api.post('/admin/requests/${hdStr(widget.request['id'])}/assign', {
        'staffId': _staffId,
        'departmentId': _deptId,
      });
      if (!mounted) return;
      hdSnack(context, 'Assignment saved.');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _saveError = hdError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = hdStr(widget.request['assignedName']);
    return HdScaffold(
      title: current.isEmpty ? 'Assign request' : 'Reassign request',
      subtitle: current.isEmpty
          ? 'Choose who should handle ${hdStr(widget.request['reference'])}.'
          : 'Currently with $current. The member who submitted it cannot be selected.',
      children: [
        if (_loading)
          const HdSkeleton(rows: 4, height: 54)
        else if (_error != null)
          HdErrorPanel(message: _error!, onRetry: _load)
        else ...[
          HdSectionTitle('Department',
              trailing: TextButton.icon(
                  onPressed: _addDepartment, icon: const Icon(Icons.add_rounded), label: const Text('New'))),
          DropdownButtonFormField<String?>(
            value: _deptId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Department'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('No department')),
              for (final d in _departments)
                DropdownMenuItem<String?>(value: hdStr(d['id']), child: Text(hdStr(d['name']))),
            ],
            onChanged: (v) => setState(() => _deptId = v),
          ),
          const HdSectionTitle('Staff member'),
          if (_staff.isEmpty)
            const HdEmpty(
                title: 'No eligible staff',
                message: 'There are no other active staff accounts available.',
                icon: Icons.person_off_outlined)
          else
            RadioGroupFallback(
              options: {for (final s in _staff) hdStr(s['id']): hdStr(s['name'])},
              value: _staffId,
              onChanged: (v) => setState(() => _staffId = v),
            ),
          if (_saveError != null) ...[
            const SizedBox(height: 10),
            Text(_saveError!, style: const TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(backgroundColor: AppColors.navy, padding: const EdgeInsets.symmetric(vertical: 15)),
            child: Text(_saving ? 'Saving' : 'Save assignment'),
          ),
        ],
      ],
    );
  }
}

/// Selectable list of staff, implemented with tiles to avoid Radio API churn.
class RadioGroupFallback extends StatelessWidget {
  const RadioGroupFallback({required this.options, required this.value, required this.onChanged, super.key});
  final Map<String, String> options;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return HdCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        for (final e in options.entries)
          ListTile(
            onTap: () => onChanged(value == e.key ? null : e.key),
            leading: CircleAvatar(
              backgroundColor: AppColors.goldWash,
              foregroundColor: AppColors.navy,
              child: Text(e.value.isEmpty ? '?' : e.value.trim()[0].toUpperCase()),
            ),
            title: Text(e.value),
            trailing: Icon(
              value == e.key ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: value == e.key ? AppColors.green : AppColors.muted,
            ),
          ),
      ]),
    );
  }
}
