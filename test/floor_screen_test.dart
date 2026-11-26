import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_staff/core/network/api_failure.dart';
import 'package:md_staff/core/providers.dart';
import 'package:md_staff/core/theme/app_theme.dart';
import 'package:md_staff/data/dto/floor_dto.dart';
import 'package:md_staff/data/dto/order_dto.dart';
import 'package:md_staff/data/local/floor_store.dart';
import 'package:md_staff/data/repositories/menu_repository.dart';
import 'package:md_staff/features/bootstrap/session_controller.dart';
import 'package:md_staff/features/tables/table_action_sheet.dart';
import 'package:md_staff/features/zones/floor_screen.dart';
import 'package:mocktail/mocktail.dart';

import 'support/fakes.dart';

FloorZone _zone(String id, String name, List<Map<String, dynamic>> tables) =>
    FloorZone.fromJson({'zone_id': id, 'zone_name': name, 'tables': tables});

final _floor = [
  _zone('z1', '1st Floor', [
    tableJson('A1', foodStatus: 'SERVED'),
    tableJson('A2', foodStatus: 'WAITING'),
    tableJson('A3', foodStatus: 'NOT_ORDERED'),
    tableJson('A4'),
    tableJson('A5', heldByMe: false),
    tableJson('A6', heldByMe: true),
    tableJson('A7', foodStatus: 'WAITING', sessionStatus: 'PENDING_PAYMENT'),
  ]),
  _zone('z2', 'Terrace', [tableJson('T1')]),
  _zone('z3', 'Empty room', []),
];

