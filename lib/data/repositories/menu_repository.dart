import '../../core/network/api_client.dart';
import '../../core/network/api_failure.dart';
import '../dto/json.dart';
import '../dto/menu_dto.dart';

/// The whole menu as the server sent it, or the news that the copy held is still current.
class MenuSnapshot {
  const MenuSnapshot({this.data, this.etag});

  /// `{categories: [...], products: [...]}`; null when nothing changed.
  final Map<String, dynamic>? data;
  final String? etag;

  bool get notModified => data == null;
}

/// The same menu the kiosk and the QR flows read, so a waiter sees exactly what a customer would.
class MenuRepository {
  MenuRepository({required ApiClient api}) : _api = api;

  final ApiClient _api;

  static const _listingPageSize = 100;

  /// Every category, product and option group in one call. Pass the [etag] of the copy already
  /// held to be told when it is still current.
  Future<MenuSnapshot> snapshot({String? etag}) async {
    try {
      final response = await _api.getIfChanged('api/v1/staff-app/menu/snapshot', etag: etag);
      final body = response.body;
      if (body == null) return MenuSnapshot(etag: etag);
      return MenuSnapshot(data: envelopeData(body), etag: response.etag);
    } on ApiFailure catch (failure) {
      if (!failure.isMissingRoute) rethrow;
      return MenuSnapshot(data: await _listing());
    }
  }

  /// The same, assembled from the listing for a server that has no snapshot endpoint yet. Option
  /// groups are not part of the listing, so choosing options then needs a connection.
  Future<Map<String, dynamic>> _listing() async {
    final categories = envelopeList(await _api.get('api/v1/staff-app/menu/categories'));
    final products = <Map<String, dynamic>>[];
    for (var page = 1, more = true; more; page += 1) {
      final body = await _api.get(
        'api/v1/staff-app/menu/products',
        query: {'page': page, 'limit': _listingPageSize},
      );
      products.addAll(envelopeList(body));
      more = MenuPage.fromJson(body).hasNextPage;
    }
    return {'categories': categories, 'products': products};
  }

  Future<ProductDetail> productDetail(String productId) async {
    final body = await _api.get('api/v1/staff-app/menu/products/$productId');
    return ProductDetail.fromJson(envelopeData(body));
  }

  /// Ids of products that cannot be ordered right now — a cheap check between full menu loads, so
  /// a sold-out dish greys out without reloading the menu.
  Future<Set<String>> unavailableProductIds() async {
    final body = await _api.get('api/v1/staff-app/menu/availability');
    final data = envelopeData(body);
    final ids = data['unavailable_product_ids'];
    if (ids is! List) return <String>{};
    return ids.map((e) => asString(e)).where((e) => e.isNotEmpty).toSet();
  }
}
