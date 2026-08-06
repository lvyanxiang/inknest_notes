import 'dart:async';

import 'package:flutter/material.dart';
import 'package:inknest_notes/app/theme.dart';
import 'package:inknest_notes/auth/auth_controller.dart';
import 'package:inknest_notes/features/library/library_screen.dart';
import 'package:inknest_notes/storage/file_notebook_repository.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';
import 'package:inknest_notes/sync/inknest_api_client.dart';
import 'package:path_provider/path_provider.dart';

class InkNestApp extends StatefulWidget {
  const InkNestApp({super.key, this.notebookRepository, this.authController});

  final NotebookRepository? notebookRepository;
  final AuthController? authController;

  @override
  State<InkNestApp> createState() => _InkNestAppState();
}

class _InkNestAppState extends State<InkNestApp> {
  late final Future<NotebookRepository> _notebookRepository;
  late final AuthController _authController;
  InkNestApiClient? _ownedApiClient;
  late final bool _ownsAuthController;

  @override
  void initState() {
    super.initState();
    _notebookRepository = _createRepository();
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
      );
    }
    unawaited(_authController.initialize());
  }

  @override
  void dispose() {
    if (_ownsAuthController) {
      _authController.dispose();
    }
    _ownedApiClient?.close();
    super.dispose();
  }

  Future<NotebookRepository> _createRepository() async {
    final injectedRepository = widget.notebookRepository;
    if (injectedRepository != null) {
      return injectedRepository;
    }

    final documentsDirectory = await getApplicationDocumentsDirectory();
    return FileNotebookRepository(rootDirectory: documentsDirectory);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InkNest Notes',
      debugShowCheckedModeBanner: false,
      theme: buildInkNestTheme(),
      home: FutureBuilder<NotebookRepository>(
        future: _notebookRepository,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return LibraryScreen(
              notebookRepository: snapshot.requireData,
              authController: _authController,
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
