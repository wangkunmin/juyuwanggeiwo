import 'dart:convert';
import 'dart:io';

import 'package:localsend_isolates/rust/api/model.dart' show FileDto;
import 'package:localsend_isolates/src/task/server/file_saver.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

final _logger = Logger('PartialTransferStore');

/// Suffix of a file whose transfer was interrupted.
///
/// A half-written file must not look like a complete one: the user would open a
/// truncated file. The suffix is removed again once the file is complete.
const partialFileSuffix = '.part';

/// Name of the registry file inside the app support directory.
const _registryFileName = 'partial_transfers.json';

/// One interrupted transfer: where its bytes are and how many arrived.
class PartialTransfer {
  PartialTransfer({
    required this.target,
    required this.receivedBytes,
    required this.fileSize,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  /// The destination of the interrupted attempt. It is reused so a resumed file
  /// keeps its name instead of being saved as a numbered copy.
  ///
  /// [FileSaveTarget.fileDescriptor] is not persisted (a descriptor does not
  /// survive a restart); the SAF document is reopened from
  /// [FileSaveTarget.displayPath] when the transfer continues.
  final FileSaveTarget target;

  final int receivedBytes;
  final int fileSize;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => {
        'path': target.path,
        'displayPath': target.displayPath,
        'receivedBytes': receivedBytes,
        'fileSize': fileSize,
        'updatedAt': updatedAt.toIso8601String(),
      };

  /// Parses an entry, returning `null` for anything malformed.
  static PartialTransfer? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final displayPath = json['displayPath'];
    final receivedBytes = json['receivedBytes'];
    final fileSize = json['fileSize'];
    final updatedAt = DateTime.tryParse('${json['updatedAt']}');
    final path = json['path'];
    if (displayPath is! String || receivedBytes is! int || fileSize is! int || updatedAt == null) {
      return null;
    }
    return PartialTransfer(
      target: FileSaveTarget(
        path: path is String ? path : null,
        fileDescriptor: null,
        displayPath: displayPath,
      ),
      receivedBytes: receivedBytes,
      fileSize: fileSize,
      updatedAt: updatedAt,
    );
  }
}

/// Remembers interrupted transfers, also across app restarts.
///
/// The key prefers the sender-provided SHA-256 and falls back to name + size, so
/// unrelated files never share an entry; the sender fingerprint keeps one device
/// from continuing another device's partial file.
class PartialTransferStore {
  /// [storage] is the registry file; the isolate passes the app support
  /// directory through [attach], tests pass a temporary file.
  PartialTransferStore({File? storage}) : _storage = storage {
    if (_storage != null) {
      _load();
    }
  }

  /// Entries older than this are dropped: a stale entry would keep a file from
  /// ever being received completely.
  static const maxAge = Duration(days: 7);

  final Map<String, PartialTransfer> _entries = {};
  File? _storage;
  bool _attached = false;

  static String keyOf({required String senderFingerprint, required FileDto file}) {
    final identity = file.sha256 ?? '${file.fileName}|${file.size}';
    return '$senderFingerprint|$identity';
  }

  /// Attaches the registry below [supportDirectory]; safe to call repeatedly.
  ///
  /// Passing `null` keeps the store in memory only.
  void attach(String? supportDirectory) {
    if (_attached) {
      return;
    }
    _attached = true;
    if (supportDirectory == null || _storage != null) {
      return;
    }
    _storage = File(p.join(supportDirectory, _registryFileName));
    _load();
  }

  /// The entry to continue, or `null` when the file must start from scratch.
  PartialTransfer? resumable({required String senderFingerprint, required FileDto file}) {
    final entry = _entries[keyOf(senderFingerprint: senderFingerprint, file: file)];
    if (entry == null || entry.receivedBytes <= 0 || entry.receivedBytes >= entry.fileSize) {
      return null;
    }
    return entry;
  }

  void remember(String key, PartialTransfer transfer) {
    _entries[key] = transfer;
    _persist();
  }