void main() {
  late MockFloorRepository floor;
  late MockMenuRepository menu;
  late MemoryLocalCache cache;

  setUp(() {
    floor = MockFloorRepository();
    menu = MockMenuRepository();
    cache = MemoryLocalCache();
    when(() => menu.snapshot(etag: any(named: 'etag')))
        .thenAnswer((_) async => MenuSnapshot(data: menuJson()));
  });

  Future<void> pumpFloor(WidgetTester tester, {Size size = const Size(390, 844)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith(SignedInSession.new),
          floorRepositoryProvider.overrideWithValue(floor),
          menuRepositoryProvider.overrideWithValue(menu),
          localCacheProvider.overrideWithValue(cache),
        ],
        child: MaterialApp(theme: buildAppTheme(), home: const FloorScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  BorderSide ringOf(WidgetTester tester, String label) {
    final tile = tester.widget<Material>(
      find.ancestor(of: find.text(label), matching: find.byType(Material)).first,
    );
    return (tile.shape! as RoundedRectangleBorder).side;
  }

  testWidgets('shows a tab per zone, and the chosen zone\'s tables three across', (tester) async {
    when(floor.zones).thenAnswer((_) async => _floor);
    await pumpFloor(tester);

    expect(find.widgetWithText(Tab, '1st Floor'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Terrace'), findsOneWidget);
    final top = [for (final label in ['A1', 'A2', 'A3']) tester.getCenter(find.text(label))];
    expect(top.map((p) => p.dy).toSet(), hasLength(1));
    expect(top[0].dx < top[1].dx && top[1].dx < top[2].dx, isTrue);
    expect(tester.getCenter(find.text('A4')).dy, greaterThan(top[0].dy));
    expect(tester.getCenter(find.text('A4')).dx, top[0].dx);
    expect(find.text('T1'), findsNothing);

    await tester.tap(find.widgetWithText(Tab, 'Terrace'));
    await tester.pumpAndSettle();
    expect(find.text('T1'), findsOneWidget);
    expect(find.text('A1'), findsNothing);

    await tester.tap(find.widgetWithText(Tab, 'Empty room'));
    await tester.pumpAndSettle();
    expect(find.text('โซนนี้ยังไม่มีโต๊ะ'), findsOneWidget);
    // Switching zones asks the server nothing.
    verify(floor.zones).called(1);
  });

  testWidgets('rings each table in the colour of its food, with a legend', (tester) async {
    when(floor.zones).thenAnswer((_) async => _floor);
    await pumpFloor(tester);

    expect(ringOf(tester, 'A1').color, MeedColors.ringServed);
    expect(ringOf(tester, 'A2').color, MeedColors.ringWaiting);
    expect(ringOf(tester, 'A3').color, MeedColors.ringNotOrdered);
    expect(ringOf(tester, 'A4').color, MeedColors.ringFree);
    expect({for (final label in ['A1', 'A2', 'A3', 'A4']) ringOf(tester, label).width}, {4});
    for (final meaning in ['ว่าง', 'ยังไม่ได้สั่ง', 'รออาหาร', 'เสิร์ฟครบแล้ว']) {
      expect(find.text(meaning), findsOneWidget);
    }
    // What the ring cannot say.
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('counts the guests at a table, not its seats', (tester) async {
    const group = [
      {'floor_item_id': 'M1', 'label': 'M1'},
      {'floor_item_id': 'M2', 'label': 'M2'},
    ];
    Map<String, dynamic> member(String id) {
      final table = tableJson(id, foodStatus: 'WAITING', guests: 7);
      (table['session'] as Map<String, dynamic>)
        ..['tables'] = group
        ..['primary_floor_item_id'] = 'M1';
      return table;
    }

    when(floor.zones).thenAnswer(
      (_) async => [
        _zone('z1', 'Zone', [
          // Four seats each; three guests at S1, and a party of seven across M1 and M2.
          tableJson('S1', foodStatus: 'NOT_ORDERED', guests: 3),
          member('M1'),
          member('M2'),
        ]),
      ],
    );
    await pumpFloor(tester);

    expect(find.text('3'), findsOneWidget);
    expect(find.text('7'), findsNWidgets(2));
    expect(find.text('4'), findsNothing);
  });

  testWidgets('says a table nobody sits at is free, with no head count', (tester) async {
    when(floor.zones).thenAnswer(
      (_) async => [
        _zone('z1', 'Zone', [
          tableJson('F1'),
          tableJson('F2', heldByMe: false),
          tableJson('F3', status: 'DISABLED'),
        ]),
      ],
    );
    await pumpFloor(tester);

    // F2 is held by another handset but nobody is seated yet.
    expect(find.text('(ว่าง)'), findsNWidgets(2));
    expect(find.text('(งดใช้)'), findsOneWidget);
    expect(find.byIcon(Icons.person_rounded), findsNothing);
    expect(find.text('4'), findsNothing);
  });

  testWidgets('fits a small phone at the largest text size', (tester) async {
    when(floor.zones).thenAnswer((_) async => _floor);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpFloor(tester, size: const Size(320, 568));

    expect(find.text('A1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline, shows the stored floor and says how old it is', (tester) async {
    final earlier = DateTime.now().subtract(const Duration(minutes: 10));
    await FloorStore(cache).save(testBranch, _floor, earlier);
    when(floor.zones).thenThrow(
      const ApiFailure(code: 'NETWORK_UNREACHABLE', message: 'no connection'),
    );
    await pumpFloor(tester);

    expect(find.text('A1'), findsOneWidget);
    expect(find.textContaining('ออฟไลน์ · ข้อมูลเมื่อ'), findsOneWidget);
    // Claims are not kept on disk, so no stale padlock is shown.
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
  });

  testWidgets('tapping a table brings up its menu without claiming it', (tester) async {
    when(floor.zones).thenAnswer((_) async => _floor);
    when(() => floor.table('A4')).thenAnswer(
      (_) async => const TableDetail(
        floorItemId: 'A4',
        label: 'A4',
        zoneId: 'z1',
        zoneName: '1st Floor',
      ),
    );
    await pumpFloor(tester);

    await tester.tap(find.text('A4'));
    await tester.pumpAndSettle();

    expect(find.byType(TableActionSheet), findsOneWidget);
    expect(find.text('ยังไม่ได้เปิดโต๊ะ'), findsOneWidget);
    verify(() => floor.table('A4')).called(1);
    verifyNever(() => floor.claim(any()));
  });

  testWidgets('marks the tables of a merged party, naming the primary on the others',
      (tester) async {
    const group = [
      {'floor_item_id': 'M1', 'label': 'M1'},
      {'floor_item_id': 'M2', 'label': 'M2'},
    ];
    Map<String, dynamic> member(String id) {
      final table = tableJson(id, foodStatus: 'WAITING');
      (table['session'] as Map<String, dynamic>)
        ..['tables'] = group
        ..['primary_floor_item_id'] = 'M1';
      return table;
    }

    when(floor.zones).thenAnswer(
      (_) async => [
        _zone('z1', 'Zone', [member('M1'), member('M2'), tableJson('M3')]),
      ],
    );
    await pumpFloor(tester);

    expect(find.byIcon(Icons.link_rounded), findsNWidgets(2));
    // The primary's own name, and again on the table merged into it.
    expect(find.text('M1'), findsNWidgets(2));
    expect(find.text('M2'), findsOneWidget);
  });

  testWidgets('with nothing stored and no server, offers a retry', (tester) async {
    when(floor.zones).thenThrow(
      const ApiFailure(code: 'NETWORK_UNREACHABLE', message: 'no connection'),
    );
    await pumpFloor(tester);

    expect(find.text('ลองใหม่'), findsOneWidget);
    // Not retried behind the waiter's back.
    await tester.pump(const Duration(minutes: 5));
    verify(floor.zones).called(1);

    when(floor.zones).thenAnswer((_) async => _floor);
    await tester.tap(find.text('ลองใหม่'));
    await tester.pumpAndSettle();
    expect(find.text('A1'), findsOneWidget);
  });
}
