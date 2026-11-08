import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../data/program_area.dart';

class AppPage extends StatelessWidget {
  const AppPage({
    required this.title,
    required this.subtitle,
    required this.child,
    this.eyebrow = 'ORAKZAI.ORG',
    super.key,
  });

  final String title;
  final String subtitle;
  final String eyebrow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BrandHeader(),
            const SizedBox(height: 24),
            Text(
              eyebrow.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.goldDeep,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(title, style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(subtitle, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 22),
            child,
          ],
        ),
      ),
    );
  }
}

class BrandHeader extends StatelessWidget {
  const BrandHeader({this.trailing, super.key});

  /// Optional trailing control (e.g. a search button on Home).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: AppColors.navy,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Image.asset(
              'assets/images/orakzai_emblem.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const ColoredBox(
                color: AppColors.emerald,
                child: Icon(Icons.landscape_outlined, color: AppColors.gold),
              ),
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ORAKZAI.ORG',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              Text(
                'GLOBAL ORAKZAI COMMUNITY',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.goldDeep,
                  fontSize: 9.5,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    required this.title,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

class InfoBanner extends StatelessWidget {
  const InfoBanner({
    required this.title,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.background = AppColors.goldWash,
    this.foreground = AppColors.navy,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: foreground.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foreground, size: 21),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.82),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class QuickActionCard extends StatelessWidget {
  const QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.emergency = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool emergency;

  @override
  Widget build(BuildContext context) {
    final background = emergency ? AppColors.emerald : AppColors.surface;
    final foreground = emergency ? AppColors.ivory : AppColors.ink;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 132),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: emergency ? AppColors.navy : AppColors.line,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: emergency ? AppColors.gold : AppColors.green),
              const SizedBox(height: 22),
              Text(
                title,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: foreground.withValues(alpha: emergency ? 0.76 : 0.68),
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProgramAreaCard extends StatelessWidget {
  const ProgramAreaCard({required this.area, required this.onTap, super.key});

  final ProgramArea area;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.greenWash,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(area.icon, color: AppColors.emerald, size: 21),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(area.title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 5),
                    Text(
                      area.summary,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 9),
                    Text(
                      area.source.toUpperCase(),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: AppColors.goldDeep,
                        fontSize: 9.5,
                        letterSpacing: 0.9,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppColors.muted,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.muted, size: 28),
          const SizedBox(height: 10),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 5),
          Text(
            message,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class ProfileOptionTile extends StatelessWidget {
  const ProfileOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.greenWash,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppColors.emerald, size: 20),
      ),
      title: Text(title, style: theme.textTheme.titleMedium),
      subtitle: Text(subtitle, style: theme.textTheme.bodyMedium),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
      onTap: onTap,
    );
  }
}
