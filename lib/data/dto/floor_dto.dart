import 'json.dart';

/// Who is holding a table.
class ClaimHolder {
  const ClaimHolder({
    required this.terminalId,
    required this.terminalCode,
    required this.terminalName,
    required this.staffId,
    required this.staffName,
    this.expiresAt,
  });

  final String terminalId;
  final String terminalCode;
  final String terminalName;
  final String staffId;
  final String staffName;
  final String? expiresAt;

  factory ClaimHolder.fromJson(Map<String, dynamic> json) => ClaimHolder(
        terminalId: asString(json['terminal_id']),
        terminalCode: asString(json['terminal_code']),
        terminalName: asString(json['terminal_name']),
        staffId: asString(json['staff_id']),
        staffName: asString(json['staff_name']),
        expiresAt: asStringOrNull(json['expires_at']),
      );

  @override
  bool operator ==(Object other) =>
      other is ClaimHolder &&
      other.terminalId == terminalId &&
      other.terminalCode == terminalCode &&
      other.terminalName == terminalName &&
      other.staffId == staffId &&
      other.staffName == staffName &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode =>
      Object.hash(terminalId, terminalCode, terminalName, staffId, staffName, expiresAt);
}

/// A table's claim as this handset sees it. [leaseToken] is only ever filled in when the claim is
/// ours — the server hands that capability to nobody else.
class ClaimSummary {
  const ClaimSummary({
    required this.isMine,
    required this.expiresAt,
    required this.holder,
    this.leaseToken,
  });

  final bool isMine;
  final String expiresAt;
  final ClaimHolder holder;
  final String? leaseToken;

  factory ClaimSummary.fromJson(Map<String, dynamic> json) => ClaimSummary(
        isMine: asBool(json['is_mine']),
        expiresAt: asString(json['expires_at']),
        leaseToken: asStringOrNull(json['lease_token']),
        holder: ClaimHolder.fromJson(asMapOrNull(json['holder']) ?? const {}),
      );

  @override
  bool operator ==(Object other) =>
      other is ClaimSummary &&
      other.isMine == isMine &&
      other.expiresAt == expiresAt &&
      other.leaseToken == leaseToken &&
      other.holder == holder;

  @override
  int get hashCode => Object.hash(isMine, expiresAt, leaseToken, holder);
}

/// `POST /api/v1/staff-app/tables/:id/claim` and its renew sibling.
class TableClaim {
  const TableClaim({
    required this.floorItemId,
    required this.leaseToken,
    required this.expiresAt,
    this.sessionId,
    this.renewAfterMs = 60000,
    this.tookOverFrom,
  });

  final String floorItemId;
  final String leaseToken;
  final String expiresAt;
  final String? sessionId;
  final int renewAfterMs;

  /// Set only when a manager PIN took this table off another handset.
  final ClaimHolder? tookOverFrom;

  Duration get renewInterval => Duration(milliseconds: renewAfterMs);

  factory TableClaim.fromJson(Map<String, dynamic> json) {
    final tookOver = asMapOrNull(json['took_over_from']);
    return TableClaim(
      floorItemId: asString(json['floor_item_id']),
      leaseToken: asString(json['lease_token']),
      expiresAt: asString(json['expires_at']),
      sessionId: asStringOrNull(json['session_id']),
      renewAfterMs: asInt(json['renew_after_ms'], fallback: 60000),
      tookOverFrom: tookOver == null ? null : ClaimHolder.fromJson(tookOver),
    );
  }
}

/// How far along a table's food is — what the colour of its tile says.
enum TableFoodStatus {
  /// Nobody is seated.
  free,

  /// Seated, nothing sent to the kitchen yet.
  notOrdered,

  /// At least one dish has not reached the table.
  waiting,

  /// Every dish ordered has been served.
  served,
}

class TableSessionSummary {
  const TableSessionSummary({
    required this.sessionId,
    required this.status,
    required this.openedAt,
    this.guestCount = 1,
    this.currentRound = 0,
    this.orderId,
    this.itemCount = 0,
    this.totalAmount = 0,
    this.serverFoodStatus,
  });

  final String sessionId;
  final String status;
  final String openedAt;
  final int guestCount;
  final int currentRound;
  final String? orderId;
  final int itemCount;
  final num totalAmount;

