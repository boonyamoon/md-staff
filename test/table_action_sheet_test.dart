import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_staff/core/network/api_failure.dart';
import 'package:md_staff/core/providers.dart';
import 'package:md_staff/core/theme/app_theme.dart';
import 'package:md_staff/data/dto/floor_dto.dart';
import 'package:md_staff/data/dto/order_dto.dart';
import 'package:md_staff/features/bootstrap/session_controller.dart';
import 'package:md_staff/features/tables/active_table_controller.dart';
import 'package:md_staff/features/tables/table_action_sheet.dart';
import 'package:md_staff/features/tables/table_tile.dart';
import 'package:mocktail/mocktail.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'support/fakes.dart';

const _lease = 'lease-1';
const _offline = ApiFailure(code: 'NETWORK_UNREACHABLE', message: 'no connection');

Map<String, dynamic> _ref(String id) => {'floor_item_id': id, 'label': id};

/// `staff-app/tables/:id`. [kitchen] holds one kitchen status per dish; null leaves the table free.
TableDetail _detail({
  String id = 'A1',
  List<String>? kitchen = const [],
  String status = 'OPEN',
  num total = 0,
  int guests = 2,
  List<String> tables = const [],
  String? heldBy,
}) =>
    TableDetail.fromJson({
      'floor_item_id': id,
      'label': id,
      if (kitchen != null)
        'session': {
          'session_id': 's1',
          'status': status,
          'opened_at': '2026-01-01T12:00:00',
          'guest_count': guests,
          'primary_floor_item_id': tables.isEmpty ? id : tables.first,
          'tables': [for (final table in tables.isEmpty ? [id] : tables) _ref(table)],
        },
      if (kitchen != null && kitchen.isNotEmpty)
        'order': {
          'order_id': 'o1',
          'status': 'HELD',
          'total_amount': total,
          'lines': [
            for (var i = 0; i < kitchen.length; i++)
              {'order_item_id': 'line-$i', 'kitchen_status': kitchen[i]},
          ],
        },
      if (heldBy != null)
        'claim': {
          'is_mine': false,
          'holder': {'staff_name': heldBy, 'terminal_name': 'Handset 2'},
        },
    });

final _floor = [
  FloorZone.fromJson({
    'zone_id': 'z1',
    'zone_name': 'Terrace',
    'tables': [
      tableJson('A1', foodStatus: 'NOT_ORDERED'),
      tableJson('FREE'),
      tableJson('BUSY', foodStatus: 'WAITING'),
      tableJson('CLOSED', status: 'DISABLED'),
      tableJson('THEIRS', heldByMe: false),
    ],
  }),
];

