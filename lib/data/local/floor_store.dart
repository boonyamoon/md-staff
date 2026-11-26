import '../dto/floor_dto.dart';
import '../dto/json.dart';
import 'local_cache.dart';

class StoredFloor {
  const StoredFloor({required this.zones, required this.fetchedAt});

  final List<FloorZone> zones;
  final DateTime fetchedAt;
}

/// The last floor the server sent, minus the claims: a claim lasts minutes and carries the lease
/// that lets a handset order, so an old one is both wrong and not something to keep on disk.
class FloorStore {
  const FloorStore(this._cache);

  final LocalCache _cache;

  static const _name = 'floor';

  Future<StoredFloor?> load(String branchId) async {
    final entry = await _cache.read(_name, branchId: branchId);
    if (entry == null) return null;
    final zones = asList(entry.data, FloorZone.fromJson);
    return zones.isEmpty ? null : StoredFloor(zones: zones, fetchedAt: entry.fetchedAt);
  }

  Future<void> save(String branchId, List<FloorZone> zones, DateTime fetchedAt) => _cache.write(
        _name,
        CacheEntry(data: [for (final zone in zones) zone.toCacheJson()], fetchedAt: fetchedAt),
        branchId: branchId,
      );
}
