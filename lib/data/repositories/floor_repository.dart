import 'package:uuid/uuid.dart';

import '../../core/network/api_client.dart';
import '../dto/floor_dto.dart';
import '../dto/json.dart';
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

  /// Marks dishes as brought to the table. Needs no claim, and asking twice changes nothing.
  /// Refused when the table no longer seats the party named by [sessionId].
  Future<void> markServed(
    String floorItemId, {
    required String sessionId,
    required List<String> orderItemIds,
  }) async {
    await _api.post(
      'api/v1/staff-app/tables/$floorItemId/served',
      body: {'session_id': sessionId, 'order_item_ids': orderItemIds},
    );
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
  ///
  /// [sessionId] names the party the round is for, when the table had one: the server then refuses
  /// it if that party is gone, rather than opening the table afresh.
  Future<PlacedRound> placeOrder({
    required String floorItemId,
    required String leaseToken,
    required String idempotencyKey,
    required List<Map<String, dynamic>> items,
    int? guestCount,
    String? sessionId,
    String orderType = 'DINE_IN',
  }) async {
    final body = await _api.post(
      'api/v1/staff-app/tables/$floorItemId/orders',
      headers: {'X-Claim-Lease': leaseToken, 'Idempotency-Key': idempotencyKey},
      body: {
        'items': items,
        'order_type': orderType,
        'guest_count': ?guestCount,
        'session_id': ?sessionId,
      },
    );
    return PlacedRound.fromJson(envelopeData(body));
  }

  // ── The table menu. Each acts under the table's claim lease; [sessionId] is the party the waiter
  // was looking at, so an action meant for one party never lands on the next. ──

  /// Seats [guestCount] at a free table without ordering yet. Answers with the session's id.
  Future<String> openTable(
    String floorItemId, {
    required String leaseToken,
    required String idempotencyKey,
    required int guestCount,
  }) async {
    final body = await _api.post(
      'api/v1/staff-app/tables/$floorItemId/open',
      headers: _leased(leaseToken, idempotencyKey),
      body: {'guest_count': guestCount},
    );
    return asString(envelopeData(body)['session_id']);
  }

  Future<void> setGuestCount(
    String floorItemId, {
    required String leaseToken,
    required String sessionId,
    required int guestCount,
  }) async {
    await _api.patch(
      'api/v1/staff-app/tables/$floorItemId/guests',
      headers: _leased(leaseToken),
      body: {'session_id': sessionId, 'guest_count': guestCount},
    );
  }

  /// The link a guest scans to order for this table.
  Future<TableQr> tableQr(String floorItemId, {required String leaseToken}) async {
    final body = await _api.post(
      'api/v1/staff-app/tables/$floorItemId/qr',
      headers: _leased(leaseToken),
    );
    return TableQr.fromJson(envelopeData(body));
  }

  /// Releases a table nobody has ordered at.
  Future<void> cancelTable(
    String floorItemId, {
    required String leaseToken,
    required String idempotencyKey,
    required String sessionId,
  }) async {
    await _api.post(
      'api/v1/staff-app/tables/$floorItemId/cancel',
      headers: _leased(leaseToken, idempotencyKey),
      body: {'session_id': sessionId},
    );
  }

  Future<void> transferTable(
    String floorItemId, {
    required String leaseToken,
    required String idempotencyKey,
    required String sessionId,
    required String destinationId,
  }) async {
    await _api.post(
      'api/v1/staff-app/tables/$floorItemId/transfer',
      headers: _leased(leaseToken, idempotencyKey),
      body: {'session_id': sessionId, 'destination_floor_item_id': destinationId},
    );
  }

  /// Adds the free table [otherId] to the party at [floorItemId].
  Future<void> mergeTable(
    String floorItemId, {
    required String leaseToken,
    required String idempotencyKey,
    required String sessionId,
    required String otherId,
  }) async {
    await _api.post(
      'api/v1/staff-app/tables/$floorItemId/merge',
      headers: _leased(leaseToken, idempotencyKey),
      body: {'session_id': sessionId, 'floor_item_id': otherId},
    );
  }

  /// Takes [otherId] out of the party at [floorItemId].
  Future<void> unmergeTable(
    String floorItemId, {
    required String leaseToken,
    required String idempotencyKey,
    required String sessionId,
    required String otherId,
  }) async {
    await _api.post(
      'api/v1/staff-app/tables/$floorItemId/unmerge',
      headers: _leased(leaseToken, idempotencyKey),
      body: {'session_id': sessionId, 'floor_item_id': otherId},
    );
  }

  static Map<String, String> _leased(String leaseToken, [String? idempotencyKey]) =>
      {'X-Claim-Lease': leaseToken, 'Idempotency-Key': ?idempotencyKey};

  String newIdempotencyKey() => _uuid.v4();
}
