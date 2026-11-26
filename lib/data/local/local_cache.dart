import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';

/// One thing kept on the device for offline use, with the moment it came from the server.
class CacheEntry {
  const CacheEntry({required this.data, required this.fetchedAt, this.etag});

  /// Plain JSON: maps, lists and scalars only.
  final Object data;
  final DateTime fetchedAt;
  final String? etag;
}

/// What the app keeps to work without a connection. A cache in the strict sense: anything missing,
/// unreadable or belonging to another branch simply reads as "nothing here", and a failed write
/// costs only the offline copy — so no call on this ever throws.
abstract class LocalCache {
  Future<CacheEntry?> read(String name, {required String branchId});

  Future<void> write(String name, CacheEntry entry, {required String branchId});

  Future<void> clear();
}

/// [LocalCache] as one JSON file per name in the app's private support directory.
///
/// Not the keystore: this is menu and floor data, too large for it and not a secret. Nothing that
/// grants anything — tokens, claim leases — may be written here.
class FileLocalCache implements LocalCache {
  FileLocalCache({Future<Directory> Function()? root})
      : _root = root ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _root;

  /// Bumped whenever the shape of what is stored changes; older files are then ignored.
  static const schemaVersion = 1;

  /// Writes and clears run one at a time, in the order asked: a sign-out's clear must not be
  /// overtaken by a write that was already under way.
  Future<void> _tail = Future<void>.value();

  Future<Directory> _directory() async => Directory('${(await _root()).path}/offline_cache');

  @override
  Future<CacheEntry?> read(String name, {required String branchId}) async {
    try {
      await _tail;
      final path = '${(await _directory()).path}/$name.json';
      if (!await File(path).exists()) return null;
      final envelope = await _decodeInBackground(path);
      if (envelope is! Map ||
          envelope['schema'] != schemaVersion ||
          envelope['branch_id'] != branchId) {
        return null;
      }
      final fetchedAt = DateTime.tryParse('${envelope['fetched_at']}');
      final data = envelope['data'];
      if (fetchedAt == null || data == null) return null;
      return CacheEntry(
        data: data as Object,
        fetchedAt: fetchedAt.toLocal(),
        etag: envelope['etag'] as String?,
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String name, CacheEntry entry, {required String branchId}) => _queued(() async {
        final directory = await _directory();
        await directory.create(recursive: true);
        final path = '${directory.path}/$name.json';
        // Written beside the real file and renamed over it, so a crash mid-write leaves the
        // previous copy rather than half of a new one.
        await _encodeInBackground('$path.tmp', {
          'schema': schemaVersion,
          'branch_id': branchId,
          'fetched_at': entry.fetchedAt.toUtc().toIso8601String(),
          'etag': entry.etag,
          'data': entry.data,
        });
        await File('$path.tmp').rename(path);
      });

  @override
  Future<void> clear() => _queued(() async {
        final directory = await _directory();
        if (await directory.exists()) await directory.delete(recursive: true);
      });

  Future<void> _queued(Future<void> Function() operation) =>
      _tail = _tail.then((_) => operation()).catchError((Object _) {});
}

// Top-level so the isolate closures capture only their arguments. A whole menu is large enough
// that reading or writing it on the UI isolate would drop frames.
Future<Object?> _decodeInBackground(String path) =>
    Isolate.run(() => jsonDecode(File(path).readAsStringSync()) as Object?);

Future<void> _encodeInBackground(String path, Map<String, Object?> envelope) =>
    Isolate.run(() => File(path).writeAsStringSync(jsonEncode(envelope), flush: true));
