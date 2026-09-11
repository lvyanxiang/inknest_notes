import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/development/developer_data_reset.dart';

void main() {
  late Directory root;
  late FileDeveloperDataResetService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('inknest-reset-test-');
    service = FileDeveloperDataResetService(rootDirectory: root);
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('notebook reset deletes only notebook data', () async {
    await _seed(root);

    await service.reset(DeveloperDataResetScope.notebooks);

    expect(Directory('${root.path}/notebooks').existsSync(), isFalse);
    expect(Directory('${root.path}/sync').existsSync(), isTrue);
    expect(File('${root.path}/keep.txt').existsSync(), isTrue);
  });

  test('sync reset deletes only synchronization sidecars', () async {
    await _seed(root);

    await service.reset(DeveloperDataResetScope.syncState);

    expect(Directory('${root.path}/notebooks').existsSync(), isTrue);
    expect(Directory('${root.path}/sync').existsSync(), isFalse);
    expect(File('${root.path}/keep.txt').existsSync(), isTrue);
  });

  test('combined reset preserves unrelated app files', () async {
    await _seed(root);

    await service.reset(DeveloperDataResetScope.notebooksAndSync);

    expect(Directory('${root.path}/notebooks').existsSync(), isFalse);
    expect(Directory('${root.path}/sync').existsSync(), isFalse);
    expect(File('${root.path}/keep.txt').existsSync(), isTrue);
  });
}

Future<void> _seed(Directory root) async {
  await File(
    '${root.path}/notebooks/notebook-1/pages/page-1.json',
  ).create(recursive: true);
  await File(
    '${root.path}/sync/user-1/device-1/state.json',
  ).create(recursive: true);
  await File('${root.path}/keep.txt').writeAsString('keep');
}
