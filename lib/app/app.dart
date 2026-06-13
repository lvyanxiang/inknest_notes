import 'package:flutter/material.dart';
import 'package:inknest_notes/app/theme.dart';
import 'package:inknest_notes/features/library/library_screen.dart';
import 'package:inknest_notes/storage/file_notebook_repository.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';
import 'package:path_provider/path_provider.dart';

class InkNestApp extends StatefulWidget {
  const InkNestApp({super.key, this.notebookRepository});

  final NotebookRepository? notebookRepository;

  @override
  State<InkNestApp> createState() => _InkNestAppState();
}

class _InkNestAppState extends State<InkNestApp> {
  late final Future<NotebookRepository> _notebookRepository;

  @override
  void initState() {
    super.initState();
    _notebookRepository = _createRepository();
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
            return LibraryScreen(notebookRepository: snapshot.requireData);
          }

          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        },
      ),
    );
  }
}
