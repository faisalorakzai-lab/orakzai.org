import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../auth/auth_api.dart';
import '../auth/auth_controller.dart';
import '../widgets/app_components.dart';

enum _AuthView { login, register, verifyEmail, forgotPassword, resetPassword }

class AuthFlowScreen extends StatefulWidget {
  const AuthFlowScreen({required this.auth, super.key});

  final AuthController auth;

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
  _AuthView _view = _AuthView.login;
  bool _busy = false;
  bool _showPassword = false;
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_notice != null) ...[
          InfoBanner(
            title: 'Account update',
            message: _notice!,
            icon: Icons.mark_email_read_outlined,
            background: AppColors.greenWash,
            foreground: AppColors.green,
          ),
          const SizedBox(height: 14),
        ],
        if (_error != null) ...[
          InfoBanner(
            title: 'Could not complete',
            message: _error!,
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
                  onPressed: _busy ? null : _submit,
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
          const SizedBox(height: 12),
          Text(
            'More sign-in options',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 9),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.g_mobiledata_rounded),
              label: const Text('Google sign-in · not configured'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('Wallet sign-in · not configured'),
            ),
          ),
        ],
      ],
    );
  }

  String get _primaryAction => switch (_view) {
    _AuthView.login => 'Sign in',
    _AuthView.register => 'Create account',
    _AuthView.verifyEmail => 'Verify email',
    _AuthView.forgotPassword => 'Send reset code',
    _AuthView.resetPassword => 'Reset password',
  };

  Widget _loginFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(
          controller: _identifier,
          label: 'Email or phone number',
          hint: 'name@example.org or +923001234567',
          keyboardType: TextInputType.emailAddress,
          validator: (value) => value == null || value.trim().length < 3
              ? 'Enter your email or phone.'
              : null,
        ),
        const SizedBox(height: 13),
        _passwordField(
          controller: _password,
          label: 'Password',
          validator: (value) =>
              value == null || value.isEmpty ? 'Enter your password.' : null,
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
          label: 'Full name',
          validator: (value) => value == null || value.trim().length < 2
              ? 'Enter your full name.'
              : null,
        ),
        const SizedBox(height: 13),
        _field(
          controller: _email,
          label: 'Email address',
          keyboardType: TextInputType.emailAddress,
          validator: _validateEmail,
        ),
        const SizedBox(height: 13),
        _field(
          controller: _phone,
          label: 'Phone number',
          hint: 'Include country code, e.g. +923001234567',
          keyboardType: TextInputType.phone,
          validator: (value) =>
              value == null ||
                  !RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value.trim())
              ? 'Use international phone format, e.g. +923001234567.'
              : null,
        ),
        const SizedBox(height: 13),
        _passwordField(
          controller: _password,
          label: 'Password',
          validator: _validatePassword,
        ),
        const SizedBox(height: 8),
        Text(
          'Use at least 12 characters with a letter and a number.',
          style: Theme.of(context).textTheme.bodyMedium,
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
          );
          break;
        case _AuthView.register:
          await widget.auth.register(
            fullName: _name.text.trim(),
            email: _email.text.trim(),
            phone: _phone.text.trim(),
            password: _password.text,
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
            ? error.message
            : 'The request could not be completed. Please try again.';
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
            ? error.message
            : 'The request could not be completed. Please try again.';
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
      return 'Enter a valid email address.';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.length < 12) {
      return 'Use at least 12 characters.';
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(value) ||
        !RegExp(r'\d').hasMatch(value)) {
      return 'Include at least one letter and one number.';
    }
    return null;
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
