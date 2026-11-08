import 'package:flutter/material.dart';

import '../app/app_theme.dart';

/// Section header: small emerald eyebrow, confident title, optional action.
class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({
    required this.eyebrow,
    required this.title,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String eyebrow;
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.end,
        runSpacing: 4,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.goldDeep,
                  fontSize: 10.5,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 4),
              Semantics(
                header: true,
                child: Text(title,
                    style: theme.textTheme.titleLarge?.copyWith(fontSize: 18)),
              ),
            ],
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(48, 40),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(actionLabel!),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_rounded, size: 16),
              ]),
            ),
        ],
      ),
    );
  }
}

/// Skeleton blocks (static, tinted to the ivory canvas).
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({this.lines = 2, this.height = 74, super.key});
  final int lines;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: Column(
        children: [
          for (var i = 0; i < lines; i++)
            Container(
              height: height,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bar(110),
                  if (height > 60) ...[
                    const SizedBox(height: 10),
                    Flexible(child: _bar(double.infinity)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _bar(double w) => Container(
        width: w,
        height: 10,
        decoration: BoxDecoration(
          color: AppColors.line.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(6),
        ),
      );
}

enum HomeNoticeTone { neutral, error, gate }

/// Composed empty / error / sign-in state with an optional action.
class HomeStateCard extends StatelessWidget {
  const HomeStateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.tone = HomeNoticeTone.neutral,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final HomeNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, iconBg) = switch (tone) {
      HomeNoticeTone.error =>
        (AppColors.dangerWash, AppColors.danger, AppColors.surface),
      HomeNoticeTone.gate =>
        (AppColors.surface, AppColors.emerald, AppColors.goldWash),
      HomeNoticeTone.neutral =>
        (AppColors.surface, AppColors.navy, AppColors.blueWash),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: tone == HomeNoticeTone.error
              ? fg.withValues(alpha: 0.18)
              : AppColors.line,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon,
                color: tone == HomeNoticeTone.gate ? AppColors.goldDeep : fg,
                size: 20),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: AppColors.ink)),
                const SizedBox(height: 3),
                Text(message, style: Theme.of(context).textTheme.bodySmall),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      foregroundColor: fg,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(48, 40),
                    ),
                    icon: Icon(
                      tone == HomeNoticeTone.error
                          ? Icons.refresh_rounded
                          : Icons.arrow_forward_rounded,
                      size: 18,
                    ),
                    label: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Action row used for Emergency Help and Submit a Request.
class HomeShortcut extends StatelessWidget {
  const HomeShortcut({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.urgent = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = urgent ? AppColors.dangerWash : AppColors.emerald;
    final fg = urgent ? AppColors.danger : AppColors.ivory;
    return Semantics(
      button: true,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: urgent
                    ? AppColors.danger.withValues(alpha: 0.16)
                    : AppColors.emerald,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: urgent
                        ? AppColors.danger
                        : AppColors.ivory.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon,
                      color: urgent ? AppColors.ivory : AppColors.gold,
                      size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: theme.textTheme.titleSmall?.copyWith(
                              color: urgent ? AppColors.ink : AppColors.ivory,
                              fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: urgent
                              ? AppColors.muted
                              : AppColors.ivory.withValues(alpha: 0.74),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Icon(Icons.arrow_forward_rounded, color: fg, size: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A real feed record (id, body, authorName, createdAt, isAnnouncement).
class HomeFeedTile extends StatelessWidget {
  const HomeFeedTile({required this.record, required this.onOpen, super.key});
  final Map<String, dynamic> record;
  final VoidCallback onOpen;

  static String formatDate(Object? raw) {
    final d = DateTime.tryParse('${raw ?? ''}')?.toLocal();
    if (d == null) return '';
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = '${record['body'] ?? ''}'.trim();
    final author = '${record['authorName'] ?? ''}'.trim();
    final announcement = record['isAnnouncement'] == true;
    final date = formatDate(record['createdAt']);
    final initial = author.isEmpty ? 'O' : author[0].toUpperCase();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onOpen,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        announcement ? AppColors.navy : AppColors.goldWash,
                    shape: BoxShape.circle,
                  ),
                  child: announcement
                      ? const Icon(Icons.campaign_outlined,
                          color: AppColors.gold, size: 18)
                      : Text(initial,
                          style: const TextStyle(
                              color: AppColors.goldDeep,
                              fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (author.isNotEmpty)
                            Text(author,
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontSize: 13.5)),
                          if (announcement)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.goldWash,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('ANNOUNCEMENT',
                                  style: TextStyle(
                                      color: AppColors.goldDeep,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.9)),
                            ),
                          if (date.isNotEmpty)
                            Text(date, style: theme.textTheme.bodySmall),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        body.isEmpty ? 'No text in this post.' : body,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontSize: 14.5, height: 1.45),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One verified statistic, designed to sit on an emerald panel.
class HomeStatTile extends StatelessWidget {
  const HomeStatTile({
    required this.value,
    required this.label,
    required this.icon,
    super.key,
  });
  final int value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
        decoration: BoxDecoration(
          color: AppColors.ivory.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.ivory.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.gold, size: 18),
            const SizedBox(height: 10),
            Text('$value',
                style: const TextStyle(
                    color: AppColors.ivory,
                    fontSize: 28,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    fontFeatures: [FontFeature.tabularFigures()])),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    color: AppColors.ivory.withValues(alpha: 0.75),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// Reference-style action tile: tinted icon block, bold label, short detail.
/// Content-sized (no fixed height) so large text grows instead of clipping.
class HomeActionTile extends StatelessWidget {
  const HomeActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.tone = HomeActionTone.neutral,
    this.horizontal = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final HomeActionTone tone;

  /// Row layout used when tiles are stacked (narrow width or large text).
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = tone == HomeActionTone.primary;
    final (bg, border, iconBg, iconFg, titleFg, subFg) = switch (tone) {
      HomeActionTone.primary => (
          AppColors.navy,
          AppColors.navy,
          AppColors.gold.withValues(alpha: 0.18),
          AppColors.gold,
          AppColors.onDark,
          AppColors.onDark.withValues(alpha: 0.72),
        ),
      HomeActionTone.urgent => (
          AppColors.dangerWash,
          AppColors.danger.withValues(alpha: 0.16),
          AppColors.danger,
          AppColors.onDark,
          AppColors.ink,
          AppColors.muted,
        ),
      HomeActionTone.neutral => (
          AppColors.surface,
          AppColors.line,
          AppColors.blueWash,
          AppColors.blue,
          AppColors.ink,
          AppColors.muted,
        ),
      HomeActionTone.gold => (
          AppColors.surface,
          AppColors.line,
          AppColors.goldWash,
          AppColors.goldDeep,
          AppColors.ink,
          AppColors.muted,
        ),
    };
    final iconBox = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: iconBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: iconFg, size: 21),
    );
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title,
            style: theme.textTheme.titleSmall
                ?.copyWith(color: titleFg, fontSize: 14.5, height: 1.25)),
        const SizedBox(height: 3),
        Text(subtitle,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: subFg, fontSize: 12, height: 1.35)),
      ],
    );
    return Semantics(
      button: true,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: border),
            ),
            child: horizontal
                ? Row(children: [
                    iconBox,
                    const SizedBox(width: 12),
                    Expanded(child: texts),
                    const SizedBox(width: 6),
                    Icon(Icons.chevron_right_rounded,
                        color: primary ? AppColors.gold : AppColors.muted),
                  ])
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        iconBox,
                        const Spacer(),
                        Icon(Icons.arrow_outward_rounded,
                            size: 18,
                            color: primary ? AppColors.gold : AppColors.muted),
                      ]),
                      const SizedBox(height: 12),
                      texts,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

enum HomeActionTone { primary, urgent, neutral, gold }
