import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../app/app_theme.dart';
import 'community_controller.dart';
import 'community_widgets.dart';
import 'media_preview.dart';

class CommunityChatScreen extends StatefulWidget {
  const CommunityChatScreen({
    required this.controller,
    required this.conversation,
    super.key,
  });

  final CommunityController controller;
  final Map<String, dynamic> conversation;

  @override
  State<CommunityChatScreen> createState() => _CommunityChatScreenState();
}

class _CommunityChatScreenState extends State<CommunityChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _recorder = AudioRecorder();
  bool _recording = false;
  bool _uploading = false;
  double? _progress;
  String? _replyId;
  String? _replySummary;

  String get _conversationId => widget.conversation['id'] as String;
  String get _title {
    final group = widget.conversation['groupName'] as String?;
    if (group != null) return group;
    final other = widget.conversation['otherMember'];
    if (other is Map && other['fullName'] is String) return other['fullName'] as String;
    return 'Private conversation';
  }

  @override
  void initState() {
    super.initState();
    widget.controller.openConversation(_conversationId);
  }

  @override
  void dispose() {
    widget.controller.typing(active: false);
    widget.controller.closeConversation();
    _text.dispose();
    _scroll.dispose();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              widget.conversation['groupName'] == null ? 'Private chat' : 'Group chat',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Search messages',
            onPressed: _searchMessages,
            icon: const Icon(Icons.search_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'mute') {
                widget.controller.muteTarget('conversation', _conversationId);
              } else if (value == 'report') {
                _reportLatest();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'mute', child: Text('Mute conversation')),
              PopupMenuItem(value: 'report', child: Text('Report latest message')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: AnimatedBuilder(
                animation: widget.controller,
                builder: (context, _) {
                  final messages = widget.controller.messages;
                  if (messages.isEmpty && widget.controller.error != null) {
                    return Center(child: Text(widget.controller.error!));
                  }
                  if (messages.isEmpty) {
                    return const CommunityEmpty(
                      title: 'Start the conversation',
                      message: 'Only members with access to this conversation can read it.',
                      icon: Icons.lock_outline_rounded,
                    );
                  }
                  return Column(
                    children: [
                      if (widget.controller.loadingMore)
                        const LinearProgressIndicator(minHeight: 2),
                      Expanded(
                        child: ListView.builder(
                          controller: _scroll,
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                          itemCount: messages.length + 1,
                          itemBuilder: (context, index) {
                            if (index == messages.length) {
                              return Center(
                                child: TextButton(
                                  onPressed: widget.controller.messagesCursor == null
                                      ? null
                                      : widget.controller.loadOlderMessages,
                                  child: const Text('Load older messages'),
                                ),
                              );
                            }
                            final message = messages[messages.length - 1 - index];
                            return _MessageBubble(
                              controller: widget.controller,
                              message: message,
                              onReply: () => setState(() {
                                _replyId = message['id'] as String?;
                                _replySummary = message['body'] as String? ?? 'Attachment';
                              }),
                              onEdit: () => _editMessage(message),
                              onDelete: () => _deleteMessage(message),
                              onReport: () => _reportMessage(message),
                              onForward: () => _forwardMessage(message),
                            );
                          },
                        ),
                      ),
                      if (widget.controller.typingUserId != null)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 7),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text('A member is typing…'),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            if (_replySummary != null)
              Material(
                color: AppColors.goldWash,
                child: ListTile(
                  dense: true,
                  title: const Text('Replying to'),
                  subtitle: Text(_replySummary!, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    onPressed: () => setState(() {
                      _replyId = null;
                      _replySummary = null;
                    }),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              ),
            if (_progress != null)
              LinearProgressIndicator(value: _progress),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _composer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            tooltip: 'Attach a photo, video or document',
            onPressed: _uploading ? null : _pickAttachment,
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
          Expanded(
            child: TextField(
              controller: _text,
              minLines: 1,
              maxLines: 5,
              maxLength: 5000,
              onChanged: (value) => widget.controller.typing(active: value.isNotEmpty),
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                hintText: 'Message',
                counterText: '',
                contentPadding: EdgeInsets.symmetric(horizontal: 15, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: _recording ? 'Stop and send voice message' : 'Record voice message',
            onPressed: _uploading ? null : _toggleRecording,
            color: _recording ? AppColors.danger : AppColors.navy,
            icon: Icon(_recording ? Icons.stop_circle_outlined : Icons.mic_none_rounded),
          ),
          IconButton.filled(
            tooltip: 'Send message',
            onPressed: _uploading ? null : _send,
            icon: _uploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    if (_text.text.trim().isEmpty) return;
    final body = _text.text.trim();
    _text.clear();
    widget.controller.typing(active: false);
    final replyId = _replyId;
    setState(() {
      _replyId = null;
      _replySummary = null;
    });
    await widget.controller.sendMessage(body, replyToId: replyId);
    _scrollToLatest();
  }

  Future<void> _pickAttachment() async {
    final selected = await FilePicker.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
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
        'm4a',
        'mp3',
        'ogg',
        'wav',
        'pdf',
        'docx',
        'txt',
      ],
    );
    if (selected == null || selected.files.isEmpty) return;
    final file = selected.files.first;
    if (file.bytes == null) {
      _notice('Could not read the selected file.');
      return;
    }
    await _uploadAndSend(file.bytes!, file.name);
  }

  Future<void> _uploadAndSend(Uint8List bytes, String name) async {
    setState(() {
      _uploading = true;
      _progress = 0;
    });
    try {
      final result = await widget.controller.uploadMedia(
        bytes,
        name,
        onProgress: (sent, total) {
          if (mounted && total > 0) setState(() => _progress = sent / total);
        },
      );
      final media = result['media'] as Map?;
      final id = media?['id'];
      if (id is! String) throw StateError('The upload response did not include a file ID.');
      await widget.controller.sendMessage('', mediaIds: [id], replyToId: _replyId);
      setState(() {
        _replyId = null;
        _replySummary = null;
      });
      _scrollToLatest();
    } catch (error) {
      _notice(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      final path = await _recorder.stop();
      if (mounted) setState(() => _recording = false);
      if (path == null) {
        return;
      }
      final bytes = await File(path).readAsBytes();
      await _uploadAndSend(bytes, 'voice-message.m4a');
      return;
    }
    try {
      if (!await _recorder.hasPermission()) {
        _notice('Microphone permission is required to record a voice message.');
        return;
      }
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/orakzai-voice-${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 96000, sampleRate: 44100),
        path: path,
      );
      if (mounted) setState(() => _recording = true);
    } catch (error) {
      _notice('Voice recording could not start: $error');
    }
  }

  Future<void> _searchMessages() async {
    final query = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search messages'),
        content: TextField(
          controller: query,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Search in this conversation'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, query.text.trim()),
            child: const Text('Search'),
          ),
        ],
      ),
    );
    query.dispose();
    if (value != null && value.isNotEmpty) {
      await widget.controller.searchMessages(value);
    } else {
      await widget.controller.openConversation(_conversationId);
    }
  }

  Future<void> _editMessage(Map<String, dynamic> message) async {
    final text = TextEditingController(text: message['body'] as String? ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(controller: text, minLines: 2, maxLines: 5, maxLength: 5000),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, text.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    text.dispose();
    if (value != null && value.isNotEmpty) {
      await widget.controller.editMessage(message['id'] as String, value);
    }
  }

  Future<void> _deleteMessage(Map<String, dynamic> message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('The message will be removed from this conversation.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.controller.deleteMessage(message['id'] as String);
    }
  }

  Future<void> _reportMessage(Map<String, dynamic> message) async {
    await widget.controller.reportContent(
      type: 'message',
      id: message['id'] as String,
      category: 'other',
    );
    if (mounted) _notice(widget.controller.error ?? 'Report submitted to moderators.');
  }

  Future<void> _reportLatest() async {
    final latest = widget.controller.messages.isEmpty
        ? null
        : widget.controller.messages.last;
    if (latest != null) await _reportMessage(latest);
  }

  Future<void> _forwardMessage(Map<String, dynamic> message) async {
    final choices = widget.controller.conversations
        .where((conversation) => conversation['id'] != _conversationId)
        .toList();
    if (choices.isEmpty) {
      _notice('Open or start another conversation before forwarding.');
      return;
    }
    final target = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Forward to')),
            ...choices.map((conversation) {
              final group = conversation['groupName'] as String?;
              final other = conversation['otherMember'];
              final title = group ??
                  (other is Map ? other['fullName'] as String? : null) ??
                  'Private conversation';
              return ListTile(
                leading: Icon(
                  group == null ? Icons.person_outline_rounded : Icons.groups_2_outlined,
                ),
                title: Text(title),
                onTap: () => Navigator.pop(context, conversation['id'] as String?),
              );
            }),
          ],
        ),
      ),
    );
    if (target == null) return;
    await widget.controller.forwardMessage(message['id'] as String, target);
    if (mounted) {
      _notice(widget.controller.error ?? 'Message forwarded.');
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.controller,
    required this.message,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    required this.onReport,
    required this.onForward,
  });

  final CommunityController controller;
  final Map<String, dynamic> message;
  final VoidCallback onReply;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onReport;
  final VoidCallback onForward;

  @override
  Widget build(BuildContext context) {
    final mine = message['senderId'] == controller.auth.user?.id;
    final status = message['status'] as String? ?? 'sent';
    final media = message['media'] is List
        ? (message['media'] as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
        : <Map<String, dynamic>>[];
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: GestureDetector(
          onLongPress: () => _showActions(context, mine),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: mine ? AppColors.navy : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(mine ? 16 : 4),
                bottomRight: Radius.circular(mine ? 4 : 16),
              ),
              border: mine ? null : Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!mine && message['senderName'] is String)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      message['senderName'] as String,
                      style: const TextStyle(
                        color: AppColors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (message['replyToPreview'] is String)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: mine ? Colors.white12 : AppColors.canvas,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      message['replyToPreview'] as String,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: mine ? Colors.white70 : AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if ((message['body'] as String? ?? '').isNotEmpty)
                  SelectableText(
                    message['body'] as String,
                    style: TextStyle(color: mine ? Colors.white : AppColors.ink),
                  ),
                if (media.isNotEmpty) ...[
                  if ((message['body'] as String? ?? '').isNotEmpty)
                    const SizedBox(height: 7),
                  ...media.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: MediaAttachmentTile(controller: controller, media: item),
                    ),
                  ),
                ],
                const SizedBox(height: 5),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _time(message['createdAt'] as String?),
                      style: TextStyle(
                        color: mine ? Colors.white60 : AppColors.muted,
                        fontSize: 10,
                      ),
                    ),
                    if (mine) ...[
                      const SizedBox(width: 5),
                      Icon(
                        status == 'read'
                            ? Icons.done_all_rounded
                            : status == 'delivered'
                                ? Icons.done_all_rounded
                                : Icons.done_rounded,
                        size: 14,
                        color: status == 'read' ? AppColors.gold : Colors.white60,
                      ),
                      if (status == 'failed')
                        const Text(' Not sent', style: TextStyle(color: Colors.redAccent, fontSize: 10)),
                    ],
                  ],
                ),
                if (message['forwardedFromMessageId'] != null)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Forwarded',
                      style: TextStyle(
                        color: AppColors.gold,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showActions(BuildContext context, bool mine) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('Reply'),
              onTap: () => Navigator.pop(context, 'reply'),
            ),
            ListTile(
              leading: const Icon(Icons.thumb_up_alt_outlined),
              title: const Text('React'),
              onTap: () => Navigator.pop(context, 'react'),
            ),
            ListTile(
              leading: const Icon(Icons.forward_rounded),
              title: const Text('Forward'),
              onTap: () => Navigator.pop(context, 'forward'),
            ),
            if (mine) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit message'),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Delete message'),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ] else
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Report message'),
                onTap: () => Navigator.pop(context, 'report'),
              ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'reply':
        onReply();
        return;
      case 'react':
        await controller.reactToMessage(message['id'] as String, 'like');
        return;
      case 'edit':
        onEdit();
        return;
      case 'delete':
        onDelete();
        return;
      case 'report':
        onReport();
        return;
      case 'forward':
        onForward();
        return;
    }
  }

  String _time(String? value) {
    final date = DateTime.tryParse(value ?? '');
    if (date == null) return '';
    final local = date.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
