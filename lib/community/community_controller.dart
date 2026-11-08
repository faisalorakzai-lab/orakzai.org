import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../auth/auth_controller.dart';
import 'community_api.dart';
import 'community_realtime.dart';

class CommunityController extends ChangeNotifier {
  CommunityController({required this.auth})
    : api = CommunityApi(auth: auth.api),
      realtime = CommunityRealtime(auth.api) {
    _messageSubscription = realtime.messages.listen(_onMessage);
    _conversationSubscription = realtime.conversationUpdates.listen((_) {
      unawaited(loadConversations());
    });
    _notificationSubscription = realtime.notifications.listen((_) {
      unawaited(loadNotifications());
    });
    _typingSubscription = realtime.typingUpdates.listen(_onTypingUpdate);
    _presenceSubscription = realtime.presenceUpdates.listen((_) {
      unawaited(loadOnlineMembers());
    });
    _connectionSubscription = realtime.connectionUpdates.listen((value) {
      connected = value;
      notifyListeners();
    });
  }

  final AuthController auth;
  final CommunityApi api;
  final CommunityRealtime realtime;
  final _uuid = const Uuid();

  List<Map<String, dynamic>> feed = [];
  List<Map<String, dynamic>> myGroups = [];
  List<Map<String, dynamic>> discoverGroups = [];
  List<Map<String, dynamic>> conversations = [];
  List<Map<String, dynamic>> notifications = [];
  List<Map<String, dynamic>> onlineMembers = [];
  List<Map<String, dynamic>> invitations = [];
  List<Map<String, dynamic>> moderationReports = [];
  List<Map<String, dynamic>> messages = [];
  Map<String, dynamic>? currentConversation;
  String? feedCursor;
  String? messagesCursor;
  String? activeConversationId;
  String? typingUserId;
  String? error;
  bool loading = false;
  bool loadingMore = false;
  bool sending = false;
  bool connected = false;
  bool notificationLoading = false;

  StreamSubscription<Map<String, dynamic>>? _messageSubscription;
  StreamSubscription<Map<String, dynamic>>? _conversationSubscription;
  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;
  StreamSubscription<Map<String, dynamic>>? _typingSubscription;
  StreamSubscription<Map<String, dynamic>>? _presenceSubscription;
  StreamSubscription<bool>? _connectionSubscription;
  Timer? _typingExpiry;

  bool get isAuthenticated => auth.isAuthenticated && auth.user != null;
  bool get canModerate => auth.permissions.contains('content:moderate');
  bool get canSuspendGroups => auth.permissions.contains('groups:suspend');
  bool get canRestrictMembers => auth.permissions.contains('members:restrict');

  String? get assignedRegionId {
    final assignments = auth.user?.regionAssignments ?? const [];
    for (final assignment in assignments) {
      final id = assignment['regionId'];
      if (id is String && id.isNotEmpty) return id;
    }
    return null;
  }