  void forget(String key) {
    if (_entries.remove(key) != null) {
      _persist();
    }
  }

  /// The number of remembered transfers (used by tests and diagnostics).
  int get length => _entries.length;

  void _load() {
    final file = _storage;
    if (file == null || !file.existsSync()) {
      return;
    }

    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) {
        return;
      }
      var dropped = 0;
      decoded.forEach((key, value) {
        if (key is! String) {
          return;
        }
        final entry = PartialTransfer.fromJson(value);
        final checked = entry == null ? null : _reconcile(entry);
        if (checked == null) {
          dropped++;
          return;
        }
        _entries[key] = checked;
      });
      _logger.info('Loaded ${_entries.length} interrupted transfers ($dropped dropped)');
    } catch (e, st) {
      _logger.warning('Failed to load interrupted transfers', e, st);
    }
  }

  /// Verifies a loaded entry against the file system.
  ///
  /// An entry is only useful while the bytes it claims are still there: a file
  /// that was deleted, truncated or moved on must not be continued.
  static PartialTransfer? _reconcile(PartialTransfer entry) {
    if (entry.receivedBytes <= 0 || entry.receivedBytes >= entry.fileSize) {
      return null;
    }
    if (DateTime.now().difference(entry.updatedAt) > maxAge) {
      return null;
    }
    final path = entry.target.path;
    if (path == null) {
      // An Android SAF document cannot be checked without opening it; the file
      // length check in the writer rejects it if the content is gone.
      return entry;
    }
    final file = File(path);
    if (!file.existsSync() || file.lengthSync() < entry.receivedBytes) {
      return null;
    }
    return entry;
  }

  void _persist() {
    final file = _storage;
    if (file == null) {
      return;
    }
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode({for (final entry in _entries.entries) entry.key: entry.value.toJson()}),
      );
    } catch (e, st) {
      _logger.warning('Failed to persist interrupted transfers', e, st);
    }
  }
}

/// Marks [target]'s file as an interrupted transfer so it is visibly incomplete.
///
/// Only plain file paths are renamed: an Android SAF document cannot be renamed
/// reliably, and its partial state is tracked by the registry alone.
FileSaveTarget markIncomplete(FileSaveTarget target) {
  final path = target.path;
  if (path == null || path.endsWith(partialFileSuffix)) {
    return target;
  }

  final renamedPath = '$path$partialFileSuffix';
  final renamedDisplay = '${target.displayPath}$partialFileSuffix';
  try {
    final renamed = File(renamedPath);
    if (renamed.existsSync()) {
      renamed.deleteSync();
    }
    File(path).renameSync(renamedPath);
    _logger.info('Marked $path as incomplete');
    return FileSaveTarget(path: renamedPath, fileDescriptor: null, displayPath: renamedDisplay);
  } catch (e, st) {
    // The transfer can still be continued, it just keeps its original name.
    _logger.warning('Failed to mark $path as incomplete', e, st);
    return target;
  }
}

/// Restores the final name of a file marked by [markIncomplete].
///
/// Keeps the `.part` name when the final name is taken by another file, so
/// nothing is overwritten.
FileSaveTarget finishIncomplete(FileSaveTarget target) {
  final path = target.path;
  if (path == null || !path.endsWith(partialFileSuffix)) {
    return target;
  }

  final finalPath = path.substring(0, path.length - partialFileSuffix.length);
  final finalDisplay = target.displayPath.substring(0, target.displayPath.length - partialFileSuffix.length);
  try {
    if (File(finalPath).existsSync()) {
      _logger.warning('$finalPath already exists, keeping $path');
      return target;
    }
    File(path).renameSync(finalPath);
    _logger.info('Completed $finalPath');
    return FileSaveTarget(path: finalPath, fileDescriptor: null, displayPath: finalDisplay);
  } catch (e, st) {
    _logger.warning('Failed to finish $path', e, st);
    return target;
  }
}
