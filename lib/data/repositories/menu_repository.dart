import '../../core/network/api_client.dart';
import '../dto/json.dart';
import '../dto/menu_dto.dart';

/// The same menu the kiosk and the QR flows read, so a waiter sees exactly what a customer would.
class MenuRepository {
  MenuRepository({required ApiClient api}) : _api = api;

  final ApiClient _api;

  Future<List<MenuCategory>> categories() async {
    final body = await _api.get('api/v1/staff-app/menu/categories');
    return envelopeList(body)
        .map(MenuCategory.fromJson)
        // Only top-level categories become filter chips; a shop with sub-categories would
        // otherwise show two rows of chips on a phone.
        .where((c) => c.parentCategoryId == null)
        .toList();
  }

  Future<MenuPage> products({String? categoryId, String? search, int page = 1, int limit = 50}) async {
    final body = await _api.get(
      'api/v1/staff-app/menu/products',
      query: {
        'page': page,
        'limit': limit,
        'category_id': ?categoryId,
        if (search != null && search.isNotEmpty) 'search': search,
      },
    );
    return MenuPage.fromJson(body);
  }

  Future<ProductDetail> productDetail(String productId) async {
    final body = await _api.get('api/v1/staff-app/menu/products/$productId');
    return ProductDetail.fromJson(envelopeData(body));
  }

  /// Ids of products that cannot be ordered right now. Polled between full menu loads so a
  /// sold-out dish greys out without reloading the grid — the kiosk polls the same endpoint.
  Future<Set<String>> unavailableProductIds() async {
    final body = await _api.get('api/v1/staff-app/menu/availability');
    final data = envelopeData(body);
    final ids = data['unavailable_product_ids'];
    if (ids is! List) return <String>{};
    return ids.map((e) => asString(e)).where((e) => e.isNotEmpty).toSet();
  }
}
