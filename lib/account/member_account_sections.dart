import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_language.dart';
import '../app/app_theme.dart';
import '../auth/account_api.dart';
import '../auth/auth_controller.dart';
import 'account_strings.dart';

class MemberAccountSections extends StatefulWidget {
  const MemberAccountSections({
    required this.auth,
    required this.language,
    required this.appearance,
    required this.onAppearanceChanged,
    required this.onLanguageChanged,
    required this.onOpenHelpDesk,
    required this.onReviewOnboarding,
    super.key,
  });
  final AuthController auth;
  final AppLanguage language;
  final ThemeMode appearance;
  final ValueChanged<ThemeMode> onAppearanceChanged;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final VoidCallback onOpenHelpDesk;
  final VoidCallback onReviewOnboarding;

  @override
  State<MemberAccountSections> createState() => _MemberAccountSectionsState();
}

class _MemberAccountSectionsState extends State<MemberAccountSections> {
  late final AccountApi _api = AccountApi(widget.auth.api);
  String t(String key, [Map<String, String>? args]) =>
      AccountStrings.text(widget.language, key, args);
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final caps = widget.auth.capabilities;
    final blocks = <Widget>[
      _group(t('sectionAccount'), [
        _tile(
          Icons.password_outlined,
          t('changePassword'),
          t('securityBody'),
          onTap: _changePassword,
        ),
        _tile(
          Icons.devices_outlined,
          t('activeSessions'),
          t('securityBody'),
          onTap: () => _showData('sessions', t('activeSessions')),
        ),
        _tile(
          Icons.mark_email_read_outlined,
          t('verification'),
          widget.auth.user?.emailVerified == true
              ? t('verifiedState')
              : t('unverifiedState'),
          trailing: widget.auth.user?.emailVerified == true
              ? Icons.check_circle_outline
              : Icons.schedule_outlined,
        ),
        _tile(
          Icons.phone_android_outlined,
          t('phone'),
          t('phoneVerifyUnavailable'),
          trailing: Icons.info_outline_rounded,
        ),
      ]),
      _group(t('sectionCommunity'), [
        _tile(
          Icons.groups_2_outlined,
          t('myGroups'),
          t('emptyBody'),
          onTap: () => _showData('community/groups', t('myGroups')),
        ),
        _tile(
          Icons.article_outlined,
          t('myPosts'),
          t('emptyBody'),
          onTap: () => _showData('community/posts', t('myPosts')),
        ),
        _tile(
          Icons.forum_outlined,
          t('myComments'),
          t('emptyBody'),
          onTap: () => _showData('community/comments', t('myComments')),
        ),
        _tile(
          Icons.bookmark_border_rounded,
          t('saved'),
          t('emptyBody'),
          onTap: () => _showData('community/saved', t('saved')),
        ),
        _tile(
          Icons.volunteer_activism_outlined,
          t('contributions'),
          t('emptyBody'),
          onTap: () => _showData('community/contributions', t('contributions')),
        ),
      ]),
      _group(t('sectionActivity'), [
        _tile(
          Icons.support_agent_outlined,
          t('helpRequests'),
          t('emptyBody'),
          onTap: () => _showData('community/requests', t('helpRequests')),
        ),
        if (caps['applicationsAvailable'] == true)
          _tile(
            Icons.assignment_outlined,
            t('myApplications'),
            t('emptyBody'),
            onTap: () =>
                _showData('community/applications', t('myApplications')),
          ),
        _tile(
          Icons.notifications_none_rounded,
          t('notifications'),
          t('emptyBody'),
          onTap: () => _showData('community/notifications', t('notifications')),
        ),
        _tile(
          Icons.history_rounded,
          t('activityHistory'),
          t('emptyBody'),
          onTap: () => _showData('activity', t('activityHistory')),
        ),
      ]),
      _group(t('sectionSettings'), [
        _tile(
          Icons.tune_rounded,
          t('notificationPrefs'),
          t('prefsSaved'),
          onTap: _editNotificationPreferences,
        ),
        _tile(
          Icons.block_outlined,
          t('blockedUsers'),
          t('noBlocked'),
          onTap: () => _showData('blocked-users', t('blockedUsers')),
        ),
        _languageChooser(),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(15, 5, 15, 15),
          child: SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(value: ThemeMode.system, label: Text(t('system'))),
              ButtonSegment(value: ThemeMode.light, label: Text(t('light'))),
              ButtonSegment(value: ThemeMode.dark, label: Text(t('dark'))),
            ],
            selected: {widget.appearance},
            onSelectionChanged: (selection) =>
                widget.onAppearanceChanged(selection.first),
          ),
        ),
        _tile(
          Icons.privacy_tip_outlined,
          t('privacySettings'),
          t('private'),
          onTap: () => _openPrivacy(),
        ),
        _tile(
          Icons.slideshow_rounded,
          t('replayOnboarding'),
          t('slogan'),
          onTap: widget.onReviewOnboarding,
        ),
      ]),
      _group(t('sectionSupport'), [
        _tile(
          Icons.headset_mic_outlined,
          t('helpCenter'),
          t('helpRequests'),
          onTap: widget.onOpenHelpDesk,
        ),
        _tile(
          Icons.shield_outlined,
          t('privacyPolicy'),
          t('policyNotConfigured'),
          onTap: () => _openPolicy('privacy'),
        ),
        _tile(
          Icons.gavel_rounded,
          t('termsOfService'),
          t('policyNotConfigured'),
          onTap: () => _openPolicy('terms'),
        ),
        _tile(
          Icons.info_outline_rounded,
          t('about'),
          t('aboutBody'),
          onTap: _about,
        ),
        _tile(
          Icons.phone_iphone_rounded,
          t('appVersion'),
          t('versionUnavailable'),
          onTap: _showVersion,
        ),
      ]),
      _group(t('sectionActions'), [
        _tile(
          Icons.download_outlined,
          t('exportData'),
          t('exportBody'),
          onTap: _exportData,
        ),
        if (caps['deletionAvailable'] == true)
          _tile(
            Icons.delete_outline_rounded,
            t('deleteAccount'),
            t('deleteBody', {'days': '${caps['deletionRetentionDays']}'}),
            danger: true,
            onTap: _deleteAccount,
          )
        else
          _tile(
            Icons.delete_outline_rounded,
            t('deleteAccount'),
            t('deleteUnavailableBody'),
            onTap: widget.onOpenHelpDesk,
          ),
        _tile(
          Icons.logout_rounded,
          t('logout'),
          t('logoutConfirm'),
          danger: true,
          onTap: _logout,
        ),
      ]),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final block in blocks) ...[block, const SizedBox(height: 15)],
      ],
    );
  }

  Widget _group(String title, List<Widget> tiles) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 17, 16, 9),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColors.navy,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        ...tiles,
      ],
    ),
  );

  Widget _tile(
    IconData icon,
    String title,
    String subtitle, {
    VoidCallback? onTap,
    IconData? trailing,
    bool danger = false,
  }) => ListTile(
    leading: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: danger ? AppColors.dangerWash : AppColors.greenWash,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(
        icon,
        size: 20,
        color: danger ? AppColors.danger : AppColors.navy,
      ),
    ),
    title: Text(
      title,
      style: TextStyle(
        color: danger ? AppColors.danger : null,
        fontWeight: FontWeight.w700,
      ),
    ),
    subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
    trailing: trailing == null
        ? const Icon(Icons.chevron_right_rounded)
        : Icon(trailing),
    onTap: onTap,
  );

  Widget _languageChooser() => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t('language'), style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 9),
        Wrap(
          spacing: 8,
          children: AppLanguage.values
              .map(
                (item) => ChoiceChip(
                  label: Text(item.displayName),
                  selected: item == widget.language,
                  onSelected: (_) => widget.onLanguageChanged(item),
                ),
              )
              .toList(),
        ),
      ],
    ),
  );

  Future<void> _showData(String path, String title) async {
    if (path == 'sessions') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _AccountListPage(
            title: title,
            language: widget.language,
            load: (page) => _api.get('sessions'),
            onAction: _revokeSession,
          ),
        ),
      );
      return;
    }
    if (path == 'blocked-users') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _AccountListPage(
            title: title,
            language: widget.language,
            load: (page) => _api.get(path),
            onAction: _unblock,
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AccountListPage(
          title: title,
          language: widget.language,
          load: (page) => _api.get('$path?page=$page'),
          onAction: path.endsWith('notifications') ? _markRead : null,
        ),
      ),
    );
  }

  Future<void> _revokeSession(Map<String, dynamic> row) async {
    final id = row['id'] as String?;
    if (id == null) return;
    final result = await _api.delete('sessions/$id');
    if (result['current'] == true) widget.auth.expireSession();
  }

  Future<void> _unblock(Map<String, dynamic> row) async {
    final id = (row['blockedId'] ?? row['blocked_id'] ?? row['id']) as String?;
    if (id != null) await _api.delete('blocked-users/$id');
  }

  Future<void> _markRead(Map<String, dynamic> row) async {
    final id = row['id'] as String?;
    if (id != null) await _api.markNotificationRead(id);
  }

  Future<void> _editNotificationPreferences() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final response = await _api.get('notification-preferences');
      final prefs = Map<String, dynamic>.from(
        response['preferences'] as Map? ?? const <String, dynamic>{},
      );
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => _NotificationPreferencesSheet(
          language: widget.language,
          preferences: prefs,
          save: (values) => _api.patch('notification-preferences', values),
        ),
      );
    } catch (_) {
      if (mounted) _notice(t('loadError'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPrivacy() async {
    final user = widget.auth.user;
    if (user == null) return;
    final flags = Map<String, dynamic>.from(
      user.profile['privacy'] as Map? ?? const {},
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PrivacySheet(
        language: widget.language,
        initial: flags,
        save: (values) => widget.auth.updateProfile(values),
      ),
    );
  }

  Future<String?> _passwordPrompt({required String title}) async {
    final password = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: password,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(labelText: t('currentPassword')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, password.text),
            child: Text(t('confirm')),
          ),
        ],
      ),
    );
    password.dispose();
    return result;
  }

  Future<void> _changePassword() async {
    final current = await _passwordPrompt(title: t('changePassword'));
    if (current == null || current.isEmpty) return;
    if (!context.mounted) return;
    final newPassword = TextEditingController();
    final confirm = TextEditingController();
    final value = await showDialog<(String, String)>(
      // The current credential prompt above was awaited and the State was
      // checked before this dialog is opened.
      // ignore: use_build_context_synchronously
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('changePassword')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: newPassword,
              obscureText: true,
              decoration: InputDecoration(labelText: t('newPassword')),
            ),
            TextField(
              controller: confirm,
              obscureText: true,
              decoration: InputDecoration(labelText: t('confirmPassword')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, (newPassword.text, confirm.text)),
            child: Text(t('save')),
          ),
        ],
      ),
    );
    newPassword.dispose();
    confirm.dispose();
    if (value == null) return;
    if (value.$1.length < 12 ||
        !RegExp(r'[A-Za-z]').hasMatch(value.$1) ||
        !RegExp(r'\d').hasMatch(value.$1) ||
        value.$1 != value.$2) {
      _notice(t('err_password'));
      return;
    }
    try {
      await _api.post('change-password', {
        'currentPassword': current,
        'newPassword': value.$1,
      });
      if (mounted) _notice(t('passwordChanged'));
    } catch (_) {
      if (mounted) _notice(t('err_credentials'));
    }
  }

  Future<void> _deleteAccount() async {
    final days = widget.auth.capabilities['deletionRetentionDays'];
    if (days is! int) return;
    final password = await _passwordPrompt(title: t('deleteTitle'));
    if (password == null || password.isEmpty) return;
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      // The secure re-authentication prompt above was awaited and State remains
      // current for this confirmed action.
      // ignore: use_build_context_synchronously
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('deleteTitle')),
        content: Text(t('deleteBody', {'days': '$days'})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('cancel')),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('deleteAccount')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final result = await _api.post('delete-account', {
        'currentPassword': password,
        'confirmation': true,
      });
      if (mounted) {
        _notice(
          t('deleteRequested', {'date': '${result['scheduledFor'] ?? ''}'}),
        );
        widget.auth.expireSession();
      }
    } catch (_) {
      if (mounted) _notice(t('err_credentials'));
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('logout')),
        content: Text(t('logoutConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('logout')),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.auth.logout();
  }

  Future<void> _exportData() async {
    final password = await _passwordPrompt(title: t('exportTitle'));
    if (password == null || password.isEmpty) return;
    try {
      final data = await _api.post('data-export', {
        'currentPassword': password,
      });
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/orakzai-account-data.json');
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
        flush: true,
      );
      if (!mounted) return;
      _notice(t('exportReady'));
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          title: t('exportTitle'),
        ),
      );
    } catch (_) {
      if (mounted) _notice(t('err_credentials'));
    }
  }

  Future<void> _openPolicy(String name) async {
    final legal = Map<String, dynamic>.from(
      widget.auth.capabilities['legal'] as Map? ?? const <String, dynamic>{},
    );
    final uri = Uri.tryParse(
      '${legal[name == 'terms' ? 'termsUrl' : 'privacyUrl'] ?? ''}',
    );
    if (uri == null || uri.scheme != 'https') {
      _notice(t('policyNotConfigured'));
      return;
    }
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          mounted) {
        _notice(t('openFailed'));
      }
    } catch (_) {
      if (mounted) _notice(t('openFailed'));
    }
  }

  Future<void> _about() async {
    String version = t('versionUnavailable');
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version} (${info.buildNumber})';
    } catch (_) {}
    if (!mounted) return;
    showAboutDialog(
      context: context,
      applicationName: 'ORAKZAI.ORG',
      applicationVersion: version,
      applicationIcon: Image.asset(
        'assets/images/orakzai_emblem.png',
        width: 52,
      ),
      children: [Text(t('aboutBody'))],
    );
  }

  Future<void> _showVersion() async {
    var version = t('versionUnavailable');
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version} (${info.buildNumber})';
    } catch (_) {}
    if (mounted) _notice('${t('appVersion')}: $version');
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AccountListPage extends StatefulWidget {
  const _AccountListPage({
    required this.title,
    required this.language,
    required this.load,
    this.onAction,
  });
  final String title;
  final AppLanguage language;
  final Future<Map<String, dynamic>> Function(int page) load;
  final Future<void> Function(Map<String, dynamic> row)? onAction;
  @override
  State<_AccountListPage> createState() => _AccountListPageState();
}

