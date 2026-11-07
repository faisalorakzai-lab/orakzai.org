import 'package:flutter/material.dart';

import '../app/app_language.dart';
import '../app/app_theme.dart';
import '../widgets/app_components.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    required this.language,
    required this.onLanguageChanged,
    super.key,
  });

  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _notificationsEnabled = false;

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: AppCopy.text(widget.language, 'profile'),
      subtitle: 'Your account and privacy settings.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GuestProfileCard(language: widget.language),
          const SizedBox(height: 22),
          const SectionHeading(title: 'My activity'),
          _ProfileOptions(onOpen: _showUnavailable),
          const SizedBox(height: 22),
          SectionHeading(title: AppCopy.text(widget.language, 'language')),
          Text(
            'English is fully available in this first milestone. Urdu and Pashto include translated navigation and home controls; remaining copy is prepared for localization.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: AppLanguage.values
                .map(
                  (language) => ChoiceChip(
                    label: Text(language.displayName),
                    selected: widget.language == language,
                    onSelected: (_) => widget.onLanguageChanged(language),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 22),
          const SectionHeading(title: 'Privacy & security'),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  value: _notificationsEnabled,
                  onChanged: (value) =>
                      setState(() => _notificationsEnabled = value),
                  title: const Text('Notification preference'),
                  subtitle: const Text(
                    'Local preview setting only; push notifications are not connected.',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.lock_outline_rounded),
                  title: const Text('Private details'),
                  subtitle: const Text(
                    'No contact or profile data is stored in this milestone.',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showUnavailable('Privacy settings'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const InfoBanner(
            title: 'No account is signed in',
            message:
                'Authentication, membership verification and secure profile storage are not connected yet.',
            icon: Icons.person_off_outlined,
            background: AppColors.goldWash,
            foreground: AppColors.navy,
          ),
        ],
      ),
    );
  }

  Future<void> _showUnavailable(String section) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(section),
        content: const Text(
          'This section becomes available after secure accounts and the organization’s backend are connected. No member information is being fabricated.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _GuestProfileCard extends StatelessWidget {
  const _GuestProfileCard({required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.11),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.gold, width: 1.4),
            ),
            child: const Icon(
              Icons.person_outline_rounded,
              color: AppColors.gold,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppCopy.text(language, 'guest'),
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 5),
                Text(
                  'Membership ID: not assigned',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.78),
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

class _ProfileOptions extends StatelessWidget {
  const _ProfileOptions({required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          ProfileOptionTile(
            icon: Icons.assignment_outlined,
            title: 'Submitted requests',
            subtitle: 'Private assistance request history',
            onTap: () => onOpen('Submitted requests'),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ProfileOptionTile(
            icon: Icons.groups_outlined,
            title: 'My groups',
            subtitle: 'Your community spaces',
            onTap: () => onOpen('My groups'),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ProfileOptionTile(
            icon: Icons.bookmark_border_rounded,
            title: 'Saved posts',
            subtitle: 'Your saved community updates',
            onTap: () => onOpen('Saved posts'),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ProfileOptionTile(
            icon: Icons.notifications_none_rounded,
            title: 'Notifications',
            subtitle: 'Alerts and announcements',
            onTap: () => onOpen('Notifications'),
          ),
        ],
      ),
    );
  }
}
