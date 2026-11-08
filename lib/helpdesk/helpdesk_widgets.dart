import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import 'helpdesk_common.dart';

/// Inner route scaffold used by every pushed help desk screen.
class HdScaffold extends StatelessWidget {
  const HdScaffold({
    required this.title,
    required this.children,
    this.subtitle,
    this.actions,
    this.onRefresh,
    this.bottom,
    this.floatingActionButton,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final List<Widget>? actions;
  final Future<void> Function()? onRefresh;
  final Widget? bottom;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 32),
      children: [
        Text('HELP DESK',
            style: theme.textTheme.labelLarge?.copyWith(
                color: AppColors.goldDeep, letterSpacing: 1.3, fontSize: 11)),
        const SizedBox(height: 6),
        Text(title, style: theme.textTheme.headlineMedium),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 18),
        ...children,
      ],
    );
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.navy,
        elevation: 0,
        actions: actions,
      ),
      floatingActionButton: floatingActionButton,
      body: onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list),
      bottomNavigationBar: bottom,
    );
  }
}

class HdPill extends StatelessWidget {
  const HdPill({required this.label, required this.color, required this.background, super.key});
  final String label;
  final Color color;
  final Color background;

  factory HdPill.status(String? status) =>
      HdPill(label: hdStatus(status), color: hdStatusColor(status), background: hdStatusWash(status));

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(99)),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
    );
  }
}

class HdCard extends StatelessWidget {
  const HdCard({required this.child, this.onTap, this.padding = const EdgeInsets.all(16), this.accent, super.key});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (accent != null) Container(width: 4, color: accent),
                  Expanded(child: Padding(padding: padding, child: child)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HdNotice extends StatelessWidget {
  const HdNotice({
    required this.title,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.tone = HdTone.neutral,
    this.action,
    super.key,
  });
  final String title;
  final String message;
  final IconData icon;
  final HdTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      HdTone.danger => (AppColors.dangerWash, AppColors.danger),
      HdTone.success => (AppColors.greenWash, AppColors.green),
      HdTone.warning => (AppColors.goldWash, const Color(0xFF7A5C14)),
      HdTone.neutral => (AppColors.surface, AppColors.navy),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tone == HdTone.neutral ? AppColors.line : bg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 14.5)),
                const SizedBox(height: 4),
                Text(message, style: const TextStyle(color: AppColors.ink, fontSize: 13.5, height: 1.45)),
                if (action != null) ...[const SizedBox(height: 8), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum HdTone { neutral, danger, success, warning }

class HdErrorPanel extends StatelessWidget {
  const HdErrorPanel({required this.message, required this.onRetry, super.key});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => HdNotice(
        title: 'This did not load',
        message: message,
        icon: Icons.cloud_off_rounded,
        tone: HdTone.danger,
        action: TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
      );
}

class HdEmpty extends StatelessWidget {
  const HdEmpty({required this.title, required this.message, this.icon = Icons.inbox_outlined, this.action, super.key});
  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
        color: AppColors.surface,
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(color: AppColors.goldWash, shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.navy),
          ),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}

/// Skeletal loading placeholder, no spinners.
class HdSkeleton extends StatefulWidget {
  const HdSkeleton({this.rows = 3, this.height = 76, super.key});
  final int rows;
  final double height;

  @override
  State<HdSkeleton> createState() => _HdSkeletonState();
}

class _HdSkeletonState extends State<HdSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: FadeTransition(
        opacity: Tween(begin: 0.45, end: 1.0).animate(_c),
        child: Column(
          children: List.generate(
            widget.rows,
            (i) => Container(
              height: widget.height,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(18)),
            ),
          ),
        ),
      ),
    );
  }
}

class HdSectionTitle extends StatelessWidget {
  const HdSectionTitle(this.title, {this.trailing, super.key});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Row(
        children: [
          Container(width: 14, height: 2, color: AppColors.gold),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class HdRequestCard extends StatelessWidget {
  const HdRequestCard({required this.request, required this.onTap, this.showAssignee = false, super.key});
  final Map<String, dynamic> request;
  final VoidCallback onTap;
  final bool showAssignee;

  @override
  Widget build(BuildContext context) {
    final status = hdStr(request['status']);
    final priority = hdStr(request['priority']);
    final assigned = hdStr(request['assignedName']);
    final dept = hdStr(request['departmentName']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: HdCard(
        onTap: onTap,
        accent: hdStatusColor(status),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(hdStr(request['reference']),
                    style: const TextStyle(
                        fontFamily: 'monospace', color: AppColors.muted, fontSize: 12, letterSpacing: 0.6)),
                const Spacer(),
                HdPill.status(status),
              ],
            ),
            const SizedBox(height: 8),
            Text(hdStr(request['title']),
                maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(hdCategory(hdStr(request['category'])), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                Text('${hdPriority(priority)} priority',
                    style: TextStyle(color: hdPriorityColor(priority), fontSize: 12.5, fontWeight: FontWeight.w600)),
                Text('Updated ${hdDate(request['updatedAt'])}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ],
            ),
            if (showAssignee) ...[
              const SizedBox(height: 6),
              Text(
                assigned.isEmpty ? 'Unassigned${dept.isEmpty ? '' : ' - $dept'}' : 'With $assigned${dept.isEmpty ? '' : ' - $dept'}',
                style: const TextStyle(color: AppColors.navySoft, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class HdKeyValue extends StatelessWidget {
  const HdKeyValue(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13))),
          Expanded(child: Text(value.isEmpty ? 'Not provided' : value, style: const TextStyle(color: AppColors.ink, fontSize: 13.5))),
        ],
      ),
    );
  }
}

/// Simple text dialog with validation and backend error display.
Future<bool> hdTextDialog(
  BuildContext context, {
  required String title,
  required List<HdDialogField> fields,
  required Future<void> Function(List<String> values) onSubmit,
  String submitLabel = 'Save',
}) async {
  final controllers = fields.map((_) => TextEditingController()).toList();
  final formKey = GlobalKey<FormState>();
  String? error;
  var busy = false;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < fields.length; i++) ...[
                  TextFormField(
                    controller: controllers[i],
                    maxLines: fields[i].maxLines,
                    maxLength: fields[i].max,
                    decoration: InputDecoration(labelText: fields[i].label),
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.length < fields[i].min) return 'Enter at least ${fields[i].min} characters.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                if (error != null)
                  Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (!formKey.currentState!.validate()) return;
                    setLocal(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await onSubmit(controllers.map((c) => c.text.trim()).toList());
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      setLocal(() {
                        busy = false;
                        error = hdError(e);
                      });
                    }
                  },
            child: Text(busy ? 'Saving' : submitLabel),
          ),
        ],
      ),
    ),
  );
  for (final c in controllers) {
    c.dispose();
  }
  return result ?? false;
}

class HdDialogField {
  const HdDialogField(this.label, {this.min = 1, this.max = 2000, this.maxLines = 1});
  final String label;
  final int min;
  final int max;
  final int maxLines;
}

void hdSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? AppColors.danger : AppColors.navy,
    behavior: SnackBarBehavior.floating,
  ));
}
