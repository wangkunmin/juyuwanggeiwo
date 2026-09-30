import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_isolates/rust/api/model.dart' show FileDto;
import 'package:localsend_isolates/src/task/server/file_saver.dart';
import 'package:localsend_isolates/src/task/server/partial_transfer_store.dart';

/// Builds the file description the sender offers for `name`.
FileDto _file(String name, int size, {String? sha256}) {
  return FileDto(
    id: 'file-1',
    fileName: name,
    size: BigInt.from(size),
    fileType: 'application/octet-stream',
    sha256: sha256,
  );
}

void main() {
  late Directory tempDir;
  late File registry;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('partial-transfer-test');
    registry = File('${tempDir.path}/partial_transfers.json');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  FileSaveTarget targetOf(String name) {
    final path = '${tempDir.path}/$name';
    return FileSaveTarget(path: path, fileDescriptor: null, displayPath: path);
  }

  test('remembers an offset and reports it as resumable', () {
    final store = PartialTransferStore(storage: registry);
    final file = _file('a.bin', 100);
    final target = targetOf('a.bin');

    store.remember(
      PartialTransferStore.keyOf(senderFingerprint: 'ABC', file: file),
      PartialTransfer(target: target, receivedBytes: 40, fileSize: 100),
    );

    expect(store.resumable(senderFingerprint: 'ABC', file: file)?.receivedBytes, 40);
  });

  test('never resumes for another sender or another file', () {
    final store = PartialTransferStore(storage: registry);
    final file = _file('a.bin', 100);
    store.remember(
      PartialTransferStore.keyOf(senderFingerprint: 'ABC', file: file),
      PartialTransfer(target: targetOf('a.bin'), receivedBytes: 40, fileSize: 100),
    );

    expect(store.resumable(senderFingerprint: 'OTHER', file: file), isNull);
    expect(store.resumable(senderFingerprint: 'ABC', file: _file('b.bin', 100)), isNull);
  });

  test('a complete or empty transfer is not resumable', () {
    final store = PartialTransferStore(storage: registry);
    final file = _file('a.bin', 100);
    final key = PartialTransferStore.keyOf(senderFingerprint: 'ABC', file: file);

    store.remember(key, PartialTransfer(target: targetOf('a.bin'), receivedBytes: 100, fileSize: 100));
    expect(store.resumable(senderFingerprint: 'ABC', file: file), isNull);

    store.remember(key, PartialTransfer(target: targetOf('a.bin'), receivedBytes: 0, fileSize: 100));
    expect(store.resumable(senderFingerprint: 'ABC', file: file), isNull);
  });

  test('survives a restart and keeps the destination', () {
    final file = _file('a.bin', 100, sha256: 'deadbeef');
    final partial = targetOf('a.bin.part');
    File(partial.path!).writeAsBytesSync(List.filled(40, 7));

    final first = PartialTransferStore(storage: registry);
    first.remember(
      PartialTransferStore.keyOf(senderFingerprint: 'ABC', file: file),
      PartialTransfer(target: partial, receivedBytes: 40, fileSize: 100),
    );
    expect(registry.existsSync(), isTrue);

    // A new store instance is what a restarted app sees.
    final second = PartialTransferStore(storage: registry);
    final resumed = second.resumable(senderFingerprint: 'ABC', file: file);
    expect(resumed?.receivedBytes, 40);
    expect(resumed?.target.path, partial.path);
  });

  test('drops entries whose prefix is gone or shorter than announced', () {
    final file = _file('a.bin', 100, sha256: 'deadbeef');
    final target = targetOf('a.bin.part');

    final store = PartialTransferStore(storage: registry);
    final key = PartialTransferStore.keyOf(senderFingerprint: 'ABC', file: file);
    store.remember(key, PartialTransfer(target: target, receivedBytes: 40, fileSize: 100));

    // Nothing on disk: reconciliation must reject the entry.
    expect(PartialTransferStore(storage: registry).resumable(senderFingerprint: 'ABC', file: file), isNull);

    // Too few bytes on disk: also rejected.
    File(target.path!).writeAsBytesSync(List.filled(10, 1));
    expect(PartialTransferStore(storage: registry).resumable(senderFingerprint: 'ABC', file: file), isNull);

    // Enough bytes: usable again.
    File(target.path!).writeAsBytesSync(List.filled(40, 1));
    expect(PartialTransferStore(storage: registry).resumable(senderFingerprint: 'ABC', file: file)?.receivedBytes, 40);
  });

  test('drops stale entries', () {
    final file = _file('a.bin', 100);
    final target = targetOf('a.bin.part');
    File(target.path!).writeAsBytesSync(List.filled(40, 1));

    registry.writeAsStringSync(jsonEncode({
      PartialTransferStore.keyOf(senderFingerprint: 'ABC', file: file): {
        'path': target.path,
        'displayPath': target.displayPath,
        'receivedBytes': 40,
        'fileSize': 100,
        'updatedAt': DateTime.now().subtract(PartialTransferStore.maxAge + const Duration(days: 1)).toIso8601String(),
      },
    }));

    expect(PartialTransferStore(storage: registry).resumable(senderFingerprint: 'ABC', file: file), isNull);
  });

  test('ignores a corrupt registry', () {
    registry.writeAsStringSync('{not json');
    final store = PartialTransferStore(storage: registry);
    expect(store.length, 0);
    expect(store.resumable(senderFingerprint: 'ABC', file: _file('a.bin', 100)), isNull);
  });

  test('markIncomplete and finishIncomplete are reversible', () {
    final file = File('${tempDir.path}/report.pdf')..writeAsBytesSync(List.filled(20, 3));
    final target = FileSaveTarget(path: file.path, fileDescriptor: null, displayPath: file.path);

    final partial = markIncomplete(target);
    expect(partial.path, '${file.path}.part');
    expect(File(partial.path!).existsSync(), isTrue);
    expect(file.existsSync(), isFalse);

    final finished = finishIncomplete(partial);
    expect(finished.path, file.path);
    expect(file.existsSync(), isTrue);
    expect(File(partial.path!).existsSync(), isFalse);
  });

  test('finishIncomplete never overwrites an existing file', () {
    final file = File('${tempDir.path}/report.pdf')..writeAsBytesSync(List.filled(20, 3));
    final partial = File('${file.path}.part')..writeAsBytesSync(List.filled(5, 9));

    final finished = finishIncomplete(
      FileSaveTarget(path: partial.path, fileDescriptor: null, displayPath: partial.path),
    );

    expect(finished.path, partial.path);
    expect(file.lengthSync(), 20);
  });

  test('markIncomplete leaves SAF targets (no path) untouched', () {
    final target = FileSaveTarget(path: null, fileDescriptor: 7, displayPath: 'content://documents/1');
    expect(markIncomplete(target).displayPath, 'content://documents/1');
    expect(finishIncomplete(target).displayPath, 'content://documents/1');
  });
}