  /// `food_status` as the server sent it: `NOT_ORDERED`, `WAITING` or `SERVED`.
  final String? serverFoodStatus;

  /// The cashier has this table's bill open at the POS; a waiter cannot add to it right now.
  bool get isPendingPayment => status == 'PENDING_PAYMENT';

  /// A server that does not send `food_status` still says whether anything was ordered; it just
  /// cannot say it has all been served.
  TableFoodStatus get foodStatus => switch (serverFoodStatus) {
        'NOT_ORDERED' => TableFoodStatus.notOrdered,
        'WAITING' => TableFoodStatus.waiting,
        'SERVED' => TableFoodStatus.served,
        _ => itemCount == 0 ? TableFoodStatus.notOrdered : TableFoodStatus.waiting,
      };

  factory TableSessionSummary.fromJson(Map<String, dynamic> json) => TableSessionSummary(
        sessionId: asString(json['session_id']),
        status: asString(json['status'], fallback: 'OPEN'),
        openedAt: asString(json['opened_at']),
        guestCount: asInt(json['guest_count'], fallback: 1),
        currentRound: asInt(json['current_round']),
        orderId: asStringOrNull(json['order_id']),
        itemCount: asInt(json['item_count']),
        totalAmount: asNum(json['total_amount']),
        serverFoodStatus: asStringOrNull(json['food_status']),
      );

  Map<String, dynamic> toCacheJson() => {
        'session_id': sessionId,
        'status': status,
        'opened_at': openedAt,
        'guest_count': guestCount,
        'current_round': currentRound,
        'order_id': orderId,
        'item_count': itemCount,
        'total_amount': totalAmount,
        'food_status': serverFoodStatus,
      };

  @override
  bool operator ==(Object other) =>
      other is TableSessionSummary &&
      other.sessionId == sessionId &&
      other.status == status &&
      other.openedAt == openedAt &&
      other.guestCount == guestCount &&
      other.currentRound == currentRound &&
      other.orderId == orderId &&
      other.itemCount == itemCount &&
      other.totalAmount == totalAmount &&
      other.serverFoodStatus == serverFoodStatus;

  @override
  int get hashCode => Object.hash(sessionId, status, openedAt, guestCount, currentRound, orderId,
      itemCount, totalAmount, serverFoodStatus);
}

class FloorTable {
  const FloorTable({
    required this.floorItemId,
    required this.label,
    this.itemType = 'TABLE',
    this.status = 'AVAILABLE',
    this.capacity,
    this.sortOrder = 0,
    this.session,
    this.claim,
  });

  final String floorItemId;
  final String label;
  final String itemType;
  final String status;
  final int? capacity;
  final int sortOrder;
  final TableSessionSummary? session;
  final ClaimSummary? claim;

  bool get isOccupied => session != null;
  bool get isOutOfService => status == 'DISABLED';
  bool get isHeldByMe => claim?.isMine ?? false;
  bool get isHeldByOther => claim != null && !claim!.isMine;
  TableFoodStatus get foodStatus => session?.foodStatus ?? TableFoodStatus.free;

  FloorTable withoutClaim() => FloorTable(
        floorItemId: floorItemId,
        label: label,
        itemType: itemType,
        status: status,
        capacity: capacity,
        sortOrder: sortOrder,
        session: session,
      );

  /// Everything but the claim — see `FloorStore`.
  Map<String, dynamic> toCacheJson() => {
        'floor_item_id': floorItemId,
        'label': label,
        'item_type': itemType,
        'status': status,
        'capacity': capacity,
        'sort_order': sortOrder,
        'session': session?.toCacheJson(),
      };

  @override
  bool operator ==(Object other) =>
      other is FloorTable &&
      other.floorItemId == floorItemId &&
      other.label == label &&
      other.itemType == itemType &&
      other.status == status &&
      other.capacity == capacity &&
      other.sortOrder == sortOrder &&
      other.session == session &&
      other.claim == claim;

  @override
  int get hashCode =>
      Object.hash(floorItemId, label, itemType, status, capacity, sortOrder, session, claim);

