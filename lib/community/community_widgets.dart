import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app/app_theme.dart';
import 'community_controller.dart';
import 'media_preview.dart';

class CommunityNotice extends StatelessWidget {
  const CommunityNotice({
    required this.title,
    required this.message,
    this.action,
    this.icon = Icons.info_outline_rounded,
    super.key,
  });

  final String title;
  final String message;
  final Widget? action;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.blueWash,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(message, style: Theme.of(context).textTheme.bodyMedium),
                if (action != null) ...[const SizedBox(height: 10), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CommunityEmpty extends StatelessWidget {
  const CommunityEmpty({
    required this.title,
    required this.message,
    this.action,
    this.icon = Icons.groups_2_outlined,
    super.key,
  });

  final String title;
  final String message;
  final Widget? action;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
      child: Column(
        children: [
          Icon(icon, size: 36, color: AppColors.goldDeep),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 5),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}

class CommunityGroupCard extends StatelessWidget {
  const CommunityGroupCard({
    required this.group,
    required this.onTap,
    this.onJoin,
    super.key,
  });

  final Map<String, dynamic> group;
  final VoidCallback onTap;
  final VoidCallback? onJoin;

  @override
  Widget build(BuildContext context) {
    final myStatus = group['myStatus'] as String?;
    final visibility = group['visibility'] as String? ?? 'public';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.line),
      ),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: AppColors.goldWash,
          foregroundColor: AppColors.navy,
          child: Icon(_categoryIcon(group['category'] as String? ?? 'general')),
        ),
        title: Text(group['name'] as String? ?? 'Community group'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((group['description'] as String? ?? '').isNotEmpty)
              Text(
                group['description'] as String,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 4),
            Text(
              '${group['memberCount'] ?? 0} members · ${visibility == 'private' ? 'Private' : 'Public'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        isThreeLine: (group['description'] as String? ?? '').isNotEmpty,
        trailing: myStatus == 'active'
            ? const Icon(Icons.chevron_right_rounded)
            : onJoin == null
                ? const Icon(Icons.lock_outline_rounded)
                : TextButton(onPressed: onJoin, child: const Text('Join')),
      ),
    );
  }

  IconData _categoryIcon(String category) => switch (category) {
    'education' => Icons.school_outlined,
    'healthcare' => Icons.health_and_safety_outlined,
    'business' => Icons.storefront_outlined,
    'employment' => Icons.work_outline_rounded,
    'overseas' => Icons.public_rounded,
    'welfare' => Icons.volunteer_activism_outlined,
    'culture' => Icons.theater_comedy_outlined,
    'youth' => Icons.sports_outlined,
    'regional' => Icons.place_outlined,
    _ => Icons.groups_2_outlined,
  };
}

class ConversationTile extends StatelessWidget {
  const ConversationTile({
    required this.conversation,
    required this.onTap,
    super.key,
  });

