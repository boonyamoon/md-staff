import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_failure.dart';
import '../../core/providers.dart';
import '../../data/dto/menu_catalog.dart';
import '../../data/local/menu_store.dart';
import '../bootstrap/session_controller.dart';

class MenuCatalogState {
  const MenuCatalogState({this.catalog, this.fetchedAt, this.refreshing = false, this.failure});

  /// Null until the first copy arrives, from the device or the server.
  final MenuCatalog? catalog;

  /// When the server last confirmed [catalog] was the whole current menu.
  final DateTime? fetchedAt;
  final bool refreshing;

  /// Why the last refresh failed; [catalog], if any, is the older copy.
  final ApiFailure? failure;

  MenuCatalogState copyWith({
    MenuCatalog? catalog,
    DateTime? fetchedAt,
    bool? refreshing,
    ApiFailure? failure,
    bool clearFailure = false,
  }) =>
      MenuCatalogState(
        catalog: catalog ?? this.catalog,
        fetchedAt: fetchedAt ?? this.fetchedAt,
        refreshing: refreshing ?? this.refreshing,
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}

final menuCatalogProvider = NotifierProvider<MenuCatalogController, MenuCatalogState>(
  MenuCatalogController.new,
);

/// The whole menu, kept on the device.
///
/// Fetched when there is no copy, when the copy is older than [AppConfig.menuMaxAge] at launch or
/// on return to the app, when the server refuses an order because the menu moved on, and whenever
/// the waiter asks. Which dishes are sold out is checked separately and more often, on entering
/// the menu. Nothing runs on a timer.
class MenuCatalogController extends Notifier<MenuCatalogState> {
  Future<void>? _inFlight;
  StoredMenu? _stored;
  DateTime? _availabilityAt;
  bool _checkingAvailability = false;

  /// Completes once the copy on the device has been read (or there is none to read).
  Completer<void> _restored = Completer<void>();

  @override
  MenuCatalogState build() {
    final branchId = ref.watch(signedInBranchProvider);
    _inFlight = null;
    _stored = null;
    _availabilityAt = null;
    _checkingAvailability = false;
    final restored = _restored = Completer<void>();
    if (branchId == null) {
      restored.complete();
    } else {
      Future.microtask(() {
        if (ref.mounted) unawaited(_restore(branchId, restored));
      });
    }
    return const MenuCatalogState();
  }

  Future<void> _restore(String branchId, Completer<void> restored) async {
    final stored = await ref.read(menuStoreProvider).load(branchId);
    if (!ref.mounted || ref.read(signedInBranchProvider) != branchId) return;
    if (stored != null && state.catalog == null) {
      _stored = stored;
      state = state.copyWith(
        catalog: MenuCatalog.fromJson(stored.data),
        fetchedAt: stored.fetchedAt,
      );
    }
    // Started before anything waiting on the copy runs, so that it can tell a fetch is on its way.
    final fetch = refreshIfStale();
    restored.complete();
    await fetch;
  }

  /// Fetches only when there is no menu yet, or it is at least [maxAge] old.
  Future<void> refreshIfStale([Duration maxAge = AppConfig.menuMaxAge]) async {
    final fetchedAt = state.fetchedAt;
    if (state.catalog != null &&
        fetchedAt != null &&
        ref.read(clockProvider)().difference(fetchedAt) < maxAge) {
      return;
    }
    await refresh();
  }

  /// Fetches the menu now. Calls made while one is under way share it.
  Future<void> refresh() => _inFlight ??= _fetch().whenComplete(() => _inFlight = null);

  Future<void> _fetch() async {
    final branchId = ref.read(signedInBranchProvider);
    if (branchId == null) return;
    state = state.copyWith(refreshing: true, clearFailure: true);
    try {
      final snapshot = await ref.read(menuRepositoryProvider).snapshot(
            etag: state.catalog == null ? null : _stored?.etag,
          );
      if (!ref.mounted || ref.read(signedInBranchProvider) != branchId) return;
      final now = ref.read(clockProvider)();
      final data = snapshot.data ?? _stored?.data;
      if (data == null) {
        throw const ApiFailure(
          code: 'MALFORMED_RESPONSE',
          message: 'Unexpected answer from the server',
        );
      }
      // Re-read even when unchanged: "unchanged" covers availability too, so any sold-out marks
      // applied since are replaced by what the server just confirmed.
      final catalog = MenuCatalog.fromJson(data);
      _stored = StoredMenu(data: data, fetchedAt: now, etag: snapshot.etag);
      _availabilityAt = now;
      unawaited(ref.read(menuStoreProvider).save(branchId, _stored!));
      state = MenuCatalogState(catalog: catalog, fetchedAt: now);
    } on ApiFailure catch (failure) {
      if (!ref.mounted || ref.read(signedInBranchProvider) != branchId) return;
      state = state.copyWith(refreshing: false, failure: failure);
    }
  }

  /// Greys out what has sold out since the menu was fetched, if that was last checked at least
  /// [AppConfig.availabilityMaxAge] ago.
  Future<void> refreshAvailabilityIfStale() async {
    await _restored.future;
    if (!ref.mounted) return;
    // No menu yet, or one is on its way: it brings availability with it.
    if (state.catalog == null || _inFlight != null || _checkingAvailability) return;
    final checkedAt = _availabilityAt;
    if (checkedAt != null &&
        ref.read(clockProvider)().difference(checkedAt) < AppConfig.availabilityMaxAge) {
      return;
    }
    final branchId = ref.read(signedInBranchProvider);
    _checkingAvailability = true;
    try {
      final unavailable = await ref.read(menuRepositoryProvider).unavailableProductIds();
      if (!ref.mounted || ref.read(signedInBranchProvider) != branchId) return;
      _availabilityAt = ref.read(clockProvider)();
      state = state.copyWith(catalog: state.catalog?.withUnavailable(unavailable));
    } on ApiFailure {
      // A missed check just means the menu keeps the availability it last knew; the server
      // refuses a sold-out dish on send either way.
    } finally {
      _checkingAvailability = false;
    }
  }
}