  Future<void> load() async {
    if (!isAuthenticated) {
      _clearPrivateData();
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    await realtime.connect();
    await Future.wait([
      loadFeed(),
      loadGroups(),
      loadConversations(),
      loadInvitations(),
      loadNotifications(),
      loadOnlineMembers(),
      if (canModerate) loadModerationReports(),
    ]);
    loading = false;
    connected = realtime.isConnected;
    notifyListeners();
  }

  Future<void> refresh() async {
    await load();
  }

  Future<void> loadFeed({
    String? groupId,
    String? regionId,
    String? search,
    bool announcementsOnly = false,
    bool append = false,
  }) async {
    if (!isAuthenticated) return;
    if (!append) {
      feedCursor = null;
      feed = [];
    }
    try {
      final result = await api.getFeed(
        groupId: groupId,
        regionId: regionId,
        search: search,
        cursor: append ? feedCursor : null,
        announcementsOnly: announcementsOnly,
      );
      final posts = _mapList(result['posts']);
      feed = append ? [...feed, ...posts] : posts;
      feedCursor = result['nextCursor'] as String?;
      error = null;
    } catch (exception) {
      error = _message(exception);
    }
    notifyListeners();
  }

  Future<void> loadMoreFeed() async {
    if (loadingMore || feedCursor == null) return;
    loadingMore = true;
    notifyListeners();
    await loadFeed(append: true);
    loadingMore = false;
    notifyListeners();
  }

  Future<void> loadGroups({String? search, String? category}) async {
    if (!isAuthenticated) return;
    try {
      final results = await Future.wait([
        api.getGroups(mine: true, search: search),
        api.getGroups(search: search, category: category),
      ]);
      myGroups = _mapList(results[0]['groups']);
      final mineIds = myGroups.map((group) => group['id']).toSet();
      discoverGroups = _mapList(results[1]['groups'])
          .where((group) => !mineIds.contains(group['id']))
          .toList();
      error = null;
    } catch (exception) {
      error = _message(exception);
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>?> getGroup(String groupId) async {
    try {
      return await api.getGroup(groupId);
    } catch (exception) {
      _setError(exception);
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getGroupMembers(String groupId) async {
    try {
      final result = await api.getGroupMembers(groupId);
      return _mapList(result['members']);
    } catch (exception) {
      _setError(exception);
      return [];
    }
  }

  Future<Map<String, dynamic>?> getMemberProfile(String memberId) async {
    try {
      return await api.getMemberProfile(memberId);
    } catch (exception) {
      _setError(exception);
      return null;
    }
  }

  Future<void> inviteToGroup(String groupId, String memberId) async {
    await _run(() async {
      await api.inviteToGroup(groupId, memberId);
    });
  }

  Future<void> updateGroup(String groupId, Map<String, dynamic> updates) async {
    await _run(() async {
      await api.updateGroup(groupId, updates);
      await loadGroups();
    });
  }

  Future<void> updateGroupMember(
    String groupId,
    String memberId,
    Map<String, dynamic> updates,
  ) async {
    await _run(() async {
      await api.updateGroupMember(groupId, memberId, updates);
    });
  }

  Future<void> updateGroupRules(
    String groupId,
    List<Map<String, String>> rules,
  ) async {
    await _run(() async {
      await api.setGroupRules(groupId, rules);
    });
  }

  Future<void> createGroup({
    required String name,
    required String description,
    required String category,
    required String visibility,
  }) async {
    await _run(() async {
      await api.createGroup(
        name: name,
        description: description,
        category: category,
        visibility: visibility,
      );
      await loadGroups();
    });
  }

  Future<void> joinGroup(String groupId) async {
    await _run(() async {
      await api.joinGroup(groupId);
      await loadGroups();
    });
  }

  Future<void> leaveGroup(String groupId) async {
    await _run(() async {
      await api.leaveGroup(groupId);
      await loadGroups();
    });
  }

  Future<void> respondToInvitation(String invitationId, {required bool accept}) async {
    await _run(() async {
      await api.respondInvitation(invitationId, accept: accept);
      await loadInvitations();
      if (accept) await loadGroups();
    });
  }

  Future<void> createPost({
    required String body,
    required String visibility,
    String? groupId,
    String? regionId,
    List<String> mediaIds = const [],
  }) async {
    await _run(() async {
      await api.createPost(
        body: body,
        visibility: visibility,
        groupId: groupId,
        regionId: regionId,
        mediaIds: mediaIds,
      );
      await loadFeed();
    });
  }

  Future<void> reactToPost(String postId, String reaction) async {
    await _run(() async {
      await api.reactToPost(postId, reaction);
      await loadFeed();
    });
  }

  Future<void> bookmarkPost(String postId, {required bool saved}) async {
    await _run(() async {
      await api.bookmarkPost(postId, saved: saved);
      await loadFeed();
    });
  }

  Future<void> sharePost(String postId) async {
    await _run(() async {
      await api.recordPostShare(postId);
      await loadFeed();
    });
  }

  Future<void> setAnnouncement(String postId, {required bool pinned}) async {
    await _run(() async {
      await api.setAnnouncement(postId, pinned: pinned);
      await loadFeed(announcementsOnly: true);
    });
  }

  Future<void> updatePost(String postId, String body) async {
    await _run(() async {
      await api.updatePost(postId, body);
      await loadFeed();
    });
  }

  Future<void> deletePost(String postId) async {
    await _run(() async {
      await api.deletePost(postId);
      feed.removeWhere((post) => post['id'] == postId);
    });
  }

  Future<List<Map<String, dynamic>>> loadComments(String postId) async {
    try {
      final result = await api.getComments(postId);
      return _mapList(result['comments']);
    } catch (exception) {
      _setError(exception);
      return [];
    }
  }

  Future<void> addComment(
    String postId,
    String body, {
    String? parentCommentId,
  }) async {
    await _run(() async {
      await api.addComment(postId, body, parentCommentId: parentCommentId);
      await loadFeed();
    });
  }

  Future<List<Map<String, dynamic>>> searchMembers(String query) async {
    try {
      final result = await api.searchMembers(query);
      return _mapList(result['members']);
    } catch (exception) {
      _setError(exception);
      return [];
    }
  }

  Future<void> loadConversations({String? search}) async {
    if (!isAuthenticated) return;
    try {
      final result = await api.getConversations(search: search);
      conversations = _mapList(result['conversations']);
      error = null;
    } catch (exception) {
      error = _message(exception);
    }
    notifyListeners();
  }

  Future<String?> startDirectConversation(String recipientId) async {
    try {
      final result = await api.createDirectConversation(recipientId);
      final id = result['id'] as String?;
      if (id != null) await loadConversations();
      return id;
    } catch (exception) {
      _setError(exception);
      return null;
    }
  }

  Future<void> openConversation(String conversationId) async {
    try {
      final results = await Future.wait([
        api.getConversation(conversationId),
        api.getMessages(conversationId),
      ]);
      if (activeConversationId != null && activeConversationId != conversationId) {
        realtime.leaveConversation(activeConversationId!);
      }
      activeConversationId = conversationId;
      currentConversation = Map<String, dynamic>.from(results[0]);
      messages = _mapList(results[1]['messages']);
      messagesCursor = results[1]['nextCursor'] as String?;
      realtime.joinConversation(conversationId);
      await api.markRead(conversationId);
      final deliveredIds = messages
          .where((message) =>
              message['senderId'] != auth.user?.id && message['id'] is String)
          .map((message) => message['id'] as String)
          .toList();
      if (deliveredIds.isNotEmpty) {
        await api.markDelivered(conversationId, deliveredIds.take(100).toList());
      }
      await loadConversations();
      error = null;
    } catch (exception) {
      _setError(exception);
    }
    notifyListeners();
  }

  Future<void> loadOlderMessages() async {
    final conversationId = activeConversationId;
    if (conversationId == null || messagesCursor == null || loadingMore) return;
    loadingMore = true;
    notifyListeners();
    try {
      final result = await api.getMessages(
        conversationId,
        cursor: messagesCursor,
      );
      messages = [..._mapList(result['messages']), ...messages];
      messagesCursor = result['nextCursor'] as String?;
    } catch (exception) {
      _setError(exception);
    }
    loadingMore = false;
    notifyListeners();
  }

  Future<void> sendMessage(
    String body, {
    List<String> mediaIds = const [],
    String? replyToId,
  }) async {
    final conversationId = activeConversationId;
    if (conversationId == null || sending) return;
    if (body.trim().isEmpty && mediaIds.isEmpty) return;
    sending = true;
    error = null;
    final nonce = _uuid.v4();
    final temporaryId = 'local-$nonce';
    messages = [
      ...messages,
      {
        'id': temporaryId,
        'senderId': auth.user?.id,
        'senderName': auth.user?.fullName,
        'body': body.trim(),
        'replyToId': replyToId,
        'media': mediaIds.map((id) => {'id': id}).toList(),
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'status': 'sending',
      },
    ];
    notifyListeners();
    try {
      final result = await api.sendMessage(
        conversationId,
        body: body,
        replyToId: replyToId,
        clientNonce: nonce,
        mediaIds: mediaIds,
      );
      final saved = Map<String, dynamic>.from(result['message'] as Map);
      messages = messages.map((message) => message['id'] == temporaryId ? saved : message).toList();
      await loadConversations();
    } catch (exception) {
      error = _message(exception);
      messages = messages.map((message) {
        if (message['id'] == temporaryId) return {...message, 'status': 'failed'};
        return message;
      }).toList();
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  Future<void> forwardMessage(
    String messageId,
    String targetConversationId,
  ) async {
    final sourceConversationId = activeConversationId;
    if (sourceConversationId == null) return;
    await _run(() async {
      await api.forwardMessage(
        sourceConversationId,
        messageId,
        targetConversationId,
        _uuid.v4(),
      );
      await loadConversations();
    });
  }

  Future<void> editMessage(String messageId, String body) async {
    final conversationId = activeConversationId;
    if (conversationId == null) return;
    await _run(() async {
      await api.editMessage(conversationId, messageId, body);
      await openConversation(conversationId);
    });
  }

  Future<void> deleteMessage(String messageId) async {
    final conversationId = activeConversationId;
    if (conversationId == null) return;
    await _run(() async {
      await api.deleteMessage(conversationId, messageId);
      await openConversation(conversationId);
    });
  }

  Future<void> reactToMessage(String messageId, String reaction) async {
    final conversationId = activeConversationId;
    if (conversationId == null) return;
    await _run(() async {
      await api.reactToMessage(conversationId, messageId, reaction);
      await openConversation(conversationId);
    });
  }

  Future<void> searchMessages(String query) async {
    final conversationId = activeConversationId;
    if (conversationId == null) return;
    try {
      final result = await api.searchMessages(conversationId, query);
      messages = _mapList(result['messages']);
      notifyListeners();
    } catch (exception) {
      _setError(exception);
    }
  }

  Future<void> loadInvitations() async {
    if (!isAuthenticated) return;
    try {
      final result = await api.getInvitations();
      invitations = _mapList(result['invitations']);
      notifyListeners();
    } catch (exception) {
      error = _message(exception);
    }
  }

  Future<void> loadNotifications() async {
    if (!isAuthenticated) return;
    notificationLoading = true;
    try {
      final result = await api.getNotifications();
      notifications = _mapList(result['notifications']);
      error = null;
    } catch (exception) {
      error = _message(exception);
    } finally {
      notificationLoading = false;
      notifyListeners();
    }
  }

  Future<void> markNotificationRead(String id) async {
    await _run(() async {
      await api.markNotificationRead(id);
      notifications = notifications.map((notification) {
        if (notification['id'] == id) {
          return {...notification, 'readAt': DateTime.now().toUtc().toIso8601String()};
        }
        return notification;
      }).toList();
    });
  }

  Future<void> loadOnlineMembers() async {
    if (!isAuthenticated) return;
    try {
      final result = await api.getOnlineMembers();
      onlineMembers = _mapList(result['members']);
    } catch (exception) {
      error = _message(exception);
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>> getNotificationPreferences() async {
    final result = await api.getNotificationPreferences();
    return Map<String, dynamic>.from(result['preferences'] as Map);
  }

  Future<void> updateNotificationPreferences(Map<String, bool> preferences) async {
    await _run(() async {
      await api.updateNotificationPreferences(preferences);
    });
  }

  Future<Map<String, dynamic>> getPresenceSettings() async {
    final result = await api.getPresenceSettings();
    return Map<String, dynamic>.from(result['settings'] as Map);
  }

  Future<void> updatePresenceSettings(Map<String, bool> settings) async {
    await _run(() async {
      await api.updatePresenceSettings(settings);
      await loadOnlineMembers();
    });
  }

  Future<List<Map<String, dynamic>>> loadBlockedUsers() async {
    final result = await api.getBlockedUsers();
    return _mapList(result['blockedMembers']);
  }

  Future<Map<String, dynamic>> uploadMedia(
    Uint8List bytes,
    String fileName, {
    void Function(int sent, int total)? onProgress,
  }) {
    return api.uploadMedia(bytes: bytes, fileName: fileName, onProgress: onProgress);
  }

  Future<Uint8List> downloadMedia(
    String mediaId, {
    void Function(int received, int total)? onProgress,
  }) =>
      api.downloadMedia(mediaId, onProgress: onProgress);

  Future<void> reportContent({
    required String type,
    required String id,
    required String category,
    String details = '',
  }) async {
    await _run(() async {
      await api.reportContent(
        targetType: type,
        targetId: id,
        category: category,
        details: details,
      );
    });
  }

  Future<void> blockUser(String userId) async {
    await _run(() async {
      await api.blockUser(userId);
      await loadConversations();
    });
  }

  Future<void> unblockUser(String userId) async {
    await _run(() async {
      await api.unblockUser(userId);
      await loadConversations();
    });
  }

  Future<void> muteTarget(String type, String id) async {
    await _run(() async {
      await api.muteTarget(type, id);
      await loadConversations();
    });
  }

  Future<void> loadModerationReports() async {
    if (!isAuthenticated || !canModerate) return;
    try {
      final result = await api.getModerationReports(status: 'open');
      moderationReports = _mapList(result['reports']);
      error = null;
    } catch (exception) {
      error = _message(exception);
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>?> getModerationReport(String reportId) async {
    try {
      return await api.getModerationReport(reportId);
    } catch (exception) {
      _setError(exception);
      return null;
    }
  }

  Future<void> applyModerationAction(
    String reportId,
    String action,
    String reason,
  ) async {
    await _run(() async {
      await api.applyModerationAction(reportId, action, reason);
      await loadModerationReports();
    });
  }

  void typing({required bool active}) {
    final id = activeConversationId;
    if (id != null) realtime.typing(id, active: active);
  }

  void closeConversation() {
    final id = activeConversationId;
    if (id != null) realtime.leaveConversation(id);
    activeConversationId = null;
    currentConversation = null;
    messages = [];
    messagesCursor = null;
    typingUserId = null;
    notifyListeners();
  }

  Future<void> _run(Future<void> Function() action) async {
    error = null;
    try {
      await action();
    } catch (exception) {
      error = _message(exception);
    }
    notifyListeners();
  }

  void _onMessage(Map<String, dynamic> message) {
    final conversationId = message['conversationId'];
    if (conversationId == activeConversationId) {
      if (!messages.any((current) => current['id'] == message['id'])) {
        messages = [...messages, message];
      }
      if (message['senderId'] != auth.user?.id && activeConversationId != null) {
        unawaited(api.markRead(activeConversationId!));
      }
    } else {
      unawaited(loadConversations());
    }
    notifyListeners();
  }

  void _onTypingUpdate(Map<String, dynamic> event) {
    if (event['conversationId'] != activeConversationId) return;
    final userId = event['userId'];
    if (event['isTyping'] == true && userId is String) {
      typingUserId = userId;
      _typingExpiry?.cancel();
      _typingExpiry = Timer(const Duration(seconds: 4), () {
        typingUserId = null;
        notifyListeners();
      });
    } else {
      typingUserId = null;
    }
    notifyListeners();
  }

  void _clearPrivateData() {
    realtime.disconnect();
    feed = [];
    myGroups = [];
    discoverGroups = [];
    conversations = [];
    notifications = [];
    onlineMembers = [];
    invitations = [];
    moderationReports = [];
    messages = [];
    activeConversationId = null;
    currentConversation = null;
  }

  void reset() {
    _clearPrivateData();
    error = null;
    loading = false;
    notifyListeners();
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return [];
    return value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }

  String _message(Object exception) {
    if (exception is CommunityApiException) return exception.message;
    return exception.toString();
  }

  void _setError(Object exception) {
    error = _message(exception);
    notifyListeners();
  }

  @override
  void dispose() {
    _typingExpiry?.cancel();
    if (_messageSubscription != null) unawaited(_messageSubscription!.cancel());
    if (_conversationSubscription != null) {
      unawaited(_conversationSubscription!.cancel());
    }
    if (_notificationSubscription != null) {
      unawaited(_notificationSubscription!.cancel());
    }
    if (_typingSubscription != null) unawaited(_typingSubscription!.cancel());
    if (_presenceSubscription != null) unawaited(_presenceSubscription!.cancel());
    if (_connectionSubscription != null) {
      unawaited(_connectionSubscription!.cancel());
    }
    realtime.dispose();
    super.dispose();
  }
}