  final Map<String, dynamic> conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final groupName = conversation['groupName'] as String?;
    final other = conversation['otherMember'] is Map
        ? Map<String, dynamic>.from(conversation['otherMember'] as Map)
        : null;
    final title = groupName ?? other?['fullName'] as String? ?? 'Private conversation';
    final unread = conversation['unreadCount'] as int? ?? 0;
    final lastMessage = conversation['lastMessage'] as String? ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.line),
      ),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: AppColors.navy,
          foregroundColor: AppColors.gold,
          child: Icon(
            groupName == null ? Icons.person_outline_rounded : Icons.groups_2_outlined,
          ),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          lastMessage.isEmpty ? 'No messages yet' : lastMessage,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: unread > 0
            ? CircleAvatar(
                radius: 13,
                backgroundColor: AppColors.green,
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  style: const TextStyle(color: AppColors.ivory, fontSize: 10),
                ),
              )
            : const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class CommunityPostCard extends StatelessWidget {
  const CommunityPostCard({
    required this.controller,
    required this.post,
    required this.onComments,
    this.onMemberTap,
    super.key,
  });

  final CommunityController controller;
  final Map<String, dynamic> post;
  final VoidCallback onComments;
  final ValueChanged<String>? onMemberTap;

  @override
  Widget build(BuildContext context) {
    final authorId = post['authorId'] as String?;
    final name = post['authorName'] as String? ?? 'Community member';
    final media = post['media'] is List
        ? (post['media'] as List).whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
        : <Map<String, dynamic>>[];
    final saved = post['isBookmarked'] == true;
    final reacted = post['myReaction'] != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
        boxShadow: const [
          BoxShadow(color: Color(0x0A064E3B), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.goldWash,
                foregroundColor: AppColors.navy,
                child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: authorId != null ? () => onMemberTap?.call(authorId) : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: Theme.of(context).textTheme.titleSmall),
                      Text(
                        _postContext(post),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) => _handleMenu(context, value),
                itemBuilder: (context) => [
                  if (authorId == controller.auth.user?.id)
                    const PopupMenuItem(value: 'edit', child: Text('Edit post')),
                  if (authorId == controller.auth.user?.id)
                    const PopupMenuItem(value: 'delete', child: Text('Delete post')),
                  if (controller.canModerate)
                    PopupMenuItem(
                      value: post['isAnnouncement'] == true ? 'unpin' : 'pin',
                      child: Text(post['isAnnouncement'] == true
                          ? 'Remove announcement'
                          : 'Pin as announcement'),
                    ),
                  const PopupMenuItem(value: 'report', child: Text('Report post')),
                ],
              ),
            ],
          ),
          if ((post['body'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 13),
            SelectableText(post['body'] as String),
          ],
          if (media.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: media
                  .map((item) => MediaAttachmentTile(controller: controller, media: item))
                  .toList(),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Text('${post['reactionCount'] ?? 0} reactions'),
              const SizedBox(width: 13),
              Text('${post['commentCount'] ?? 0} comments'),
              const Spacer(),
              Text('${post['shareCount'] ?? 0} shares'),
            ],
          ),
          const Divider(height: 18),
          Row(
            children: [
              _ActionButton(
                icon: reacted ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                label: reacted ? 'Reacted' : 'React',
                onTap: () => controller.reactToPost(post['id'] as String, 'like'),
              ),
              _ActionButton(
                icon: Icons.mode_comment_outlined,
                label: 'Comment',
                onTap: onComments,
              ),
              _ActionButton(
                icon: saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                label: 'Save',
                onTap: () => controller.bookmarkPost(
                  post['id'] as String,
                  saved: !saved,
                ),
              ),
              _ActionButton(
                icon: Icons.ios_share_rounded,
                label: 'Share',
                onTap: () => _share(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _share(BuildContext context) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        text: '${post['body'] ?? ''}\n\nShared from ORAKZAI.ORG community.',
      ),
    );
    if (result.status == ShareResultStatus.success) {
      await controller.sharePost(post['id'] as String);
    }
  }

  Future<void> _handleMenu(BuildContext context, String action) async {
    final id = post['id'] as String;
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete this post?'),
          content: const Text('The post will be removed from the community feed.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
          ],
        ),
      );
      if (confirmed == true) await controller.deletePost(id);
    } else if (action == 'edit') {
      final bodyController = TextEditingController(text: post['body'] as String? ?? '');
      final updated = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Edit post'),
          content: TextField(
            controller: bodyController,
            autofocus: true,
            maxLines: 6,
            maxLength: 10000,
            decoration: const InputDecoration(labelText: 'Post text'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context, bodyController.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      bodyController.dispose();
      if (updated != null && updated.isNotEmpty) await controller.updatePost(id, updated);
    } else if (action == 'pin' || action == 'unpin') {
      await controller.setAnnouncement(id, pinned: action == 'pin');
    } else if (action == 'report') {
      await _report(context, id);
    }
  }

  Future<void> _report(BuildContext context, String id) async {
    const categories = <String, String>{
      'spam': 'Spam',
      'harassment': 'Harassment',
      'threats': 'Threats',
      'hate_abuse': 'Hate or abusive content',
      'fraud_scams': 'Fraud or scams',
      'impersonation': 'Impersonation',
      'inappropriate': 'Inappropriate content',
      'other': 'Other',
    };
    var category = 'spam';
    final details = TextEditingController();
    final report = await showDialog<(String, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Report post'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: category,
                items: categories.entries
                    .map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => category = value);
                },
                decoration: const InputDecoration(labelText: 'Reason'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: details,
                maxLength: 1000,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Details (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context, (category, details.text.trim())),
              child: const Text('Submit report'),
            ),
          ],
        ),
      ),
    );
    details.dispose();
    if (report != null) {
      await controller.reportContent(
        type: 'post',
        id: id,
        category: report.$1,
        details: report.$2,
      );
    }
  }

  String _postContext(Map<String, dynamic> value) {
    final group = value['groupName'] as String?;
    final pinned = value['isAnnouncement'] == true;
    final date = DateTime.tryParse(value['createdAt'] as String? ?? '');
    final age = date == null ? '' : _timeAgo(date);
    return [
      if (pinned) 'Organization announcement' else if (group != null) group else 'Community post',
      if (age.isNotEmpty) age,
    ].join(' · ');
  }

  String _timeAgo(DateTime value) {
    final diff = DateTime.now().difference(value.toLocal());
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${value.toLocal().month}/${value.toLocal().day}/${value.toLocal().year}';
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 17),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.navy,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          textStyle: const TextStyle(fontSize: 11),
        ),
      ),
    );
  }
}
