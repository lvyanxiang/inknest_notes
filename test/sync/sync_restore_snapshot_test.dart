import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inknest_notes/sync/sync_restore_snapshot.dart';

void main() {
  test(
    'restores notebooks and device sidecars after an action fails',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'inknest-restore-snapshot-',
      );
      addTearDown(() => root.delete(recursive: true));
      final notebookFile = File('${root.path}/notebooks/note/notebook.json');
      final stateFile = File('${root.path}/sync/user-1/device-1/state.json');
      await notebookFile.parent.create(recursive: true);
      await notebookFile.writeAsString('before-note');
      await stateFile.parent.create(recursive: true);
      await stateFile.writeAsString('before-state');

      await expectLater(
        withSyncRestoreSnapshot<void>(
          rootDirectory: root,
          userId: 'user-1',
          deviceId: 'device-1',
          action: () async {
            await notebookFile.writeAsString('after-note');
            await stateFile.delete();
            await File('${root.path}/notebooks/new.json').writeAsString('new');
            throw StateError('restore failed');
          },
        ),
        throwsStateError,
      );

      expect(await notebookFile.readAsString(), 'before-note');
      expect(await stateFile.readAsString(), 'before-state');
      expect(await File('${root.path}/notebooks/new.json').exists(), isFalse);
      expect(
        await Directory('${root.path}/sync/restore-recovery').exists(),
        isFalse,
      );
    },
  );

  test('keeps successful changes and discards the recovery snapshot', () async {
    final root = await Directory.systemTemp.createTemp(
      'inknest-restore-success-',
    );
    addTearDown(() => root.delete(recursive: true));
    final notebookFile = File('${root.path}/notebooks/note/notebook.json');
    await notebookFile.parent.create(recursive: true);
    await notebookFile.writeAsString('before');

    final result = await withSyncRestoreSnapshot<String>(
      rootDirectory: root,
      userId: 'user-1',
      deviceId: 'device-1',
      action: () async {
        await notebookFile.writeAsString('after');
        return 'done';
      },
    );

    expect(result, 'done');
    expect(await notebookFile.readAsString(), 'after');
    expect(
      await Directory('${root.path}/sync/restore-recovery').exists(),
      isFalse,
    );
  });
}
