import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_failure.dart';
import '../../core/providers.dart';
import '../../data/dto/floor_dto.dart';
import '../bootstrap/session_controller.dart';

/// The floor as last known, and how current that is.
class FloorState {
  FloorState({
    this.zones = const <FloorZone>[],
    this.fetchedAt,
    this.refreshing = false,
    this.failure,
  });

  final List<FloorZone> zones;

  /// When the server sent [zones]. Null only while signed out.
  final DateTime? fetchedAt;
  final bool refreshing;

  /// Why the last refresh failed. [zones] is then the older copy, and the screen says so.
  final ApiFailure? failure;

  late final Map<String, FloorTable> _tables = {
    for (final zone in zones)
      for (final table in zone.tables) table.floorItemId: table,
  };

  late final Map<String, FloorZone> _zones = {for (final zone in zones) zone.zoneId: zone};

  FloorTable? table(String floorItemId) => _tables[floorItemId];
  FloorZone? zone(String zoneId) => _zones[zoneId];

  FloorState copyWith({
    List<FloorZone>? zones,
    bool? refreshing,
    ApiFailure? failure,
    bool clearFailure = false,
  }) =>
      FloorState(
        zones: zones ?? this.zones,
        fetchedAt: fetchedAt,
        refreshing: refreshing ?? this.refreshing,
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}

/// The floor: every zone with its tables, their sessions and their claims, in one request.
///
/// Not retried behind the waiter's back: nothing here fetches on a timer, and the screen offers a
/// retry when there is nothing to show.
final zonesProvider = AsyncNotifierProvider<ZonesController, FloorState>(
  ZonesController.new,
  retry: (_, _) => null,
);

/// Shows the copy on the device at once and asks the server only at the moments that call for it —
/// opening the app, [refreshIfStale] on the way back to the floor, after an order or a collision,
/// and whenever the waiter pulls down.
class ZonesController extends AsyncNotifier<FloorState> {
  Future<void>? _inFlight;

  @override
  Future<FloorState> build() async {
    // Tied to the shift: ending one must not leave a stale floor behind for the next sign-in.
    final branchId = ref.watch(signedInBranchProvider);
    _inFlight = null;
    if (branchId == null) return FloorState();
    final repository = ref.watch(floorRepositoryProvider);
    final store = ref.watch(floorStoreProvider);
    final clock = ref.watch(clockProvider);

    final stored = await store.load(branchId);
    if (stored != null) {
      // Asked after this build has been delivered, so the stored floor is on screen first and the
      // answer cannot be overwritten by it.
      Timer.run(() {
        if (ref.mounted) unawaited(refresh());
      });
      return FloorState(zones: stored.zones, fetchedAt: stored.fetchedAt);
    }

    final zones = await repository.zones();
    final now = clock();
    if (ref.mounted) unawaited(store.save(branchId, zones, now));
    return FloorState(zones: zones, fetchedAt: now);
  }

  /// Fetches the floor now. Calls made while one is under way share it. The floor already on screen
  /// stays there meanwhile — a waiter mid-service must not watch the grid blank out.
  Future<void> refresh() => _inFlight ??= _fetch().whenComplete(() => _inFlight = null);

  /// For after this handset has changed something: a fetch already under way may have left
  /// before the change, so it does not count.
  Future<void> refreshAfterChange() async {
    await _inFlight;
    if (ref.mounted) await refresh();
  }

  /// Fetches only when the floor on screen is at least [maxAge] old.
  Future<void> refreshIfStale([Duration maxAge = AppConfig.floorMaxAge]) async {
    if (ref.read(signedInBranchProvider) == null) return;
    // Still on its first load, which is as fresh as it gets.
    if (state.isLoading && state.value?.fetchedAt == null) return;
    final fetchedAt = state.value?.fetchedAt;
    if (fetchedAt != null && ref.read(clockProvider)().difference(fetchedAt) < maxAge) return;
    await refresh();
  }

  /// This handset gave [floorItemId] back. That much is known without asking the server.
  Future<void> tableReleased(String floorItemId) async {
    final current = state.value;
    // Whoever the floor on screen says holds it — after a takeover that is still the previous
    // holder — nobody does now.
    if (current?.table(floorItemId)?.claim != null) {
      state = AsyncData(
        current!.copyWith(
          zones: [
            for (final zone in current.zones)
              zone.withTables([
                for (final table in zone.tables)
                  table.floorItemId == floorItemId ? table.withoutClaim() : table,
              ]),
          ],
        ),
      );
    }
    await refreshIfStale();
  }

  Future<void> _fetch() async {
    final branchId = ref.read(signedInBranchProvider);
    if (branchId == null) return;
    final before = state.value;
    if (before?.fetchedAt != null) {
      state = AsyncData(before!.copyWith(refreshing: true));
    } else {
      state = const AsyncLoading();
    }
    try {
      final zones = await ref.read(floorRepositoryProvider).zones();
      // Signed out, or into another branch, while the request was out.
      if (!ref.mounted || ref.read(signedInBranchProvider) != branchId) return;
      final now = ref.read(clockProvider)();
      unawaited(ref.read(floorStoreProvider).save(branchId, zones, now));
      state = AsyncData(FloorState(zones: zones, fetchedAt: now));
    } on Object catch (error, stack) {
      if (!ref.mounted || ref.read(signedInBranchProvider) != branchId) return;
      final current = state.value;
      if (current?.fetchedAt == null) {
        state = AsyncError(error, stack);
        return;
      }
      state = AsyncData(
        current!.copyWith(
          refreshing: false,
          failure: error is ApiFailure
              ? error
              : ApiFailure(code: 'UNKNOWN', message: error.toString()),
        ),
      );
    }
  }
}
