import 'package:flutter/material.dart';
import 'package:inknest_notes/app/theme.dart';
import 'package:inknest_notes/features/library/library_screen.dart';
import 'package:inknest_notes/storage/in_memory_notebook_repository.dart';
import 'package:inknest_notes/storage/notebook_repository.dart';

class InkNestApp extends StatefulWidget {
  const InkNestApp({super.key});

  @override
  State<InkNestApp> createState() => _InkNestAppState();
}

class _InkNestAppState extends State<InkNestApp> {
  late final NotebookRepository _notebookRepository;

  @override
  void initState() {
    super.initState();
    _notebookRepository = InMemoryNotebookRepository();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InkNest Notes',
      debugShowCheckedModeBanner: false,
      theme: buildInkNestTheme(),
      home: LibraryScreen(notebookRepository: _notebookRepository),
    );
  }
}
