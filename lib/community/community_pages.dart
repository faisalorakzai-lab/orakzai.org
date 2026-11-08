import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app/app_theme.dart';
import '../community/community_controller.dart';
import '../community/community_widgets.dart';
import '../community/chat_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({required this.controller, super.key});

  final CommunityController controller;

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  String _category = 'general';
  String _visibility = 'public';
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create a community group')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const CommunityNotice(
                title: 'Create a real group',
                message:
                    'Group membership, posts and chats are stored by the community service. Choose the audience before creating it.',
                icon: Icons.groups_2_outlined,
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _name,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Group name'),
                validator: (value) => (value == null || value.trim().length < 3)
                    ? 'Enter at least 3 characters.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                maxLength: 1000,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Purpose and description',
                  alignLabelWithHint: true,
                ),
                validator: (value) => (value == null || value.trim().length < 10)
                    ? 'Add a short description (at least 10 characters).'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: CommunityGroupCategories.labels.entries
                    .map((entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'public',
                    label: Text('Public'),
                    icon: Icon(Icons.public_rounded),
                  ),
                  ButtonSegment(
                    value: 'private',
                    label: Text('Private'),
                    icon: Icon(Icons.lock_outline_rounded),
                  ),
                ],
                selected: {_visibility},
                onSelectionChanged: (selection) =>
                    setState(() => _visibility = selection.first),
              ),
              const SizedBox(height: 8),
              Text(
                _visibility == 'public'
                    ? 'Anyone can find and request to join this group.'
                    : 'Only invited members can see this group and its content.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _saving ? null : _create,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_rounded),
                label: Text(_saving ? 'Creating…' : 'Create group'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await widget.controller.createGroup(
      name: _name.text.trim(),
      description: _description.text.trim(),
      category: _category,
      visibility: _visibility,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (widget.controller.error == null) {
      Navigator.of(context).pop(true);
    } else {
      _showError(widget.controller.error!);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class CommunityGroupCategories {
  static const labels = <String, String>{
    'general': 'General community',
    'regional': 'Regional network',
    'youth': 'Youth network',
    'education': 'Education and students',
    'healthcare': 'Healthcare',
    'business': 'Business and entrepreneurs',
    'employment': 'Employment and opportunities',
    'overseas': 'Overseas Orakzai community',
    'welfare': 'Social welfare',
    'culture': 'Culture and heritage',
  };
}

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({
    required this.controller,
    required this.groups,
    required this.regionId,
    super.key,
  });

  final CommunityController controller;
  final List<Map<String, dynamic>> groups;
  final String? regionId;

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _body = TextEditingController();
  final _imagePicker = ImagePicker();
  final List<_PendingCommunityFile> _files = [];
  String _visibility = 'public';
  String? _groupId;
  bool _saving = false;
  double? _uploadProgress;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create a post')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            DropdownButtonFormField<String>(
              value: _visibility,
              decoration: const InputDecoration(labelText: 'Who can see this?'),
              items: [
                const DropdownMenuItem(value: 'public', child: Text('Public')),
                if (widget.regionId != null)
                  const DropdownMenuItem(value: 'regional', child: Text('My region')),
                if (widget.groups.isNotEmpty)
                  const DropdownMenuItem(value: 'group', child: Text('A group')),
                const DropdownMenuItem(value: 'private', child: Text('Only me')),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() {
                        _visibility = value ?? 'public';
                        if (_visibility != 'group') _groupId = null;
                      }),
            ),
            if (_visibility == 'group') ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _groupId,
                decoration: const InputDecoration(labelText: 'Choose group'),
                items: widget.groups
                    .where((group) => group['status'] == 'active' || group['myStatus'] == 'active')
                    .map((group) => DropdownMenuItem<String>(
                          value: group['id'] as String,
                          child: Text(group['name'] as String? ?? 'Group'),
                        ))
                    .toList(),
                onChanged: _saving ? null : (value) => setState(() => _groupId = value),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _body,
              minLines: 5,
              maxLines: 10,
              maxLength: 10000,
              decoration: const InputDecoration(
                labelText: 'What would you like to share?',
                alignLabelWithHint: true,
                hintText: 'Write a community update, question or announcement…',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _saving ? null : _pickFiles,
                  icon: const Icon(Icons.attach_file_rounded),
                  label: const Text('Photo, video or file'),
                ),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _takePhoto,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Take photo'),
                ),
              ],
            ),
            if (_files.isNotEmpty) ...[
              const SizedBox(height: 12),
              ..._files.asMap().entries.map(
                    (entry) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.attach_file_rounded),
                      title: Text(entry.value.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(_size(entry.value.bytes.length)),
                      trailing: IconButton(
                        onPressed: _saving ? null : () => setState(() => _files.removeAt(entry.key)),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                  ),
            ],
            if (_uploadProgress != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _uploadProgress),
              const SizedBox(height: 5),
              Text('Uploading attachment ${(_uploadProgress! * 100).round()}%'),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _publish,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(_saving ? 'Publishing…' : 'Publish post'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowMultiple: true,
      withData: true,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'gif',
        'mp4',
        'mov',
        'webm',
        'mp3',
        'ogg',
        'wav',
        'pdf',
        'docx',
        'txt',
      ],
    );
    if (result == null || !mounted) return;
    final files = result.files
        .where((file) => file.bytes != null)
        .take(5)
        .map((file) => _PendingCommunityFile(file.name, file.bytes!));
    setState(() => _files.addAll(files));
  }

  Future<void> _takePhoto() async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 88,
      maxWidth: 2200,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    setState(() => _files.add(_PendingCommunityFile(file.name, bytes)));
  }

  Future<void> _publish() async {
    if (_body.text.trim().isEmpty && _files.isEmpty) {
      _notice('Write a post or attach a file first.');
      return;
    }
    if (_visibility == 'group' && _groupId == null) {
      _notice('Choose a group for this post.');
      return;
    }
    setState(() {
      _saving = true;
      _uploadProgress = _files.isEmpty ? null : 0;
    });
    final uploadedIds = <String>[];
    try {
      for (var index = 0; index < _files.length; index++) {
        final file = _files[index];
        final result = await widget.controller.uploadMedia(
          file.bytes,
          file.name,
          onProgress: (sent, total) {
            if (!mounted || total <= 0) return;
            setState(() {
              _uploadProgress = (index + sent / total) / _files.length;
            });
          },
        );
        final media = result['media'] as Map?;
        if (media?['id'] is String) uploadedIds.add(media!['id'] as String);
      }
      await widget.controller.createPost(
        body: _body.text.trim(),
        visibility: _visibility,
        groupId: _groupId,
        regionId: _visibility == 'regional' ? widget.regionId : null,
        mediaIds: uploadedIds,
      );
      if (!mounted) return;
      if (widget.controller.error == null) {
        Navigator.of(context).pop(true);
      } else {
        _notice(widget.controller.error!);
      }
    } catch (error) {
      if (mounted) _notice(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _uploadProgress = null;
        });
      }
    }
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _size(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(0)} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _PendingCommunityFile {
  const _PendingCommunityFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

class GroupDetailsScreen extends StatefulWidget {
  const GroupDetailsScreen({
    required this.controller,
    required this.groupId,
    super.key,
  });

  final CommunityController controller;
  final String groupId;

  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> {
  Map<String, dynamic>? _group;
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _posts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final group = await widget.controller.getGroup(widget.groupId);
    if (group == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = widget.controller.error;
        });
      }
      return;
    }
    final members = await widget.controller.getGroupMembers(widget.groupId);
    final postResult = await widget.controller.api.getFeed(groupId: widget.groupId);
    if (!mounted) return;
    setState(() {
      _group = group;
      _members = members;
      _posts = (postResult['posts'] as List? ?? const [])
          .whereType<Map>()
          .map((post) => Map<String, dynamic>.from(post))
          .toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final group = _group;
    final isMember = group?['myStatus'] == 'active';
    final role = group?['myRole'] as String? ?? '';
    final canManage = role == 'owner' || role == 'admin';
    return Scaffold(
      appBar: AppBar(
        title: Text(group?['name'] as String? ?? 'Group'),
        actions: [
          if (isMember)
            IconButton(
              tooltip: 'Group options',
              onPressed: _groupOptions,
              icon: const Icon(Icons.more_vert_rounded),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      _groupHeader(group!, isMember, canManage),
                      const SizedBox(height: 18),
                      if (isMember) ...[
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: group['conversationId'] is String
                                    ? () => _openChat(group)
                                    : null,
                                icon: const Icon(Icons.chat_bubble_outline_rounded),
                                label: const Text('Group chat'),
                              ),
                            ),
                            if (canManage) ...[
                              const SizedBox(width: 8),
                              IconButton.filledTonal(
                                tooltip: 'Invite a member',
                                onPressed: _inviteMember,
                                icon: const Icon(Icons.person_add_alt_1_rounded),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 18),
                      ],
                      _rulesSection(group, canManage),
                      const SizedBox(height: 18),
                      Text('Members (${_members.length})',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      ..._members.map((member) => _memberTile(member, canManage)),
                      const SizedBox(height: 18),
                      Text('Group posts', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (!isMember)
                        const CommunityNotice(
                          title: 'Members-only posts',
                          message: 'Join this group to view its private posts and discussion.',
                        )
                      else if (_posts.isEmpty)
                        const CommunityEmpty(
                          title: 'No group posts yet',
                          message: 'Start a conversation with the group.',
                          icon: Icons.forum_outlined,
                        )
                      else
                        ..._posts.map((post) => CommunityPostCard(
                              controller: widget.controller,
                              post: post,
                              onComments: () => _openComments(post),
                            )),
                    ],
                  ),
                ),
    );
  }

  Widget _groupHeader(Map<String, dynamic> group, bool isMember, bool canManage) {
    final isPrivate = group['visibility'] == 'private';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.groups_2_outlined, color: AppColors.gold),
              const SizedBox(width: 8),
              Text(
                isPrivate ? 'Private group' : 'Public group',
                style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text('${group['memberCount'] ?? _members.length} members',
                  style: const TextStyle(color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            group['name'] as String? ?? '',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            group['description'] as String? ?? '',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          if (!isMember)
            FilledButton(
              onPressed: isPrivate ? null : _join,
              child: Text(isPrivate ? 'Invitation required' : 'Join group'),
            )
          else if (canManage)
            OutlinedButton.icon(
              onPressed: _editGroup,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit group'),
            ),
        ],
      ),
    );
  }

  Widget _rulesSection(Map<String, dynamic> group, bool canManage) {
    final rules = (group['rules'] as List? ?? const []).whereType<Map>().toList();
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.line),
      ),
      child: ExpansionTile(
        title: const Text('Group rules'),
        subtitle: Text(rules.isEmpty ? 'No group rules published' : '${rules.length} rules'),
        children: [
          if (rules.isEmpty)
            const ListTile(title: Text('The group has not published any rules yet.'))
          else
            ...rules.map((rule) => ListTile(
                  leading: const Icon(Icons.rule_rounded),
                  title: Text(rule['title'] as String? ?? 'Group rule'),
                  subtitle: Text(rule['body'] as String? ?? ''),
                )),
          if (canManage)
            TextButton.icon(
              onPressed: _editRules,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit rules'),
            ),
        ],
      ),
    );
  }

  Widget _memberTile(Map<String, dynamic> member, bool canManage) {
    final id = member['userId'] as String? ?? member['id'] as String?;
    final role = member['role'] as String? ?? 'member';
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person_outline_rounded)),
        title: Text(member['fullName'] as String? ?? 'Community member'),
        subtitle: Text(role),
        onTap: id == null
            ? null
            : () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => MemberProfileScreen(
                      controller: widget.controller,
                      memberId: id,
                    ),
                  ),
                ),
        trailing: canManage && id != null && role != 'owner'
            ? PopupMenuButton<String>(
                onSelected: (value) => widget.controller.updateGroupMember(
                  widget.groupId,
                  id,
                  value == 'remove'
                      ? {'action': 'remove'}
                      : {'action': 'role', 'role': value},
                ),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'admin', child: Text('Make admin')),
                  PopupMenuItem(value: 'moderator', child: Text('Make moderator')),
                  PopupMenuItem(value: 'member', child: Text('Set as member')),
                  PopupMenuItem(value: 'remove', child: Text('Remove member')),
                ],
              )
            : null,
      ),
    );
  }

  Future<void> _join() async {
    await widget.controller.joinGroup(widget.groupId);
    await _load();
  }

  Future<void> _openChat(Map<String, dynamic> group) async {
    final conversationId = group['conversationId'] as String?;
    if (conversationId == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CommunityChatScreen(
          controller: widget.controller,
          conversation: {
            'id': conversationId,
            'groupName': group['name'],
            'groupId': widget.groupId,
          },
        ),
      ),
    );
  }

  Future<void> _inviteMember() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MemberSearchScreen(
          controller: widget.controller,
          groupId: widget.groupId,
        ),
      ),
    );
  }

  Future<void> _editGroup() async {
    final name = TextEditingController(text: _group?['name'] as String? ?? '');
    final description = TextEditingController(text: _group?['description'] as String? ?? '');
    final updates = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit group details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, maxLength: 80, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: description, maxLength: 1000, maxLines: 3, decoration: const InputDecoration(labelText: 'Description')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, {
              'name': name.text.trim(),
              'description': description.text.trim(),
            }),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    name.dispose();
    description.dispose();
    if (updates == null || updates['name']!.isEmpty) return;
    await widget.controller.updateGroup(widget.groupId, updates);
    await _load();
  }

  Future<void> _editRules() async {
    final existing = (_group?['rules'] as List? ?? const [])
        .whereType<Map>()
        .map((rule) => rule['body'] as String? ?? '')
        .where((text) => text.isNotEmpty)
        .join('\n');
    final editor = TextEditingController(text: existing);
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Group rules'),
        content: TextField(
          controller: editor,
          minLines: 5,
          maxLines: 8,
          maxLength: 2000,
          decoration: const InputDecoration(
            hintText: 'Enter one rule per line',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, editor.text), child: const Text('Save')),
        ],
      ),
    );
    editor.dispose();
    if (text == null) return;
    final rules = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList()
        .asMap()
        .entries
        .map((entry) => {
              'title': 'Rule ${entry.key + 1}',
              'body': entry.value,
            })
        .toList();
    await widget.controller.updateGroupRules(widget.groupId, rules);
    await _load();
  }

  Future<void> _groupOptions() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.notifications_off_outlined),
              title: const Text('Mute group'),
              onTap: () => Navigator.pop(context, 'mute'),
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Report group'),
              onTap: () => Navigator.pop(context, 'report'),
            ),
            if ((_group?['myRole'] as String?) != 'owner')
              ListTile(
                leading: const Icon(Icons.exit_to_app_rounded),
                title: const Text('Leave group'),
                onTap: () => Navigator.pop(context, 'leave'),
              ),
          ],
        ),
      ),
    );
    if (choice == 'mute') {
      await widget.controller.muteTarget('group', widget.groupId);
    } else if (choice == 'leave') {
      await widget.controller.leaveGroup(widget.groupId);
      if (mounted) Navigator.of(context).pop();
    } else if (choice == 'report') {
      await widget.controller.reportContent(
        type: 'group',
        id: widget.groupId,
        category: 'inappropriate',
      );
    }
  }

  Future<void> _openComments(Map<String, dynamic> post) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PostCommentsScreen(controller: widget.controller, post: post),
      ),
    );
  }
}

