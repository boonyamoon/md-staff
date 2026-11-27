import 'floor_dto.dart';
import 'json.dart';

class OrderLineOption {
  const OrderLineOption({
    required this.optionId,
    required this.optionName,
    this.groupName = '',
    this.priceAdjustment = 0,
    this.quantity = 1,
  });

  final String optionId;
  final String optionName;
  final String groupName;
  final num priceAdjustment;
  final int quantity;

  factory OrderLineOption.fromJson(Map<String, dynamic> json) => OrderLineOption(
        optionId: asString(json['option_id']),
        optionName: asString(json['option_name']),
        groupName: asString(json['group_name']),
        priceAdjustment: asNum(json['price_adjustment']),
        quantity: asInt(json['quantity'], fallback: 1),
      );
}

/// A line already sent to the kitchen. Read-only here: a handset cannot change or void a line —
/// that is the POS's job.
class OrderLine {
  const OrderLine({
    required this.orderItemId,
    required this.skuId,
    required this.productName,
    this.skuName = '',
    this.quantity = 1,
    this.unitPrice = 0,
    this.lineTotal = 0,
    this.roundNumber = 0,
    this.note,
    this.kitchenStatus,
    this.isCancelled = false,
    this.options = const <OrderLineOption>[],
  });

  final String orderItemId;
  final String skuId;
  final String productName;
  final String skuName;
  final num quantity;
  final num unitPrice;
  final num lineTotal;
  final int roundNumber;
  final String? note;
  final String? kitchenStatus;
  final bool isCancelled;
  final List<OrderLineOption> options;

  /// Whether this dish can still be called served: the kitchen has been asked for it and it has
  /// not been brought out yet. Any stage on the way counts, since a branch without a kitchen screen
  /// never moves a dish past SENT.
  bool get canBeServed => const {'SENT', 'PREPARING', 'READY'}.contains(kitchenStatus?.toUpperCase());

  factory OrderLine.fromJson(Map<String, dynamic> json) => OrderLine(
        orderItemId: asString(json['order_item_id']),
        skuId: asString(json['sku_id']),
        productName: asString(json['product_name']),
        skuName: asString(json['sku_name']),
        quantity: asNum(json['quantity'], fallback: 1),
        unitPrice: asNum(json['unit_price']),
        lineTotal: asNum(json['line_total']),
        roundNumber: asInt(json['round_number']),
        note: asStringOrNull(json['note']),
        kitchenStatus: asStringOrNull(json['kitchen_status']),
        isCancelled: asBool(json['is_cancelled']),
        options: asList(json['options'], OrderLineOption.fromJson),
      );
}

class TableOrder {
  const TableOrder({
    required this.orderId,
    required this.orderNumber,
    required this.status,
    this.orderType = 'DINE_IN',
    this.subtotal = 0,
    this.discountAmount = 0,
    this.serviceChargeAmount = 0,
    this.taxAmount = 0,
    this.taxIncluded = true,
    this.totalAmount = 0,
    this.lines = const <OrderLine>[],
  });

  final String orderId;
  final String orderNumber;
  final String status;
  final String orderType;
  final num subtotal;
  final num discountAmount;
  final num serviceChargeAmount;
  final num taxAmount;
  final bool taxIncluded;
  final num totalAmount;
  final List<OrderLine> lines;

  List<OrderLine> get activeLines => lines.where((l) => !l.isCancelled).toList();

  /// Lines grouped by the round they were sent in, newest round first.
  Map<int, List<OrderLine>> get linesByRound {
    final grouped = <int, List<OrderLine>>{};
    for (final line in activeLines) {
      grouped.putIfAbsent(line.roundNumber, () => <OrderLine>[]).add(line);
    }
    return Map.fromEntries(
      grouped.entries.toList()..sort((a, b) => b.key.compareTo(a.key)),
    );
  }

  factory TableOrder.fromJson(Map<String, dynamic> json) => TableOrder(
        orderId: asString(json['order_id']),
        orderNumber: asString(json['order_number']),
        status: asString(json['status']),
        orderType: asString(json['order_type'], fallback: 'DINE_IN'),
        subtotal: asNum(json['subtotal']),
        discountAmount: asNum(json['discount_amount']),
        serviceChargeAmount: asNum(json['service_charge_amount']),
        taxAmount: asNum(json['tax_amount']),
        taxIncluded: asBool(json['tax_included'], fallback: true),
        totalAmount: asNum(json['total_amount']),
        lines: asList(json['lines'], OrderLine.fromJson),
      );
}

