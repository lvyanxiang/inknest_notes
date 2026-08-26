import 'dart:async';

import 'package:flutter/material.dart';
import 'package:inknest_notes/app/theme.dart';
import 'package:inknest_notes/auth/auth_controller.dart';
import 'package:inknest_notes/auth/device_installation_id_store.dart';
import 'package:inknest_notes/features/library/library_screen.dart';
import 'package:inknest_notes/storage/file_notebook_repository.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';
import 'package:inknest_notes/sync/first_sign_in_sync_service.dart';
import 'package:inknest_notes/sync/inknest_api_client.dart';
import 'package:inknest_notes/sync/sync_mutation_tracker.dart';
import 'package:inknest_notes/sync/sync_trigger.dart';
import 'package:path_provider/path_provider.dart';

class InkNestApp extends StatefulWidget {
  const InkNestApp({
    super.key,
    this.notebookRepository,
    this.authController,
    this.firstSignInSyncService,
  });

  final NotebookRepository? notebookRepository;
  final AuthController? authController;
  final FirstSignInSyncService? firstSignInSyncService;

  @override
  State<InkNestApp> createState() => _InkNestAppState();
}

class _InkNestAppState extends State<InkNestApp> {
  late final Future<_AppResources> _resources;
  late final AuthController _authController;
  InkNestApiClient? _ownedApiClient;
  SyncTriggerController? _ownedSyncTrigger;
  late final bool _ownsAuthController;

  @override
  void initState() {
    super.initState();
    final injectedAuthController = widget.authController;
    _ownsAuthController = injectedAuthController == null;
    if (injectedAuthController != null) {
      _authController = injectedAuthController;
    } else {
      final identity = defaultInkNestDeviceIdentity();
      final client = InkNestApiClient();
      _ownedApiClient = client;
      _authController = AuthController(
        service: client,
        deviceName: identity.name,
        platform: identity.platform,
        deviceInstallationIdStore: SecureDeviceInstallationIdStore(),
      );
    }
    _resources = _createResources();
    unawaited(_authController.initialize());
  }

  @override
  void dispose() {
    if (_ownsAuthController) {
      _authController.dispose();
    }
    _ownedApiClient?.close();
    unawaited(_ownedSyncTrigger?.dispose());
    super.dispose();
  }

  Future<_AppResources> _createResources() async {
    final injectedRepository = widget.notebookRepository;
    if (injectedRepository != null) {
      return _AppResources(
        repository: injectedRepository,
        firstSignInSyncService: widget.firstSignInSyncService,
      );
    }

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final syncTrigger = SyncTriggerController();
    _ownedSyncTrigger = syncTrigger;
    final mutationTracker = SyncMutationTracker(
      rootDirectory: documentsDirectory,
      activeSession: () => _authController.session,
      onSyncRequested: syncTrigger.request,
    );
    final repository = FileNotebookRepository(
      rootDirectory: documentsDirectory,
      onPagePersisted: mutationTracker.pageSaved,
      onNotebookContentPersisted: mutationTracker.notebookContentSaved,
      onNotebookMetadataPersisted: mutationTracker.notebookMetadataSaved,
      onFolderPersisted: mutationTracker.folderSaved,
      onFolderDeleted: mutationTracker.folderDeleted,
      onInfiniteCanvasPersisted: mutationTracker.infiniteCanvasSaved,
      onNotebookDeleted: mutationTracker.notebookDeleted,
      onPageDeleted: mutationTracker.pageDeleted,
    );
    final apiClient = _ownedApiClient;
    return _AppResources(
      repository: repository,
      syncRequests: syncTrigger.requests,
      firstSignInSyncService:
          widget.firstSignInSyncService ??
          (apiClient == null
              ? null
              : ApiFirstSignInSyncService(
                  repository: repository,
                  apiClient: apiClient,
                  rootDirectory: documentsDirectory,
                  mutationTracker: mutationTracker,
                )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InkNest Notes',
      debugShowCheckedModeBanner: false,
      theme: buildInkNestTheme(),
      home: FutureBuilder<_AppResources>(
        future: _resources,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return LibraryScreen(
              notebookRepository: snapshot.requireData.repository,
              authController: _authController,
              firstSignInSyncService:
                  snapshot.requireData.firstSignInSyncService,
              syncRequests: snapshot.requireData.syncRequests,
            );
          }

          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        },
      ),
    );
  }
}

class _AppResources {
  const _AppResources({
    required this.repository,
    required this.firstSignInSyncService,
    this.syncRequests,
  });

  final NotebookRepository repository;
  final FirstSignInSyncService? firstSignInSyncService;
  final Stream<void>? syncRequests;
}
