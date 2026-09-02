import 'package:flutter/material.dart';
import 'package:inknest_notes/auth/auth_controller.dart';

Future<bool> showChangePasswordDialog(
  BuildContext context,
  AuthController controller,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _ChangePasswordDialog(controller: controller),
    ) ??
    false;

Future<bool> showDeleteAccountFlow(
  BuildContext context,
  AuthController controller,
) async {
  final continueDeletion = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded),
      title: const Text('Delete cloud account?'),
      content: const Text(
        'Your InkNest account, cloud notebooks, attachments, revisions, conflicts, and sessions will be permanently deleted. Notes already stored on this device will remain available locally. This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('account-delete-continue'),
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  if (continueDeletion != true || !context.mounted) return false;
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _DeleteAccountDialog(controller: controller),
      ) ??
      false;
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.controller});

  final AuthController controller;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirmation = TextEditingController();

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final succeeded = await widget.controller.changePassword(
      currentPassword: _current.text,
      newPassword: _next.text,
    );
    if (succeeded && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => AlertDialog(
        title: const Text('Change password'),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PasswordField(
                  key: const ValueKey('account-current-password'),
                  controller: _current,
                  label: 'Current password',
                  enabled: !widget.controller.isBusy,
                ),
                const SizedBox(height: 12),
                _PasswordField(
                  key: const ValueKey('account-new-password'),
                  controller: _next,
                  label: 'New password',
                  enabled: !widget.controller.isBusy,
                ),
                const SizedBox(height: 12),
                _PasswordField(
                  key: const ValueKey('account-new-password-confirmation'),
                  controller: _confirmation,
                  label: 'Confirm new password',
                  enabled: !widget.controller.isBusy,
                  validator: (value) =>
                      value != _next.text ? 'Passwords do not match.' : null,
                ),
                if (widget.controller.errorMessage case final error?) ...[
                  const SizedBox(height: 12),
                  _DialogError(error),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: widget.controller.isBusy
                ? null
                : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('account-change-password-submit'),
            onPressed: widget.controller.isBusy ? null : _submit,
            child: widget.controller.isBusy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Update password'),
          ),
        ],
      ),
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.controller});

  final AuthController controller;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final succeeded = await widget.controller.deleteAccount(
      password: _password.text,
    );
    if (succeeded && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => AlertDialog(
        icon: Icon(Icons.delete_forever_rounded, color: colors.error),
        title: const Text('Confirm permanent deletion'),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Enter your password and type DELETE. Cloud data will be deleted; local notes on this device will stay.',
                ),
                const SizedBox(height: 16),
                _PasswordField(
                  key: const ValueKey('account-delete-password'),
                  controller: _password,
                  label: 'Current password',
                  enabled: !widget.controller.isBusy,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('account-delete-confirmation'),
                  controller: _confirmation,
                  enabled: !widget.controller.isBusy,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Type DELETE',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value == 'DELETE' ? null : 'Type DELETE to confirm.',
                ),
                if (widget.controller.errorMessage case final error?) ...[
                  const SizedBox(height: 12),
                  _DialogError(error),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: widget.controller.isBusy
                ? null
                : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('account-delete-submit'),
            onPressed: widget.controller.isBusy ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
            ),
            child: widget.controller.isBusy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Delete account'),
          ),
        ],
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    super.key,
    required this.controller,
    required this.label,
    required this.enabled,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      obscureText: true,
      enableSuggestions: false,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator:
          validator ??
          (value) {
            final password = value ?? '';
            if (password.length < 8) return 'Use at least 8 characters.';
            if (password.length > 128) return 'Use 128 characters or fewer.';
            return null;
          },
    );
  }
}

class _DialogError extends StatelessWidget {
  const _DialogError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}
