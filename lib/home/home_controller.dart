import 'dart:async';
import 'package:flutter/foundation.dart';
import '../auth/auth_controller.dart';
import 'home_api.dart';

class HomeSection<T> {
  const HomeSection({this.data, this.loading = false, this.error});
  final T? data;
  final bool loading;
  final String? error;
}

/// Never keeps one member's records after sign-out or an account switch.
class HomeController extends ChangeNotifier {
  HomeController({required this.auth, HomeApi? api})
      : api = api ?? HomeApi(auth: auth.api) {
    auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  final AuthController auth;
  final HomeApi api;
  HomeSection<Map<String, dynamic>> statistics = const HomeSection();
  HomeSection<List<Map<String, dynamic>>> announcements = const HomeSection();
  HomeSection<List<Map<String, dynamic>>> updates = const HomeSection();
  String? _userId;
  int _generation = 0;
  bool _disposed = false;

  void _onAuthChanged() {
    final id = auth.isAuthenticated ? auth.user!.id : null;
    if (id == _userId) {
      if (!_disposed) notifyListeners();
      return;
    }
    _userId = id;
    _generation++;
    statistics = const HomeSection();
    announcements = const HomeSection();
    updates = const HomeSection();
    if (id != null) {
      unawaited(refresh());
    } else {
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (_disposed || !auth.isAuthenticated) return;
    final generation = ++_generation;
    statistics = const HomeSection(loading: true);
    announcements = const HomeSection(loading: true);
    updates = const HomeSection(loading: true);
    notifyListeners();
    await Future.wait([
      _fetch(api.statistics, (state) => statistics = state, generation),
      _fetch(() => api.feed(announcementsOnly: true), (state) => announcements = state, generation),
      _fetch(() => api.feed(), (state) => updates = state, generation),
    ]);
  }

  Future<void> _fetch<T>(
    Future<T> Function() request,
    void Function(HomeSection<T>) apply,
    int generation,
  ) async {
    HomeSection<T> result;
    try {
      result = HomeSection(data: await request());
    } catch (error) {
      result = HomeSection(error: error.toString());
    }
    if (_disposed || generation != _generation) return;
    apply(result);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    auth.removeListener(_onAuthChanged);
    super.dispose();
  }
}
