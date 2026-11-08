import 'dart:async';
import 'package:flutter/material.dart';
import '../app/app_theme.dart';
import '../auth/auth_controller.dart';
import '../community/community_controller.dart';
import '../community/community_pages.dart';
import '../data/program_area.dart';
import '../widgets/app_components.dart';
import 'home_api.dart';

/// Searches approved public program information and authorized live records.
class HomeSearchScreen extends StatefulWidget {
  const HomeSearchScreen({required this.auth, required this.api, super.key});
  final AuthController auth;
  final HomeApi api;

  @override
  State<HomeSearchScreen> createState() => _HomeSearchScreenState();
}

class _HomeSearchScreenState extends State<HomeSearchScreen> {
  final _input = TextEditingController();
  Timer? _debounce;
  CommunityController? _community;
  String _query = '';
  String? _error;
  String? _userId;
  bool _loading = false;
  int _generation = 0;
  Map<String, List<Map<String, dynamic>>>? _results;

  @override
  void initState() {
    super.initState();
    _userId = widget.auth.user?.id;
    widget.auth.addListener(_authChanged);
  }

  void _authChanged() {
    final id = widget.auth.isAuthenticated ? widget.auth.user!.id : null;
    if (id != _userId) {
      _userId = id;
      _generation++;
      _debounce?.cancel();
      setState(() {
        _results = null;
        _loading = false;
        _error = null;
      });
    }
  }

  void _changed(String value) {
    _debounce?.cancel();
    _generation++;
    setState(() {
      _query = value.trim();
      _results = null;
      _error = null;
      _loading = false;
    });
    if (_query.length >= 2 && widget.auth.isAuthenticated) {
      _debounce = Timer(const Duration(milliseconds: 400), _search);
    }
  }

  Future<void> _search() async {
    _debounce?.cancel();
    if (_query.length < 2 || !widget.auth.isAuthenticated) return;
    final generation = ++_generation;
    setState(() { _loading = true; _error = null; });
    try {
      final result = await widget.api.search(_query);
      if (!mounted || generation != _generation) return;
      setState(() => _results = result);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  Future<void> _open(String kind, Map<String, dynamic> item) async {
    if (!widget.auth.isAuthenticated) return;
    final controller = _community ??= CommunityController(auth: widget.auth);
    final Widget page;
    switch (kind) {
      case 'groups':
        page = GroupDetailsScreen(controller: controller, groupId: item['id'] as String);
      case 'members':
        page = MemberProfileScreen(controller: controller, memberId: item['id'] as String);
      default:
        page = PostCommentsScreen(controller: controller, post: item);
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    widget.auth.removeListener(_authChanged);
    _input.dispose();
    _community?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _query.length < 2 ? <ProgramArea>[] : publicProgramAreas.where((p) =>
      '${p.title} ${p.summary}'.toLowerCase().contains(_query.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Search ORAKZAI.ORG')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            key: const Key('home-global-search-input'),
            controller: _input,
            autofocus: true,
            maxLength: 80,
            textInputAction: TextInputAction.search,
            onChanged: _changed,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Programs, updates, groups and members',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(tooltip: 'Clear search', onPressed: () {
                _input.clear(); _changed('');
              }, icon: const Icon(Icons.close_rounded)),
            ),
          ),
          const SizedBox(height: 16),
          if (_query.length < 2)
            const EmptyState(title: 'Find your community', message: 'Enter at least two characters to search.'),
          if (_query.length >= 2) ...[
            const SectionHeading(title: 'Programs'),
            for (final program in matches) Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ProgramAreaCard(area: program, onTap: () => showDialog<void>(
                context: context, builder: (_) => AlertDialog(
                  title: Text(program.title),
                  content: Text('${program.summary}\n\nPublic website information; current service availability is not confirmed.'),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
                ))),
            ),
            if (matches.isEmpty) const Text('No matching program information.'),
            const SizedBox(height: 22),
            if (!widget.auth.isAuthenticated)
              const InfoBanner(title: 'Member search requires sign-in',
                message: 'Public program information is available above. Sign in from Profile to search authorized updates, groups and member profiles.'),
            if (_loading) const LinearProgressIndicator(semanticsLabel: 'Searching authorized community records'),
            if (_error != null) ...[
              InfoBanner(title: 'Live search could not complete', message: _error!),
              TextButton(onPressed: _search, child: const Text('Retry live search')),
            ],
            if (_results != null)
              for (final kind in ['posts', 'groups', 'members']) ...[
                const SizedBox(height: 18),
                SectionHeading(title: {'posts': 'Community updates', 'groups': 'Groups', 'members': 'Members'}[kind]!),
                for (final item in _results![kind]!) Card(
                  child: ListTile(
                    title: Text((item['body'] ?? item['name'] ?? item['fullName'] ?? 'Community record').toString(),
                      maxLines: 3, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.green),
                    onTap: () => _open(kind, item),
                  ),
                ),
                if (_results![kind]!.isEmpty) const Text('No authorized matches.'),
                if (_results![kind]!.length >= 10)
                  const Text('Showing the first 10 matches. Refine your search for more specific results.'),
              ],
          ],
        ],
      ),
    );
  }
}
