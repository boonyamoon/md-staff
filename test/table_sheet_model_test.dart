import 'package:flutter_test/flutter_test.dart';
import 'package:md_staff/core/l10n/strings.dart';
import 'package:md_staff/core/network/api_failure.dart';
import 'package:md_staff/data/dto/floor_dto.dart';
import 'package:md_staff/data/dto/order_dto.dart';
import 'package:md_staff/features/tables/table_actions.dart';
import 'package:md_staff/features/tables/table_sheet_model.dart';

const _open = TableSheetView(floorItemId: 'A1', label: 'A1', sessionId: 's1');

TableSheetView _view({bool free = false, bool hasOrder = false, bool paying = false}) =>
    TableSheetView(
      floorItemId: 'A1',
      label: 'A1',
      sessionId: free ? null : 's1',
      hasOrder: hasOrder,
      pendingPayment: paying,
    );

Set<TableMenuAction> _usable(TableSheetView view, {bool offline = false}) => {
      for (final action in TableMenuAction.values)
        if (blockedReason(action, view, offline: offline) == null) action,
    };

void main() {
  group('which buttons can be used', () {
    final all = TableMenuAction.values.toSet();

    test('on a free table: ordering, guests and the QR', () {
      expect(_usable(_view(free: true)),
          {TableMenuAction.order, TableMenuAction.guests, TableMenuAction.qr});
    });

    test('on an open table with nothing ordered: all of them', () {
      expect(_usable(_view()), all);
    });

    test('once ordered: all but cancel', () {
      expect(_usable(_view(hasOrder: true)), all.difference({TableMenuAction.cancel}));
    });

    test('while being paid for: only the bill', () {
      expect(_usable(_view(hasOrder: true, paying: true)), {TableMenuAction.bill});
    });

    test('offline: none', () {
      expect(_usable(_open, offline: true), isEmpty);
    });
  });

  group('splitting', () {
    const group = [
      TableRef(floorItemId: 'A1', label: 'A1'),
      TableRef(floorItemId: 'B1', label: 'B1'),
      TableRef(floorItemId: 'B2', label: 'B2'),
    ];
    TableSheetView at(String id) => TableSheetView(
          floorItemId: id,
          label: id,
          sessionId: 's1',
          tables: group,
          primaryFloorItemId: 'A1',
        );

    test('from the primary offers every other table', () {
      expect(at('A1').splittable.map((t) => t.label), ['B1', 'B2']);
    });

    test('from another table offers only itself', () {
      expect(at('B2').splittable.map((t) => t.label), ['B2']);
    });
  });

  test('the server’s answer replaces the floor’s copy, including a table that turned free', () {
    final floor = FloorTable.fromJson({
      'floor_item_id': 'A1',
      'label': 'A1',
      'session': {'session_id': 's1', 'total_amount': 500, 'order_id': 'o1', 'item_count': 2},
    });

    expect(TableSheetView.of('A1', floor: floor).total, 500);

    final view = TableSheetView.of(
      'A1',
      floor: floor,
      detail: const TableDetail(floorItemId: 'A1', label: 'A1', zoneId: 'z', zoneName: 'Z'),
    );
    expect(view.isOpen, isFalse);
    expect(view.total, 0);
    expect(view.hasOrder, isFalse);
    expect(view.foodStatus, TableFoodStatus.free);
  });

  test('says when a table was opened and how long ago', () {
    const th = AppStrings(AppLanguage.th);
    final now = DateTime(2026, 1, 2, 14, 5);

    expect(th.since(DateTime(2026, 1, 2, 14), now: now), 'วันนี้ 14:00 (5 นาที)');
    expect(th.since(DateTime(2026, 1, 2, 12), now: now), 'วันนี้ 12:00 (2 ชม. 5 นาที)');
    expect(th.since(DateTime(2026, 1, 1, 12), now: now), '1/1 12:00 (1 วัน)');
    // A clock ahead of this handset's must not count backwards.
    expect(th.since(DateTime(2026, 1, 2, 14, 7), now: now), 'วันนี้ 14:07 (0 นาที)');
  });

  group('idempotency keys', () {
    Future<String> attempt(IdempotencyKeys keys, ApiFailure? failure) async {
      late String used;
      try {
        await keys.run('transfer:s1:A2', (key) async {
          used = key;
          if (failure != null) throw failure;
        });
      } on ApiFailure {
        // Expected for the failing attempts.
      }
      return used;
    }

    test('are reused while the outcome is unknown, and renewed once it is known', () async {
      final keys = IdempotencyKeys();
      const lost = ApiFailure(code: 'TIMEOUT', message: 'slow');
      const refused = ApiFailure(code: 'TABLE_ALREADY_MAPPED', message: 'busy', statusCode: 409);

      final first = await attempt(keys, lost);
      final second = await attempt(keys, refused);
      final third = await attempt(keys, null);
      final fourth = await attempt(keys, null);

      expect(second, first);
      expect(third, isNot(second));
      expect(fourth, isNot(third));
    });
  });
}
