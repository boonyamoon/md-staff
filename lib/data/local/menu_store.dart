import '../dto/json.dart';
import 'local_cache.dart';

class StoredMenu {
  const StoredMenu({required this.data, required this.fetchedAt, this.etag});

  /// The `{categories, products}` document as it came from the server.
  final Map<String, dynamic> data;
  final DateTime fetchedAt;
  final String? etag;
}

/// The last whole menu the server sent.
class MenuStore {
  const MenuStore(this._cache);

  final LocalCache _cache;

  static const _name = 'menu';

  Future<StoredMenu?> load(String branchId) async {
    final entry = await _cache.read(_name, branchId: branchId);
    final data = asMapOrNull(entry?.data);
    if (entry == null || data == null) return null;
    return StoredMenu(data: data, fetchedAt: entry.fetchedAt, etag: entry.etag);
  }

  Future<void> save(String branchId, StoredMenu menu) => _cache.write(
        _name,
        CacheEntry(data: menu.data, fetchedAt: menu.fetchedAt, etag: menu.etag),
        branchId: branchId,
      );
}
