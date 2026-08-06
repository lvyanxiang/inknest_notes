import 'package:flutter/material.dart';
import 'package:inknest_notes/auth/auth_controller.dart';

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
    });
    widget.controller.clearError();
    _formKey.currentState?.reset();
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
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
          ],
        ),
      ),
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
