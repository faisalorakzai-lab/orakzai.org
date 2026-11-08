import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../account/account_strings.dart';
import '../app/app_language.dart';
import '../app/app_theme.dart';
import '../auth/auth_api.dart';
import '../auth/auth_controller.dart';
import '../widgets/app_components.dart';

enum _AuthView { login, register, verifyEmail, forgotPassword, resetPassword }

class AuthFlowScreen extends StatefulWidget {
  const AuthFlowScreen({
    required this.auth,
    this.language = AppLanguage.english,
    super.key,
  });

  final AuthController auth;
  final AppLanguage language;

  @override
  State<AuthFlowScreen> createState() => _AuthFlowScreenState();
}

class _AuthFlowScreenState extends State<AuthFlowScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _country = TextEditingController();
  final _region = TextEditingController();
  final _district = TextEditingController();
  _AuthView _view = _AuthView.login;
  bool _busy = false;
  bool _showPassword = false;
  bool _acceptedTerms = false;
  bool _rememberSession = true;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _identifier.dispose();
    _password.dispose();
    _code.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    _country.dispose();
    _region.dispose();
    _district.dispose();
    super.dispose();
  }

  String _t(String key, [Map<String, String>? args]) =>
      AccountStrings.text(widget.language, key, args);

  String _errorCopy(AuthApiException error) => switch (error.code) {
    'INVALID_CREDENTIALS' ||
    'AUTHENTICATION_FAILED' => _t('err_invalid_credentials'),
    'EMAIL_ALREADY_EXISTS' ||
    'PHONE_ALREADY_EXISTS' ||
    'DUPLICATE_EMAIL' ||
    'DUPLICATE_PHONE' => _t('err_duplicate'),
    'EMAIL_NOT_VERIFIED' ||
    'EMAIL_VERIFICATION_REQUIRED' => _t('err_not_verified'),
    'INVALID_VERIFICATION_CODE' ||
    'INVALID_RESET_CODE' ||
    'INVALID_CODE' => _t('err_invalid_code'),
    'RATE_LIMITED' || 'TOO_MANY_REQUESTS' => _t('err_rate_limited'),
    'NETWORK_ERROR' => _t('err_network'),
    'SESSION_EXPIRED' || 'UNAUTHENTICATED' => _t('err_session'),
    'REGISTRATION_NOT_AVAILABLE' ||
    'EMAIL_DELIVERY_NOT_CONFIGURED' ||
    'RETENTION_POLICY_NOT_CONFIGURED' => _t('err_unavailable'),
    'PASSWORD_MISMATCH' => _t('err_wrong_password'),
    'FORBIDDEN' || 'PERMISSION_DENIED' => _t('err_forbidden'),
    'VALIDATION_ERROR' => _t('err_validation'),
    _ => _t('err_generic'),
  };

  Future<void> _openLegal(String kind) async {
    final legal = Map<String, dynamic>.from(
      widget.auth.capabilities['legal'] as Map? ?? const {},
    );
    final value = legal[kind == 'terms' ? 'termsUrl' : 'privacyUrl'];
    final uri = Uri.tryParse('$value');
    if (uri == null || uri.scheme != 'https') return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_notice != null) ...[
          InfoBanner(
            title: _t('accountCreated'),
            message: _notice!,
            icon: Icons.mark_email_read_outlined,
            background: AppColors.greenWash,
            foreground: AppColors.green,
          ),
          const SizedBox(height: 14),
        ],
        if (_error != null) ...[
          InfoBanner(
            title: _t('err_generic'),
            message: _t(_error!),
            icon: Icons.error_outline_rounded,
            background: AppColors.dangerWash,
            foreground: AppColors.danger,
          ),
          const SizedBox(height: 14),
        ],
        if (widget.auth.lastDevelopmentCode != null &&
            (_view == _AuthView.verifyEmail ||
                _view == _AuthView.resetPassword))
          _DevelopmentCodeCard(
            purpose: widget.auth.lastDevelopmentCodePurpose ?? 'security',
            code: widget.auth.lastDevelopmentCode!,
          ),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_view == _AuthView.login) _loginFields(),
              if (_view == _AuthView.register) _registerFields(),
              if (_view == _AuthView.verifyEmail) _verificationFields(),
              if (_view == _AuthView.forgotPassword) _forgotFields(),
              if (_view == _AuthView.resetPassword) _resetFields(),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed:
                      _busy || (_view == _AuthView.register && !_acceptedTerms)
                      ? null
                      : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(_primaryAction),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _secondaryActions(),
        if (_view == _AuthView.login || _view == _AuthView.register) ...[
          const SizedBox(height: 20),
          const Divider(),
        ],
      ],
    );
  }

  String get _primaryAction => switch (_view) {
    _AuthView.login => _t('signIn'),
    _AuthView.register => _t('createAccount'),
    _AuthView.verifyEmail => _t('verifyEmail'),
    _AuthView.forgotPassword => _t('sendResetCode'),
    _AuthView.resetPassword => _t('resetPasswordAction'),
  };

  Widget _loginFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(
          controller: _identifier,
          label: _t('identifier'),
          hint: _t('identifierHint'),
          keyboardType: TextInputType.emailAddress,
          validator: (value) => value == null || value.trim().length < 3
              ? _t('vIdentifier')
              : null,
        ),
        const SizedBox(height: 13),
        _passwordField(
          controller: _password,
          label: _t('password'),
          validator: (value) =>
              value == null || value.isEmpty ? _t('vRequired') : null,
        ),
        const SizedBox(height: 6),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _rememberSession,
          onChanged: (value) =>
              setState(() => _rememberSession = value ?? false),
          title: Text(_t('rememberSession')),
          controlAffinity: ListTileControlAffinity.leading,
        ),
      ],
    );
  }

  Widget _registerFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(
          controller: _name,
          label: _t('fullName'),
          validator: (value) =>
              value == null || value.trim().length < 2 ? _t('vName') : null,
        ),
        const SizedBox(height: 13),
        _field(
          controller: _email,
          label: _t('email'),
          keyboardType: TextInputType.emailAddress,
          validator: _validateEmail,
        ),
        const SizedBox(height: 13),
        _field(
          controller: _phone,
          label: _t('phone'),
          hint: _t('phoneHint'),
          keyboardType: TextInputType.phone,
          validator: (value) =>
              value == null ||
                  !RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value.trim())
              ? _t('vPhone')
              : null,
        ),
        const SizedBox(height: 13),
        _field(
          controller: _country,
          label: _t('country'),
          validator: (value) =>
              value == null || value.trim().length < 2 ? _t('vRequired') : null,
        ),
        const SizedBox(height: 13),
        Row(
          children: [
            Expanded(
              child: _field(controller: _region, label: _t('region')),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _field(controller: _district, label: _t('district')),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(top: 5, bottom: 8),
          child: Text(
            _t('locationOptional'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        _passwordField(
          controller: _password,
          label: _t('password'),
          validator: _validatePassword,
        ),
        const SizedBox(height: 8),
        Text(_t('passwordRule'), style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _password,
          builder: (context, value, _) {
            final score = _passwordStrength(value.text);
            final label = _t('strength$score');
            return Semantics(
              liveRegion: true,
              label: '${_t('passwordStrength')}: $label',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: value.text.isEmpty ? 0 : score / 4,
                    minHeight: 5,
                    color: score < 2 ? AppColors.gold : AppColors.green,
                    backgroundColor: AppColors.greenWash,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_t('passwordStrength')}: $label',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _passwordField(
          controller: _confirmPassword,
          label: _t('confirmPassword'),
          validator: (value) =>
              value != _password.text ? _t('vMismatch') : null,
        ),
        const SizedBox(height: 10),
        if (widget.auth.developmentMode)
          InfoBanner(
            title: _t('policyDraftNotice'),
            message: _t('acknowledgeDraft'),
            icon: Icons.policy_outlined,
            background: AppColors.goldWash,
            foreground: AppColors.goldDeep,
          ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _acceptedTerms,
          onChanged: (value) => setState(() => _acceptedTerms = value ?? false),
          title: Text(
            widget.auth.developmentMode
                ? _t('acknowledgeDraft')
                : _t('acceptTerms'),
          ),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => _openLegal('terms'),
              child: Text(_t('readTerms')),
            ),
            TextButton(
              onPressed: () => _openLegal('privacy'),
              child: Text(_t('readPrivacy')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _verificationFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(
          controller: _email,
          label: 'Email address',
          keyboardType: TextInputType.emailAddress,
          validator: _validateEmail,
        ),
        const SizedBox(height: 13),
        _field(
          controller: _code,
          label: '6-digit verification code',
          keyboardType: TextInputType.number,
          validator: (value) =>
              value == null || !RegExp(r'^\d{6}$').hasMatch(value.trim())
              ? 'Enter the 6-digit code from your email.'
              : null,
        ),
      ],
    );
  }

  Widget _forgotFields() {
    return _field(
      controller: _email,
      label: 'Email address',
      keyboardType: TextInputType.emailAddress,
      validator: _validateEmail,
    );
  }

  Widget _resetFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(
          controller: _email,
          label: 'Email address',
          keyboardType: TextInputType.emailAddress,
          validator: _validateEmail,
        ),
        const SizedBox(height: 13),
        _field(
          controller: _code,
          label: '6-digit password reset code',
          keyboardType: TextInputType.number,
          validator: (value) =>
              value == null || !RegExp(r'^\d{6}$').hasMatch(value.trim())
              ? 'Enter the 6-digit code from your email.'
              : null,
        ),
        const SizedBox(height: 13),
        _passwordField(
          controller: _newPassword,
          label: 'New password',
          validator: _validatePassword,
        ),
        const SizedBox(height: 13),
        _passwordField(
          controller: _confirmPassword,
          label: 'Confirm new password',
          validator: (value) =>
              value != _newPassword.text ? 'Passwords do not match.' : null,
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: TextCapitalization.none,
      autocorrect: false,
      validator: validator,
      decoration: InputDecoration(labelText: label, hintText: hint),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: !_showPassword,
      autocorrect: false,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          tooltip: _showPassword ? 'Hide password' : 'Show password',
          onPressed: () => setState(() => _showPassword = !_showPassword),
          icon: Icon(
            _showPassword
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
        ),
      ),
    );
  }

  Widget _secondaryActions() {
    switch (_view) {
      case _AuthView.login:
        return Wrap(
          alignment: WrapAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () => _switchTo(_AuthView.register),
              child: const Text('Create account'),
            ),
            TextButton(
              onPressed: () => _switchTo(_AuthView.forgotPassword),
              child: const Text('Forgot password?'),
            ),
          ],
        );
      case _AuthView.register:
        return TextButton(
          onPressed: () => _switchTo(_AuthView.login),
          child: const Text('Already have an account? Sign in'),
        );
      case _AuthView.verifyEmail:
        return Wrap(
          children: [
            TextButton(
              onPressed: _busy ? null : _resendCode,
              child: const Text('Resend verification code'),
            ),
            TextButton(
              onPressed: () => _switchTo(_AuthView.login),
              child: const Text('Back to sign in'),
            ),
          ],
        );
      case _AuthView.forgotPassword:
        return TextButton(
          onPressed: () => _switchTo(_AuthView.login),
          child: const Text('Back to sign in'),
        );
      case _AuthView.resetPassword:
        return TextButton(
          onPressed: () => _switchTo(_AuthView.forgotPassword),
          child: const Text('Request another reset code'),
        );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      switch (_view) {
        case _AuthView.login:
          await widget.auth.login(
            identifier: _identifier.text.trim(),
            password: _password.text,
            rememberSession: _rememberSession,
          );
          break;
        case _AuthView.register:
          await widget.auth.register(
            fullName: _name.text.trim(),
            email: _email.text.trim(),
            phone: _phone.text.trim(),
            password: _password.text,
            country: _country.text.trim(),
            region: _region.text.trim(),
            district: _district.text.trim(),
            acceptedTerms: _acceptedTerms,
          );
          setState(() {
            _view = _AuthView.verifyEmail;
            _notice =
                'Account created. Enter the verification code sent to your email.';
          });
          break;
        case _AuthView.verifyEmail:
          await widget.auth.verifyEmail(
            email: _email.text.trim(),
            code: _code.text.trim(),
          );
          setState(() {
            _view = _AuthView.login;
            _identifier.text = _email.text.trim();
            _notice = 'Email verified. Sign in to continue.';
          });
          break;
        case _AuthView.forgotPassword:
          await widget.auth.requestPasswordReset(_email.text.trim());
          setState(() {
            _view = _AuthView.resetPassword;
            _notice =
                'If an account matches, a reset code will be sent. Enter the code from your email.';
          });
          break;
        case _AuthView.resetPassword:
          await widget.auth.resetPassword(
            email: _email.text.trim(),
            code: _code.text.trim(),
            newPassword: _newPassword.text,
          );
          setState(() {
            _view = _AuthView.login;
            _identifier.text = _email.text.trim();
            _password.clear();
            _notice = 'Password reset. Sign in with your new password.';
          });
          break;
      }
    } catch (error) {
      setState(() {
        _error = error is AuthApiException
            ? _errorCopy(error)
            : _t('err_generic');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendCode() async {
    final emailError = _validateEmail(_email.text);
    if (emailError != null) {
      setState(() => _error = emailError);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.auth.resendVerification(_email.text.trim());
      setState(() {
        _notice = 'If the account needs verification, a code will be sent.';
      });
    } catch (error) {
      setState(() {
        _error = error is AuthApiException
            ? _errorCopy(error)
            : _t('err_generic');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _switchTo(_AuthView view) {
    setState(() {
      _view = view;
      _error = null;
      _notice = null;
      if (view == _AuthView.verifyEmail && _email.text.isEmpty) {
        _email.text = _identifier.text.contains('@')
            ? _identifier.text.trim()
            : '';
      }
    });
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return _t('vEmail');
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.length < 12) {
      return _t('vPassword12');
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(value) ||
        !RegExp(r'\d').hasMatch(value)) {
      return _t('vPasswordMix');
    }
    return null;
  }

  int _passwordStrength(String value) {
    if (value.isEmpty) return 0;
    var score = 0;
    if (value.length >= 8) score++;
    if (value.length >= 12) score++;
    if (RegExp(r'[A-Za-z]').hasMatch(value) && RegExp(r'\d').hasMatch(value)) {
      score++;
    }
    if ((RegExp(r'[a-z]').hasMatch(value) &&
            RegExp(r'[A-Z]').hasMatch(value)) ||
        RegExp(r'[^A-Za-z0-9]').hasMatch(value)) {
      score++;
    }
    return score;
  }
}

class _DevelopmentCodeCard extends StatelessWidget {
  const _DevelopmentCodeCard({required this.purpose, required this.code});

  final String purpose;
  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.goldWash,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.developer_mode_rounded, color: AppColors.navy),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Development-only $purpose code',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                SelectableText(
                  code,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
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
