enum NotebookLayoutMode { paged, infiniteCanvas }

NotebookLayoutMode notebookLayoutModeFromJson(Object? value) {
  if (value == NotebookLayoutMode.infiniteCanvas.name) {
    return NotebookLayoutMode.infiniteCanvas;
  }
  return NotebookLayoutMode.paged;
}