class TableSessionDetail {
  const TableSessionDetail({
    required this.sessionId,
    required this.status,
    required this.openedAt,
    this.guestCount = 1,
    this.currentRound = 0,
    this.primaryFloorItemId,
    this.tables = const <TableRef>[],
  });

  final String sessionId;
  final String status;
  final String openedAt;
  final int guestCount;
  final int currentRound;
  final String? primaryFloorItemId;

  /// Every table the party sits at, the primary first. Empty from a server that does not say.
  final List<TableRef> tables;

  bool get isPendingPayment => status == 'PENDING_PAYMENT';

  factory TableSessionDetail.fromJson(Map<String, dynamic> json) => TableSessionDetail(
        sessionId: asString(json['session_id']),
        status: asString(json['status'], fallback: 'OPEN'),
        openedAt: asString(json['opened_at']),
        guestCount: asInt(json['guest_count'], fallback: 1),
        currentRound: asInt(json['current_round']),
        primaryFloorItemId: asStringOrNull(json['primary_floor_item_id']),
        tables: asList(json['tables'], TableRef.fromJson),
      );
}

/// `GET /api/v1/staff-app/tables/:floorItemId` — the table screen's whole state.
class TableDetail {
  const TableDetail({
    required this.floorItemId,
    required this.label,
    required this.zoneId,
    required this.zoneName,
    this.capacity,
    this.status = 'AVAILABLE',
    this.claim,
    this.session,
    this.order,
  });

  final String floorItemId;
  final String label;
  final String zoneId;
  final String zoneName;
  final int? capacity;
  final String status;
  final ClaimSummary? claim;
  final TableSessionDetail? session;
  final TableOrder? order;

  bool get isHeldByMe => claim?.isMine ?? false;
  bool get isHeldByOther => claim != null && !claim!.isMine;
  String? get myLeaseToken => claim?.isMine == true ? claim!.leaseToken : null;

  factory TableDetail.fromJson(Map<String, dynamic> json) {
    final claim = asMapOrNull(json['claim']);
    final session = asMapOrNull(json['session']);
    final order = asMapOrNull(json['order']);
    return TableDetail(
      floorItemId: asString(json['floor_item_id']),
      label: asString(json['label']),
      zoneId: asString(json['zone_id']),
      zoneName: asString(json['zone_name']),
      capacity: asIntOrNull(json['capacity']),
      status: asString(json['status'], fallback: 'AVAILABLE'),
      claim: claim == null ? null : ClaimSummary.fromJson(claim),
      session: session == null ? null : TableSessionDetail.fromJson(session),
      order: order == null ? null : TableOrder.fromJson(order),
    );
  }
}

/// `POST /api/v1/staff-app/tables/:floorItemId/orders` — the round the kitchen just got.
class PlacedRound {
  const PlacedRound({
    required this.orderId,
    required this.orderNumber,
    required this.sessionId,
    this.itemsAdded = 0,
    this.isNewOrder = false,
    this.totalAmount = 0,
    this.tableLabel,
    this.idempotentReplay = false,
  });

  final String orderId;
  final String orderNumber;
  final String sessionId;
  final int itemsAdded;
  final bool isNewOrder;
  final num totalAmount;
  final String? tableLabel;

  /// True when a retry was answered from the ledger: the round had already been sent, and nothing
  /// was added a second time.
  final bool idempotentReplay;

  factory PlacedRound.fromJson(Map<String, dynamic> json) => PlacedRound(
        orderId: asString(json['order_id']),
        orderNumber: asString(json['order_number']),
        sessionId: asString(json['session_id']),
        itemsAdded: asInt(json['items_added']),
        isNewOrder: asBool(json['is_new_order']),
        totalAmount: asNum(json['total_amount']),
        tableLabel: asStringOrNull(json['table_label_snapshot']),
        idempotentReplay: asBool(json['idempotent_replay']),
      );
}
