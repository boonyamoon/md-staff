import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/dto/floor_dto.dart';
import '../bootstrap/session_controller.dart';

/// The floor: every zone with its tables, their sessions and their claims. One request, because a
/// waiter pulls this list down constantly during service.
final zonesProvider = AsyncNotifierProvider<ZonesController, List<FloorZone>>(
  ZonesController.new,
);

class ZonesController extends AsyncNotifier<List<FloorZone>> {
  @override
  Future<List<FloorZone>> build() async {
    // Tied to the shift: ending one must not leave a stale floor behind for the next sign-in.
    final session = ref.watch(sessionProvider);
    if (session.phase != AppPhase.ready) return const <FloorZone>[];
    return ref.watch(floorRepositoryProvider).zones();
  }

  /// Pull-to-refresh, and after a round is sent so the table's totals are current. The previous
  /// floor stays on screen while this runs — a waiter mid-service must not watch the grid blank
  /// out every time they pull it down.
  Future<void> refresh() async {
    state = await AsyncValue.guard(() => ref.read(floorRepositoryProvider).zones());
  }
}

/// One zone out of the loaded floor, by id — the tables screen's source.
final zoneByIdProvider = Provider.family<FloorZone?, String>((ref, zoneId) {
  final zones = ref.watch(zonesProvider).value ?? const <FloorZone>[];
  for (final FloorZone zone in zones) {
    if (zone.zoneId == zoneId) return zone;
  }
  return null;
});
