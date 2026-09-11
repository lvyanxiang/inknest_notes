import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:inknest_notes/auth/auth_controller.dart';
import 'package:inknest_notes/development/developer_data_reset.dart';
import 'package:inknest_notes/features/account/account_screen.dart';
import 'package:inknest_notes/features/editor/editor_screen.dart';
import 'package:inknest_notes/features/editor/infinite_canvas_screen.dart';
import 'package:inknest_notes/models/notebook.dart';
import 'package:inknest_notes/models/notebook_folder.dart';
import 'package:inknest_notes/models/notebook_layout_mode.dart';
import 'package:inknest_notes/models/note_page_size.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';
import 'package:inknest_notes/sync/automatic_first_sign_in_sync.dart';
import 'package:inknest_notes/sync/first_sign_in_sync_service.dart';
import 'package:inknest_notes/sync/incremental_sync_pull_service.dart';
import 'package:inknest_notes/sync/incremental_sync_push_service.dart';
import 'package:inknest_notes/sync/inknest_api_client.dart';
import 'package:inknest_notes/sync/inknest_api_models.dart';
import 'package:inknest_notes/sync/sync_conflict_resolution_service.dart';
import 'package:inknest_notes/sync/sync_conflicts.dart';
import 'package:inknest_notes/sync/sync_tombstone_restore_service.dart';
import 'package:inknest_notes/sync/sync_tombstones.dart';
import 'package:inknest_notes/sync/sync_structural_conflicts.dart';
import 'package:inknest_notes/sync/sync_state.dart';

enum _LibrarySyncPhase {
  idle,
  syncing,
  completed,
  needsAttention,
  failed,
  preservedEdit,
}

class _LibrarySyncStatus {
  const _LibrarySyncStatus(this.phase, this.message);

  static const idle = _LibrarySyncStatus(_LibrarySyncPhase.idle, '');

  final _LibrarySyncPhase phase;
  final String message;

  bool get canRetry =>
      phase == _LibrarySyncPhase.failed ||
      phase == _LibrarySyncPhase.needsAttention;
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.notebookRepository,
    required this.authController,
    this.firstSignInSyncService,
    this.syncRequests,
    this.developerDataResetService,
    this.syncDebounceDuration = const Duration(seconds: 2),
    this.foregroundSyncInterval = const Duration(seconds: 30),
  });

  final NotebookRepository notebookRepository;
  final AuthController authController;
  final FirstSignInSyncService? firstSignInSyncService;
  final Stream<void>? syncRequests;
  final DeveloperDataResetService? developerDataResetService;
  final Duration syncDebounceDuration;
  final Duration foregroundSyncInterval;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

enum _LibrarySortMode { recent, title, created, updated }

const _phoneLibraryBreakpoint = 480.0;

extension _LibrarySortModeLabel on _LibrarySortMode {
  String get label {
    switch (this) {
      case _LibrarySortMode.recent:
        return 'Recent';
      case _LibrarySortMode.title:
        return 'Title';
      case _LibrarySortMode.created:
        return 'Created date';
      case _LibrarySortMode.updated:
        return 'Updated date';
    }
  }
}

class _NotebookCreationChoice {
  const _NotebookCreationChoice({
    required this.layoutMode,
    this.pageSize,
    this.orientation,
  });

  final NotebookLayoutMode layoutMode;
  final NotePageSizePreset? pageSize;
  final NotePageOrientation? orientation;
}

class _NotebookTypePicker extends StatefulWidget {
  const _NotebookTypePicker({required this.selectedOrientation});

  final NotePageOrientation selectedOrientation;

  @override
  State<_NotebookTypePicker> createState() => _NotebookTypePickerState();
}

class _NotebookTypePickerState extends State<_NotebookTypePicker> {
  late NotePageOrientation _orientation;

