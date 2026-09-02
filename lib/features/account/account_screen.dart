import 'package:flutter/material.dart';
import 'package:inknest_notes/auth/account_agreements.dart';
import 'package:inknest_notes/auth/auth_controller.dart';
import 'package:inknest_notes/features/account/account_legal_screen.dart';
import 'package:inknest_notes/features/account/account_security_dialogs.dart';

enum _AuthMode { signIn, register }

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, required this.controller});

  final AuthController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 600;
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 20 : 32,
                    24,
                    compact ? 20 : 32,
                    32,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Card(
                        margin: EdgeInsets.zero,
                        clipBehavior: Clip.antiAlias,
                        child: Padding(
                          padding: EdgeInsets.all(compact ? 22 : 32),
                          child: _AccountContent(controller: controller),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _AccountContent extends StatelessWidget {
  const _AccountContent({required this.controller});

  final AuthController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.status == AuthStatus.restoring) {
      return Semantics(
        liveRegion: true,
        label: 'Restoring account',
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (controller.isSignedIn) {
      return _SignedInAccount(controller: controller);
    }
    return _AuthForm(controller: controller);
  }
}

class _SignedInAccount extends StatelessWidget {
  const _SignedInAccount({required this.controller});

  final AuthController controller;

  @override
  Widget build(BuildContext context) {
    final session = controller.session!;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: colorScheme.primaryContainer,
          foregroundColor: colorScheme.onPrimaryContainer,
          child: Text(
            session.user.email.substring(0, 1).toUpperCase(),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Signed in',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        SelectableText(
          session.user.email,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 24),
        _AccountDetail(
          icon: Icons.devices_outlined,
          label: 'Current device',
          value: '${session.device.name} · ${session.device.platform}',
        ),
        if (!controller.agreementsCurrent) ...[
          const SizedBox(height: 16),
          Card(
            color: colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Review required',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Review and accept the current Privacy Policy and Terms before using InkNest Cloud.',
                  ),
                  const SizedBox(height: 8),
                  _LegalLinks(),
                  const SizedBox(height: 8),
                  FilledButton(
                    key: const ValueKey('account-accept-agreements'),
                    onPressed: controller.isBusy
                        ? null
                        : controller.acceptCurrentAgreements,
                    child: const Text('Accept current agreements'),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'Signing out removes this cloud session only. Notes stored on this device stay available.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        if (controller.errorMessage case final message?) ...[
          const SizedBox(height: 16),
          _AccountError(message: message),
        ],
        const SizedBox(height: 24),
        Text('Security', style: Theme.of(context).textTheme.titleMedium),
        ListTile(
          key: const ValueKey('account-change-password'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.password_rounded),
          title: const Text('Change password'),
          trailing: const Icon(Icons.chevron_right_rounded),
          enabled: !controller.isBusy,
          onTap: controller.isBusy
              ? null
              : () async {
                  final changed = await showChangePasswordDialog(
                    context,
                    controller,
                  );
                  if (changed && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Password updated. Other devices were signed out.',
                        ),
                      ),
                    );
                  }
                },
        ),
        const SizedBox(height: 12),
        Text('Legal', style: Theme.of(context).textTheme.titleMedium),
        const _LegalDocumentTiles(),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          key: const ValueKey('account-sign-out'),
          onPressed: controller.isBusy ? null : controller.logout,
          icon: controller.isBusy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.logout_rounded),
          label: const Text('Sign out'),
        ),
        const SizedBox(height: 28),
        Divider(color: colorScheme.error.withValues(alpha: 0.45)),
        const SizedBox(height: 12),
        Text(
          'Danger zone',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: colorScheme.error,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Permanently delete this cloud account and its cloud data. Local notes on this device remain.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('account-delete'),
          onPressed: controller.isBusy
              ? null
              : () async {
                  final deleted = await showDeleteAccountFlow(
                    context,
                    controller,
                  );
                  if (deleted && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Account deletion accepted. Local notes remain on this device.',
                        ),
                      ),
                    );
                  }
                },
          style: OutlinedButton.styleFrom(foregroundColor: colorScheme.error),
          icon: const Icon(Icons.delete_forever_rounded),
          label: const Text('Delete account'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: controller.isBusy
              ? null
              : () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _AccountDetail extends StatelessWidget {
  const _AccountDetail({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(value),
    );
  }
}

class _AuthForm extends StatefulWidget {
  const _AuthForm({required this.controller});

  final AuthController controller;

  @override
  State<_AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<_AuthForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  final _passwordFocus = FocusNode();
  final _confirmationFocus = FocusNode();
  _AuthMode _mode = _AuthMode.signIn;
  bool _obscurePassword = true;
  bool _agreementsAccepted = false;
  bool _showAgreementError = false;

  bool get _registering => _mode == _AuthMode.register;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    _passwordFocus.dispose();
    _confirmationFocus.dispose();
    super.dispose();
  }

  void _changeMode(Set<_AuthMode> selected) {
    if (selected.isEmpty || widget.controller.isBusy) {
      return;
    }
    setState(() {
      _mode = selected.single;
      _confirmationController.clear();
      _agreementsAccepted = false;
      _showAgreementError = false;
    });
    widget.controller.clearError();
    _formKey.currentState?.reset();
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_registering && !_agreementsAccepted) {
      setState(() => _showAgreementError = true);
      return;
    }
    final succeeded = _registering
        ? await widget.controller.register(
            email: _emailController.text,
            password: _passwordController.text,
          )
        : await widget.controller.login(
            email: _emailController.text,
            password: _passwordController.text,
          );
    if (succeeded && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.controller.isBusy;
    final colorScheme = Theme.of(context).colorScheme;
    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.cloud_outlined, size: 44, color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              _registering
                  ? 'Create your InkNest account'
                  : 'Sign in to InkNest',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Your local notes remain available even when you are signed out or offline.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            SegmentedButton<_AuthMode>(
              key: const ValueKey('account-auth-mode'),
              segments: const [
                ButtonSegment(value: _AuthMode.signIn, label: Text('Sign in')),
                ButtonSegment(
                  value: _AuthMode.register,
                  label: Text('Create account'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: busy ? null : _changeMode,
            ),
            const SizedBox(height: 24),
            TextFormField(
              key: const ValueKey('account-email'),
              controller: _emailController,
              enabled: !busy,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [
                AutofillHints.username,
                AutofillHints.email,
              ],
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.mail_outline_rounded),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty) {
                  return 'Enter your email address.';
                }
                if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
                  return 'Enter a valid email address.';
                }
                return null;
              },
              onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('account-password'),
              controller: _passwordController,
              focusNode: _passwordFocus,
              enabled: !busy,
              obscureText: _obscurePassword,
              enableSuggestions: false,
              autocorrect: false,
              textInputAction: _registering
                  ? TextInputAction.next
                  : TextInputAction.done,
              autofillHints: [
                _registering
                    ? AutofillHints.newPassword
                    : AutofillHints.password,
              ],
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: _registering ? 'Use at least 8 characters.' : null,
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: busy
                      ? null
                      : () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (value) {
                final password = value ?? '';
                if (password.length < 8) {
                  return 'Password must be at least 8 characters.';
                }
                if (password.length > 128) {
                  return 'Password must be 128 characters or fewer.';
                }
                return null;
              },
              onFieldSubmitted: (_) {
                if (_registering) {
                  _confirmationFocus.requestFocus();
                } else {
                  _submit();
                }
              },
            ),
            if (_registering) ...[
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('account-password-confirmation'),
                controller: _confirmationController,
                focusNode: _confirmationFocus,
                enabled: !busy,
                obscureText: _obscurePassword,
                enableSuggestions: false,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                  prefixIcon: Icon(Icons.lock_reset_rounded),
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value != _passwordController.text
                    ? 'Passwords do not match.'
                    : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                key: const ValueKey('account-agreements'),
                value: _agreementsAccepted,
                enabled: !busy,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'I agree to the Privacy Policy and Terms of Service.',
                ),
                onChanged: (value) => setState(() {
                  _agreementsAccepted = value ?? false;
                  if (_agreementsAccepted) _showAgreementError = false;
                }),
              ),
              const _LegalLinks(),
              if (_showAgreementError)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Review and accept both agreements to create an account.',
                    style: TextStyle(color: colorScheme.error),
                  ),
                ),
            ],
            if (widget.controller.errorMessage case final message?) ...[
              const SizedBox(height: 16),
              _AccountError(message: message),
            ],
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey('account-submit'),
              onPressed: busy ? null : _submit,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(_registering ? 'Create account' : 'Sign in'),
              ),
            ),
            if (!_registering) ...[
              const SizedBox(height: 12),
              const _LegalLinks(),
            ],
          ],
        ),
      ),
    );
  }
}

class _LegalLinks extends StatelessWidget {
  const _LegalLinks();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      children: [
        TextButton(
          key: const ValueKey('account-privacy-policy'),
          onPressed: () =>
              openAccountLegalDocument(context, privacyPolicyDocument),
          child: const Text('Privacy Policy'),
        ),
        TextButton(
          key: const ValueKey('account-terms'),
          onPressed: () =>
              openAccountLegalDocument(context, termsOfServiceDocument),
          child: const Text('Terms of Service'),
        ),
      ],
    );
  }
}

class _LegalDocumentTiles extends StatelessWidget {
  const _LegalDocumentTiles();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Privacy Policy'),
          subtitle: const Text('版本 $currentPrivacyPolicyVersion'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => openAccountLegalDocument(context, privacyPolicyDocument),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.description_outlined),
          title: const Text('Terms of Service'),
          subtitle: const Text('版本 $currentTermsVersion'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () =>
              openAccountLegalDocument(context, termsOfServiceDocument),
        ),
      ],
    );
  }
}

class _AccountError extends StatelessWidget {
  const _AccountError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
