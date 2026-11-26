import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/dto/menu_dto.dart';
import 'menu_catalog_controller.dart';

/// What the menu screen is currently showing: a category and a search term.
class MenuFilter {
  const MenuFilter({this.categoryId, this.search = ''});

  /// Null means "all categories".
  final String? categoryId;
  final String search;
}

/// Disposed with the menu screen, so the next table starts on the whole menu.
final menuProvider = NotifierProvider.autoDispose<MenuController, MenuFilter>(MenuController.new);

class MenuController extends Notifier<MenuFilter> {
  @override
  MenuFilter build() => const MenuFilter();

  void selectCategory(String? categoryId) =>
      state = MenuFilter(categoryId: categoryId, search: state.search);

  void search(String term) => state = MenuFilter(categoryId: state.categoryId, search: term);
}

/// The products to list, filtered on the device.
final visibleProductsProvider = Provider.autoDispose<List<MenuProduct>>((ref) {
  final catalog = ref.watch(menuCatalogProvider.select((s) => s.catalog));
  final filter = ref.watch(menuProvider);
  return catalog?.filter(categoryId: filter.categoryId, search: filter.search) ??
      const <MenuProduct>[];
});

/// A product's options, for the option sheet: from the menu on the device when it carries them,
/// otherwise from the server. Disposed with the sheet.
final productDetailProvider = FutureProvider.autoDispose.family<ProductDetail, String>(
  (ref, productId) async {
    final local = ref.watch(menuCatalogProvider.select((s) => s.catalog?.detail(productId)));
    if (local != null) return local;
    return ref.watch(menuRepositoryProvider).productDetail(productId);
  },
  retry: (_, _) => null,
);
