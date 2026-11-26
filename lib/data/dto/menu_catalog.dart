import 'json.dart';
import 'menu_dto.dart';

/// The whole menu, held in memory and searched there: choosing a category or typing a search never
/// goes to the server.
class MenuCatalog {
  MenuCatalog._(this.categories, this.products, this._details)
      : _byCategory = _group(products),
        _searchKeys = [for (final product in products) product.productName.toLowerCase()];

  /// From the `{categories, products}` document `MenuRepository.snapshot` returns.
  factory MenuCatalog.fromJson(Map<String, dynamic> json) => MenuCatalog._(
        // Only top-level categories become filter chips; a shop with sub-categories would
        // otherwise show two rows of chips on a phone.
        asList(json['categories'], MenuCategory.fromJson)
            .where((c) => c.parentCategoryId == null)
            .toList(growable: false),
        asList(json['products'], MenuProduct.fromJson),
        {
          for (final product in asList(json['products'], (m) => m))
            if (product.containsKey('option_groups'))
              asString(product['id']): ProductDetail.fromJson(product),
        },
      );

  final List<MenuCategory> categories;

  /// In the order the shop set, as the server sends them.
  final List<MenuProduct> products;

  final Map<String, ProductDetail> _details;
  final Map<String, List<int>> _byCategory;
  final List<String> _searchKeys;

  static Map<String, List<int>> _group(List<MenuProduct> products) {
    final grouped = <String, List<int>>{};
    for (var i = 0; i < products.length; i++) {
      final category = products[i].categoryId;
      if (category != null) grouped.putIfAbsent(category, () => <int>[]).add(i);
    }
    return grouped;
  }

  /// A product's options, when the menu came with them (see `MenuRepository.snapshot`).
  ProductDetail? detail(String productId) => _details[productId];

  /// The products of [categoryId] (all when null) whose name contains [search].
  List<MenuProduct> filter({String? categoryId, String search = ''}) {
    final term = search.trim().toLowerCase();
    if (categoryId == null && term.isEmpty) return products;
    final candidates = categoryId == null
        ? Iterable<int>.generate(products.length)
        : (_byCategory[categoryId] ?? const <int>[]);
    return [
      for (final i in candidates)
        if (term.isEmpty || _searchKeys[i].contains(term)) products[i],
    ];
  }

  /// The same menu with exactly [unavailable] marked sold out.
  MenuCatalog withUnavailable(Set<String> unavailable) => MenuCatalog._(
        categories,
        [
          for (final product in products)
            product.isAvailable == !unavailable.contains(product.id)
                ? product
                : product.copyWith(isAvailable: !unavailable.contains(product.id)),
        ],
        _details,
      );
}