class _AccountListPageState extends State<_AccountListPage> {
  final List<Map<String, dynamic>> _items = [];
  int _page = 1;
  bool _loading = false;
  bool _failed = false;
  bool _hasMore = true;
  String t(String key) => AccountStrings.text(widget.language, key);
  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final result = await widget.load(_page);
      final raw = result['items'];
      final rows = raw is List
          ? raw
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _items.addAll(rows);
        _hasMore = result['nextPage'] != null;
        _page = (result['nextPage'] as int?) ?? (_page + 1);
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: RefreshIndicator(
      onRefresh: () async {
        setState(() => _items.clear());
        _page = 1;
        _hasMore = true;
        await _fetch();
      },
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount:
            _items.length + (_failed || _items.isEmpty || _hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 9),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            if (_failed) {
              return Center(
                child: TextButton.icon(
                  onPressed: _fetch,
                  icon: const Icon(Icons.refresh),
                  label: Text(t('retry')),
                ),
              );
            }
            if (_items.isEmpty && !_loading) {
              return Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    const Icon(
                      Icons.inbox_outlined,
                      size: 38,
                      color: AppColors.muted,
                    ),
                    const SizedBox(height: 12),
                    Text(t('emptyTitle')),
                    Text(t('emptyBody'), textAlign: TextAlign.center),
                  ],
                ),
              );
            }
            if (_loading) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(22),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            return Center(
              child: TextButton(onPressed: _fetch, child: Text(t('loadMore'))),
            );
          }
          final row = _items[index];
          final title = (row['title'] ?? row['name'] ?? row['reference'] ?? '')
              .toString();
          final body =
              (row['body'] ?? row['description'] ?? row['status'] ?? '')
                  .toString();
          final date = (row['createdAt'] ?? row['created_at'] ?? '').toString();
          return Card(
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.greenWash,
                child: Icon(Icons.circle_outlined, color: AppColors.navy),
              ),
              title: Text(
                title.isEmpty ? t('notProvided') : title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [body, date].where((v) => v.isNotEmpty).join('\n'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: widget.onAction == null
                  ? null
                  : IconButton(
                      tooltip: row['isCurrent'] == true
                          ? t('sessionCurrent')
                          : t(
                              widget.title == t('blockedUsers')
                                  ? 'unblock'
                                  : 'revoke',
                            ),
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(widget.title),
                            content: Text(
                              row['isCurrent'] == true
                                  ? t('revokeConfirm')
                                  : t('confirm'),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: Text(t('cancel')),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: Text(t('confirm')),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                        try {
                          await widget.onAction!(row);
                          if (mounted) {
                            setState(() => _items.removeAt(index));
                          }
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(t('err_generic'))),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.more_horiz_rounded),
                    ),
            ),
          );
        },
      ),
    ),
  );
}

