import 'package:flutter/foundation.dart';

import '../../data/dto/floor_dto.dart';
import '../../data/dto/order_dto.dart';

/// What the table menu shows: the floor's copy of the table at first, then the server's answer.
@immutable
class TableSheetView {
  const TableSheetView({
    required this.floorItemId,
    required this.label,
    this.sessionId,
    this.openedAt,
    this.guestCount,
    this.foodStatus = TableFoodStatus.free,
    this.total = 0,
    this.hasOrder = false,
    this.pendingPayment = false,
    this.heldBy,
    this.tables = const <TableRef>[],
    this.primaryFloorItemId,
  });

  factory TableSheetView.of(String floorItemId, {FloorTable? floor, TableDetail? detail}) {
    if (detail == null) {
      final session = floor?.session;
      return TableSheetView(
        floorItemId: floorItemId,
        label: floor?.label ?? '',
        sessionId: session?.sessionId,
        openedAt: _parse(session?.openedAt),
        guestCount: session?.guestCount,
        foodStatus: floor?.foodStatus ?? TableFoodStatus.free,
        total: session?.totalAmount ?? 0,
        hasOrder: session?.orderId != null,
        pendingPayment: session?.isPendingPayment ?? false,
        heldBy: (floor?.isHeldByOther ?? false) ? floor!.claim!.holder.staffName : null,
        tables: session?.tables ?? const <TableRef>[],
        primaryFloorItemId: session?.primaryFloorItemId,
      );
    }

    final session = detail.session;
    final order = detail.order;
    final liveOrder =
        order != null && order.status != 'CANCELLED' && order.status != 'VOIDED' ? order : null;
    final lines = liveOrder?.activeLines ?? const <OrderLine>[];
    // A server that does not list the group still leaves the floor's copy of it, which holds as
    // long as it is the same party.
    final stored = floor?.session?.sessionId == session?.sessionId ? floor?.session : null;

    return TableSheetView(
      floorItemId: floorItemId,
      label: detail.label,
      sessionId: session?.sessionId,
      openedAt: _parse(session?.openedAt),
      guestCount: session?.guestCount,
      foodStatus: session == null
          ? TableFoodStatus.free
          : lines.isEmpty
              ? TableFoodStatus.notOrdered
              : lines.every((line) => line.kitchenStatus == 'SERVED')
                  ? TableFoodStatus.served
                  : TableFoodStatus.waiting,
      total: liveOrder?.totalAmount ?? 0,
      hasOrder: liveOrder != null,
      pendingPayment: session?.isPendingPayment ?? false,
      heldBy: detail.isHeldByOther ? detail.claim!.holder.staffName : null,
      tables: (session?.tables.isNotEmpty ?? false)
          ? session!.tables
          : stored?.tables ?? const <TableRef>[],
      primaryFloorItemId: session?.primaryFloorItemId ?? stored?.primaryFloorItemId,
    );
  }

  final String floorItemId;
  final String label;

  /// Null while the table is free.
  final String? sessionId;
  final DateTime? openedAt;
  final int? guestCount;
  final TableFoodStatus foodStatus;
  final num total;
  final bool hasOrder;
  final bool pendingPayment;

  /// The staff member on another handset holding this table, if any.
  final String? heldBy;

  /// Every table of the party, the primary first.
  final List<TableRef> tables;
  final String? primaryFloorItemId;

  bool get isOpen => sessionId != null;
  bool get isMerged => tables.length > 1;

  /// Whether anything has been ordered that is still on the bill.
  bool get hasDishes =>
      foodStatus == TableFoodStatus.waiting || foodStatus == TableFoodStatus.served;

  /// `A1`, or `A1 + A2` when merged.
  String get title => isMerged ? tables.map((t) => t.label).join(' + ') : label;

  /// The tables that can be split off: all but the primary — or just this one, when it is not the
  /// primary itself.
  List<TableRef> get splittable {
    if (!isMerged) return const <TableRef>[];
    final primary = primaryFloorItemId ?? tables.first.floorItemId;
    return [
      for (final table in tables)
        if (table.floorItemId != primary &&
            (floorItemId == primary || table.floorItemId == floorItemId))
          table,
    ];
  }

  static DateTime? _parse(String? value) =>
      value == null ? null : DateTime.tryParse(value)?.toLocal();
}

enum TableMenuAction { order, bill, guests, qr, cancel, transfer, merge, unmerge }

/// Why [action] cannot be used on this table, as a string key — or null when it can. A table
/// another handset holds is not a reason: pressing asks for a manager PIN.
String? blockedReason(TableMenuAction action, TableSheetView view, {required bool offline}) {
  if (offline) return 'sheet.why.offline';
  if (view.pendingPayment) {
    return action == TableMenuAction.bill ? null : 'error.pendingPayment';
  }
  if (!view.isOpen) {
    return switch (action) {
      TableMenuAction.order || TableMenuAction.guests || TableMenuAction.qr => null,
      _ => 'sheet.why.free',
    };
  }
  if (action == TableMenuAction.cancel && view.hasOrder) return 'sheet.why.hasOrder';
  return null;
}
