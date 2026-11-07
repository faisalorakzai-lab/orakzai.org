import 'package:flutter/material.dart';

import '../app/app_language.dart';
import '../app/app_theme.dart';
import '../auth/app_user.dart';
import '../auth/auth_controller.dart';
import '../widgets/app_components.dart';
import 'auth_flow_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    required this.language,
    required this.onLanguageChanged,
    required this.authController,
    super.key,
  });

  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final AuthController authController;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _notificationsEnabled = false;
  bool _profileUpdateBusy = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.authController,
      builder: (context, _) {
        final auth = widget.authController;
        return AppPage(
          title: AppCopy.text(widget.language, 'profile'),
          subtitle: auth.isAuthenticated
              ? 'Your private account and privacy settings.'
              : 'Sign in or create an account to manage your private profile.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (auth.status == AuthStatus.restoring)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 36),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (auth.isAuthenticated && auth.user != null)
                _signedInProfile(auth.user!)
              else
                AuthFlowScreen(auth: auth),
              const SizedBox(height: 22),
              SectionHeading(title: AppCopy.text(widget.language, 'language')),
              Text(
                'English is fully available. Urdu and Pashto navigation and home controls are translated; the remaining account text is currently English.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AppLanguage.values
                    .map(
                      (language) => ChoiceChip(
                        label: Text(language.displayName),
                        selected: widget.language == language,
                        onSelected: (_) => widget.onLanguageChanged(language),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _signedInProfile(AppUser user) {
    final auth = widget.authController;
    final privacy = Map<String, dynamic>.from(
      user.profile['privacy'] as Map? ?? const {},
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AccountCard(user: user),
        const SizedBox(height: 17),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Profile details',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _profileUpdateBusy
                        ? null
                        : () => _editProfile(user),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _DetailRow(
                label: 'Username',
                value: _textOrUnset(user.profile['username']),
              ),
              _DetailRow(label: 'Phone', value: user.phone),
              _DetailRow(label: 'City', value: _textOrUnset(user.city)),
              _DetailRow(label: 'Country', value: _textOrUnset(user.country)),
              _DetailRow(
                label: 'Profession',
                value: _textOrUnset(user.profile['profession']),
              ),
              _DetailRow(
                label: 'Education',
                value: _textOrUnset(user.profile['education']),
              ),
              _DetailRow(
                label: 'Skills',
                value: (user.profile['skills'] as List? ?? const []).join(', '),
              ),
              _DetailRow(
                label: 'Biography',
                value: _textOrUnset(user.profile['biography']),
              ),
              _DetailRow(
                label: 'Member ID',
                value: user.memberId ?? 'Not assigned by the organization',
              ),
              _DetailRow(
                label: 'Account verification',
                value: user.emailVerified
                    ? 'Email verified'
                    : 'Email not verified',
              ),
              _DetailRow(
                label: 'Organization role',
                value: _displayRoles(auth.roles),
              ),
            ],
          ),
        ),
        if (user.regionAssignments.isNotEmpty) ...[
          const SizedBox(height: 17),
          const SectionHeading(title: 'Assigned community region'),
          ...user.regionAssignments.map(
            (assignment) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InfoBanner(
                title:
                    [
                          assignment['village'],
                          assignment['qoum'],
                          assignment['district'],
                          assignment['region'],
                        ]
                        .whereType<String>()
                        .where((value) => value.isNotEmpty)
                        .join(' · '),
                message: assignment['primary'] == true
                    ? 'Primary organization assignment'
                    : 'Organization assignment',
                icon: Icons.place_outlined,
                background: AppColors.greenWash,
                foreground: AppColors.green,
              ),
            ),
          ),
        ],
        const SizedBox(height: 17),
        const SectionHeading(title: 'Profile privacy'),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            children: [
              _PrivacyToggle(
                title: 'Show city publicly',
                value: privacy['showCityPublicly'] == true,
                onChanged: (value) => _updatePrivacy('showCityPublicly', value),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _PrivacyToggle(
                title: 'Show profession publicly',
                value: privacy['showProfessionPublicly'] == true,
                onChanged: (value) =>
                    _updatePrivacy('showProfessionPublicly', value),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _PrivacyToggle(
                title: 'Show skills publicly',
                value: privacy['showSkillsPublicly'] == true,
                onChanged: (value) =>
                    _updatePrivacy('showSkillsPublicly', value),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _PrivacyToggle(
                title: 'Show education publicly',
                value: privacy['showEducationPublicly'] == true,
                onChanged: (value) =>
                    _updatePrivacy('showEducationPublicly', value),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _PrivacyToggle(
                title: 'Allow profile search',
                value: privacy['allowProfileSearch'] == true,
                onChanged: (value) =>
                    _updatePrivacy('allowProfileSearch', value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const InfoBanner(
          title: 'Contact details stay private',
          message:
              'Email and phone are shown only in your signed-in account. They are not editable from the public profile controls.',
          icon: Icons.privacy_tip_outlined,
          background: AppColors.greenWash,
          foreground: AppColors.green,
        ),
        const SizedBox(height: 17),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            children: [
              SwitchListTile(
                value: _notificationsEnabled,
                onChanged: (value) =>
                    setState(() => _notificationsEnabled = value),
                title: const Text('Notification preference'),
                subtitle: const Text(
                  'Local device preview only; push delivery is not configured.',
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.lock_outline_rounded),
                title: const Text('Change password'),
                subtitle: const Text(
                  'Use the password reset flow from sign-in.',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Sign out and choose “Forgot password?” to reset it.',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              try {
                await auth.logout();
              } catch (_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Signed out on this device.')),
                );
              }
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  String _textOrUnset(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value;
    return 'Not provided';
  }

  String _displayRoles(List<String> roles) {
    if (roles.isEmpty) return 'Standard Member';
    return roles
        .map((role) {
          return role
              .split('_')
              .map(
                (word) => word.isEmpty
                    ? word
                    : '${word[0].toUpperCase()}${word.substring(1)}',
              )
              .join(' ');
        })
        .join(', ');
  }

  Future<void> _editProfile(AppUser user) async {
    final updates = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _ProfileEditDialog(user: user),
    );
    if (updates == null) return;
    setState(() => _profileUpdateBusy = true);
    try {
      await widget.authController.updateProfile(updates);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _profileUpdateBusy = false);
    }
  }

  Future<void> _updatePrivacy(String field, bool value) async {
    try {
      await widget.authController.updateProfile({field: value});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.gold, width: 1.5),
            ),
            child: ClipOval(
              child: user.profilePhotoUrl == null
                  ? const ColoredBox(
                      color: AppColors.navySoft,
                      child: Icon(
                        Icons.person_outline_rounded,
                        color: AppColors.gold,
                        size: 30,
                      ),
                    )
                  : Image.network(
                      user.profilePhotoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const ColoredBox(
                            color: AppColors.navySoft,
                            child: Icon(
                              Icons.person_outline_rounded,
                              color: AppColors.gold,
                              size: 30,
                            ),
                          ),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.fullName,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  user.email,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  user.emailVerified ? 'EMAIL VERIFIED' : 'EMAIL NOT VERIFIED',
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? 'Not provided' : value,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyToggle extends StatelessWidget {
  const _PrivacyToggle({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeTrackColor: AppColors.green,
      title: Text(title),
      subtitle: Text(
        value ? 'Visible to approved public profile views' : 'Private',
      ),
    );
  }
}

class _ProfileEditDialog extends StatefulWidget {
  const _ProfileEditDialog({required this.user});

  final AppUser user;

  @override
  State<_ProfileEditDialog> createState() => _ProfileEditDialogState();
}

class _ProfileEditDialogState extends State<_ProfileEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullName;
  late final TextEditingController _username;
  late final TextEditingController _photoUrl;
  late final TextEditingController _city;
  late final TextEditingController _country;
  late final TextEditingController _profession;
  late final TextEditingController _skills;
  late final TextEditingController _education;
  late final TextEditingController _biography;

  @override
  void initState() {
    super.initState();
    final profile = widget.user.profile;
    _fullName = TextEditingController(text: widget.user.fullName);
    _username = TextEditingController(
      text: profile['username'] as String? ?? '',
    );
    _photoUrl = TextEditingController(
      text: profile['profilePhotoUrl'] as String? ?? '',
    );
    _city = TextEditingController(text: widget.user.city ?? '');
    _country = TextEditingController(text: widget.user.country ?? '');
    _profession = TextEditingController(
      text: profile['profession'] as String? ?? '',
    );
    _skills = TextEditingController(
      text: (profile['skills'] as List? ?? const []).join(', '),
    );
    _education = TextEditingController(
      text: profile['education'] as String? ?? '',
    );
    _biography = TextEditingController(
      text: profile['biography'] as String? ?? '',
    );
  }

  @override
  void dispose() {
    _fullName.dispose();
    _username.dispose();
    _photoUrl.dispose();
    _city.dispose();
    _country.dispose();
    _profession.dispose();
    _skills.dispose();
    _education.dispose();
    _biography.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit profile'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _textField(
                  _fullName,
                  'Full name',
                  maxLength: 100,
                  required: true,
                ),
                _textField(_username, 'Username', maxLength: 30),
                _textField(
                  _photoUrl,
                  'Profile photo URL',
                  keyboardType: TextInputType.url,
                  maxLength: 2048,
                  hint: 'https://',
                ),
                _textField(_city, 'City', maxLength: 100),
                _textField(_country, 'Country', maxLength: 100),
                _textField(_profession, 'Profession', maxLength: 120),
                _textField(
                  _skills,
                  'Skills',
                  hint: 'Separate skills with commas',
                  maxLength: 500,
                ),
                _textField(_education, 'Education', maxLength: 200),
                _textField(
                  _biography,
                  'Short biography',
                  maxLength: 500,
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                Text(
                  'Photo upload is not connected yet; a URL is stored privately in your profile.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save profile')),
      ],
    );
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    String? hint,
    int? maxLength,
    int maxLines = 1,
    bool required = false,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        maxLength: maxLength,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          counterText: '',
        ),
        validator: (value) {
          if (required && (value == null || value.trim().length < 2)) {
            return 'Enter at least 2 characters.';
          }
          if (controller == _photoUrl &&
              value != null &&
              value.trim().isNotEmpty &&
              !(Uri.tryParse(value.trim())?.hasScheme == true &&
                  Uri.tryParse(value.trim())?.host.isNotEmpty == true)) {
            return 'Enter a valid image URL.';
          }
          return null;
        },
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop({
      'fullName': _fullName.text.trim(),
      'username': _username.text.trim().isEmpty ? null : _username.text.trim(),
      'profilePhotoUrl': _photoUrl.text.trim().isEmpty
          ? null
          : _photoUrl.text.trim(),
      'city': _city.text.trim().isEmpty ? null : _city.text.trim(),
      'country': _country.text.trim().isEmpty ? null : _country.text.trim(),
      'profession': _profession.text.trim().isEmpty
          ? null
          : _profession.text.trim(),
      'skills': _skills.text
          .split(',')
          .map((skill) => skill.trim())
          .where((skill) => skill.isNotEmpty)
          .take(30)
          .toList(),
      'education': _education.text.trim().isEmpty
          ? null
          : _education.text.trim(),
      'biography': _biography.text.trim().isEmpty
          ? null
          : _biography.text.trim(),
    });
  }
}