  factory FloorTable.fromJson(Map<String, dynamic> json) {
    final session = asMapOrNull(json['session']);
    final claim = asMapOrNull(json['claim']);
    return FloorTable(
      floorItemId: asString(json['floor_item_id']),
      label: asString(json['label']),
      itemType: asString(json['item_type'], fallback: 'TABLE'),
      status: asString(json['status'], fallback: 'AVAILABLE'),
      capacity: asIntOrNull(json['capacity']),
      sortOrder: asInt(json['sort_order']),
      session: session == null ? null : TableSessionSummary.fromJson(session),
      claim: claim == null ? null : ClaimSummary.fromJson(claim),
    );
  }
}

class FloorZone {
  const FloorZone({
    required this.zoneId,
    required this.zoneName,
    this.sortOrder = 0,
    this.colorHex,
    this.tableCount = 0,
    this.occupiedCount = 0,
    this.tables = const <FloorTable>[],
  });

  final String zoneId;
  final String zoneName;
  final int sortOrder;
  final String? colorHex;
  final int tableCount;
  final int occupiedCount;
  final List<FloorTable> tables;

  int get freeCount => tableCount - occupiedCount;

  FloorZone withTables(List<FloorTable> tables) => FloorZone(
        zoneId: zoneId,
        zoneName: zoneName,
        sortOrder: sortOrder,
        colorHex: colorHex,
        tableCount: tableCount,
        occupiedCount: occupiedCount,
        tables: tables,
      );

  Map<String, dynamic> toCacheJson() => {
        'zone_id': zoneId,
        'zone_name': zoneName,
        'sort_order': sortOrder,
        'color_hex': colorHex,
        'table_count': tableCount,
        'occupied_count': occupiedCount,
        'tables': [for (final table in tables) table.toCacheJson()],
      };

  factory FloorZone.fromJson(Map<String, dynamic> json) => FloorZone(
        zoneId: asString(json['zone_id']),
        zoneName: asString(json['zone_name']),
        sortOrder: asInt(json['sort_order']),
        colorHex: asStringOrNull(json['color_hex']),
        tableCount: asInt(json['table_count']),
        occupiedCount: asInt(json['occupied_count']),
        tables: asList(json['tables'], FloorTable.fromJson),
      );
}

/// `GET /api/v1/staff-app/session` — read on resume, to find the table this handset still holds.
class CurrentClaim {
  const CurrentClaim({
    required this.floorItemId,
    required this.leaseToken,
    required this.expiresAt,
    this.sessionId,
  });

  final String floorItemId;
  final String leaseToken;
  final String expiresAt;
  final String? sessionId;

  factory CurrentClaim.fromJson(Map<String, dynamic> json) => CurrentClaim(
        floorItemId: asString(json['floor_item_id']),
        leaseToken: asString(json['lease_token']),
        expiresAt: asString(json['expires_at']),
        sessionId: asStringOrNull(json['session_id']),
      );
}

/// `GET /api/v1/staff-app/session`
class StaffAppSessionState {
  const StaffAppSessionState({required this.staff, required this.terminal, this.currentClaim});

  final StaffSessionStaff staff;
  final StaffSessionTerminal terminal;
  final CurrentClaim? currentClaim;

  factory StaffAppSessionState.fromJson(Map<String, dynamic> json) {
    final claim = asMapOrNull(json['current_claim']);
    return StaffAppSessionState(
      staff: StaffSessionStaff.fromJson(asMapOrNull(json['staff']) ?? const {}),
      terminal: StaffSessionTerminal.fromJson(asMapOrNull(json['terminal']) ?? const {}),
      currentClaim: claim == null ? null : CurrentClaim.fromJson(claim),
    );
  }
}

class StaffSessionStaff {
  const StaffSessionStaff({required this.staffId, required this.staffName});

  final String staffId;
  final String staffName;

  factory StaffSessionStaff.fromJson(Map<String, dynamic> json) => StaffSessionStaff(
        staffId: asString(json['staff_id']),
        staffName: asString(json['staff_name']),
      );
}

class StaffSessionTerminal {
  const StaffSessionTerminal({
    required this.terminalId,
    required this.terminalCode,
    required this.terminalName,
  });

  final String terminalId;
  final String terminalCode;
  final String terminalName;

  factory StaffSessionTerminal.fromJson(Map<String, dynamic> json) => StaffSessionTerminal(
        terminalId: asString(json['terminal_id']),
        terminalCode: asString(json['terminal_code']),
        terminalName: asString(json['terminal_name']),
      );
}
