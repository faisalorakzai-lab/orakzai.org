import '../auth/auth_api.dart';
import '../community/community_api.dart';

/// Uses the application's existing authenticated clients and visibility rules.
class HomeApi {
  HomeApi({required AuthApi auth})
      : _auth = auth,
        _community = CommunityApi(auth: auth);

  final AuthApi _auth;
  final CommunityApi _community;

  Future<Map<String, dynamic>> statistics() async {
    final result = await _auth.requestAuthorized('GET', '/community/summary');
    for (final key in ['accessiblePosts', 'accessibleAnnouncements', 'joinedGroups']) {
      if (result[key] is! int || (result[key] as int) < 0) {
        throw const FormatException('Community statistics returned an invalid response.');
      }
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> feed({
    bool announcementsOnly = false,
    String? search,
    int limit = 3,
  }) async => _rows(await _community.getFeed(
      announcementsOnly: announcementsOnly, search: search, limit: limit), 'posts');

  Future<Map<String, List<Map<String, dynamic>>>> search(String query) async {
    final term = query.trim();
    if (term.length < 2 || term.length > 80) {
      throw const FormatException('Search must contain 2–80 characters.');
    }
    final results = await Future.wait([
      _community.getFeed(search: term, limit: 10),
      _community.getGroups(search: term, limit: 10),
      _community.searchMembers(term),
    ]);
    return {
      'posts': _rows(results[0], 'posts'),
      'groups': _rows(results[1], 'groups'),
      'members': _rows(results[2], 'members').take(10).toList(),
    };
  }

  List<Map<String, dynamic>> _rows(Map<String, dynamic> response, String key) {
    final rows = response[key];
    if (rows is! List || rows.any((row) => row is! Map)) {
      throw FormatException('The $key search response is invalid.');
    }
    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }
}