  @override
  void initState() {
    super.initState();
    _orientation = widget.selectedOrientation;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Create a notebook', style: textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'Choose a paper or start with an infinite canvas.',
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.auto_stories_outlined,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Paged notebook',
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          SegmentedButton<NotePageOrientation>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(
                                value: NotePageOrientation.portrait,
                                icon: Icon(
                                  Icons.stay_current_portrait,
                                  size: 18,
                                ),
                                tooltip: 'Portrait paper',
                              ),
                              ButtonSegment(
                                value: NotePageOrientation.landscape,
                                icon: Icon(
                                  Icons.stay_current_landscape,
                                  size: 18,
                                ),
                                tooltip: 'Landscape paper',
                              ),
                            ],
                            selected: {_orientation},
                            onSelectionChanged: (selection) {
                              setState(() {
                                _orientation = selection.first;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tap a paper size to create immediately.',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (
                            var index = 0;
                            index < NotePageSizePreset.values.length;
                            index++
                          ) ...[
                            if (index > 0) const SizedBox(width: 8),
                            Expanded(
                              child: _NotebookPaperCard(
                                preset: NotePageSizePreset.values[index],
                                orientation: _orientation,
                                onTap: () => Navigator.of(context).pop(
                                  _NotebookCreationChoice(
                                    layoutMode: NotebookLayoutMode.paged,
                                    pageSize: NotePageSizePreset.values[index],
                                    orientation: _orientation,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _NotebookTypeCard(
                key: const ValueKey('create-infinite-canvas'),
                icon: Icons.gesture,
                title: 'Infinite canvas',
                description:
                    'A flexible space for freeform thinking, zooming, and spatial notes.',
                onTap: () => Navigator.of(context).pop(
                  const _NotebookCreationChoice(
                    layoutMode: NotebookLayoutMode.infiniteCanvas,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotebookPaperCard extends StatelessWidget {
  const _NotebookPaperCard({
    required this.preset,
    required this.orientation,
    required this.onTap,
  });

  final NotePageSizePreset preset;
  final NotePageOrientation orientation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final pageSize = preset.sizeFor(orientation);
    return Semantics(
      button: true,
      label: '${preset.label}, ${orientation.label}, ${preset.detail}',
      child: Material(
        key: ValueKey('create-paged-notebook-${preset.name}'),
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 9),
              child: Column(
                children: [
                  SizedBox(
                    height: 58,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: pageSize.width / pageSize.height,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(
                              color: colorScheme.outlineVariant,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x141E2526),
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    preset.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preset.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotebookTypeCard extends StatelessWidget {
  const _NotebookTypeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: title,
      child: Material(
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Icon(icon, color: colorScheme.onPrimaryContainer),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(description),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LibraryScreenState extends State<LibraryScreen>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  late List<Notebook> _notebooks;
  late List<NotebookFolder> _folders;
  bool _isLoading = true;
  bool _showArchived = false;
  String _searchQuery = '';
  _LibrarySortMode _sortMode = _LibrarySortMode.recent;
  NotePageOrientation _newNotebookOrientation = NotePageOrientation.portrait;
  String? _currentFolderId;
  NotebookFolder? _currentFolder;
  String? _checkedSessionKey;
  bool _syncCheckScheduled = false;
  bool _syncRequestedWhileRunning = false;
  bool _pullRequestedWhileRunning = false;
  bool _developerDataResetInProgress = false;
  Completer<void>? _syncIdleCompleter;
  StreamSubscription<void>? _syncRequestSubscription;
  Timer? _syncDebounceTimer;
  Timer? _foregroundSyncTimer;
  List<CloudSyncConflict> _pendingConflicts = const [];
  List<SyncStructuralConflict> _structuralConflicts = const [];
  List<CloudSyncTombstone> _activeTombstones = const [];
  _LibrarySyncStatus _syncStatus = _LibrarySyncStatus.idle;

  @override
  void initState() {
    super.initState();
    _notebooks = [];
    _folders = [];
    WidgetsBinding.instance.addObserver(this);
    widget.authController.addListener(_handleAuthChanged);
    _syncRequestSubscription = widget.syncRequests?.listen((_) {
      _scheduleAutomaticSync();
    });
    _foregroundSyncTimer = Timer.periodic(widget.foregroundSyncInterval, (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _requestAutomaticSync();
      }
    });
    _loadNotebooks();
    _handleAuthChanged();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.authController.removeListener(_handleAuthChanged);
    _syncRequestSubscription?.cancel();
    _syncDebounceTimer?.cancel();
    _foregroundSyncTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _requestAutomaticSync();
    }
  }

  void _scheduleAutomaticSync() {
    if (_developerDataResetInProgress ||
        !widget.authController.agreementsCurrent) {
      return;
    }
    _syncDebounceTimer?.cancel();
    _syncDebounceTimer = Timer(
      widget.syncDebounceDuration,
      _requestAutomaticSync,
    );
  }

  void _requestAutomaticSync() {
    if (!mounted ||
        _developerDataResetInProgress ||
        !widget.authController.agreementsCurrent) {
      return;
    }
    unawaited(
      _checkCloudAfterSignIn(
        force: true,
        pullRemote: ModalRoute.of(context)?.isCurrent == true,
      ),
    );
  }

  void _handleAuthChanged() {
    final session = widget.authController.session;
    if (session == null) {
      _syncDebounceTimer?.cancel();
      _syncRequestedWhileRunning = false;
      _pullRequestedWhileRunning = false;
      _checkedSessionKey = null;
      if (_pendingConflicts.isNotEmpty ||
          _structuralConflicts.isNotEmpty ||
          _activeTombstones.isNotEmpty ||
          _syncStatus.phase != _LibrarySyncPhase.idle) {
        setState(() {
          _pendingConflicts = const [];
          _structuralConflicts = const [];
          _activeTombstones = const [];
          _syncStatus = _LibrarySyncStatus.idle;
        });
      }
      return;
    }
    if (!widget.authController.agreementsCurrent) {
      _checkedSessionKey = null;
      return;
    }
    if (widget.firstSignInSyncService == null || _syncCheckScheduled) return;
    final sessionKey = '${session.user.id}:${session.device.id}';
    if (_checkedSessionKey == sessionKey) return;
    _syncCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncCheckScheduled = false;
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      _checkCloudAfterSignIn();
    });
  }

  Future<void> _checkCloudAfterSignIn({
    bool force = false,
    bool pullRemote = true,
  }) async {
    if (_developerDataResetInProgress) {
      return;
    }
    if (_syncStatus.phase == _LibrarySyncPhase.syncing) {
      if (force) {
        _syncRequestedWhileRunning = true;
        _pullRequestedWhileRunning |= pullRemote;
      }
      return;
    }
    final syncIdleCompleter = Completer<void>();
    _syncIdleCompleter = syncIdleCompleter;
    try {
      var shouldPullRemote = pullRemote;
      do {
        _syncRequestedWhileRunning = false;
        _pullRequestedWhileRunning = false;
        await _runCloudSyncCycle(force: force, pullRemote: shouldPullRemote);
        force = true;
        shouldPullRemote = _pullRequestedWhileRunning;
      } while (mounted &&
          !_developerDataResetInProgress &&
          _syncRequestedWhileRunning &&
          widget.authController.agreementsCurrent);
    } finally {
      if (identical(_syncIdleCompleter, syncIdleCompleter)) {
        _syncIdleCompleter = null;
      }
      if (!syncIdleCompleter.isCompleted) {
        syncIdleCompleter.complete();
      }
    }
  }

  Future<void> _runCloudSyncCycle({
    required bool force,
    required bool pullRemote,
  }) async {
    final session = widget.authController.session;
    final service = widget.firstSignInSyncService;
    if (session == null ||
        !widget.authController.agreementsCurrent ||
        service == null) {
      return;
    }
    final sessionKey = '${session.user.id}:${session.device.id}';
    if (!force && _checkedSessionKey == sessionKey) {
      return;
    }
    _checkedSessionKey = sessionKey;
    setState(() {
      _syncStatus = const _LibrarySyncStatus(
        _LibrarySyncPhase.syncing,
        'Uploading local changes and checking for cloud updates…',
      );
    });
    try {
      final pushResult = await service.pushIncremental(
        userId: session.user.id,
        deviceId: session.device.id,
      );
      if (!pullRemote) {
        if (!mounted) return;
        setState(() {
          _syncStatus = _LibrarySyncStatus(
            pushResult.preservedDeleteEditCount > 0
                ? _LibrarySyncPhase.preservedEdit
                : _LibrarySyncPhase.completed,
            pushResult.preservedDeleteEditCount > 0
                ? 'Edits from another device were preserved; cloud updates will be checked when you return to the library.'
                : pushResult.uploadedOperationCount > 0
                ? 'Uploaded ${_counted(pushResult.uploadedOperationCount, 'local change')}; cloud updates will be checked when you return to the library.'
                : 'Local changes checked; cloud updates will be checked when you return to the library.',
          );
        });
        return;
      }
      final pullResult = await service.pullIncremental(
        userId: session.user.id,
        deviceId: session.device.id,
      );
      if (!mounted) return;
      setState(() {
        _pendingConflicts = pullResult.pendingConflicts;
        _activeTombstones = pullResult.activeTombstones;
      });
      switch (pullResult.status) {
        case IncrementalSyncPullStatus.notInitialized:
          setState(() => _syncStatus = _LibrarySyncStatus.idle);
          break;
        case IncrementalSyncPullStatus.upToDate:
          final message = pushResult.uploadedOperationCount > 0
              ? 'Uploaded ${_counted(pushResult.uploadedOperationCount, 'local change')}. Everything is up to date.'
              : 'Local notes are up to date with the cloud.';
          setState(() {
            _syncStatus = _LibrarySyncStatus(
              pushResult.preservedDeleteEditCount > 0
                  ? _LibrarySyncPhase.preservedEdit
                  : _LibrarySyncPhase.completed,
              pushResult.preservedDeleteEditCount > 0
                  ? 'Edits from another device were preserved. No action is needed.'
                  : message,
            );
          });
          return;
        case IncrementalSyncPullStatus.applied:
          if (pullResult.changedLocalLibrary) {
            await _loadNotebooks();
          }
          if (!mounted) return;
          final message = _incrementalSyncResultMessage(
            pushResult: pushResult,
            pullResult: pullResult,
          );
          setState(() {
            _syncStatus = _LibrarySyncStatus(
              pushResult.preservedDeleteEditCount > 0
                  ? _LibrarySyncPhase.preservedEdit
                  : pullResult.receivedConflictCount > 0
                  ? _LibrarySyncPhase.needsAttention
                  : _LibrarySyncPhase.completed,
              message,
            );
          });
          return;
        case IncrementalSyncPullStatus.requiresReconciliation:
          final message = pushResult.preservedDeleteEditCount > 0
              ? 'Edits from another device were preserved. You do not need to choose between the deletion and the edits.'
              : pushResult.uploadedOperationCount == 0
              ? 'Cloud changes require reconciliation. Local notes were not overwritten.'
              : 'Uploaded ${_counted(pushResult.uploadedOperationCount, 'local change')}. '
                    'Other cloud changes require reconciliation; local notes were not overwritten.';
          setState(() {
            _syncStatus = _LibrarySyncStatus(
              pushResult.preservedDeleteEditCount > 0
                  ? _LibrarySyncPhase.preservedEdit
                  : _LibrarySyncPhase.needsAttention,
              message,
            );
          });
          return;
      }
    } on IncrementalSyncPushException catch (error) {
      if (!mounted) return;
      final count = error.pendingOperationCount;
      setState(() {
        _structuralConflicts = error.structuralConflicts;
        _syncStatus = _LibrarySyncStatus(
          error.structuralConflicts.isEmpty
              ? _LibrarySyncPhase.failed
              : _LibrarySyncPhase.needsAttention,
          error.structuralConflicts.isNotEmpty
              ? '${_counted(error.structuralConflicts.length, 'structural conflict')} ${error.structuralConflicts.length == 1 ? 'needs' : 'need'} attention. Both local and cloud versions were preserved.'
              : count > 0
              ? 'Sync failed. ${_counted(count, 'local change')} ${count == 1 ? 'remains' : 'remain'} safely stored and ready to retry.'
              : 'Sync failed. Local notes were not affected; you can retry.',
        );
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _syncStatus = const _LibrarySyncStatus(
          _LibrarySyncPhase.failed,
          'Cloud changes cannot be checked right now. Local notes were not affected; you can retry.',
        );
      });
      return;
    }
    await _runAutomaticFirstSignInSync(service: service, session: session);
  }

  Future<void> _runAutomaticFirstSignInSync({
    required FirstSignInSyncService service,
    required InkNestAuthSession session,
  }) async {
    try {
      final result = await runAutomaticFirstSignInSync(
        service: service,
        userId: session.user.id,
        deviceId: session.device.id,
      );
      if (!mounted || !_isCurrentSession(session)) return;
      if (result.changedLocalLibrary) {
        await _loadNotebooks();
      }
      if (!mounted || !_isCurrentSession(session)) return;
      final message = result.restoreResult != null
          ? 'Received ${_counted(result.restoreResult!.downloadedNotebookCount, 'cloud notebook')} and '
                '${_counted(result.restoreResult!.downloadedAssetCount, 'attachment')}.'
          : result.uploadResult != null
          ? 'Synchronized ${_counted(result.uploadResult!.uploadedNotebookCount, 'local notebook')} and '
                '${_counted(result.uploadResult!.uploadedAssetCount, 'attachment')}.'
          : result.mixedResult != null
          ? 'Uploaded ${_counted(result.mixedResult!.uploadedNotebookCount, 'notebook')} and received '
                '${_counted(result.mixedResult!.downloadedNotebookCount, 'notebook')}.'
          : 'Local notes are up to date with the cloud.';
      final pendingConflicts = _mergePendingConflicts(
        _pendingConflicts,
        result.pendingConflicts,
      );
      setState(() {
        _pendingConflicts = pendingConflicts;
        _syncStatus = _LibrarySyncStatus(
          pendingConflicts.isEmpty
              ? _LibrarySyncPhase.completed
              : _LibrarySyncPhase.needsAttention,
          pendingConflicts.isEmpty
              ? message
              : '${_counted(pendingConflicts.length, 'sync conflict')} ${pendingConflicts.length == 1 ? 'needs' : 'need'} attention. Both versions were preserved.',
        );
      });
    } on InkNestApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _syncStatus = _LibrarySyncStatus(
          _LibrarySyncPhase.failed,
          error.statusCode == 401
              ? 'Your session expired. Local notes were not affected; sign in again to sync.'
              : 'Initial cloud sync cannot be completed right now. Local notes were not affected; you can retry.',
        );
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _syncStatus = const _LibrarySyncStatus(
          _LibrarySyncPhase.failed,
          'Initial cloud sync was not completed. Content that could not be reconciled safely was not overwritten; you can retry.',
        );
      });
    }
  }

  bool _isCurrentSession(InkNestAuthSession session) {
    final current = widget.authController.session;
    return current?.user.id == session.user.id &&
        current?.device.id == session.device.id;
  }

  List<CloudSyncConflict> _mergePendingConflicts(
    List<CloudSyncConflict> current,
    List<CloudSyncConflict> incoming,
  ) {
    final byId = <String, CloudSyncConflict>{
      for (final conflict in current) conflict.id: conflict,
      for (final conflict in incoming) conflict.id: conflict,
    };
    return byId.values.where((conflict) => conflict.isPending).toList()
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
  }

  String _incrementalSyncResultMessage({
    required IncrementalSyncPushResult pushResult,
    required IncrementalSyncPullResult pullResult,
  }) {
    if (pushResult.preservedDeleteEditCount > 0) {
      return 'Edits from another device were preserved. You do not need to choose between the deletion and the edits.';
    }
    if (pullResult.receivedConflictCount > 0) {
      return '${_counted(pullResult.receivedConflictCount, 'sync conflict')} ${pullResult.receivedConflictCount == 1 ? 'needs' : 'need'} attention. Both versions were preserved.';
    }
    if (pullResult.deletedNotebookCount > 0) {
      return 'Synchronized ${_counted(pullResult.changeCount, 'cloud change')} and removed '
          '${_counted(pullResult.deletedNotebookCount, 'notebook')} deleted on another device from the shelf. Local recovery copies were preserved.';
    }
    if (pullResult.confirmedLocalDeletionCount > 0) {
      return 'The deletion was synchronized to the cloud. Other devices will remove this notebook on their next sync.';
    }
    if (pullResult.deletedPageCount > 0) {
      return 'Page deletions from another device were synchronized. Recoverable local page copies were preserved.';
    }
    if (pullResult.confirmedLocalPageDeletionCount > 0) {
      return 'The local page deletion was synchronized to the cloud.';
    }
    if (pullResult.deletedFolderCount > 0) {
      return 'A folder deletion from another device was synchronized. Its notebooks were moved to the library root.';
    }
    if (pullResult.confirmedLocalFolderDeletionCount > 0) {
      return 'The local folder deletion was synchronized to the cloud. Its notebooks remain in the library.';
    }
    if (pullResult.appliedSharedResourceCount > 0) {
      return 'Uploaded ${_counted(pushResult.uploadedOperationCount, 'local change')}, '
          'synchronized ${_counted(pullResult.changeCount, 'cloud change')}, and updated '
          '${_counted(pullResult.appliedSharedResourceCount, 'existing item')}.';
    }
    return 'Uploaded ${_counted(pushResult.uploadedOperationCount, 'local change')}, '
        'synchronized ${_counted(pullResult.changeCount, 'cloud change')}, and downloaded '
        '${_counted(pullResult.downloadedNotebookCount, 'notebook')}.';
  }

  Future<void> _openSyncStatus() async {
    if (widget.authController.session == null ||
        widget.firstSignInSyncService == null) {
      return;
    }
    final syncNow = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _syncStatusTitle(_syncStatus.phase),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                _syncStatus.phase == _LibrarySyncPhase.idle
                    ? 'Local notes work offline and sync automatically while you are signed in.'
                    : _syncStatus.message,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                key: ValueKey(
                  _syncStatus.canRetry
                      ? 'retry-library-sync'
                      : 'sync-now-library',
                ),
                onPressed: _syncStatus.phase == _LibrarySyncPhase.syncing
                    ? null
                    : () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.sync_rounded),
                label: Text(_syncStatus.canRetry ? 'Retry Sync' : 'Sync Now'),
              ),
            ],
          ),
        ),
      ),
    );
    if (syncNow == true && mounted) {
      await _checkCloudAfterSignIn(force: true);
    }
  }

  Future<void> _openSyncConflicts() async {
    if (_pendingConflicts.isEmpty && _structuralConflicts.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 560),
          child: Column(
            children: [
              ListTile(
                title: const Text('Sync Conflicts'),
                subtitle: Text(
                  '${_counted(_pendingConflicts.length + _structuralConflicts.length, 'item')} ${_pendingConflicts.length + _structuralConflicts.length == 1 ? 'needs' : 'need'} attention. Local and cloud versions are safely preserved.',
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount:
                      _pendingConflicts.length + _structuralConflicts.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    if (index >= _pendingConflicts.length) {
                      final conflict =
                          _structuralConflicts[index -
                              _pendingConflicts.length];
                      return ListTile(
                        leading: const Icon(Icons.account_tree_outlined),
                        title: Text(_structuralConflictTitle(conflict)),
                        subtitle: Text(
                          conflict.fields.map(_structuralFieldLabel).join(', '),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          Navigator.of(context).pop();
                          await Future<void>.delayed(Duration.zero);
                          if (mounted) {
                            await _openStructuralConflictDetail(conflict);
                          }
                        },
                      );
                    }
                    final conflict = _pendingConflicts[index];
                    final resourceLabel = conflict.resourceType == 'page'
                        ? 'Page conflict'
                        : 'Notebook conflict';
                    final createdAt = conflict.createdAt.toLocal();
                    final time =
                        '${createdAt.year.toString().padLeft(4, '0')}-'
                        '${createdAt.month.toString().padLeft(2, '0')}-'
                        '${createdAt.day.toString().padLeft(2, '0')} '
                        '${createdAt.hour.toString().padLeft(2, '0')}:'
                        '${createdAt.minute.toString().padLeft(2, '0')}';
                    return ListTile(
                      leading: const Icon(Icons.call_split_outlined),
                      title: Text(conflict.displayName),
                      subtitle: Text('$resourceLabel · $time'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        Navigator.of(context).pop();
                        await Future<void>.delayed(Duration.zero);
                        if (mounted) await _openConflictDetail(conflict);
                      },
                    );
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 12, 24, 20),
                child: Text(
                  'Content conflicts can keep both copies. For structural conflicts, choose the local or cloud version.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openStructuralConflictDetail(
    SyncStructuralConflict conflict,
  ) async {
    final service = widget.firstSignInSyncService;
    SyncStructuralConflictResolution? busy;
    String? errorMessage;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> resolve(SyncStructuralConflictResolution choice) async {
            if (busy != null ||
                service is! SyncStructuralConflictResolutionService) {
              return;
            }
            final resolver = service as SyncStructuralConflictResolutionService;
            final useLocal =
                choice == SyncStructuralConflictResolution.useLocal;
            final confirmed =
                await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(
                      useLocal
                          ? 'Use the local version?'
                          : 'Use the cloud version?',
                    ),
                    content: Text(
                      useLocal
                          ? 'The local structure will be submitted to the cloud. You will be notified again if the cloud version changes.'
                          : 'This local structural change will be reverted and the verified cloud structure applied. Note content and attachments will not be deleted.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Confirm'),
                      ),
                    ],
                  ),
                ) ??
                false;
            if (!confirmed || !context.mounted) return;
            final session = widget.authController.session;
            if (session == null) return;
            setSheetState(() {
              busy = choice;
              errorMessage = null;
            });
            try {
              final result = await resolver.resolveStructuralConflict(
                userId: session.user.id,
                deviceId: session.device.id,
                conflictId: conflict.id,
                resolution: choice,
              );
              if (!mounted || !context.mounted) return;
              setState(() {
                _structuralConflicts = result.pendingConflicts;
                _syncStatus = _LibrarySyncStatus(
                  result.pendingConflicts.isEmpty
                      ? _LibrarySyncPhase.completed
                      : _LibrarySyncPhase.needsAttention,
                  result.pendingConflicts.isEmpty
                      ? 'The structural conflict was resolved. Local and cloud data are synchronized.'
                      : '${_counted(result.pendingConflicts.length, 'structural conflict')} still ${result.pendingConflicts.length == 1 ? 'needs' : 'need'} attention.',
                );
              });
              await _loadNotebooks();
              if (context.mounted) Navigator.of(context).pop();
            } on Object {
              if (!context.mounted) return;
              setSheetState(() {
                busy = null;
                errorMessage =
                    'Resolution was not completed. Local and cloud versions remain safely preserved; please retry.';
              });
            }
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _structuralConflictTitle(conflict),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Conflicting fields: ${conflict.fields.map(_structuralFieldLabel).join(', ')}',
                  ),
                  const SizedBox(height: 16),
                  _StructuralVersionCard(
                    title: 'Shared Baseline',
                    summary: _structuralMetadataSummary(
                      conflict.baseMetadata,
                      conflict.fields,
                    ),
                  ),
                  _StructuralVersionCard(
                    title: 'Local Version',
                    summary: _structuralMetadataSummary(
                      conflict.localMetadata,
                      conflict.fields,
                    ),
                  ),
                  _StructuralVersionCard(
                    title: 'Cloud Version',
                    summary: _structuralMetadataSummary(
                      conflict.cloudMetadata,
                      conflict.fields,
                    ),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: busy == null
                        ? () =>
                              resolve(SyncStructuralConflictResolution.useLocal)
                        : null,
                    child: const Text('Use Local Version'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: busy == null
                        ? () =>
                              resolve(SyncStructuralConflictResolution.useCloud)
                        : null,
                    child: const Text('Use Cloud Version'),
                  ),
                  TextButton(
                    onPressed: busy == null
                        ? () => Navigator.of(context).pop()
                        : null,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openConflictDetail(CloudSyncConflict conflict) async {
    final resolutionService = widget.firstSignInSyncService;
    SyncConflictResolution? busyResolution;
    String? errorMessage;
    String? successMessage;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> resolve(SyncConflictResolution resolution) async {
            if (busyResolution != null) return;
            if (resolutionService is! SyncConflictResolutionService) {
              setSheetState(() {
                errorMessage =
                    'Conflict resolution is not available from the current sync service. Please try again later.';
              });
              return;
            }
            final resolver = resolutionService as SyncConflictResolutionService;
            if (resolution != SyncConflictResolution.keepBoth) {
              final confirmed = await _confirmConflictResolution(
                context,
                resolution,
              );
              if (!confirmed || !context.mounted) return;
            }
            setSheetState(() {
              busyResolution = resolution;
              errorMessage = null;
            });
            final session = widget.authController.session;
            if (session == null) {
              setSheetState(() {
                busyResolution = null;
                errorMessage =
                    'Your session expired. Both versions remain safely preserved.';
              });
              return;
            }
            try {
              final result = await resolver.resolveConflict(
                userId: session.user.id,
                deviceId: session.device.id,
                conflictId: conflict.id,
                resolution: resolution,
              );
              if (!mounted || !context.mounted) return;
              setState(() {
                _pendingConflicts = result.pullResult.pendingConflicts;
              });
              await _loadNotebooks();
              if (!mounted || !context.mounted) return;
              successMessage =
                  '${resolution.label} completed. Cloud and local data are synchronized.';
              Navigator.of(context).pop();
            } on SyncConflictResolutionException catch (error) {
              if (!context.mounted) return;
              setSheetState(() {
                busyResolution = null;
                errorMessage = switch (error.failure) {
                  SyncConflictResolutionFailure.staleOriginal =>
                    'The original changed again and cannot be replaced directly. Choose Keep Original or Keep Both.',
                  SyncConflictResolutionFailure.alreadyResolved =>
                    'This conflict was resolved on another device. Please sync again.',
                  SyncConflictResolutionFailure.reconciliationRequired =>
                    'The cloud received your choice, but local synchronization is incomplete. Both versions remain preserved; please retry.',
                  SyncConflictResolutionFailure.unavailable =>
                    'Resolution failed. Both versions remain safely preserved; please retry.',
                };
              });
            } on Object {
              if (!context.mounted) return;
              setSheetState(() {
                busyResolution = null;
                errorMessage =
                    'Resolution failed. Both versions remain safely preserved; please retry.';
              });
            }
          }

          final source = conflict.sourceDeviceId == null
              ? 'Unknown device'
              : conflict.sourceDeviceId!;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Resolve Sync Conflict',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    conflict.resourceType == 'page'
                        ? 'Page conflict'
                        : 'Notebook conflict',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.description_outlined),
                    title: Text(conflict.originalDisplayName),
                    subtitle: const Text('Current original'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.call_split_outlined),
                    title: Text(conflict.displayName),
                    subtitle: Text('From device: $source'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Both versions are safely preserved. Choose an outcome; closing this sheet makes no changes.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorMessage!,
                      key: const ValueKey('conflict-resolution-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    key: const ValueKey('conflict-keep-both'),
                    onPressed: busyResolution == null
                        ? () => resolve(SyncConflictResolution.keepBoth)
                        : null,
                    icon: busyResolution == SyncConflictResolution.keepBoth
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.copy_all_outlined),
                    label: const Text('Keep Both (Recommended)'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    key: const ValueKey('conflict-keep-original'),
                    onPressed: busyResolution == null
                        ? () => resolve(SyncConflictResolution.keepOriginal)
                        : null,
                    child: const Text('Keep Original'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    key: const ValueKey('conflict-use-conflict'),
                    onPressed: busyResolution == null
                        ? () => resolve(SyncConflictResolution.useConflict)
                        : null,
                    child: const Text('Use Conflict Version'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: busyResolution == null
                        ? () => Navigator.of(context).pop()
                        : null,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (mounted && successMessage != null) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(SnackBar(content: Text(successMessage!)));
    }
  }

  Future<bool> _confirmConflictResolution(
    BuildContext context,
    SyncConflictResolution resolution,
  ) async {
    final description = resolution == SyncConflictResolution.keepOriginal
        ? 'This ends the pending conflict and keeps the current original. The conflict snapshot remains available for recovery.'
        : 'This updates the current original with the conflict version. If the original changed again, the operation stops safely.';
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Confirm ${resolution.label}?'),
            content: Text(description),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const ValueKey('confirm-conflict-resolution'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Confirm'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _openRecentlyDeleted() async {
    if (_activeTombstones.isEmpty) return;
    final restoreService = widget.firstSignInSyncService;
    String? busyId;
    String? errorMessage;
    String? successMessage;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> restore(CloudSyncTombstone tombstone) async {
            if (busyId != null) return;
            if (restoreService is! SyncTombstoneRestoreService) {
              setSheetState(() {
                errorMessage =
                    'Restore is not available from the current sync service. Please try again later.';
              });
              return;
            }
            final restorer = restoreService as SyncTombstoneRestoreService;
            final session = widget.authController.session;
            if (session == null) {
              setSheetState(() {
                errorMessage =
                    'Your session expired. The deletion record remains available.';
              });
              return;
            }
            setSheetState(() {
              busyId = tombstone.id;
              errorMessage = null;
            });
            try {
              final result = await restorer.restoreTombstone(
                userId: session.user.id,
                deviceId: session.device.id,
                tombstoneId: tombstone.id,
              );
              if (!mounted || !context.mounted) return;
              setState(() {
                _pendingConflicts = result.pullResult.pendingConflicts;
                _activeTombstones = result.pullResult.activeTombstones;
              });
              await _loadNotebooks();
              if (!mounted || !context.mounted) return;
              successMessage = '${tombstone.resourceLabel} restored.';
              Navigator.of(context).pop();
            } on SyncTombstoneRestoreException catch (error) {
              if (!context.mounted) return;
              setSheetState(() {
                busyId = null;
                errorMessage = switch (error.failure) {
                  SyncTombstoneRestoreFailure.alreadyRestored =>
                    'This item is already restored in the cloud, but local synchronization is incomplete. Please sync again.',
                  SyncTombstoneRestoreFailure.reconciliationRequired =>
                    'The item was restored in the cloud, but local synchronization is incomplete. The deletion record remains; please retry.',
                  SyncTombstoneRestoreFailure.unavailable =>
                    'Restore failed. The deletion record remains safely stored; please retry.',
                };
              });
            } on Object {
              if (!context.mounted) return;
              setSheetState(() {
                busyId = null;
                errorMessage =
                    'Restore failed. The deletion record remains safely stored; please retry.';
              });
            }
          }

          return SafeArea(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 620),
              child: Column(
                children: [
                  ListTile(
                    title: const Text('Recently Deleted'),
                    subtitle: Text(
                      '${_counted(_activeTombstones.length, 'item')} can be restored. Permanent deletion is not currently available.',
                    ),
                  ),
                  if (errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          errorMessage!,
                          key: const ValueKey('tombstone-restore-error'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _activeTombstones.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final tombstone = _activeTombstones[index];
                        final deletedAt = tombstone.deletedAt.toLocal();
                        final time =
                            '${deletedAt.year.toString().padLeft(4, '0')}-'
                            '${deletedAt.month.toString().padLeft(2, '0')}-'
                            '${deletedAt.day.toString().padLeft(2, '0')} '
                            '${deletedAt.hour.toString().padLeft(2, '0')}:'
                            '${deletedAt.minute.toString().padLeft(2, '0')}';
                        final source = tombstone.deletedByDeviceId == null
                            ? 'Unknown device'
                            : tombstone.deletedByDeviceId!;
                        final busy = busyId == tombstone.id;
                        return ListTile(
                          leading: Icon(
                            tombstone.resourceType == 'notebook'
                                ? Icons.menu_book_outlined
                                : Icons.description_outlined,
                          ),
                          title: Text(tombstone.resourceLabel),
                          subtitle: Text('$time · Source device: $source'),
                          trailing: FilledButton.tonalIcon(
                            key: ValueKey('restore-tombstone-${tombstone.id}'),
                            onPressed: busyId == null
                                ? () => restore(tombstone)
                                : null,
                            icon: busy
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.restore),
                            label: const Text('Restore'),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (mounted && successMessage != null) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(SnackBar(content: Text(successMessage!)));
    }
  }

  Future<void> _loadNotebooks() async {
    final notebooks = await widget.notebookRepository.listNotebooks(
      archived: _showArchived,
      folderId: _showArchived ? null : _currentFolderId,
    );
    final folders = !_showArchived && _currentFolderId == null
        ? await widget.notebookRepository.listFolders()
        : <NotebookFolder>[];

    if (!mounted) {
      return;
    }

    setState(() {
      _notebooks = notebooks;
      _folders = folders;
      _isLoading = false;
    });
  }

  List<Notebook> get _visibleNotebooks {
    final notebooks = _notebooks.where((notebook) {
      return _matchesSearch(notebook.title);
    }).toList();

    notebooks.sort(_compareNotebooks);
    return notebooks;
  }

  List<NotebookFolder> get _visibleFolders {
    final folders = _folders.where((folder) {
      return _matchesSearch(folder.name);
    }).toList();

    folders.sort(
      (first, second) =>
          first.name.toLowerCase().compareTo(second.name.toLowerCase()),
    );
    return folders;
  }

  bool _matchesSearch(String value) {
    final query = _searchQuery.trim().toLowerCase();
    return query.isEmpty || value.toLowerCase().contains(query);
  }

  int _compareNotebooks(Notebook first, Notebook second) {
    switch (_sortMode) {
      case _LibrarySortMode.recent:
      case _LibrarySortMode.updated:
        return second.updatedAt.compareTo(first.updatedAt);
      case _LibrarySortMode.created:
        return second.createdAt.compareTo(first.createdAt);
      case _LibrarySortMode.title:
        return first.title.toLowerCase().compareTo(second.title.toLowerCase());
    }
  }

  void _updateSearchQuery(String value) {
    setState(() {
      _searchQuery = value;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _updateSearchQuery('');
  }

  void _setSortMode(_LibrarySortMode mode) {
    setState(() {
      _sortMode = mode;
    });
  }

  Future<void> _createNotebook() async {
    final choice = await showModalBottomSheet<_NotebookCreationChoice>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) =>
          _NotebookTypePicker(selectedOrientation: _newNotebookOrientation),
    );
    if (choice == null) {
      return;
    }

    if (choice.pageSize != null && choice.orientation != null) {
      _newNotebookOrientation = choice.orientation!;
    }

    var notebook = await widget.notebookRepository.createNotebook(
      layoutMode: choice.layoutMode,
      pageSize: choice.pageSize?.sizeFor(
        choice.orientation ?? NotePageOrientation.portrait,
      ),
    );
    final folderId = _showArchived ? null : _currentFolderId;
    if (folderId != null) {
      notebook = await widget.notebookRepository.moveNotebookToFolder(
        notebook,
        folderId,
      );
    }

    _showArchived = false;
    await _loadNotebooks();

    if (!mounted) {
      return;
    }

    unawaited(_checkCloudAfterSignIn(force: true));
    await _openNotebook(notebook);
  }

  Future<void> _importPdf() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    final path = result?.files.single.path;
    if (path == null) {
      return;
    }

    final notebook = await widget.notebookRepository.importPdf(File(path));
    final folderId = _showArchived ? null : _currentFolderId;
    final importedNotebook = folderId == null
        ? notebook
        : await widget.notebookRepository.moveNotebookToFolder(
            notebook,
            folderId,
          );

    _showArchived = false;
    await _loadNotebooks();

    if (!mounted) {
      return;
    }

    unawaited(_checkCloudAfterSignIn(force: true));
    await _openNotebook(importedNotebook);
  }

  Future<void> _openNotebook(Notebook notebook) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => switch (notebook.layoutMode) {
          NotebookLayoutMode.paged => EditorScreen(
            notebook: notebook,
            notebookRepository: widget.notebookRepository,
          ),
          NotebookLayoutMode.infiniteCanvas => InfiniteCanvasScreen(
            notebook: notebook,
            notebookRepository: widget.notebookRepository,
          ),
        },
      ),
    );

    if (!mounted) {
      return;
    }

    await _loadNotebooks();
    unawaited(_checkCloudAfterSignIn(force: true));
  }

  void _toggleArchivedView() {
    setState(() {
      _showArchived = !_showArchived;
      if (_showArchived) {
        _currentFolderId = null;
        _currentFolder = null;
      }
      _isLoading = true;
    });
    _loadNotebooks();
  }

  void _showRootLibrary() {
    setState(() {
      _showArchived = false;
      _currentFolderId = null;
      _currentFolder = null;
      _isLoading = true;
    });
    _loadNotebooks();
  }

  void _openFolder(NotebookFolder folder) {
    setState(() {
      _showArchived = false;
      _currentFolderId = folder.id;
      _currentFolder = folder;
      _isLoading = true;
    });
    _loadNotebooks();
  }

  Future<void> _createFolder() async {
    final name = await _promptName(
      dialogTitle: 'New folder',
      labelText: 'Folder name',
      initialValue: '',
    );
    if (name == null) {
      return;
    }

    await widget.notebookRepository.createFolder(name);
    await _loadNotebooks();
  }

  Future<void> _renameFolder(NotebookFolder folder) async {
    final name = await _promptName(
      dialogTitle: 'Rename folder',
      labelText: 'Folder name',
      initialValue: folder.name,
    );
    if (name == null) {
      return;
    }

    await widget.notebookRepository.renameFolder(folder, name);
    if (_currentFolderId == folder.id) {
      _currentFolder = folder.copyWith(name: name);
    }
    await _loadNotebooks();
  }

  Future<void> _deleteFolder(NotebookFolder folder) async {
    final shouldDelete = await _confirmDeleteFolder(folder);
    if (!shouldDelete) {
      return;
    }

    await widget.notebookRepository.deleteFolder(folder);
    if (_currentFolderId == folder.id) {
      _currentFolderId = null;
      _currentFolder = null;
    }
    await _loadNotebooks();
  }

  Future<bool> _confirmDeleteFolder(NotebookFolder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: const Text('Delete folder?'),
          content: Text(
            '${folder.name} will be removed. Notebooks inside it will move back to the library.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
          ],
        );
      },
    );

    return confirmed ?? false;
  }

  Future<void> _renameNotebook(Notebook notebook) async {
    final title = await _promptName(
      dialogTitle: 'Rename notebook',
      labelText: 'Notebook title',
      initialValue: notebook.title,
    );
    if (title == null) {
      return;
    }

    await widget.notebookRepository.renameNotebook(notebook, title);
    await _loadNotebooks();
  }

  Future<String?> _promptName({
    required String dialogTitle,
    required String labelText,
    required String initialValue,
  }) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _NamePromptDialog(
        title: dialogTitle,
        labelText: labelText,
        initialValue: initialValue,
      ),
    );

    if (result == null || result.trim().isEmpty) {
      return null;
    }

    return result.trim();
  }

  Future<void> _moveNotebook(Notebook notebook) async {
    final folders = await widget.notebookRepository.listFolders();
    if (!mounted) {
      return;
    }

    final destination = await showDialog<String>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Move notebook'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(''),
              child: const ListTile(
                leading: Icon(Icons.home_outlined),
                title: Text('Library'),
              ),
            ),
            for (final folder in folders)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(folder.id),
                child: ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(folder.name),
                ),
              ),
          ],
        );
      },
    );

    if (destination == null) {
      return;
    }

    final folderId = destination.isEmpty ? null : destination;
    await widget.notebookRepository.moveNotebookToFolder(notebook, folderId);
    await _loadNotebooks();
  }

  Future<void> _duplicateNotebook(Notebook notebook) async {
    await widget.notebookRepository.duplicateNotebook(notebook);
    if (_showArchived) {
      setState(() {
        _showArchived = false;
        _isLoading = true;
      });
    }
    await _loadNotebooks();
    unawaited(_checkCloudAfterSignIn(force: true));
  }

  Future<void> _setNotebookArchived(Notebook notebook, bool isArchived) async {
    await widget.notebookRepository.setNotebookArchived(notebook, isArchived);
    await _loadNotebooks();
  }

  Future<void> _deleteNotebook(Notebook notebook) async {
    final shouldDelete = await _confirmDeleteNotebook(notebook);
    if (!shouldDelete) {
      return;
    }

    await widget.notebookRepository.deleteNotebook(notebook);
    await _loadNotebooks();
    await _syncLocalNotebookDeletion();
  }

  Future<void> _syncLocalNotebookDeletion() async {
    final session = widget.authController.session;
    final service = widget.firstSignInSyncService;
    if (session == null || service == null) return;
    setState(() {
      _syncStatus = const _LibrarySyncStatus(
        _LibrarySyncPhase.syncing,
        'Synchronizing the deletion to the cloud…',
      );
    });
    try {
      final pushResult = await service.pushIncremental(
        userId: session.user.id,
        deviceId: session.device.id,
      );
      final pullResult = await service.pullIncremental(
        userId: session.user.id,
        deviceId: session.device.id,
      );
      if (!mounted) return;
      setState(() {
        _pendingConflicts = pullResult.pendingConflicts;
        _activeTombstones = pullResult.activeTombstones;
      });
      if (pushResult.preservedDeleteEditCount > 0) {
        setState(() {
          _syncStatus = const _LibrarySyncStatus(
            _LibrarySyncPhase.preservedEdit,
            'New edits from another device conflicted with the deletion. The edits were preserved automatically; no action is needed.',
          );
        });
      } else if (pullResult.confirmedLocalDeletionCount > 0 ||
          pullResult.confirmedLocalFolderDeletionCount > 0) {
        setState(() {
          _syncStatus = const _LibrarySyncStatus(
            _LibrarySyncPhase.completed,
            'The deletion was synchronized to the cloud. Other devices will update on their next sync.',
          );
        });
      } else if (pullResult.status ==
              IncrementalSyncPullStatus.requiresReconciliation ||
          pushResult.preservedConflictCount > 0) {
        setState(() {
          _syncStatus = const _LibrarySyncStatus(
            _LibrarySyncPhase.needsAttention,
            'The deletion requires reconciliation. Neither local nor cloud content was overwritten.',
          );
        });
      } else {
        setState(() {
          _syncStatus = const _LibrarySyncStatus(
            _LibrarySyncPhase.completed,
            'Deletion synchronization completed.',
          );
        });
      }
    } on IncrementalSyncPushException catch (error) {
      if (!mounted) return;
      setState(() {
        _syncStatus = _LibrarySyncStatus(
          _LibrarySyncPhase.failed,
          'The notebook was deleted from this device. ${_counted(error.pendingOperationCount, 'change')} ${error.pendingOperationCount == 1 ? 'remains' : 'remain'} safely stored and ready to retry.',
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _syncStatus = const _LibrarySyncStatus(
          _LibrarySyncPhase.failed,
          'The notebook was deleted from this device. The cloud deletion remains safely queued until the network is available.',
        );
      });
    }
  }

  Future<bool> _confirmDeleteNotebook(Notebook notebook) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: const Text('Delete notebook?'),
          content: Text(
            '${notebook.title} will be permanently removed from this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
          ],
        );
      },
    );

    return confirmed ?? false;
  }

  Future<void> _openAccount() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AccountScreen(
          controller: widget.authController,
          onDeveloperDataReset: widget.developerDataResetService == null
              ? null
              : _resetDeveloperData,
        ),
      ),
    );
    if (!mounted) return;
    _handleAuthChanged();
  }

  Future<void> _resetDeveloperData(DeveloperDataResetScope scope) async {
    final service = widget.developerDataResetService;
    if (service == null || _developerDataResetInProgress) {
      return;
    }

    _developerDataResetInProgress = true;
    _syncDebounceTimer?.cancel();
    _syncRequestedWhileRunning = false;
    _pullRequestedWhileRunning = false;
    try {
      await _syncIdleCompleter?.future;
      if (widget.authController.isSignedIn) {
        await widget.authController.logout();
      }
      await service.reset(scope);
      if (!mounted) return;
      setState(() {
        _checkedSessionKey = null;
        _pendingConflicts = const [];
        _structuralConflicts = const [];
        _activeTombstones = const [];
        _syncStatus = _LibrarySyncStatus.idle;
        if (scope != DeveloperDataResetScope.syncState) {
          _showArchived = false;
          _currentFolderId = null;
          _currentFolder = null;
        }
      });
      await _loadNotebooks();
    } finally {
      _developerDataResetInProgress = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleFolders = _visibleFolders;
    final visibleNotebooks = _visibleNotebooks;
    final colorScheme = Theme.of(context).colorScheme;
    final libraryTitle = _showArchived
        ? 'Archived'
        : _currentFolder?.name ?? 'My Library';
    final itemCount = visibleFolders.length + visibleNotebooks.length;
    final librarySummary = _isLoading
        ? 'Loading library…'
        : _searchQuery.isNotEmpty
        ? '$itemCount match${itemCount == 1 ? '' : 'es'}'
        : _showArchived
        ? '${visibleNotebooks.length} archived notebook${visibleNotebooks.length == 1 ? '' : 's'}'
        : _currentFolderId != null
        ? '${visibleNotebooks.length} notebook${visibleNotebooks.length == 1 ? '' : 's'}'
        : '${visibleFolders.length} folder${visibleFolders.length == 1 ? '' : 's'} · ${visibleNotebooks.length} notebook${visibleNotebooks.length == 1 ? '' : 's'}';

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: Column(
          children: [
            _LibraryHeader(
              title: libraryTitle,
              summary: librarySummary,
              showBack: _showArchived || _currentFolderId != null,
              showNewFolder: !_showArchived && _currentFolderId == null,
              showArchived: _showArchived,
              searchController: _searchController,
              sortMode: _sortMode,
              onShowLibrary: _showRootLibrary,
              onSearchChanged: _updateSearchQuery,
              onClearSearch: _clearSearch,
              onSortChanged: _setSortMode,
              onToggleArchived: _toggleArchivedView,
              onCreateFolder: _createFolder,
              onImportPdf: _importPdf,
              onCreateNotebook: _createNotebook,
              authController: widget.authController,
              onOpenAccount: _openAccount,
              pendingConflictCount:
                  _pendingConflicts.length + _structuralConflicts.length,
              onOpenConflicts: _openSyncConflicts,
              recentlyDeletedCount: _activeTombstones.length,
              onOpenRecentlyDeleted: _openRecentlyDeleted,
              syncAvailable:
                  widget.authController.agreementsCurrent &&
                  widget.firstSignInSyncService != null,
              syncStatus: _syncStatus,
              onOpenSyncStatus: _openSyncStatus,
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : visibleNotebooks.isEmpty && visibleFolders.isEmpty
                  ? _searchQuery.isEmpty
                        ? _EmptyLibrary(
                            showArchived: _showArchived,
                            folderName: _currentFolder?.name,
                            onCreateNotebook: _createNotebook,
                            onImportPdf: _importPdf,
                          )
                        : _NoSearchResults(query: _searchQuery)
                  : _LibraryBookshelf(
                      folders: visibleFolders,
                      notebooks: visibleNotebooks,
                      showArchived: _showArchived,
                      onOpenFolder: _openFolder,
                      onRenameFolder: (folder) => _renameFolder(folder),
                      onDeleteFolder: (folder) => _deleteFolder(folder),
                      onOpenNotebook: _openNotebook,
                      onRenameNotebook: (notebook) => _renameNotebook(notebook),
                      onDuplicateNotebook: (notebook) =>
                          _duplicateNotebook(notebook),
                      onMoveNotebook: (notebook) => _moveNotebook(notebook),
                      onArchiveNotebook: (notebook) =>
                          _setNotebookArchived(notebook, true),
                      onRestoreNotebook: (notebook) =>
                          _setNotebookArchived(notebook, false),
                      onDeleteNotebook: (notebook) => _deleteNotebook(notebook),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StructuralVersionCard extends StatelessWidget {
  const _StructuralVersionCard({required this.title, required this.summary});

  final String title;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: ListTile(title: Text(title), subtitle: Text(summary)),
      ),
    );
  }
}

String _structuralConflictTitle(SyncStructuralConflict conflict) =>
    switch (conflict.resourceType) {
      SyncResourceType.folder => 'Folder Structure Conflict',
      SyncResourceType.notebook => 'Notebook Structure Conflict',
      SyncResourceType.page => 'Page Property Conflict',
      SyncResourceType.infiniteCanvas => 'Canvas Background Conflict',
    };

String _structuralFieldLabel(String field) => switch (field) {
  'name' => 'Name',
  'title' => 'Title',
  'isArchived' => 'Archive Status',
  'folderId' => 'Folder',
  'pageOrder' => 'Page Order',
  'template' => 'Paper Template',
  'rotationQuarterTurns' => 'Page Orientation',
  'width' || 'height' => 'Page Size',
  'coordinateSpaceVersion' => 'Coordinate Version',
  'background' => 'Canvas Background',
  _ => field,
};

String _structuralMetadataSummary(
  Map<String, Object?> metadata,
  List<String> fields,
) {
  final summaries = <String>[];
  for (final field in fields) {
    if (field == 'width' || field == 'height') {
      if (summaries.any((item) => item.startsWith('Page Size:'))) continue;
      summaries.add('Page Size: ${metadata['width']} × ${metadata['height']}');
      continue;
    }
    final value = metadata[field];
    final display = switch ((field, value)) {
      ('isArchived', true) => 'Archived',
      ('isArchived', false) => 'Not archived',
      ('folderId', null) => 'Library root',
      ('pageOrder', List<Object?> order) =>
        'Defined order of ${order.length} pages',
      ('rotationQuarterTurns', int turns) => '${turns * 90}°',
      (_, null) => 'None',
      _ => value.toString(),
    };
    summaries.add('${_structuralFieldLabel(field)}: $display');
  }
  return summaries.join('\n');
}

Color _libraryFurnitureColor(ColorScheme colorScheme) {
  return Color.alphaBlend(
    colorScheme.primary.withValues(alpha: 0.14),
    colorScheme.surfaceContainerHigh,
  );
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({
    required this.title,
    required this.summary,
    required this.showBack,
    required this.showNewFolder,
    required this.showArchived,
    required this.searchController,
    required this.sortMode,
    required this.onShowLibrary,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onSortChanged,
    required this.onToggleArchived,
    required this.onCreateFolder,
    required this.onImportPdf,
    required this.onCreateNotebook,
    required this.authController,
    required this.onOpenAccount,
    required this.pendingConflictCount,
    required this.onOpenConflicts,
    required this.recentlyDeletedCount,
    required this.onOpenRecentlyDeleted,
    required this.syncAvailable,
    required this.syncStatus,
    required this.onOpenSyncStatus,
  });

  final String title;
  final String summary;
  final bool showBack;
  final bool showNewFolder;
  final bool showArchived;
  final TextEditingController searchController;
  final _LibrarySortMode sortMode;
  final VoidCallback onShowLibrary;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<_LibrarySortMode> onSortChanged;
  final VoidCallback onToggleArchived;
  final VoidCallback onCreateFolder;
  final VoidCallback onImportPdf;
  final VoidCallback onCreateNotebook;
  final AuthController authController;
  final VoidCallback onOpenAccount;
  final int pendingConflictCount;
  final VoidCallback onOpenConflicts;
  final int recentlyDeletedCount;
  final VoidCallback onOpenRecentlyDeleted;
  final bool syncAvailable;
  final _LibrarySyncStatus syncStatus;
  final VoidCallback onOpenSyncStatus;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: colorScheme.surfaceContainerLowest,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final phoneLayout = constraints.maxWidth < _phoneLibraryBreakpoint;
            final horizontalPadding = phoneLayout
                ? 12.0
                : constraints.maxWidth < 600
                ? 16.0
                : 24.0;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                14,
                horizontalPadding,
                16,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      if (showBack) ...[
                        IconButton(
                          onPressed: onShowLibrary,
                          tooltip: 'Show library',
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        SizedBox(width: phoneLayout ? 0 : 4),
                      ],
                      if (!phoneLayout) ...[
                        ExcludeSemantics(
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: _libraryFurnitureColor(colorScheme),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: colorScheme.outlineVariant,
                              ),
                            ),
                            child: Icon(
                              Icons.local_library_outlined,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!phoneLayout)
                              Text(
                                'InkNest Notes',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.labelMedium?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                height: 1.05,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              summary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: phoneLayout ? 2 : 8),
                      if (syncAvailable) ...[
                        IconButton(
                          key: const ValueKey('library-sync-status'),
                          onPressed: onOpenSyncStatus,
                          tooltip: _syncStatusTitle(syncStatus.phase),
                          icon: _syncStatusIcon(context, syncStatus.phase),
                        ),
                        SizedBox(width: phoneLayout ? 0 : 8),
                      ],
                      if (pendingConflictCount > 0) ...[
                        Badge.count(
                          count: pendingConflictCount,
                          child: IconButton(
                            key: const ValueKey('library-sync-conflicts'),
                            onPressed: onOpenConflicts,
                            tooltip: '$pendingConflictCount sync conflicts',
                            icon: const Icon(Icons.sync_problem_outlined),
                          ),
                        ),
                        SizedBox(width: phoneLayout ? 0 : 8),
                      ],
                      if (recentlyDeletedCount > 0) ...[
                        Badge.count(
                          count: recentlyDeletedCount,
                          child: IconButton(
                            key: const ValueKey('library-recently-deleted'),
                            onPressed: onOpenRecentlyDeleted,
                            tooltip:
                                '$recentlyDeletedCount recently deleted items',
                            icon: const Icon(Icons.restore_from_trash_outlined),
                          ),
                        ),
                        SizedBox(width: phoneLayout ? 0 : 8),
                      ],
                      _LibraryAccountButton(
                        controller: authController,
                        onPressed: onOpenAccount,
                      ),
                      if (!phoneLayout || !showArchived) ...[
                        SizedBox(width: phoneLayout ? 0 : 8),
                        IconButton.filledTonal(
                          onPressed: onImportPdf,
                          tooltip: 'Import PDF',
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                        ),
                        SizedBox(width: phoneLayout ? 0 : 8),
                        IconButton.filled(
                          onPressed: onCreateNotebook,
                          tooltip: 'New notebook',
                          icon: const Icon(Icons.add_rounded),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  _LibraryCommandBar(
                    phone: phoneLayout,
                    searchController: searchController,
                    sortMode: sortMode,
                    showNewFolder: showNewFolder,
                    showArchived: showArchived,
                    onSearchChanged: onSearchChanged,
                    onClearSearch: onClearSearch,
                    onSortChanged: onSortChanged,
                    onToggleArchived: onToggleArchived,
                    onCreateFolder: onCreateFolder,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

String _syncStatusTitle(_LibrarySyncPhase phase) => switch (phase) {
  _LibrarySyncPhase.idle => 'Sync Status',
  _LibrarySyncPhase.syncing => 'Synchronizing',
  _LibrarySyncPhase.completed => 'Sync Complete',
  _LibrarySyncPhase.needsAttention => 'Sync Needs Attention',
  _LibrarySyncPhase.failed => 'Sync Failed',
  _LibrarySyncPhase.preservedEdit => 'Edit Preserved',
};

String _counted(int count, String singular, [String? plural]) {
  if (count == 1) return '$count $singular';
  return '$count ${plural ?? '${singular}s'}';
}

Widget _syncStatusIcon(BuildContext context, _LibrarySyncPhase phase) {
  if (phase == _LibrarySyncPhase.syncing) {
    return const SizedBox.square(
      dimension: 20,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
  final colorScheme = Theme.of(context).colorScheme;
  return Icon(
    switch (phase) {
      _LibrarySyncPhase.idle => Icons.cloud_outlined,
      _LibrarySyncPhase.syncing => Icons.sync_rounded,
      _LibrarySyncPhase.completed => Icons.cloud_done_outlined,
      _LibrarySyncPhase.needsAttention => Icons.sync_problem_outlined,
      _LibrarySyncPhase.failed => Icons.cloud_off_outlined,
      _LibrarySyncPhase.preservedEdit => Icons.cloud_done_outlined,
    },
    color: switch (phase) {
      _LibrarySyncPhase.failed => colorScheme.error,
      _LibrarySyncPhase.needsAttention => colorScheme.tertiary,
      _ => null,
    },
  );
}

class _LibraryAccountButton extends StatelessWidget {
  const _LibraryAccountButton({
    required this.controller,
    required this.onPressed,
  });

  final AuthController controller;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final session = controller.session;
        if (controller.status == AuthStatus.restoring) {
          return IconButton(
            key: const ValueKey('library-account-restoring'),
            onPressed: onPressed,
            tooltip: 'Restoring account',
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            icon: const Icon(Icons.manage_accounts_outlined),
          );
        }
        return IconButton(
          key: const ValueKey('library-account-button'),
          onPressed: onPressed,
          tooltip: session == null
              ? 'Sign in'
              : 'Account: ${session.user.email}',
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          icon: session == null
              ? const Icon(Icons.account_circle_outlined)
              : CircleAvatar(
                  radius: 15,
                  child: Text(session.user.email.substring(0, 1).toUpperCase()),
                ),
        );
      },
    );
  }
}

class _LibraryCommandBar extends StatelessWidget {
  const _LibraryCommandBar({
    required this.phone,
    required this.searchController,
    required this.sortMode,
    required this.showNewFolder,
    required this.showArchived,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onSortChanged,
    required this.onToggleArchived,
    required this.onCreateFolder,
  });

  final bool phone;
  final TextEditingController searchController;
  final _LibrarySortMode sortMode;
  final bool showNewFolder;
  final bool showArchived;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<_LibrarySortMode> onSortChanged;
  final VoidCallback onToggleArchived;
  final VoidCallback onCreateFolder;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final search = _LibrarySearchBar(
      controller: searchController,
      onChanged: onSearchChanged,
      onClear: onClearSearch,
      compact: phone,
    );
    final sortControl = _LibrarySortControl(
      mode: sortMode,
      onSelected: onSortChanged,
      compact: phone,
      expanded: false,
    );
    final controls = <Widget>[
      if (phone) SizedBox(width: 108, child: sortControl) else sortControl,
      if (showNewFolder) ...[
        SizedBox(width: phone ? 4 : 6),
        _LibraryHeaderIconButton(
          onPressed: onCreateFolder,
          tooltip: 'New folder',
          icon: const Icon(Icons.create_new_folder_outlined),
        ),
      ],
      SizedBox(width: phone ? 4 : 6),
      _LibraryHeaderIconButton(
        onPressed: onToggleArchived,
        tooltip: showArchived ? 'Show notebooks' : 'Show archived',
        icon: Icon(
          showArchived ? Icons.inventory_2 : Icons.inventory_2_outlined,
        ),
      ),
    ];

    return Container(
      key: const ValueKey('library-command-bar'),
      padding: phone ? EdgeInsets.zero : const EdgeInsets.all(8),
      decoration: phone
          ? null
          : BoxDecoration(
              color: _libraryFurnitureColor(colorScheme),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: search),
          SizedBox(width: phone ? 6 : 8),
          ...controls,
        ],
      ),
    );
  }
}

class _LibrarySortControl extends StatelessWidget {
  const _LibrarySortControl({
    required this.mode,
    required this.onSelected,
    this.compact = false,
    this.expanded = false,
  });

  final _LibrarySortMode mode;
  final ValueChanged<_LibrarySortMode> onSelected;
  final bool compact;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      button: true,
      label: 'Sort notebooks: ${mode.label}',
      child: PopupMenuButton<_LibrarySortMode>(
        tooltip: 'Sort notebooks',
        initialValue: mode,
        onSelected: onSelected,
        style: compact
            ? const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap)
            : null,
        itemBuilder: (context) {
          return [
            for (final option in _LibrarySortMode.values)
              CheckedPopupMenuItem<_LibrarySortMode>(
                value: option,
                checked: option == mode,
                child: Text(option.label),
              ),
          ];
        },
        child: ExcludeSemantics(
          child: Container(
            height: compact ? 44 : 48,
            width: expanded ? double.infinity : null,
            constraints: BoxConstraints(minWidth: compact ? 0 : 116),
            padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 14),
            decoration: BoxDecoration(
              color: compact
                  ? colorScheme.surfaceContainerHighest
                  : colorScheme.surface,
              borderRadius: BorderRadius.circular(compact ? 14 : 10),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Row(
              mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
              children: [
                Icon(Icons.sort_rounded, size: compact ? 18 : 20),
                SizedBox(width: compact ? 6 : 8),
                if (expanded || compact)
                  Flexible(
                    child: Text(
                      mode.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  Text(mode.label),
                const SizedBox(width: 4),
                const Icon(Icons.expand_more_rounded, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LibraryHeaderIconButton extends StatelessWidget {
  const _LibraryHeaderIconButton({
    required this.onPressed,
    required this.tooltip,
    required this.icon,
  });

  final VoidCallback onPressed;
  final String tooltip;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      style: IconButton.styleFrom(
        backgroundColor: colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      icon: icon,
    );
  }
}

class _LibrarySearchBar extends StatelessWidget {
  const _LibrarySearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    this.compact = false,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: compact ? 44 : 48,
      child: TextField(
        key: const ValueKey('library-search-field'),
        controller: controller,
        decoration: InputDecoration(
          hintText: 'Search notebooks',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  onPressed: onClear,
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close_rounded),
                ),
          filled: true,
          fillColor: colorScheme.surface,
          contentPadding: EdgeInsets.symmetric(horizontal: compact ? 12 : 14),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(compact ? 14 : 10),
            borderSide: BorderSide(color: colorScheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(compact ? 14 : 10),
            borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
          ),
        ),
        textInputAction: TextInputAction.search,
        onChanged: onChanged,
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      ),
    );
  }
}

class _NoSearchResults extends StatelessWidget {
  const _NoSearchResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 20),
            Text(
              'No matching notebooks',
              textAlign: TextAlign.center,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              query,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({
    required this.showArchived,
    required this.folderName,
    required this.onCreateNotebook,
    required this.onImportPdf,
  });

  final bool showArchived;
  final String? folderName;
  final VoidCallback onCreateNotebook;
  final VoidCallback onImportPdf;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.edit_note,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                showArchived
                    ? 'No archived notebooks'
                    : folderName == null
                    ? 'No notebooks yet'
                    : 'No notebooks in $folderName',
                textAlign: TextAlign.center,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                showArchived
                    ? 'Archived notebooks will appear here until you restore or delete them.'
                    : folderName == null
                    ? 'Create your first notebook to start sketching ideas, class notes, and PDF annotations.'
                    : 'Move notebooks into this folder or create a new notebook here.',
                textAlign: TextAlign.center,
                style: textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (!showArchived) ...[
                const SizedBox(height: 28),
                Align(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: onCreateNotebook,
                        icon: const Icon(Icons.add),
                        label: const Text('New notebook'),
                      ),
                      OutlinedButton.icon(
                        onPressed: onImportPdf,
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Import PDF'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NamePromptDialog extends StatefulWidget {
  const _NamePromptDialog({
    required this.title,
    required this.labelText,
    required this.initialValue,
  });

  final String title;
  final String labelText;
  final String initialValue;

  @override
  State<_NamePromptDialog> createState() => _NamePromptDialogState();
}

class _NamePromptDialogState extends State<_NamePromptDialog> {
  late final TextEditingController _controller;

  bool get _canSave => _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _controller.addListener(_handleNameChanged);
  }

  void _handleNameChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_handleNameChanged);
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (!_canSave) return;
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.labelText),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canSave ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _LibraryBookshelf extends StatelessWidget {
  const _LibraryBookshelf({
    required this.folders,
    required this.notebooks,
    required this.showArchived,
    required this.onOpenFolder,
    required this.onRenameFolder,
    required this.onDeleteFolder,
    required this.onOpenNotebook,
    required this.onRenameNotebook,
    required this.onDuplicateNotebook,
    required this.onMoveNotebook,
    required this.onArchiveNotebook,
    required this.onRestoreNotebook,
    required this.onDeleteNotebook,
  });

  final List<NotebookFolder> folders;
  final List<Notebook> notebooks;
  final bool showArchived;
  final ValueChanged<NotebookFolder> onOpenFolder;
  final ValueChanged<NotebookFolder> onRenameFolder;
  final ValueChanged<NotebookFolder> onDeleteFolder;
  final ValueChanged<Notebook> onOpenNotebook;
  final ValueChanged<Notebook> onRenameNotebook;
  final ValueChanged<Notebook> onDuplicateNotebook;
  final ValueChanged<Notebook> onMoveNotebook;
  final ValueChanged<Notebook> onArchiveNotebook;
  final ValueChanged<Notebook> onRestoreNotebook;
  final ValueChanged<Notebook> onDeleteNotebook;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 600 ? 16.0 : 24.0;
        final boundedWidth = math.min(constraints.maxWidth, 1280.0).toDouble();
        final contentWidth = math
            .max(1.0, boundedWidth - horizontalPadding * 2)
            .toDouble();
        final itemCount = folders.length + notebooks.length;
        final itemWidths = [
          for (var index = 0; index < itemCount; index++)
            _itemWidth(index, contentWidth),
        ];
        final rows = _packRows(itemWidths, contentWidth);

        return ListView.builder(
          key: const ValueKey('library-bookshelf'),
          padding: EdgeInsets.fromLTRB(
            math
                .max(
                  horizontalPadding,
                  (constraints.maxWidth - boundedWidth) / 2 + horizontalPadding,
                )
                .toDouble(),
            20,
            math
                .max(
                  horizontalPadding,
                  (constraints.maxWidth - boundedWidth) / 2 + horizontalPadding,
                )
                .toDouble(),
            32,
          ),
          itemCount: rows.length,
          itemBuilder: (context, rowIndex) {
            final rowItems = rows[rowIndex];

            return Padding(
              padding: EdgeInsets.only(
                bottom: rowIndex == rows.length - 1 ? 0 : 24,
              ),
              child: _BookshelfRow(
                rowIndex: rowIndex,
                itemWidths: [for (final item in rowItems) itemWidths[item]],
                itemBuilder: (rowItemIndex) {
                  return _buildItem(rowItems[rowItemIndex]);
                },
              ),
            );
          },
        );
      },
    );
  }

  double _itemWidth(int index, double contentWidth) {
    final minimumWidth = contentWidth < 420
        ? 52.0
        : contentWidth < 720
        ? 54.0
        : 56.0;
    final maximumWidth = contentWidth < 420
        ? 74.0
        : contentWidth < 720
        ? 82.0
        : 88.0;

    if (index < folders.length) {
      return math.min(maximumWidth, minimumWidth + 14).toDouble();
    }

    final notebook = notebooks[index - folders.length];
    final pageCount = notebook.layoutMode == NotebookLayoutMode.infiniteCanvas
        ? 1
        : math.max(1, notebook.pageIds.length);
    final width = minimumWidth + math.log(pageCount + 1) / math.ln10 * 10;
    return width.clamp(minimumWidth, maximumWidth).toDouble();
  }

  List<List<int>> _packRows(List<double> itemWidths, double contentWidth) {
    final rows = <List<int>>[];
    var currentRow = <int>[];
    var currentWidth = 0.0;

    for (var index = 0; index < itemWidths.length; index++) {
      final itemWidth = itemWidths[index];
      if (currentRow.isNotEmpty && currentWidth + itemWidth > contentWidth) {
        rows.add(currentRow);
        currentRow = <int>[];
        currentWidth = 0;
      }

      currentRow.add(index);
      currentWidth += itemWidth;
    }

    if (currentRow.isNotEmpty) {
      rows.add(currentRow);
    }

    return rows;
  }

  Widget _buildItem(int index) {
    if (index < folders.length) {
      final folder = folders[index];
      return _FolderCard(
        folder: folder,
        onTap: () => onOpenFolder(folder),
        onRename: () => onRenameFolder(folder),
        onDelete: () => onDeleteFolder(folder),
      );
    }

    final notebook = notebooks[index - folders.length];
    return _NotebookCard(
      notebook: notebook,
      showArchived: showArchived,
      onTap: () => onOpenNotebook(notebook),
      onRename: () => onRenameNotebook(notebook),
      onDuplicate: () => onDuplicateNotebook(notebook),
      onMove: () => onMoveNotebook(notebook),
      onArchive: () => onArchiveNotebook(notebook),
      onRestore: () => onRestoreNotebook(notebook),
      onDelete: () => onDeleteNotebook(notebook),
    );
  }
}

class _BookshelfRow extends StatelessWidget {
  const _BookshelfRow({
    required this.rowIndex,
    required this.itemWidths,
    required this.itemBuilder,
  });

  final int rowIndex;
  final List<double> itemWidths;
  final Widget Function(int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: ValueKey('library-bookshelf-row-$rowIndex'),
      height: 270,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 24,
            child: _ShelfRail(),
          ),
          Positioned.fill(
            bottom: 20,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (
                    var columnIndex = 0;
                    columnIndex < itemWidths.length;
                    columnIndex++
                  )
                    SizedBox(
                      width: itemWidths[columnIndex],
                      child: itemBuilder(columnIndex),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShelfRail extends StatelessWidget {
  const _ShelfRail();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final shelfColor = _libraryFurnitureColor(colorScheme);

    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: shelfColor,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(5),
            bottom: Radius.circular(3),
          ),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.8),
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.16),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.72),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  const _FolderCard({
    required this.folder,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final NotebookFolder folder;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  void _handleAction(_FolderAction action) {
    switch (action) {
      case _FolderAction.rename:
        onRename();
        break;
      case _FolderAction.delete:
        onDelete();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _LibrarySpine(
      key: ValueKey('folder-spine-${folder.id}'),
      semanticsLabel: 'Open folder ${folder.name}',
      onTap: onTap,
      backgroundColor: const Color(0xFF6D5845),
      height: 246,
      leanAngle: _spineLeanAngle,
      leadingIcon: Icons.folder_copy_outlined,
      title: folder.name,
      metadata: 'Folder',
      action: _FolderActionMenu(
        folderName: folder.name,
        foregroundColor: Colors.white,
        onSelected: _handleAction,
      ),
    );
  }
}

class _NotebookCard extends StatefulWidget {
  const _NotebookCard({
    required this.notebook,
    required this.showArchived,
    required this.onTap,
    required this.onRename,
    required this.onDuplicate,
    required this.onMove,
    required this.onArchive,
    required this.onRestore,
    required this.onDelete,
  });

  final Notebook notebook;
  final bool showArchived;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDuplicate;
  final VoidCallback onMove;
  final VoidCallback onArchive;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  State<_NotebookCard> createState() => _NotebookCardState();
}

class _NotebookCardState extends State<_NotebookCard> {
  bool _isOpening = false;
  bool _isPinnedForInspection = false;
  bool _isHovered = false;
  bool _isFocused = false;

  bool get _isInspecting => _isPinnedForInspection || _isHovered || _isFocused;

  bool get _isPulledOut => _isOpening || _isInspecting;

  Future<void> _handleTap() async {
    if (_isOpening) {
      return;
    }

    final opensImmediately =
        _isInspecting || MediaQuery.of(context).disableAnimations;
    if (!opensImmediately) {
      setState(() {
        _isOpening = true;
      });
      await Future<void>.delayed(_spinePullDuration);
      if (!mounted || !_isOpening) {
        return;
      }
    }

    widget.onTap();
    if (!mounted) {
      return;
    }

    setState(() {
      _isOpening = false;
      _isPinnedForInspection = false;
      _isHovered = false;
      _isFocused = false;
    });
  }

  void _inspect() {
    if (_isOpening || _isPinnedForInspection) {
      return;
    }
    setState(() {
      _isPinnedForInspection = true;
    });
  }

  void _handleHover(bool isHovered) {
    if (_isHovered == isHovered) {
      return;
    }
    setState(() {
      _isHovered = isHovered;
    });
  }

  void _handleFocusChange(bool isFocused) {
    if (_isFocused == isFocused) {
      return;
    }
    setState(() {
      _isFocused = isFocused;
    });
  }

  void _clearInspection() {
    if (!_isInspecting) {
      return;
    }
    setState(() {
      _isPinnedForInspection = false;
      _isHovered = false;
      _isFocused = false;
    });
  }

  void _handleAction(_NotebookAction action) {
    _clearInspection();
    switch (action) {
      case _NotebookAction.rename:
        widget.onRename();
        break;
      case _NotebookAction.duplicate:
        widget.onDuplicate();
        break;
      case _NotebookAction.move:
        widget.onMove();
        break;
      case _NotebookAction.archive:
        widget.onArchive();
        break;
      case _NotebookAction.restore:
        widget.onRestore();
        break;
      case _NotebookAction.delete:
        widget.onDelete();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final notebook = widget.notebook;
    final visualSeed = _stableVisualSeed(notebook.id);
    final backgroundColor =
        _notebookSpinePalette[visualSeed % _notebookSpinePalette.length];
    const heights = [224.0, 232.0, 240.0, 246.0, 236.0];

    return TapRegion(
      onTapOutside: (_) => _clearInspection(),
      child: _LibrarySpine(
        key: ValueKey('notebook-spine-${notebook.id}'),
        semanticsLabel: notebook.layoutMode == NotebookLayoutMode.infiniteCanvas
            ? 'Open infinite canvas notebook ${notebook.title}'
            : 'Open notebook ${notebook.title}',
        onTap: () => unawaited(_handleTap()),
        onLongPress: _inspect,
        onHover: _handleHover,
        onFocusChange: _handleFocusChange,
        isPulledOut: _isPulledOut,
        showTitleTip: _isInspecting,
        backgroundColor: backgroundColor,
        height: heights[visualSeed % heights.length],
        leanAngle: _spineLeanAngle,
        leadingIcon: widget.showArchived
            ? Icons.inventory_2_outlined
            : notebook.layoutMode == NotebookLayoutMode.infiniteCanvas
            ? Icons.gesture
            : Icons.auto_stories_outlined,
        title: notebook.title,
        metadata: notebook.layoutMode == NotebookLayoutMode.infiniteCanvas
            ? '∞'
            : '${notebook.pageIds.length}p',
        action: _NotebookActionMenu(
          notebookTitle: notebook.title,
          showArchived: widget.showArchived,
          foregroundColor: Colors.white,
          onSelected: _handleAction,
        ),
      ),
    );
  }
}

const _notebookSpinePalette = <Color>[
  Color(0xFF2F6F73),
  Color(0xFF8A5D4A),
  Color(0xFF58688E),
  Color(0xFF5E7354),
  Color(0xFF795D76),
  Color(0xFF946A47),
];

const _spineLeanAngle = -math.pi / 60;
const _spinePullDuration = Duration(milliseconds: 200);

int _stableVisualSeed(String value) {
  var result = 0;
  for (final codeUnit in value.codeUnits) {
    result = (result * 31 + codeUnit) & 0x7fffffff;
  }
  return result;
}

class _LibrarySpine extends StatefulWidget {
  const _LibrarySpine({
    super.key,
    required this.semanticsLabel,
    required this.onTap,
    this.onLongPress,
    this.onHover,
    this.onFocusChange,
    this.isPulledOut = false,
    this.showTitleTip = false,
    required this.backgroundColor,
    required this.height,
    required this.leanAngle,
    required this.leadingIcon,
    required this.title,
    required this.metadata,
    required this.action,
  });

  final String semanticsLabel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onHover;
  final ValueChanged<bool>? onFocusChange;
  final bool isPulledOut;
  final bool showTitleTip;
  final Color backgroundColor;
  final double height;
  final double leanAngle;
  final IconData leadingIcon;
  final String title;
  final String metadata;
  final Widget action;

  @override
  State<_LibrarySpine> createState() => _LibrarySpineState();
}

class _LibrarySpineState extends State<_LibrarySpine> {
  final _tooltipKey = GlobalKey<TooltipState>();
  bool _tooltipScheduled = false;

  void _scheduleTooltip() {
    if (_tooltipScheduled) {
      return;
    }
    _tooltipScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tooltipScheduled = false;
      if (mounted && widget.showTitleTip) {
        _tooltipKey.currentState?.ensureTooltipVisible();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final isVisuallyPulledOut = widget.isPulledOut && !reduceMotion;
    final motionDuration = reduceMotion ? Duration.zero : _spinePullDuration;
    const foregroundColor = Colors.white;
    const borderRadius = BorderRadius.vertical(
      top: Radius.circular(6),
      bottom: Radius.circular(2),
    );
    final titleStyle =
        textTheme.labelLarge?.copyWith(
          color: foregroundColor,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ) ??
        const TextStyle(
          color: foregroundColor,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        );
    final titlePainter = TextPainter(
      text: TextSpan(text: widget.title, style: titleStyle),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: math.max(0, widget.height - 95));
    final titleIsTruncated = titlePainter.didExceedMaxLines;
    titlePainter.dispose();

    Widget spine = Semantics(
      container: true,
      explicitChildNodes: true,
      button: true,
      selected: widget.isPulledOut,
      label: widget.semanticsLabel,
      child: AnimatedSlide(
        key: ValueKey('spine-slide-${widget.semanticsLabel}'),
        offset: isVisuallyPulledOut ? const Offset(0, -0.05) : Offset.zero,
        duration: motionDuration,
        curve: Curves.easeOutCubic,
        child: AnimatedScale(
          key: ValueKey('spine-scale-${widget.semanticsLabel}'),
          scale: isVisuallyPulledOut ? 1.04 : 1,
          alignment: Alignment.bottomCenter,
          duration: motionDuration,
          curve: Curves.easeOutCubic,
          child: Transform.rotate(
            key: ValueKey('spine-lean-${widget.semanticsLabel}'),
            angle: widget.leanAngle,
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
              duration: motionDuration,
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(
                      alpha: isVisuallyPulledOut ? 0.28 : 0.18,
                    ),
                    blurRadius: isVisuallyPulledOut ? 13 : 7,
                    offset: isVisuallyPulledOut
                        ? const Offset(4, 8)
                        : const Offset(2, 4),
                  ),
                ],
              ),
              child: Material(
                color: widget.backgroundColor,
                shape: RoundedRectangleBorder(
                  borderRadius: borderRadius,
                  side: BorderSide(color: Colors.black.withValues(alpha: 0.16)),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  excludeFromSemantics: true,
                  onTap: widget.onTap,
                  onLongPress: widget.onLongPress,
                  onHover: widget.onHover,
                  onFocusChange: widget.onFocusChange,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned(
                        left: 4,
                        top: 0,
                        bottom: 0,
                        width: 2,
                        child: ColoredBox(
                          color: foregroundColor.withValues(alpha: 0.18),
                        ),
                      ),
                      Column(
                        children: [
                          SizedBox(
                            height: 27,
                            child: Center(
                              child: Icon(
                                widget.leadingIcon,
                                size: 16,
                                color: foregroundColor.withValues(alpha: 0.9),
                              ),
                            ),
                          ),
                          Container(
                            height: 1,
                            margin: const EdgeInsets.symmetric(horizontal: 10),
                            color: foregroundColor.withValues(alpha: 0.28),
                          ),
                          Expanded(
                            child: Center(
                              child: RotatedBox(
                                quarterTurns: 1,
                                child: Text(
                                  widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: titleStyle,
                                ),
                              ),
                            ),
                          ),
                          Container(
                            height: 23,
                            alignment: Alignment.center,
                            color: Colors.black.withValues(alpha: 0.08),
                            child: Text(
                              widget.metadata,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.labelSmall?.copyWith(
                                color: foregroundColor.withValues(alpha: 0.88),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          widget.action,
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.showTitleTip && titleIsTruncated) {
      _scheduleTooltip();
      spine = Tooltip(
        key: _tooltipKey,
        message: widget.title,
        excludeFromSemantics: true,
        triggerMode: TooltipTriggerMode.manual,
        showDuration: const Duration(hours: 1),
        preferBelow: false,
        child: spine,
      );
    }

    return SizedBox(height: widget.height, child: spine);
  }
}

enum _FolderAction { rename, delete }

class _FolderActionMenu extends StatelessWidget {
  const _FolderActionMenu({
    required this.folderName,
    required this.foregroundColor,
    required this.onSelected,
  });

  final String folderName;
  final Color foregroundColor;
  final ValueChanged<_FolderAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_FolderAction>(
      tooltip: '$folderName actions',
      padding: EdgeInsets.zero,
      onSelected: onSelected,
      itemBuilder: (context) {
        return [
          _folderActionItem(
            value: _FolderAction.rename,
            icon: Icons.edit_outlined,
            label: 'Rename folder',
          ),
          _folderActionItem(
            value: _FolderAction.delete,
            icon: Icons.delete_outline,
            label: 'Delete folder',
          ),
        ];
      },
      child: SizedBox.square(
        dimension: 44,
        child: Icon(Icons.more_horiz_rounded, size: 20, color: foregroundColor),
      ),
    );
  }
}

PopupMenuItem<_FolderAction> _folderActionItem({
  required _FolderAction value,
  required IconData icon,
  required String label,
}) {
  return PopupMenuItem<_FolderAction>(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 12),
        Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}

enum _NotebookAction { rename, duplicate, move, archive, restore, delete }

class _NotebookActionMenu extends StatelessWidget {
  const _NotebookActionMenu({
    required this.notebookTitle,
    required this.showArchived,
    required this.foregroundColor,
    required this.onSelected,
  });

  final String notebookTitle;
  final bool showArchived;
  final Color foregroundColor;
  final ValueChanged<_NotebookAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_NotebookAction>(
      tooltip: '$notebookTitle actions',
      padding: EdgeInsets.zero,
      onSelected: onSelected,
      itemBuilder: (context) {
        return [
          _notebookActionItem(
            value: _NotebookAction.rename,
            icon: Icons.edit_outlined,
            label: 'Rename notebook',
          ),
          _notebookActionItem(
            value: _NotebookAction.duplicate,
            icon: Icons.copy,
            label: 'Duplicate notebook',
          ),
          if (!showArchived)
            _notebookActionItem(
              value: _NotebookAction.move,
              icon: Icons.drive_file_move_outline,
              label: 'Move notebook',
            ),
          if (showArchived)
            _notebookActionItem(
              value: _NotebookAction.restore,
              icon: Icons.unarchive_outlined,
              label: 'Restore notebook',
            )
          else
            _notebookActionItem(
              value: _NotebookAction.archive,
              icon: Icons.archive_outlined,
              label: 'Archive notebook',
            ),
          _notebookActionItem(
            value: _NotebookAction.delete,
            icon: Icons.delete_outline,
            label: 'Delete notebook',
          ),
        ];
      },
      child: SizedBox.square(
        dimension: 44,
        child: Icon(Icons.more_horiz_rounded, size: 20, color: foregroundColor),
      ),
    );
  }
}

PopupMenuItem<_NotebookAction> _notebookActionItem({
  required _NotebookAction value,
  required IconData icon,
  required String label,
}) {
  return PopupMenuItem<_NotebookAction>(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 12),
        Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}