class _NotificationPreferencesSheet extends StatefulWidget {
  const _NotificationPreferencesSheet({
    required this.language,
    required this.preferences,
    required this.save,
  });
  final AppLanguage language;
  final Map<String, dynamic> preferences;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) save;
  @override
  State<_NotificationPreferencesSheet> createState() =>
      _NotificationPreferencesSheetState();
}

class _NotificationPreferencesSheetState
    extends State<_NotificationPreferencesSheet> {
  final Map<String, dynamic> _values = {};
  bool _saving = false;
  String t(String key) => AccountStrings.text(widget.language, key);

  @override
  void initState() {
    super.initState();
    _values.addAll(widget.preferences);
  }

  @override
  Widget build(BuildContext context) {
    final names = {
      'privateMessages': 'privateMessages',
      'groupMessages': 'groupMessages',
      'groupInvitations': 'groupInvitations',
      'commentsAndReplies': 'commentsAndReplies',
      'postReactions': 'postReactions',
      'announcements': 'announcements',
      'moderatorActions': 'moderatorActions',
    };
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          18,
          16,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t('notificationPrefs'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final entry in names.entries)
              SwitchListTile(
                value: _values[entry.key] == true,
                title: Text(t(entry.value)),
                onChanged: (value) =>
                    setState(() => _values[entry.key] = value),
              ),
            FilledButton(
              onPressed: _saving
                  ? null
                  : () async {
                      setState(() => _saving = true);
                      try {
                        await widget.save(_values);
                        if (context.mounted) Navigator.pop(context);
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(t('err_generic'))),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _saving = false);
                      }
                    },
              child: Text(_saving ? '…' : t('save')),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacySheet extends StatefulWidget {
  const _PrivacySheet({
    required this.language,
    required this.initial,
    required this.save,
  });
  final AppLanguage language;
  final Map<String, dynamic> initial;
  final Future<void> Function(Map<String, dynamic>) save;
  @override
  State<_PrivacySheet> createState() => _PrivacySheetState();
}

class _PrivacySheetState extends State<_PrivacySheet> {
  late final Map<String, dynamic> _flags = Map.from(widget.initial);
  bool _saving = false;
  String t(String key) => AccountStrings.text(widget.language, key);
  @override
  Widget build(BuildContext context) {
    final labels = {
      'showCityPublicly': 'showCityPublicly',
      'showProfessionPublicly': 'showProfessionPublicly',
      'showSkillsPublicly': 'showSkillsPublicly',
      'showEducationPublicly': 'showEducationPublicly',
      'allowProfileSearch': 'allowProfileSearch',
    };
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t('privacySettings'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final entry in labels.entries)
              SwitchListTile(
                value: _flags[entry.key] == true,
                title: Text(t(entry.value)),
                onChanged: (value) => setState(() => _flags[entry.key] = value),
              ),
            FilledButton(
              onPressed: _saving
                  ? null
                  : () async {
                      setState(() => _saving = true);
                      try {
                        await widget.save(_flags);
                        if (context.mounted) Navigator.pop(context);
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(t('err_generic'))),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _saving = false);
                      }
                    },
              child: Text(_saving ? '…' : t('save')),
            ),
          ],
        ),
      ),
    );
  }
}