void main() {
  late MockFloorRepository floor;
  late TableSheetResult? result;
  late bool closed;

  setUp(() {
    floor = MockFloorRepository();
    result = null;
    closed = false;
    when(floor.zones).thenAnswer((_) async => _floor);
    when(() => floor.table(any())).thenAnswer((_) async => _detail());
    when(() => floor.claim(any())).thenAnswer(
      (call) async => TableClaim(
        floorItemId: call.positionalArguments.first as String,
        leaseToken: _lease,
        expiresAt: '2026-01-01T12:30:00Z',
        renewAfterMs: 600000,
      ),
    );
    when(() => floor.releaseClaim(any(), any())).thenAnswer((_) async {});
  });

  /// A button that opens the menu of [table] and records what it closed with.
  Future<void> open(WidgetTester tester, {String table = 'A1'}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith(SignedInSession.new),
          floorRepositoryProvider.overrideWithValue(floor),
          localCacheProvider.overrideWithValue(MemoryLocalCache()),
          clockProvider.overrideWithValue(() => DateTime(2026, 1, 1, 12, 5)),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showTableSheet(context, floorItemId: table);
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('shows the table as the server has it, claiming nothing', (tester) async {
    when(() => floor.table('A1'))
        .thenAnswer((_) async => _detail(kitchen: ['SERVED', 'PENDING'], total: 1250, guests: 4));
    await open(tester);

    expect(find.text('A1'), findsOneWidget);
    expect(find.text('วันนี้ 12:00 (5 นาที)'), findsOneWidget);
    expect(find.text('รออาหาร'), findsOneWidget);
    expect(find.text('4 คน'), findsOneWidget);
    expect(find.text('฿ 1,250.00'), findsOneWidget);
    expect(find.text('สั่งเพิ่ม'), findsOneWidget);
    expect(find.text('แยกโต๊ะ'), findsNothing);
    verify(() => floor.table('A1')).called(1);
    verifyNever(() => floor.claim(any()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a table with nothing ordered offers ordering from the status line too',
      (tester) async {
    await open(tester);

    expect(find.text('ยังไม่ได้สั่งอาหาร'), findsOneWidget);
    expect(find.text('สั่งอาหาร'), findsNWidgets(2));
    expect(find.text('฿ 0.00'), findsOneWidget);
  });

  testWidgets('ordering claims the table, keeps it, and goes to the menu', (tester) async {
    await open(tester);

    await press(tester, 'สั่งอาหาร');

    expect(result!.next, TableSheetNext.order);
    verify(() => floor.claim('A1')).called(1);
    verifyNever(() => floor.releaseClaim(any(), any()));
  });

  int guestsOnTheCart(WidgetTester tester) => ProviderScope.containerOf(
        tester.element(find.text('open')),
      ).read(activeTableProvider).guestCount;

  testWidgets('ordering at a free table asks how many guests first', (tester) async {
    when(() => floor.table('FREE')).thenAnswer((_) async => _detail(id: 'FREE', kitchen: null));
    await open(tester, table: 'FREE');

    await press(tester, 'สั่งอาหาร');
    expect(find.text('จำนวนลูกค้าโต๊ะ FREE'), findsOneWidget);
    // The surface as painted, whatever the dialog or the theme set it from.
    Color? surfaceOf(Type type) => tester
        .widget<Material>(
          find.descendant(of: find.byType(type), matching: find.byType(Material)).first,
        )
        .color;
    expect(surfaceOf(Dialog), Colors.white);
    expect(surfaceOf(BottomSheet), Colors.white);
    // Backing out takes nothing.
    await press(tester, 'ยกเลิก');
    verifyNever(() => floor.claim(any()));
    expect(closed, isFalse);

    await press(tester, 'สั่งอาหาร');
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add_rounded));
    await press(tester, 'ยืนยัน');

    expect(result!.next, TableSheetNext.order);
    verify(() => floor.claim('FREE')).called(1);
    // Goes with the first round; nothing is opened until then.
    expect(guestsOnTheCart(tester), 3);
    verifyNever(() => floor.openTable(any(),
        leaseToken: any(named: 'leaseToken'),
        idempotencyKey: any(named: 'idempotencyKey'),
        guestCount: any(named: 'guestCount')));
  });

  /// The server's table as the menu opened, then as it is when the waiter presses.
  void changesAfterOpening(TableDetail then) {
    var reads = 0;
    when(() => floor.table('A1')).thenAnswer(
      (_) async => ++reads == 1 ? _detail(kitchen: ['SENT'], total: 500, guests: 4) : then,
    );
  }

  for (final (what, now) in [
    ('was cancelled at the POS', _detail(kitchen: null)),
    ('was given to another party', TableDetail.fromJson({
      'floor_item_id': 'A1',
      'label': 'A1',
      'session': {'session_id': 's2', 'status': 'OPEN'},
    })),
    ('lost its bill while still open', _detail(kitchen: [])),
  ]) {
    testWidgets('ordering more at a table that $what does not reach the menu', (tester) async {
      changesAfterOpening(now);
      await open(tester);

      await press(tester, 'สั่งเพิ่ม');

      expect(closed, isFalse);
      expect(find.text('โต๊ะนี้เปลี่ยนไปแล้ว กรุณาตรวจสอบอีกครั้ง'), findsOneWidget);
      // Given back, and both this menu and the floor read again.
      verify(() => floor.releaseClaim('A1', _lease)).called(1);
      verify(floor.zones).called(2);
      verify(() => floor.table('A1')).called(greaterThanOrEqualTo(3));
    });
  }

  testWidgets('after a cancellation, the next press seats a new party properly', (tester) async {
    changesAfterOpening(_detail(kitchen: null));
    await open(tester);

    await press(tester, 'สั่งเพิ่ม');
    // The menu now shows the free table, so ordering asks who is sitting down.
    await press(tester, 'สั่งอาหาร');

    expect(find.text('จำนวนลูกค้าโต๊ะ A1'), findsOneWidget);
  });

  testWidgets('a table seated meanwhile keeps its own guest count', (tester) async {
    var reads = 0;
    // Free when the menu opened; seated by the time it is claimed.
    when(() => floor.table('FREE')).thenAnswer(
      (_) async => ++reads == 1
          ? _detail(id: 'FREE', kitchen: null)
          : _detail(id: 'FREE', guests: 5),
    );
    await open(tester, table: 'FREE');

    await press(tester, 'สั่งอาหาร');
    await press(tester, 'ยืนยัน');

    expect(result!.next, TableSheetNext.order);
    expect(guestsOnTheCart(tester), 5);
  });

  testWidgets('the bill is opened without claiming', (tester) async {
    await open(tester);

    await press(tester, 'บิล');

    expect(result!.next, TableSheetNext.bill);
    verifyNever(() => floor.claim(any()));
  });

  testWidgets('a faded button says why instead of acting', (tester) async {
    when(() => floor.table('A1')).thenAnswer((_) async => _detail(kitchen: ['PENDING']));
    await open(tester);

    await press(tester, 'ยกเลิกโต๊ะ');

    expect(find.text('โต๊ะมีรายการแล้ว ยกเลิกบิลได้ที่ POS'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    verifyNever(() => floor.claim(any()));
  });

  testWidgets('changing the guest count claims, saves and gives the table back', (tester) async {
    when(() => floor.setGuestCount(any(),
        leaseToken: any(named: 'leaseToken'),
        sessionId: any(named: 'sessionId'),
        guestCount: any(named: 'guestCount'))).thenAnswer((_) async {});
    await open(tester);

    await press(tester, '2 คน');
    await tester.tap(find.byIcon(Icons.add_rounded));
    await press(tester, 'ยืนยัน');

    verify(() => floor.setGuestCount('A1', leaseToken: _lease, sessionId: 's1', guestCount: 3))
        .called(1);
    verify(() => floor.releaseClaim('A1', _lease)).called(1);
    expect(find.text('บันทึกจำนวนคนแล้ว'), findsOneWidget);
    // The menu stays, and both it and the floor are read again.
    expect(closed, isFalse);
    verify(() => floor.table('A1')).called(greaterThan(1));
    verify(floor.zones).called(2);
  });

  testWidgets('a QR for a free table opens it first, then shows the code', (tester) async {
    when(() => floor.table('FREE')).thenAnswer((_) async => _detail(id: 'FREE', kitchen: null));
    when(() => floor.openTable(any(),
        leaseToken: any(named: 'leaseToken'),
        idempotencyKey: any(named: 'idempotencyKey'),
        guestCount: any(named: 'guestCount'))).thenAnswer((_) async => 's9');
    when(() => floor.tableQr(any(), leaseToken: any(named: 'leaseToken'))).thenAnswer(
      (_) async => TableQr(
        url: 'https://order.meedeepos.com/q/tok',
        expiresAt: DateTime(2026, 1, 1, 20),
      ),
    );
    await open(tester, table: 'FREE');

    await press(tester, 'Mobile Order');
    expect(find.text('เปิดโต๊ะและสร้าง QR'), findsOneWidget);
    await press(tester, 'ยืนยัน');

    verifyInOrder([
      () => floor.openTable('FREE',
          leaseToken: _lease, idempotencyKey: any(named: 'idempotencyKey'), guestCount: 1),
      () => floor.tableQr('FREE', leaseToken: _lease),
      () => floor.releaseClaim('FREE', _lease),
    ]);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('ใช้ได้ถึง 20:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling asks first, then frees the table and closes', (tester) async {
    when(() => floor.cancelTable(any(),
        leaseToken: any(named: 'leaseToken'),
        idempotencyKey: any(named: 'idempotencyKey'),
        sessionId: any(named: 'sessionId'))).thenAnswer((_) async {});
    await open(tester);

    await press(tester, 'ยกเลิกโต๊ะ');
    await press(tester, 'ยกเลิก');
    verifyNever(() => floor.claim(any()));

    await press(tester, 'ยกเลิกโต๊ะ');
    await press(tester, 'ยืนยัน');

    verify(() => floor.cancelTable('A1',
        leaseToken: _lease,
        idempotencyKey: any(named: 'idempotencyKey'),
        sessionId: 's1')).called(1);
    verify(() => floor.releaseClaim('A1', _lease)).called(1);
    expect(result!.message, 'ยกเลิกโต๊ะ A1 แล้ว');
  });

  testWidgets('a refusal is explained, and the table is still given back', (tester) async {
    when(() => floor.cancelTable(any(),
        leaseToken: any(named: 'leaseToken'),
        idempotencyKey: any(named: 'idempotencyKey'),
        sessionId: any(named: 'sessionId'))).thenThrow(
      const ApiFailure(code: 'TABLE_HAS_ORDER', message: 'has an order', statusCode: 409),
    );
    await open(tester);

    await press(tester, 'ยกเลิกโต๊ะ');
    await press(tester, 'ยืนยัน');

    expect(find.text('โต๊ะมีรายการแล้ว ยกเลิกบิลได้ที่ POS'), findsOneWidget);
    verify(() => floor.releaseClaim('A1', _lease)).called(1);
    expect(closed, isFalse);
  });

  testWidgets('moving offers only free tables, and a retry replays the same request',
      (tester) async {
    final keys = <String>[];
    var attempts = 0;
    when(() => floor.transferTable(any(),
        leaseToken: any(named: 'leaseToken'),
        idempotencyKey: any(named: 'idempotencyKey'),
        sessionId: any(named: 'sessionId'),
        destinationId: any(named: 'destinationId'))).thenAnswer((call) async {
      keys.add(call.namedArguments[#idempotencyKey] as String);
      if (++attempts == 1) throw _offline;
    });
    await open(tester);

    Future<void> moveToFree() async {
      await press(tester, 'เปลี่ยนโต๊ะ');
      expect(
        tester.widgetList<TableTile>(find.byType(TableTile)).map((t) => t.floorItemId),
        ['FREE'],
      );
      await tester.tap(find.byType(TableTile));
      await tester.pumpAndSettle();
      expect(find.text('ย้ายจากโต๊ะ A1 ไปโต๊ะ FREE?'), findsOneWidget);
      await press(tester, 'ยืนยัน');
    }

    await moveToFree();
    expect(closed, isFalse);
    await moveToFree();

    expect(keys, hasLength(2));
    expect(keys.toSet(), hasLength(1));
    expect(result!.message, 'ย้ายไปโต๊ะ FREE แล้ว');
  });

  testWidgets('merging adds the picked free table to the party', (tester) async {
    when(() => floor.mergeTable(any(),
        leaseToken: any(named: 'leaseToken'),
        idempotencyKey: any(named: 'idempotencyKey'),
        sessionId: any(named: 'sessionId'),
        otherId: any(named: 'otherId'))).thenAnswer((_) async {});
    await open(tester);

    await press(tester, 'รวมโต๊ะ');
    await tester.tap(find.byType(TableTile));
    await tester.pumpAndSettle();
    await press(tester, 'ยืนยัน');

    verify(() => floor.mergeTable('A1',
        leaseToken: _lease,
        idempotencyKey: any(named: 'idempotencyKey'),
        sessionId: 's1',
        otherId: 'FREE')).called(1);
    expect(find.text('รวมโต๊ะ FREE แล้ว'), findsOneWidget);
  });

  testWidgets('a merged party can be split, choosing which table leaves', (tester) async {
    when(() => floor.table('A1'))
        .thenAnswer((_) async => _detail(tables: ['A1', 'B1', 'B2']));
    when(() => floor.unmergeTable(any(),
        leaseToken: any(named: 'leaseToken'),
        idempotencyKey: any(named: 'idempotencyKey'),
        sessionId: any(named: 'sessionId'),
        otherId: any(named: 'otherId'))).thenAnswer((_) async {});
    await open(tester);

    expect(find.text('A1 + B1 + B2'), findsOneWidget);
    await press(tester, 'แยกโต๊ะ');
    expect(find.text('เลือกโต๊ะที่จะแยกออก'), findsOneWidget);
    await press(tester, 'B2');
    await press(tester, 'ยืนยัน');

    verify(() => floor.unmergeTable('A1',
        leaseToken: _lease,
        idempotencyKey: any(named: 'idempotencyKey'),
        sessionId: 's1',
        otherId: 'B2')).called(1);
    expect(find.text('แยกโต๊ะ B2 แล้ว'), findsOneWidget);
  });

  testWidgets('a table another handset holds asks for a manager PIN', (tester) async {
    when(() => floor.table('A1')).thenAnswer((_) async => _detail(heldBy: 'Dao'));
    await open(tester);

    expect(find.text('Dao กำลังสั่งอยู่ · การแก้ไขต้องใช้ PIN ผู้จัดการ'), findsOneWidget);
    await press(tester, 'สั่งอาหาร');

    // The takeover sheet, over the menu; no claim attempted without the PIN.
    expect(find.textContaining('Dao'), findsWidgets);
    expect(find.byType(BottomSheet), findsNWidgets(2));
    verifyNever(() => floor.claim(any()));
    expect(result, isNull);
  });

  testWidgets('offline, shows the stored table and acts on nothing', (tester) async {
    when(() => floor.table('A1')).thenThrow(_offline);
    await open(tester);

    expect(find.textContaining('ออฟไลน์'), findsOneWidget);
    expect(find.text('A1'), findsOneWidget);
    await press(tester, 'Mobile Order');
    expect(find.text('ต้องออนไลน์จึงจะทำรายการได้'), findsOneWidget);
    await press(tester, 'บิล');
    expect(closed, isFalse);
    verifyNever(() => floor.claim(any()));
  });

  testWidgets('fits a small phone at the largest text size', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    when(() => floor.table('A1')).thenAnswer(
      (_) async => _detail(kitchen: ['SERVED'], total: 123456.5, tables: ['A1', 'B1', 'B2']),
    );
    await open(tester);
    tester.view.physicalSize = const Size(320, 568);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