class MemberSearchScreen extends StatefulWidget {
  const MemberSearchScreen({
    required this.controller,
    this.groupId,
    super.key,
  });

  final CommunityController controller;
  final String? groupId;

  @override
  State<MemberSearchScreen> createState() => _MemberSearchScreenState();
}

class _MemberSearchScreenState extends State<MemberSearchScreen> {
  final _query = TextEditingController();
  Timer? _timer;
  List<Map<String, dynamic>> _members = [];
  bool _loading = false;

  @override
  void dispose() {
    _timer?.cancel();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inviteMode = widget.groupId != null;
    return Scaffold(
      appBar: AppBar(title: Text(inviteMode ? 'Invite a member' : 'Find members')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _query,
              autofocus: true,
              onChanged: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Search by member name',
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
            ),
          ),
          Expanded(
            child: _members.isEmpty
                ? CommunityEmpty(
                    title: _query.text.trim().length < 2
                        ? 'Search members'
                        : 'No members found',
                    message: _query.text.trim().length < 2
                        ? 'Enter at least two characters. Only members who allow profile search are listed.'
                        : 'Try another name.',
                    icon: Icons.person_search_rounded,
                  )
                : ListView.builder(
                    itemCount: _members.length,
                    itemBuilder: (context, index) {
                      final member = _members[index];
                      return ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.person_outline_rounded),
                        ),
                        title: Text(member['fullName'] as String? ?? 'Community member'),
                        subtitle: Text(member['city'] as String? ?? 'Orakzai community'),
                        trailing: IconButton(
                          tooltip: inviteMode ? 'Invite member' : 'Message member',
                          icon: Icon(inviteMode
                              ? Icons.person_add_alt_1_rounded
                              : Icons.chat_bubble_outline_rounded),
                          onPressed: () => _selectMember(member),
                        ),
                        onTap: () {
                          final id = member['id'] as String?;
                          if (id != null) {
                            Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => MemberProfileScreen(
                                  controller: widget.controller,
                                  memberId: id,
                                ),
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _search(String value) {
    _timer?.cancel();
    if (value.trim().length < 2) {
      setState(() => _members = []);
      return;
    }
    _timer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      setState(() => _loading = true);
      final results = await widget.controller.searchMembers(value.trim());
      if (mounted) {
        setState(() {
          _members = results;
          _loading = false;
        });
      }
    });
  }

  Future<void> _selectMember(Map<String, dynamic> member) async {
    final id = member['id'] as String?;
    if (id == null) return;
    if (widget.groupId != null) {
      await widget.controller.inviteToGroup(widget.groupId!, id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.controller.error ?? 'Invitation sent.'),
          ),
        );
      }
      return;
    }
    final conversationId = await widget.controller.startDirectConversation(id);
    if (conversationId == null || !mounted) return;
    Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute(
        builder: (_) => CommunityChatScreen(
          controller: widget.controller,
          conversation: {'id': conversationId, 'otherMember': member},
        ),
      ),
    );
  }
}

