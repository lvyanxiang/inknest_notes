import 'package:flutter/material.dart';
import 'package:inknest_notes/models/pdf_background.dart';
import 'package:pdfrx/pdfrx.dart';

class PdfPageBackgroundView extends StatefulWidget {
  const PdfPageBackgroundView({super.key, required this.background});

  final PdfBackground background;

  @override
  State<PdfPageBackgroundView> createState() => _PdfPageBackgroundViewState();
}

class _PdfPageBackgroundViewState extends State<PdfPageBackgroundView> {
  late PdfDocumentRefFile _documentRef;

  @override
  void initState() {
    super.initState();
    _documentRef = PdfDocumentRefFile(widget.background.filePath);
  }

  @override
  void didUpdateWidget(covariant PdfPageBackgroundView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.background.filePath != oldWidget.background.filePath) {
      _documentRef = PdfDocumentRefFile(widget.background.filePath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PdfDocumentViewBuilder(
      documentRef: _documentRef,
      builder: (context, document) {
        if (document == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return PdfPageView(
          document: document,
          pageNumber: widget.background.pageNumber,
          decoration: const BoxDecoration(color: Colors.white),
          backgroundColor: Colors.white,
        );
      },
      loadingBuilder: (context) {
        return const Center(child: CircularProgressIndicator());
      },
      errorBuilder: (context, error, stackTrace) {
        return Center(
          child: Icon(
            Icons.picture_as_pdf_outlined,
            color: Theme.of(context).colorScheme.error,
            size: 48,
          ),
        );
      },
    );
  }
}
