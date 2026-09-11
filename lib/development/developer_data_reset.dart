import 'dart:io';

enum DeveloperDataResetScope { notebooksAndSync, notebooks, syncState }

abstract interface class DeveloperDataResetService {
  Future<void> reset(DeveloperDataResetScope scope);
}

class FileDeveloperDataResetService implements DeveloperDataResetService {
  const FileDeveloperDataResetService({required this.rootDirectory});

  final Directory rootDirectory;

  @override
  Future<void> reset(DeveloperDataResetScope scope) async {
    switch (scope) {
      case DeveloperDataResetScope.notebooks:
        await _deleteDirectory('notebooks');
      case DeveloperDataResetScope.syncState:
        await _deleteDirectory('sync');
      case DeveloperDataResetScope.notebooksAndSync:
        await _deleteDirectory('notebooks');
        await _deleteDirectory('sync');
    }
  }

  Future<void> _deleteDirectory(String name) async {
    final directory = Directory('${rootDirectory.path}/$name');
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}
