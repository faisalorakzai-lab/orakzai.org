import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../auth/auth_api.dart';

class CommunityApiException implements Exception {
  const CommunityApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class CommunityApi {
  CommunityApi({required AuthApi auth, Dio? dio})
    : _auth = auth,
      _dio = dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(minutes: 2),
            ),
          );

  final AuthApi _auth;
  final Dio _dio;

  static const categories = <String, String>{
    'general': 'General Community',
    'regional': 'Orakzai Regional Network',
    'youth': 'Youth Network',
    'education': 'Education & Students',
    'healthcare': 'Healthcare',
    'business': 'Business & Entrepreneurs',
    'employment': 'Employment & Opportunities',
    'overseas': 'Overseas Orakzai Community',
    'welfare': 'Social Welfare',
    'culture': 'Cultural & Heritage',
  };

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) {
    return _auth.requestAuthorized(method, path, body: body);
  }

  String _query(String path, Map<String, Object?> values) {
    final parameters = <String, String>{};
    for (final entry in values.entries) {
      final value = entry.value;
      if (value != null && value.toString().isNotEmpty) {
        parameters[entry.key] = value.toString();
      }
    }
    if (parameters.isEmpty) return path;
    return Uri(path: path, queryParameters: parameters).toString();
  }

  Future<Map<String, dynamic>> getFeed({
    String? groupId,
    String? regionId,
    String? search,
    String? cursor,
    bool announcementsOnly = false,
    int limit = 20,
  }) async {
    final path = announcementsOnly ? '/community/announcements' : '/community/feed';
    return _request(
      'GET',
      _query(path, {
        'groupId': groupId,
        'regionId': regionId,
        'search': search,
        'cursor': cursor,
        'limit': limit,
      }),
    );
  }

  Future<Map<String, dynamic>> getGroups({
    String? search,
    String? category,
    bool mine = false,
    String? cursor,
    int limit = 20,
  }) {
    return _request(
      'GET',
      _query('/community/groups', {
        'search': search,
        'category': category,
        'mine': mine ? 'true' : null,
        'cursor': cursor,
        'limit': limit,
      }),
    );
  }

  Future<Map<String, dynamic>> getGroup(String groupId) =>
      _request('GET', '/community/groups/$groupId');

  Future<Map<String, dynamic>> createGroup({
    required String name,
    required String description,
    required String category,
    required String visibility,
    String? regionId,
  }) {
    return _request('POST', '/community/groups', body: {
      'name': name,
      'description': description,
      'category': category,
      'visibility': visibility,
      if (regionId != null) 'regionId': regionId,
    });
  }

  Future<Map<String, dynamic>> joinGroup(String groupId) =>
      _request('POST', '/community/groups/$groupId/join', body: const {});

  Future<Map<String, dynamic>> leaveGroup(String groupId) =>
      _request('POST', '/community/groups/$groupId/leave', body: const {});

  Future<Map<String, dynamic>> getGroupMembers(String groupId) =>
      _request('GET', '/community/groups/$groupId/members');

  Future<Map<String, dynamic>> inviteToGroup(String groupId, String userId) =>
      _request('POST', '/community/groups/$groupId/invite', body: {'inviteeId': userId});

  Future<Map<String, dynamic>> getInvitations() =>
      _request('GET', '/community/groups/invitations');

  Future<Map<String, dynamic>> respondInvitation(String invitationId, {required bool accept}) =>
      _request('POST', '/community/invitations/$invitationId/respond', body: {'accept': accept});

  Future<Map<String, dynamic>> updateGroup(
    String groupId,
    Map<String, dynamic> updates,
  ) => _request('PATCH', '/community/groups/$groupId', body: updates);

  Future<Map<String, dynamic>> updateGroupMember(
    String groupId,
    String memberId,
    Map<String, dynamic> update,
  ) => _request('PATCH', '/community/groups/$groupId/members/$memberId', body: update);

  Future<Map<String, dynamic>> setGroupRules(
    String groupId,
    List<Map<String, String>> rules,
  ) => _request('PUT', '/community/groups/$groupId/rules', body: {'rules': rules});

  Future<Map<String, dynamic>> createPost({
    required String body,
    required String visibility,
    String? groupId,
    String? regionId,
    List<String> mediaIds = const [],
  }) {
    return _request('POST', '/community/posts', body: {
      'body': body,
      'visibility': visibility,
      if (groupId != null) 'groupId': groupId,
      if (regionId != null) 'regionId': regionId,
      if (mediaIds.isNotEmpty) 'mediaIds': mediaIds,
    });
  }

  Future<Map<String, dynamic>> updatePost(String postId, String body) =>
      _request('PATCH', '/community/posts/$postId', body: {'body': body});

  Future<Map<String, dynamic>> deletePost(String postId) =>
      _request('DELETE', '/community/posts/$postId');

  Future<Map<String, dynamic>> getComments(String postId, {String? cursor}) =>
      _request('GET', _query('/community/posts/$postId/comments', {'cursor': cursor}));

  Future<Map<String, dynamic>> addComment(
    String postId,
    String body, {
    String? parentCommentId,
  }) {
    return _request('POST', '/community/posts/$postId/comments', body: {
      'body': body,
      if (parentCommentId != null) 'parentCommentId': parentCommentId,
    });
  }

  Future<Map<String, dynamic>> reactToPost(String postId, String reaction) =>
      _request('POST', '/community/posts/$postId/reactions', body: {'reaction': reaction});

  Future<Map<String, dynamic>> bookmarkPost(String postId, {required bool saved}) =>
      _request('PUT', '/community/posts/$postId/bookmark', body: {'saved': saved});

  Future<Map<String, dynamic>> setAnnouncement(String postId, {required bool pinned}) =>
      _request('PUT', '/community/posts/$postId/announcement', body: {'pinned': pinned});

  Future<Map<String, dynamic>> searchMembers(String query) =>
      _request('GET', _query('/community/members/search', {'q': query}));

  Future<Map<String, dynamic>> getMemberProfile(String memberId) =>
      _request('GET', '/community/members/$memberId');

  Future<Map<String, dynamic>> recordPostShare(String postId) =>
      _request('POST', '/community/posts/$postId/share', body: const {});

  Future<Map<String, dynamic>> getConversations({String? search}) =>
      _request('GET', _query('/messages/conversations', {'search': search}));

  Future<Map<String, dynamic>> createDirectConversation(String recipientId) =>
      _request('POST', '/messages/conversations', body: {'recipientId': recipientId});

  Future<Map<String, dynamic>> getConversation(String conversationId) =>
      _request('GET', '/messages/conversations/$conversationId');

  Future<Map<String, dynamic>> getMessages(
    String conversationId, {
    String? cursor,
    int limit = 40,
  }) {
    return _request(
      'GET',
      _query('/messages/conversations/$conversationId/messages', {
        'cursor': cursor,
        'limit': limit,
      }),
    );
  }

  Future<Map<String, dynamic>> sendMessage(
    String conversationId, {
    required String body,
    String? replyToId,
    String? clientNonce,
    List<String> mediaIds = const [],
  }) {
    return _request('POST', '/messages/conversations/$conversationId/messages', body: {
      'body': body,
      if (replyToId != null) 'replyToId': replyToId,
      if (clientNonce != null) 'clientNonce': clientNonce,
      if (mediaIds.isNotEmpty) 'mediaIds': mediaIds,
    });
  }

  Future<Map<String, dynamic>> forwardMessage(
    String sourceConversationId,
    String messageId,
    String targetConversationId,
    String clientNonce,
  ) =>
      _request(
        'POST',
        '/messages/conversations/$sourceConversationId/messages/$messageId/forward',
        body: {
          'targetConversationId': targetConversationId,
          'clientNonce': clientNonce,
        },
      );

  Future<Map<String, dynamic>> markRead(String conversationId) =>
      _request('POST', '/messages/conversations/$conversationId/read', body: const {});

  Future<Map<String, dynamic>> markDelivered(
    String conversationId,
    List<String> messageIds,
  ) =>
      _request('POST', '/messages/conversations/$conversationId/delivered', body: {
        'messageIds': messageIds,
      });

  Future<Map<String, dynamic>> editMessage(
    String conversationId,
    String messageId,
    String body,
  ) =>
      _request('PATCH', '/messages/conversations/$conversationId/messages/$messageId', body: {
        'body': body,
      });

  Future<Map<String, dynamic>> deleteMessage(
    String conversationId,
    String messageId,
  ) =>
      _request('DELETE', '/messages/conversations/$conversationId/messages/$messageId');

  Future<Map<String, dynamic>> reactToMessage(
    String conversationId,
    String messageId,
    String reaction,
  ) =>
      _request('POST', '/messages/conversations/$conversationId/messages/$messageId/reactions', body: {
        'reaction': reaction,
      });

  Future<Map<String, dynamic>> searchMessages(String conversationId, String query) =>
      _request(
        'GET',
        _query('/messages/conversations/$conversationId/search', {'q': query}),
      );

  Future<Map<String, dynamic>> getNotifications() =>
      _request('GET', '/community/notifications');

  Future<Map<String, dynamic>> markNotificationRead(String notificationId) =>
      _request('POST', '/community/notifications/$notificationId/read', body: const {});

  Future<Map<String, dynamic>> getNotificationPreferences() =>
      _request('GET', '/community/notifications/preferences');

  Future<Map<String, dynamic>> updateNotificationPreferences(
    Map<String, bool> preferences,
  ) =>
      _request('PATCH', '/community/notifications/preferences', body: preferences);

  Future<Map<String, dynamic>> getOnlineMembers() =>
      _request('GET', '/community/online-members');

  Future<Map<String, dynamic>> getPresenceSettings() =>
      _request('GET', '/community/presence/settings');

  Future<Map<String, dynamic>> updatePresenceSettings(
    Map<String, bool> settings,
  ) =>
      _request('PATCH', '/community/presence/settings', body: settings);

  Future<Map<String, dynamic>> getBlockedUsers() => _request('GET', '/community/blocks');

  Future<Map<String, dynamic>> blockUser(String userId) =>
      _request('POST', '/community/blocks/$userId', body: const {});

  Future<Map<String, dynamic>> unblockUser(String userId) =>
      _request('DELETE', '/community/blocks/$userId');

  Future<Map<String, dynamic>> muteTarget(
    String targetType,
    String targetId, {
    DateTime? until,
  }) {
    return _request('PUT', '/community/mutes', body: {
      'targetType': targetType,
      'targetId': targetId,
      if (until != null) 'mutedUntil': until.toUtc().toIso8601String(),
    });
  }

  Future<Map<String, dynamic>> unmuteTarget(String targetType, String targetId) =>
      _request('DELETE', '/community/mutes/$targetType/$targetId');

  Future<Map<String, dynamic>> reportContent({
    required String targetType,
    required String targetId,
    required String category,
    String details = '',
  }) =>
      _request('POST', '/community/reports', body: {
        'targetType': targetType,
        'targetId': targetId,
        'category': category,
        'details': details,
      });

  Future<Map<String, dynamic>> getModerationReports({String? status}) =>
      _request('GET', _query('/moderation/reports', {'status': status}));

  Future<Map<String, dynamic>> getModerationReport(String reportId) =>
      _request('GET', '/moderation/reports/$reportId');

  Future<Map<String, dynamic>> applyModerationAction(
    String reportId,
    String action,
    String reason,
  ) =>
      _request('POST', '/moderation/reports/$reportId/actions', body: {
        'action': action,
        'reason': reason,
      });

  Future<Map<String, dynamic>> uploadMedia({
    required Uint8List bytes,
    required String fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    Future<Response<Map<String, dynamic>>> send() async {
      final token = await _auth.readAccessToken();
      if (token == null) throw const AuthApiException('UNAUTHENTICATED', 'Please sign in.');
      final uri = Uri.parse('${_auth.apiBaseUrl}/media/upload');
      return _dio.postUri<Map<String, dynamic>>(
        uri,
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: fileName),
        }),
        options: Options(headers: {'Authorization': 'Bearer $token'}),
        onSendProgress: onProgress,
      );
    }

    try {
      final response = await send();
      return Map<String, dynamic>.from(response.data ?? const {});
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        await _auth.refreshSession();
        try {
          final response = await send();
          return Map<String, dynamic>.from(response.data ?? const {});
        } on DioException catch (retryError) {
          throw _dioError(retryError);
        }
      }
      throw _dioError(error);
    }
  }

  Future<Uint8List> downloadMedia(
    String mediaId, {
    void Function(int received, int total)? onProgress,
  }) async {
    Future<Uint8List> download() async {
      final access = await _request('GET', '/media/$mediaId/access');
      final token = await _auth.readAccessToken();
      if (token == null) throw const AuthApiException('UNAUTHENTICATED', 'Please sign in.');
      final uri = Uri.parse('${_auth.apiBaseUrl}${access['path']}').replace(
        queryParameters: {
          'expires': '${access['expires']}',
          'signature': '${access['signature']}',
        },
      );
      final response = await _dio.getUri<List<int>>(
        uri,
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          responseType: ResponseType.bytes,
        ),
        onReceiveProgress: onProgress,
      );
      return Uint8List.fromList(response.data ?? const []);
    }

    try {
      return await download();
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        await _auth.refreshSession();
        try {
          return await download();
        } on DioException catch (retryError) {
          throw _dioError(retryError);
        }
      }
      throw _dioError(error);
    }
  }

  CommunityApiException _dioError(DioException error) {
    final data = error.response?.data;
    final errorMap = data is Map ? data['error'] : null;
    final message = errorMap is Map && errorMap['message'] is String
        ? errorMap['message'] as String
        : 'The community request could not be completed.';
    return CommunityApiException(message, statusCode: error.response?.statusCode);
  }
}
