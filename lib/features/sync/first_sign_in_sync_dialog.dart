import 'package:flutter/material.dart';
import 'package:inknest_notes/sync/bootstrap_restore_service.dart';
import 'package:inknest_notes/sync/first_sign_in_sync_service.dart';
import 'package:inknest_notes/sync/inknest_api_client.dart';
import 'package:inknest_notes/sync/inknest_api_models.dart';
import 'package:inknest_notes/sync/sync_bootstrap.dart';
import 'package:inknest_notes/sync/sync_merge_plan.dart';

class FirstSignInSyncDialogResult {
  const FirstSignInSyncDialogResult({this.restoreResult, this.uploadResult});

  final BootstrapRestoreResult? restoreResult;
  final LocalMergeUploadResult? uploadResult;
}

Future<FirstSignInSyncDialogResult?> showFirstSignInSyncDialog({
  required BuildContext context,
  required FirstSignInSyncService service,
  required InkNestAuthSession session,
}) {
  return showDialog<FirstSignInSyncDialogResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _FirstSignInSyncDialog(service: service, session: session),
  );
}

enum _DialogState { checking, preview, restoring, error }

class _FirstSignInSyncDialog extends StatefulWidget {
  const _FirstSignInSyncDialog({required this.service, required this.session});

  final FirstSignInSyncService service;
  final InkNestAuthSession session;

  @override
  State<_FirstSignInSyncDialog> createState() => _FirstSignInSyncDialogState();
}

class _FirstSignInSyncDialogState extends State<_FirstSignInSyncDialog> {
  _DialogState _state = _DialogState.checking;
  FirstSignInSyncPreview? _preview;
  String? _errorMessage;
  bool _authenticationExpired = false;
  bool _transferFailed = false;

  @override
  void initState() {
    super.initState();
    _inspect();
  }

  Future<void> _inspect() async {
    setState(() {
      _state = _DialogState.checking;
      _errorMessage = null;
      _authenticationExpired = false;
      _transferFailed = false;
    });
    try {
      final preview = await widget.service.inspect();
      if (!mounted) return;
      if (preview.assessment.presence == SyncLibraryPresence.empty) {
        Navigator.of(context).pop(const FirstSignInSyncDialogResult());
        return;
      }
      setState(() {
        _preview = preview;
        _state = _DialogState.preview;
      });
    } on InkNestApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _authenticationExpired = error.statusCode == 401;
        _errorMessage = error.statusCode == 401
            ? '登录状态已过期，请重新登录后再检查云端笔记。'
            : '暂时无法检查云端笔记，请确认服务和网络后重试。';
        _state = _DialogState.error;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _errorMessage = '暂时无法检查云端笔记，本地笔记没有发生任何变化。';
        _state = _DialogState.error;
      });
    }
  }

  Future<void> _executeMerge() async {
    final preview = _preview;
    if (preview == null ||
        (!preview.canRestoreCloudOnly && !preview.canUploadLocalOnly)) {
      return;
    }
    setState(() => _state = _DialogState.restoring);
    try {
      final result = preview.canRestoreCloudOnly
          ? FirstSignInSyncDialogResult(
              restoreResult: await widget.service.restoreCloudOnly(
                preview: preview,
                userId: widget.session.user.id,
                deviceId: widget.session.device.id,
              ),
            )
          : FirstSignInSyncDialogResult(
              uploadResult: await widget.service.uploadLocalOnly(
                preview: preview,
                userId: widget.session.user.id,
                deviceId: widget.session.device.id,
              ),
            );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on Object {
      if (!mounted) return;
      setState(() {
        _transferFailed = true;
        _errorMessage = preview.canUploadLocalOnly
            ? '上传没有完成，本地笔记不受影响；已完成的部分可以安全重试。'
            : '恢复没有完成，已回滚本次写入；你可以安全重试。';
        _state = _DialogState.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _state != _DialogState.restoring,
      child: AlertDialog(
        key: const ValueKey('first-sign-in-sync-dialog'),
        title: Text(_title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 180),
            child: _content(),
          ),
        ),
        actions: _actions(),
      ),
    );
  }

  String get _title => switch (_state) {
    _DialogState.checking => '正在检查笔记',
    _DialogState.preview => '安全合并笔记',
    _DialogState.restoring =>
      _preview?.canUploadLocalOnly == true ? '正在保护本地笔记' : '正在恢复云端笔记',
    _DialogState.error => _authenticationExpired ? '需要重新登录' : '检查未完成',
  };

  Widget _content() {
    if (_state == _DialogState.checking) {
      return const _ProgressMessage(message: '正在检查此设备和云端笔记…');
    }
    if (_state == _DialogState.restoring) {
      return _ProgressMessage(
        message: _preview?.canUploadLocalOnly == true
            ? '正在上传并校验笔记和附件，请不要关闭 App。'
            : '正在下载并校验笔记和附件，请不要关闭 App。',
      );
    }
    if (_state == _DialogState.error) {
      return Text(_errorMessage!);
    }

    final preview = _preview!;
    final upload = preview.plan.count(SyncMergeActionKind.uploadLocal);
    final download = preview.plan.count(SyncMergeActionKind.downloadCloud);
    final shared = preview.plan.count(SyncMergeActionKind.reconcileShared);
    final explanation = switch (preview.assessment.presence) {
      SyncLibraryPresence.localOnly => '此设备有本地笔记，云端目前为空。本地内容会继续保留。',
      SyncLibraryPresence.cloudOnly => '云端有笔记，此设备目前为空。确认后会下载并校验，再加入本地书架。',
      SyncLibraryPresence.localAndCloud =>
        '此设备和云端都有笔记。InkNest 按稳定 ID 判断，不会按同名笔记覆盖或去重。',
      SyncLibraryPresence.empty => '',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(explanation),
        const SizedBox(height: 16),
        _CountRow(label: '本地待上传', count: upload),
        _CountRow(label: '云端待下载', count: download),
        _CountRow(label: '需要安全协调', count: shared),
        const SizedBox(height: 12),
        Text(
          preview.canRestoreCloudOnly || preview.canUploadLocalOnly
              ? preview.canUploadLocalOnly
                    ? '附件通过大小和 SHA-256 校验后才会成为可恢复的云端文件。'
                    : '恢复失败会自动回滚，不会留下半本笔记。'
              : '当前版本尚未执行本地上传或共同版本协调；选择稍后不会改变任何本地内容。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  List<Widget> _actions() {
    if (_state == _DialogState.checking) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ];
    }
    if (_state == _DialogState.restoring) return const [];
    if (_state == _DialogState.error) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_authenticationExpired ? '继续使用本地笔记' : '离线继续'),
        ),
        if (!_authenticationExpired)
          FilledButton(
            onPressed: _transferFailed ? _executeMerge : _inspect,
            child: const Text('重试'),
          ),
      ];
    }
    final canMerge =
        _preview!.canRestoreCloudOnly || _preview!.canUploadLocalOnly;
    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('稍后'),
      ),
      FilledButton(
        onPressed: canMerge ? _executeMerge : null,
        child: Text(canMerge ? '合并（推荐）' : '共享版本协调将在下一步开放'),
      ),
    ];
  }
}

class _ProgressMessage extends StatelessWidget {
  const _ProgressMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        const SizedBox(width: 16),
        Expanded(child: Text(message)),
      ],
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text('$count 项', style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}
