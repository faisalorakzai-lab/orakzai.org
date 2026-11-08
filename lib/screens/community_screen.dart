import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../auth/auth_controller.dart';
import '../community/community_controller.dart';
import '../community/community_widgets.dart';
import '../community/community_moderation_screen.dart';
import '../community/community_pages.dart';
import '../community/chat_screen.dart';
import '../widgets/app_components.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({
    required this.authController,
    required this.onOpenProfile,
    super.key,
  });

  final AuthController authController;
  final VoidCallback onOpenProfile;

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  late final CommunityController _community;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchTimer;
  int _section = 0;
  bool? _wasAuthenticated;
  bool _announcementMode = false;

  static const _sections = [
    'Feed',
    'My groups',
    'Discover',
    'Messages',
    'Announcements',
    'Regional',
    'Online',
  ];

  @override
  void initState() {
    super.initState();
    _community = CommunityController(auth: widget.authController);
    widget.authController.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  void _onAuthChanged() {
    final signedIn = widget.authController.isAuthenticated;
    if (signedIn == _wasAuthenticated) return;
    _wasAuthenticated = signedIn;
    if (signedIn) {
      unawaited(_community.load());
    } else {
      _community.reset();
    }
  }

  @override
  void dispose() {
    widget.authController.removeListener(_onAuthChanged);
    _searchTimer?.cancel();
    _searchController.dispose();
    _community.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Community',
      subtitle:
          'Connect with members, local groups and the wider Orakzai community.',
      child: AnimatedBuilder(
        animation: _community,
        builder: (context, _) {
          if (!_community.isAuthenticated) return _signedOut();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headerActions(),
              if (_community.loading) ...[
                const SizedBox(height: 14),
                const LinearProgressIndicator(),
              ],
              if (_community.error != null) ...[
                const SizedBox(height: 12),
                CommunityNotice(
                  title: 'Community request did not complete',
                  message: _community.error!,
                  icon: Icons.error_outline_rounded,
                  action: TextButton.icon(
                    onPressed: _community.refresh,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try again'),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _sectionPicker(),
              const SizedBox(height: 14),
              if (_section != 6) _searchField(),
              const SizedBox(height: 12),
              _sectionBody(),
            ],
          );
        },
      ),
    );
  }

  Widget _signedOut() {
    return CommunityNotice(
      title: 'Sign in to use Community',
      message:
          'Member groups, posts and private messages are available to verified accounts.',
      icon: Icons.lock_outline_rounded,
      action: FilledButton.icon(
        onPressed: widget.onOpenProfile,
        icon: const Icon(Icons.login_rounded),
        label: const Text('Open account'),
      ),
    );
  }

  Widget _headerActions() {
    final unread = _community.notifications
        .where((notification) => notification['readAt'] == null)
        .length;
    return Wrap(
      spacing: 7,
      runSpacing: 6,
      children: [
        _HeaderAction(
          icon: _community.connected
              ? Icons.wifi_rounded
              : Icons.wifi_off_rounded,
          label: _community.connected ? 'Live' : 'Reconnecting',
          onPressed: _community.refresh,
        ),
        _HeaderAction(
          icon: Icons.edit_note_rounded,
          label: 'Post',
          onPressed: () => _openCreatePost(),
        ),
        _HeaderAction(
          icon: Icons.add_circle_outline_rounded,
          label: 'Group',
          onPressed: () => _openCreateGroup(),
        ),
        _HeaderAction(
          icon: Icons.notifications_none_rounded,
          label: unread > 0 ? 'Alerts $unread' : 'Alerts',
          onPressed: _openNotifications,
        ),
        _HeaderAction(
          icon: Icons.tune_rounded,
          label: 'Privacy',
          onPressed: _openSettings,
        ),
        if (_community.canModerate)
          _HeaderAction(
            icon: Icons.shield_outlined,
            label: 'Review',
            onPressed: _openModeration,
          ),
      ],
    );
  }

  Widget _sectionPicker() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(_sections.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(_sections[index]),
              selected: _section == index,
              onSelected: (_) => _selectSection(index),
              selectedColor: AppColors.goldWash,
              side: BorderSide(
                color: _section == index ? AppColors.gold : AppColors.line,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _searchField() {
    final hint = switch (_section) {
      1 || 2 => 'Search community groups',
      3 => 'Search conversations and messages',
      4 || 5 || 0 => 'Search posts and announcements',
      _ => 'Search the community',
    };
    return TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      onChanged: _onSearch,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  _searchController.clear();
                  _onSearch('');
                },
                icon: const Icon(Icons.close_rounded),
              ),
      ),
    );
  }

  void _onSearch(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      if (_section == 1 || _section == 2) {
        unawaited(
          _community.loadGroups(
            search: value.trim().isEmpty ? null : value.trim(),
          ),
        );
      } else if (_section == 3) {
        unawaited(
          _community.loadConversations(
            search: value.trim().isEmpty ? null : value.trim(),
          ),
        );
      } else {
        unawaited(
          _loadSelectedFeed(search: value.trim().isEmpty ? null : value.trim()),
        );
      }
    });
    setState(() {});
  }

  void _selectSection(int index) {
    setState(() {
      _section = index;
      _searchController.clear();
      _announcementMode = index == 4;
    });
    if (index == 0) {
      unawaited(_community.loadFeed());
    } else if (index == 1 || index == 2) {
      unawaited(_community.loadGroups());
    } else if (index == 3) {
      unawaited(_community.loadConversations());
    } else if (index == 4) {
      unawaited(_community.loadFeed(announcementsOnly: true));
    } else if (index == 5) {
      final regionId = _community.assignedRegionId;
      if (regionId != null) {
        unawaited(_community.loadFeed(regionId: regionId));
      }
    } else if (index == 6) {
      unawaited(_community.loadOnlineMembers());
    }
  }

  Future<void> _loadSelectedFeed({String? search}) async {
    if (_section == 5) {
      final regionId = _community.assignedRegionId;
      if (regionId != null) {
        await _community.loadFeed(regionId: regionId, search: search);
      }
    } else {
      await _community.loadFeed(
        search: search,
        announcementsOnly: _announcementMode,
      );
    }
  }

  Widget _sectionBody() {
    switch (_section) {
      case 1:
        return _groupList(_community.myGroups, mine: true);
      case 2:
        return _groupList(_community.discoverGroups, mine: false);
      case 3:
        return _conversationList();
      case 4:
        return _postFeed(title: 'Organization announcements');
      case 5:
        return _regionalFeed();
      case 6:
        return _onlineMembers();
      default:
        return _postFeed(title: 'Community feed');
    }
  }

  Widget _postFeed({required String title}) {
    if (_community.feed.isEmpty) {
      return CommunityEmpty(
        title: _searchController.text.isNotEmpty
            ? 'No matching posts'
            : 'No posts yet',
        message: _searchController.text.isNotEmpty
            ? 'Try a different search.'
            : 'When members publish posts, they will appear here.',
        icon: Icons.forum_outlined,
        action: _searchController.text.isEmpty
            ? FilledButton.icon(
                onPressed: _openCreatePost,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create a post'),
              )
            : null,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        ..._community.feed.map(
          (post) => CommunityPostCard(
            controller: _community,
            post: post,
            onComments: () => _openComments(post),
            onMemberTap: _openMember,
          ),
        ),
        if (_community.feedCursor != null)
          Center(
            child: TextButton.icon(
              onPressed: _community.loadingMore
                  ? null
                  : _community.loadMoreFeed,
              icon: _community.loadingMore
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more_rounded),
              label: const Text('Load more'),
            ),
          ),
      ],
    );
  }

  Widget _groupList(List<Map<String, dynamic>> groups, {required bool mine}) {
    if (groups.isEmpty && (!mine || _community.invitations.isEmpty)) {
      return CommunityEmpty(
        title: mine ? 'You have not joined a group' : 'No groups found',
        message: mine
            ? 'Discover a public group or create one for your community.'
            : 'Groups are created by members. Search again or start a new group.',
        icon: Icons.groups_2_outlined,
        action: mine
            ? Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => _selectSection(2),
                    child: const Text('Discover groups'),
                  ),
                  FilledButton.icon(
                    onPressed: _openCreateGroup,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Create group'),
                  ),
                ],
              )
            : null,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (mine && _community.invitations.isNotEmpty) ...[
          Text(
            'Group invitations',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ..._community.invitations.map(
            (invitation) => Card(
              elevation: 0,
              color: AppColors.greenWash,
              child: ListTile(
                leading: const Icon(Icons.mail_outline_rounded),
                title: Text(
                  invitation['groupName'] as String? ?? 'Group invitation',
                ),
                subtitle: Text(
                  'Invited by ${invitation['inviterName'] ?? 'a group member'}',
                ),
                trailing: Wrap(
                  spacing: 2,
                  children: [
                    IconButton(
                      tooltip: 'Decline invitation',
                      onPressed: invitation['id'] is String
                          ? () => _community.respondToInvitation(
                              invitation['id'] as String,
                              accept: false,
                            )
                          : null,
                      icon: const Icon(Icons.close_rounded),
                    ),
                    IconButton(
                      tooltip: 'Accept invitation',
                      onPressed: invitation['id'] is String
                          ? () => _community.respondToInvitation(
                              invitation['id'] as String,
                              accept: true,
                            )
                          : null,
                      icon: const Icon(
                        Icons.check_rounded,
                        color: AppColors.green,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (groups.isNotEmpty) ...[
          Text(
            mine ? 'Your groups' : 'Discover groups',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          ...groups.map(
            (group) => CommunityGroupCard(
              group: group,
              onTap: () => _openGroup(group),
              onJoin: mine
                  ? null
                  : () async {
                      await _community.joinGroup(group['id'] as String);
                      if (_community.error != null && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(_community.error!)),
                        );
                      }
                    },
            ),
          ),
        ] else if (!mine)
          const SizedBox.shrink(),
      ],
    );
  }

  Widget _conversationList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Private messages and group chats',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Start a conversation',
              onPressed: _openMemberSearch,
              icon: const Icon(Icons.edit_square),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_community.conversations.isEmpty)
          CommunityEmpty(
            title: 'No conversations yet',
            message:
                'Search for a community member to start a private conversation.',
            icon: Icons.chat_bubble_outline_rounded,
            action: FilledButton.icon(
              onPressed: _openMemberSearch,
              icon: const Icon(Icons.person_search_rounded),
              label: const Text('Find members'),
            ),
          )
        else
          ..._community.conversations.map(
            (conversation) => ConversationTile(
              conversation: conversation,
              onTap: () => _openConversation(conversation),
            ),
          ),
      ],
    );
  }

  Widget _regionalFeed() {
    if (_community.assignedRegionId == null) {
      return const CommunityNotice(
        title: 'Regional access is not assigned',
        message:
            'A regional administrator must assign your account before regional posts are visible.',
        icon: Icons.place_outlined,
      );
    }
    if (_community.feed.isEmpty) {
      return const CommunityEmpty(
        title: 'No regional posts yet',
        message: 'Posts shared with your assigned region will appear here.',
        icon: Icons.location_on_outlined,
      );
    }
    return _postFeed(title: 'Your assigned region');
  }

  Widget _onlineMembers() {
    if (_community.onlineMembers.isEmpty) {
      return const CommunityEmpty(
        title: 'No members are visible online',
        message:
            'Only currently connected members who enabled online visibility are shown here.',
        icon: Icons.circle_outlined,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Online members', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ..._community.onlineMembers.map(
          (member) => Card(
            elevation: 0,
            color: Colors.white,
            child: ListTile(
              leading: const CircleAvatar(
                radius: 8,
                backgroundColor: AppColors.green,
              ),
              title: Text(member['fullName'] as String? ?? 'Community member'),
              subtitle: Text(member['city'] as String? ?? 'Online now'),
              onTap: member['id'] is String
                  ? () => _openMember(member['id'] as String)
                  : null,
              trailing: IconButton(
                tooltip: 'Message member',
                onPressed: member['id'] is String
                    ? () => _startConversation(member['id'] as String)
                    : null,
                icon: const Icon(Icons.chat_bubble_outline_rounded),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openCreatePost() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreatePostScreen(
          controller: _community,
          groups: _community.myGroups,
          regionId: _community.assignedRegionId,
        ),
      ),
    );
    if (created == true) {
      _selectSection(0);
    }
  }

  Future<void> _openCreateGroup() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateGroupScreen(controller: _community),
      ),
    );
    if (created == true) {
      _selectSection(1);
    }
  }

  Future<void> _openGroup(Map<String, dynamic> group) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => GroupDetailsScreen(
          controller: _community,
          groupId: group['id'] as String,
        ),
      ),
    );
  }

  Future<void> _openConversation(Map<String, dynamic> conversation) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CommunityChatScreen(
          controller: _community,
          conversation: conversation,
        ),
      ),
    );
  }

  Future<void> _startConversation(String memberId) async {
    final id = await _community.startDirectConversation(memberId);
    if (id == null || !mounted) return;
    await _openConversation({'id': id});
  }

  Future<void> _openMemberSearch() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MemberSearchScreen(controller: _community),
      ),
    );
  }

  Future<void> _openMember(String memberId) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            MemberProfileScreen(controller: _community, memberId: memberId),
      ),
    );
  }

  Future<void> _openComments(Map<String, dynamic> post) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PostCommentsScreen(controller: _community, post: post),
      ),
    );
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CommunityNotificationsScreen(controller: _community),
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CommunitySettingsScreen(controller: _community),
      ),
    );
  }

  Future<void> _openModeration() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CommunityModerationScreen(controller: _community),
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.navy,
        side: const BorderSide(color: AppColors.line),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      ),
    );
  }
}
