import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:md_staff/data/local/local_cache.dart';

void main() {
  late Directory directory;
  late FileLocalCache cache;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('md_staff_cache');
    cache = FileLocalCache(root: () async => directory);
  });

  tearDown(() => directory.delete(recursive: true));

  CacheEntry entry(Object data) =>
      CacheEntry(data: data, fetchedAt: DateTime(2026, 1, 1, 12, 30), etag: 'W/"1"');

  File file() => File('${directory.path}/offline_cache/menu.json');

  test('reads back what was written, from a new instance as after a restart', () async {
    await cache.write('menu', entry({'name': 'ผัดไทย', 'n': 2}), branchId: 'b1');

    final read = await FileLocalCache(root: () async => directory).read('menu', branchId: 'b1');

    expect(read!.data, {'name': 'ผัดไทย', 'n': 2});
    expect(read.fetchedAt, DateTime(2026, 1, 1, 12, 30));
    expect(read.etag, 'W/"1"');
    expect(File('${file().path}.tmp').existsSync(), isFalse);
  });

  test('another branch sees nothing', () async {
    await cache.write('menu', entry([1]), branchId: 'b1');

    expect(await cache.read('menu', branchId: 'b2'), isNull);
  });

  test('a damaged or outdated file reads as nothing', () async {
    expect(await cache.read('menu', branchId: 'b1'), isNull);
    await cache.write('menu', entry([1]), branchId: 'b1');

    await file().writeAsString('{"schema": 1, "branch_id": "b1", "da');
    expect(await cache.read('menu', branchId: 'b1'), isNull);

    await file().writeAsString(
      '{"schema": 0, "branch_id": "b1", "fetched_at": "2026-01-01T00:00:00Z", "data": []}',
    );
    expect(await cache.read('menu', branchId: 'b1'), isNull);
  });

  test('a clear asked for after a write is not overtaken by it', () async {
    final write = cache.write('menu', entry(List.filled(20000, 'x')), branchId: 'b1');
    final clear = cache.clear();
    await Future.wait([write, clear]);

    expect(await cache.read('menu', branchId: 'b1'), isNull);
  });

  test('a disk that cannot be used costs only the offline copy', () async {
    final broken = FileLocalCache(root: () async => throw const FileSystemException('no disk'));

    await broken.write('menu', entry([1]), branchId: 'b1');
    expect(await broken.read('menu', branchId: 'b1'), isNull);
    await broken.clear();
  });
}
