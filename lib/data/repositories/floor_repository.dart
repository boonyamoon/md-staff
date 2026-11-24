import 'package:uuid/uuid.dart';

import '../../core/network/api_client.dart';
import '../dto/floor_dto.dart';
import '../dto/order_dto.dart';

/// Zones, tables, and the claim that makes a table one handset's at a time.
class FloorRepository {
  FloorRepository({required ApiClient api, Uuid? uuid})
      : _api = api,
        _uuid = uuid ?? const Uuid();

  final ApiClient _api;
  final Uuid _uuid;

  Future<List<FloorZone>> zones() async {
    final body = await _api.get('api/v1/staff-app/zones');
    return envelopeList(body).map(FloorZone.fromJson).toList();
  }

  Future<TableDetail> table(String floorItemId) async {
    final body = await _api.get('api/v1/staff-app/tables/$floorItemId');
    return TableDetail.fromJson(envelopeData(body));
  }

  /// Takes the table. Without [managerPin] this fails with TABLE_CLAIM_HELD when another handset
  /// is on it; with a valid manager PIN it takes it over and reports who it was taken from.
  Future<TableClaim> claim(String floorItemId, {String? managerPin}) async {
    final body = await _api.post(
      'api/v1/staff-app/tables/$floorItemId/claim',
      body: {
        if (managerPin != null) 'force': true,
        'manager_pin': ?managerPin,
      },
    );
    return TableClaim.fromJson(envelopeData(body));
  }

  /// Extends the lease. Fails with TABLE_CLAIM_LOST once a manager has taken the table, which is
  /// what tells the app to leave the ordering screen.
  Future<TableClaim> renewClaim(String floorItemId, String leaseToken) async {
    final body = await _api.post(
      'api/v1/staff-app/tables/$floorItemId/claim/renew',
      headers: {'X-Claim-Lease': leaseToken},
    );
    return TableClaim.fromJson(envelopeData(body));
  }

  /// Gives the table back. Succeeds even when the lease was already gone.
  Future<void> releaseClaim(String floorItemId, String leaseToken) async {
    await _api.post(
      'api/v1/staff-app/tables/$floorItemId/claim/release',
      headers: {'X-Claim-Lease': leaseToken},
    );
  }

  /// Sends a round to the kitchen.
  ///
  /// [idempotencyKey] must stay the same across retries of the same round — pass the key the cart
  /// generated when the waiter pressed send, not a fresh one per attempt, or a retry after a lost
  /// response adds the round twice. Generate one with [newIdempotencyKey].
  Future<PlacedRound> placeOrder({
    required String floorItemId,
    required String leaseToken,
    required String idempotencyKey,
    required List<Map<String, dynamic>> items,
    int? guestCount,
    String orderType = 'DINE_IN',
  }) async {
    final body = await _api.post(
      'api/v1/staff-app/tables/$floorItemId/orders',
      headers: {'X-Claim-Lease': leaseToken, 'Idempotency-Key': idempotencyKey},
      body: {
        'items': items,
        'order_type': orderType,
        'guest_count': ?guestCount,
      },
    );
    return PlacedRound.fromJson(envelopeData(body));
  }

  String newIdempotencyKey() => _uuid.v4();
}
