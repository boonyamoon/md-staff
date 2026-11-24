import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_failure.dart';
import '../../core/providers.dart';
import '../../data/dto/menu_dto.dart';
import '../bootstrap/session_controller.dart';

class MenuState {
  const MenuState({
    this.categories = const <MenuCategory>[],
    this.products = const <MenuProduct>[],
    this.categoryId,
    this.search = '',
    this.loading = true,
    this.loadingMore = false,
    this.hasMore = false,
    this.failure,
  });

  final List<MenuCategory> categories;
  final List<MenuProduct> products;

  /// Null means "all categories".
  final String? categoryId;
  final String search;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final ApiFailure? failure;

  MenuState copyWith({
    List<MenuCategory>? categories,
    List<MenuProduct>? products,
    String? categoryId,
    String? search,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    ApiFailure? failure,
    bool clearCategory = false,
    bool clearFailure = false,
  }) =>
      MenuState(
        categories: categories ?? this.categories,
        products: products ?? this.products,
        categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
        search: search ?? this.search,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        hasMore: hasMore ?? this.hasMore,
        failure: clearFailure ? null : (failure ?? this.failure),
      );
}

final menuProvider = NotifierProvider<MenuController, MenuState>(MenuController.new);

/// The menu grid: categories, a page of products, search, and the sold-out poll.
///
/// Availability is polled rather than re-fetched: a waiter can stand on this screen for minutes
/// while the kitchen switches a dish off, and reloading the whole grid under their thumb would
/// lose their scroll position. The kiosk app polls the same endpoint for the same reason.
class MenuController extends Notifier<MenuState> {
  Timer? _availabilityTimer;
  Timer? _searchDebounce;
  int _page = 1;

  @override
  MenuState build() {
    ref.onDispose(() {
      _availabilityTimer?.cancel();
      _searchDebounce?.cancel();
    });
    ref.listen(sessionProvider, (previous, next) {
      if (next.phase != AppPhase.ready) _availabilityTimer?.cancel();
    });
    Future.microtask(load);
    return const MenuState();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, clearFailure: true);
    final menu = ref.read(menuRepositoryProvider);
    try {
      final categories = state.categories.isEmpty ? await menu.categories() : state.categories;
      _page = 1;
      final page = await menu.products(categoryId: state.categoryId, search: state.search);
      state = state.copyWith(
        categories: categories,
        products: page.products,
        hasMore: page.hasNextPage,
        loading: false,
      );
      _startAvailabilityPoll();
    } on ApiFailure catch (failure) {
      state = state.copyWith(loading: false, failure: failure);
    }
  }

  Future<void> loadMore() async {
    if (!state.hasMore || state.loadingMore || state.loading) return;
    state = state.copyWith(loadingMore: true);
    try {
      final page = await ref.read(menuRepositoryProvider).products(
            categoryId: state.categoryId,
            search: state.search,
            page: _page + 1,
          );
      _page += 1;
      state = state.copyWith(
        products: [...state.products, ...page.products],
        hasMore: page.hasNextPage,
        loadingMore: false,
      );
    } on ApiFailure catch (failure) {
      state = state.copyWith(loadingMore: false, failure: failure);
    }
  }

  void selectCategory(String? categoryId) {
    if (categoryId == state.categoryId) return;
    state = state.copyWith(categoryId: categoryId, clearCategory: categoryId == null);
    unawaited(load());
  }

  /// Debounced: a waiter typing "ก๋วยเตี๋ยว" must not fire a request per keystroke.
  void search(String term) {
    state = state.copyWith(search: term);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () => unawaited(load()));
  }

  void _startAvailabilityPoll() {
    _availabilityTimer?.cancel();
    _availabilityTimer = Timer.periodic(
      AppConfig.menuAvailabilityPollInterval,
      (_) => unawaited(_pollAvailability()),
    );
  }

  Future<void> _pollAvailability() async {
    try {
      final unavailable = await ref.read(menuRepositoryProvider).unavailableProductIds();
      state = state.copyWith(
        products: [
          for (final product in state.products)
            product.copyWith(isAvailable: !unavailable.contains(product.id)),
        ],
      );
    } on ApiFailure {
      // A missed poll just means the grid keeps the availability it last knew.
    }
  }

  void acknowledgeFailure() {
    if (state.failure != null) state = state.copyWith(clearFailure: true);
  }
}

/// A product's full detail, for the option sheet. Cached per product for the life of the screen.
final productDetailProvider = FutureProvider.family<ProductDetail, String>(
  (ref, productId) => ref.watch(menuRepositoryProvider).productDetail(productId),
);
