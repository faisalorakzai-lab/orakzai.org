import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../widgets/app_components.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  bool _saved = false;
  String _selectedCategory = 'All topics';

  static const _topics = <String>[
    'All topics',
    'Diaspora',
    'Education',
    'Community support',
  ];

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Community',
      subtitle:
          'Public updates and future group spaces for Orakzai communities.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const InfoBanner(
            title: 'Community feed preview',
            message:
                'This screen uses organization information only. No member profiles, messages or live community activity are connected.',
            icon: Icons.groups_2_outlined,
          ),
          const SizedBox(height: 22),
          const SectionHeading(title: 'Public update'),
          _OfficialPostCard(
            saved: _saved,
            onSave: () {
              setState(() => _saved = !_saved);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _saved
                        ? 'Saved in this preview only.'
                        : 'Removed from this preview.',
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            onShare: () => _showPreviewNotice(context, 'Sharing'),
          ),
          const SizedBox(height: 22),
          const SectionHeading(title: 'Suggested group topics'),
          Text(
            'Topics are based on the organization’s published program areas. They are not live groups.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _topics
                .map(
                  (topic) => ChoiceChip(
                    label: Text(topic),
                    selected: _selectedCategory == topic,
                    onSelected: (_) =>
                        setState(() => _selectedCategory = topic),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          ..._topicCards(_selectedCategory).map(
            (topic) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TopicCard(
                title: topic.$1,
                detail: topic.$2,
                icon: topic.$3,
                onTap: () => _showPreviewNotice(context, topic.$1),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeading(title: 'Messaging'),
          const InfoBanner(
            title: 'Private messages are not connected',
            message:
                'A secure messaging backend, moderation controls and member accounts are required before conversations can go live.',
            icon: Icons.lock_outline_rounded,
            background: AppColors.greenWash,
            foreground: AppColors.green,
          ),
          const SizedBox(height: 16),
          const EmptyState(
            title: 'No live polls or announcements',
            message:
                'Organization announcements can be added after a verified content source is connected.',
            icon: Icons.forum_outlined,
          ),
        ],
      ),
    );
  }

  List<(String, String, IconData)> _topicCards(String filter) {
    const topics = <(String, String, IconData, String)>[
      (
        'Global diaspora connections',
        'A suggested space for families, professionals and community organizations.',
        Icons.public_rounded,
        'Diaspora',
      ),
      (
        'Learning & mentorship',
        'A suggested space for scholarship information and student mentorship.',
        Icons.school_outlined,
        'Education',
      ),
      (
        'Community support',
        'A suggested space for welfare resources and community guidance.',
        Icons.volunteer_activism_outlined,
        'Community support',
      ),
    ];
    return topics
        .where((topic) => filter == 'All topics' || topic.$4 == filter)
        .map((topic) => (topic.$1, topic.$2, topic.$3))
        .toList();
  }

  Future<void> _showPreviewNotice(BuildContext context, String action) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(action),
        content: const Text(
          'This is a local preview interaction. It does not contact another member or publish anything.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

class _OfficialPostCard extends StatelessWidget {
  const _OfficialPostCard({
    required this.saved,
    required this.onSave,
    required this.onShare,
  });

  final bool saved;
  final VoidCallback onSave;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [AppColors.navy, AppColors.navySoft],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_outlined, color: AppColors.gold),
              const SizedBox(width: 8),
              Text(
                'ORAKZAI.ORG',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              const Text(
                'PUBLIC SITE',
                style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'United in purpose. Empowered for a better future.',
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            'The organization’s website describes pathways to education, community development and humanitarian support.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: 15),
          const Divider(color: Color(0x33FFFFFF), height: 1),
          Row(
            children: [
              TextButton.icon(
                onPressed: onSave,
                icon: Icon(
                  saved
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  color: AppColors.gold,
                  size: 19,
                ),
                label: Text(
                  saved ? 'Saved locally' : 'Save',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Share preview post',
                onPressed: onShare,
                icon: const Icon(Icons.ios_share_rounded, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({
    required this.title,
    required this.detail,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String detail;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: const BorderSide(color: AppColors.line),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: AppColors.green),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(detail),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}