class MemberProfileScreen extends StatefulWidget {
  const MemberProfileScreen({
    required this.controller,
    required this.memberId,
    super.key,
  });

  final CommunityController controller;
  final String memberId;

  @override
  State<MemberProfileScreen> createState() => _MemberProfileScreenState();
}

class _MemberProfileScreenState extends State<MemberProfileScreen> {
  Map<String, dynamic>? _member;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await widget.controller.getMemberProfile(widget.memberId);
    if (!mounted) return;
    setState(() {
      _member = result;
      _error = result == null ? widget.controller.error : null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final member = _member;
    return Scaffold(
      appBar: AppBar(title: const Text('Member profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Center(
                      child: CircleAvatar(
                        radius: 38,
                        backgroundColor: AppColors.goldWash,
                        foregroundColor: AppColors.navy,
                        child: Text(
                          (member?['fullName'] as String? ?? 'M').substring(0, 1).toUpperCase(),
                          style: const TextStyle(fontSize: 26),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        member?['fullName'] as String? ?? 'Community member',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (member?['username'] is String) ...[
                      const SizedBox(height: 4),
                      Center(child: Text('@${member!['username']}')),
                    ],
                    const SizedBox(height: 18),
                    if (member?['biography'] is String &&
                        (member!['biography'] as String).isNotEmpty)
                      _ProfileInfo(
                        label: 'About',
                        value: member['biography'] as String,
                      ),
                    if (member?['city'] is String)
                      _ProfileInfo(
                        label: 'Location',
                        value: [
                          member!['city'],
                          member['country'],
                        ].whereType<String>().where((value) => value.isNotEmpty).join(', '),
                      ),
                    if (member?['profession'] is String)
                      _ProfileInfo(label: 'Profession', value: member!['profession'] as String),
                    if (member?['education'] is String)
                      _ProfileInfo(label: 'Education', value: member!['education'] as String),
                    if (member?['skills'] is List &&
                        (member!['skills'] as List).isNotEmpty)
                      _ProfileInfo(
                        label: 'Skills',
                        value: (member['skills'] as List).whereType<String>().join(' · '),
                      ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _message,
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      label: const Text('Send private message'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _safetyOptions,
                      icon: const Icon(Icons.shield_outlined),
                      label: const Text('Safety options'),
                    ),
                  ],
                ),
    );
  }

  Future<void> _message() async {
    final id = await widget.controller.startDirectConversation(widget.memberId);
    if (id == null || !mounted) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CommunityChatScreen(
          controller: widget.controller,
          conversation: {'id': id, 'otherMember': _member},
        ),
      ),
    );
  }

  Future<void> _safetyOptions() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.block_outlined),
              title: const Text('Block member'),
              onTap: () => Navigator.pop(context, 'block'),
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Report member'),
              onTap: () => Navigator.pop(context, 'report'),
            ),
          ],
        ),
      ),
    );
    if (selected == 'block') {
      await widget.controller.blockUser(widget.memberId);
      if (mounted) Navigator.of(context).pop();
    } else if (selected == 'report') {
      await widget.controller.reportContent(
        type: 'user',
        id: widget.memberId,
        category: 'other',
      );
    }
  }
}

