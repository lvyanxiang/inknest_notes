import 'package:flutter/material.dart';
import 'package:inknest_notes/models/notebook.dart';

class EditorScreen extends StatelessWidget {
  const EditorScreen({super.key, required this.notebook});

  final Notebook notebook;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(notebook.title)),
      body: Center(
        child: AspectRatio(
          aspectRatio: 3 / 4,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            margin: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE4DED1)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A1E2526),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