class _ProfileInfo extends StatelessWidget {
  const _ProfileInfo({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 5),
            Text(value),
          ],
        ),
      ),
    );
  }
}

class PostCommentsScreen extends StatefulWidget {
  const PostCommentsScreen({
    required this.controller,
    required this.post,
    super.key,
  });

  final CommunityController controller;
  final Map<String, dynamic> post;

  @override
  State<PostCommentsScreen> createState() => _PostCommentsScreenState();
}

class _PostCommentsScreenState extends State<PostCommentsScreen> {
  final _text = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  String? _replyId;
  String? _replyName;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final comments = await widget.controller.loadComments(widget.post['id'] as String);
    if (mounted) {
      setState(() {
        _comments = comments;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comments and replies')),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _comments.isEmpty
                    ? const CommunityEmpty(
                        title: 'No comments yet',
                        message: 'Start a respectful conversation about this post.',
                        icon: Icons.mode_comment_outlined,
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _comments.length,
                          itemBuilder: (context, index) =>
                              _commentCard(_comments[index]),
                        ),
                      ),
          ),
          if (_replyName != null)
            Material(
              color: AppColors.goldWash,
              child: ListTile(
                dense: true,
                title: Text('Replying to $_replyName'),
                trailing: IconButton(
                  tooltip: 'Cancel reply',
                  onPressed: () => setState(() {
                    _replyId = null;
                    _replyName = null;
                  }),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      decoration: const InputDecoration(
                        hintText: 'Write a comment…',
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _commentCard(Map<String, dynamic> comment) {
    final isReply = comment['parentCommentId'] != null;
    return Padding(
      padding: EdgeInsets.only(left: isReply ? 22 : 0, bottom: 8),
      child: Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.line),
        ),
        child: ListTile(
          leading: CircleAvatar(
            radius: 17,
            backgroundColor: AppColors.goldWash,
            child: Text(
              ((comment['authorName'] as String? ?? 'M').characters.first).toUpperCase(),
            ),
          ),
          title: Text(comment['authorName'] as String? ?? 'Community member'),
          subtitle: Text(comment['body'] as String? ?? ''),
          trailing: PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'reply') {
                setState(() {
                  _replyId = comment['id'] as String?;
                  _replyName = comment['authorName'] as String? ?? 'member';
                });
              } else if (value == 'report') {
                await widget.controller.reportContent(
                  type: 'comment',
                  id: comment['id'] as String,
                  category: 'other',
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'reply', child: Text('Reply')),
              PopupMenuItem(value: 'report', child: Text('Report comment')),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _send() async {
    if (_text.text.trim().isEmpty) return;
    setState(() => _sending = true);
    await widget.controller.addComment(
      widget.post['id'] as String,
      _text.text.trim(),
      parentCommentId: _replyId,
    );
    if (!mounted) return;
    setState(() {
      _text.clear();
      _replyId = null;
      _replyName = null;
      _sending = false;
    });
    await _load();
  }
}

class CommunityNotificationsScreen extends StatefulWidget {
  const CommunityNotificationsScreen({required this.controller, super.key});
  final CommunityController controller;

  @override
  State<CommunityNotificationsScreen> createState() =>
      _CommunityNotificationsScreenState();
}

class _CommunityNotificationsScreenState
    extends State<CommunityNotificationsScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.loadNotifications());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Notification settings',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => CommunitySettingsScreen(controller: widget.controller),
              ),
            ),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final notifications = widget.controller.notifications;
          if (notifications.isEmpty) {
            return const CommunityEmpty(
              title: 'No notifications',
              message: 'Group invites and community activity will appear here.',
              icon: Icons.notifications_none_rounded,
            );
          }
          return RefreshIndicator(
            onRefresh: widget.controller.loadNotifications,
            child: ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: notifications.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final notification = notifications[index];
                final read = notification['readAt'] != null;
                return Card(
                  elevation: 0,
                  color: read ? Colors.white : AppColors.greenWash,
                  child: ListTile(
                    leading: Icon(
                      _notificationIcon(notification['kind'] as String? ?? ''),
                      color: AppColors.green,
                    ),
                    title: Text(notification['title'] as String? ?? 'Community update'),
                    subtitle: Text(notification['body'] as String? ?? ''),
                    trailing: read
                        ? null
                        : IconButton(
                            tooltip: 'Mark as read',
                            onPressed: notification['id'] is String
                                ? () => widget.controller.markNotificationRead(
                                      notification['id'] as String,
                                    )
                                : null,
                            icon: const Icon(Icons.done_rounded),
                          ),
                    onTap: notification['id'] is String && !read
                        ? () => widget.controller.markNotificationRead(
                              notification['id'] as String,
                            )
                        : null,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  IconData _notificationIcon(String kind) => switch (kind) {
    'group_invitation' => Icons.group_add_outlined,
    'comment' => Icons.mode_comment_outlined,
    'reaction' => Icons.favorite_border_rounded,
    'announcement' => Icons.campaign_outlined,
    'message' => Icons.chat_bubble_outline_rounded,
    _ => Icons.notifications_none_rounded,
  };
}

class CommunitySettingsScreen extends StatefulWidget {
  const CommunitySettingsScreen({required this.controller, super.key});
  final CommunityController controller;

  @override
  State<CommunitySettingsScreen> createState() =>
      _CommunitySettingsScreenState();
}

class _CommunitySettingsScreenState extends State<CommunitySettingsScreen> {
  Map<String, dynamic> _notifications = {};
  Map<String, dynamic> _presence = {};
  List<Map<String, dynamic>> _blocked = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final notificationSettings = await widget.controller.getNotificationPreferences();
      final presenceSettings = await widget.controller.getPresenceSettings();
      final blockedMembers = await widget.controller.loadBlockedUsers();
      if (!mounted) return;
      setState(() {
        _notifications = notificationSettings;
        _presence = presenceSettings;
        _blocked = blockedMembers;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Community privacy and alerts')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const CommunityNotice(
                      title: 'Privacy controls',
                      message:
                          'Online status and last-seen sharing are optional. Private messages and group access remain protected by your account permissions.',
                      icon: Icons.privacy_tip_outlined,
                    ),
                    const SizedBox(height: 16),
                    Text('Presence', style: Theme.of(context).textTheme.titleMedium),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show me online'),
                      subtitle: const Text('Only current connections are shown.'),
                      value: _presence['showOnlineStatus'] == true,
                      onChanged: (value) => _updatePresence('showOnlineStatus', value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Share last seen'),
                      value: _presence['shareLastSeen'] == true,
                      onChanged: (value) => _updatePresence('shareLastSeen', value),
                    ),
                    const Divider(height: 30),
                    Text('In-app notifications',
                        style: Theme.of(context).textTheme.titleMedium),
                    ..._notifications.entries.where((entry) => entry.value is bool).map(
                          (entry) => SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(_humanize(entry.key)),
                            value: entry.value == true,
                            onChanged: (value) => _updateNotification(entry.key, value),
                          ),
                        ),
                    const Divider(height: 30),
                    Text('Blocked members',
                        style: Theme.of(context).textTheme.titleMedium),
                    if (_blocked.isEmpty)
                      const ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('No members are blocked.'),
                      )
                    else
                      ..._blocked.map((member) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(member['fullName'] as String? ?? 'Community member'),
                            trailing: TextButton(
                              onPressed: (member['userId'] ?? member['id']) is String
                                  ? () => _unblock(
                                        (member['userId'] ?? member['id']) as String,
                                      )
                                  : null,
                              child: const Text('Unblock'),
                            ),
                          )),
                  ],
                ),
    );
  }

  Future<void> _updatePresence(String key, bool value) async {
    final next = Map<String, bool>.fromEntries(
      _presence.entries.where((entry) => entry.value is bool).map(
            (entry) => MapEntry(entry.key, entry.value as bool),
          ),
    )..[key] = value;
    await widget.controller.updatePresenceSettings(next);
    await _load();
  }

  Future<void> _updateNotification(String key, bool value) async {
    await widget.controller.updateNotificationPreferences({key: value});
    await _load();
  }

  Future<void> _unblock(String id) async {
    await widget.controller.unblockUser(id);
    await _load();
  }

  String _humanize(String key) => key
      .replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match.group(1)}')
      .replaceAll('_', ' ')
      .replaceAll('-', ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
