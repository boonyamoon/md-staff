import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_staff/core/network/api_failure.dart';
import 'package:md_staff/core/providers.dart';
import 'package:md_staff/core/theme/app_theme.dart';
import 'package:md_staff/core/widgets/option_lines.dart';
import 'package:md_staff/data/dto/order_dto.dart';
import 'package:md_staff/features/bootstrap/session_controller.dart';
import 'package:md_staff/features/tables/table_bill_screen.dart';
import 'package:mocktail/mocktail.dart';

import 'support/fakes.dart';

TableDetail _detail(List<String> dishes) => TableDetail(
      floorItemId: 'f1',
      label: 'A1',
      zoneId: 'z1',
      zoneName: 'Terrace',
      order: TableOrder(
        orderId: 'o1',
        orderNumber: 'ST-1',
        status: 'HELD',
        lines: [
          for (final dish in dishes)
            OrderLine(orderItemId: dish, skuId: 'sku', productName: dish, roundNumber: 1),
        ],
      ),
    );

void main() {
  late MockFloorRepository floor;

  setUp(() => floor = MockFloorRepository());

  /// A button that opens the bill, so it can be left and visited again.
  Future<void> pumpHost(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith(SignedInSession.new),
            floorRepositoryProvider.overrideWithValue(floor),
            localCacheProvider.overrideWithValue(MemoryLocalCache()),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TableBillScreen(floorItemId: 'f1'),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  Future<void> visit(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('asks the server on every visit, so other devices\' orders show', (tester) async {
    var dishes = ['Pad Thai'];
    when(() => floor.table('f1')).thenAnswer((_) async => _detail(dishes));
    await pumpHost(tester);

    await visit(tester);
    expect(find.text('Pad Thai'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    dishes = ['Pad Thai', 'Thai tea'];
    await visit(tester);
    expect(find.text('Thai tea'), findsOneWidget);
    verify(() => floor.table('f1')).called(2);
  });

  testWidgets('names each dish’s kitchen stage in the waiter’s language', (tester) async {
    when(() => floor.table('f1')).thenAnswer(
      (_) async => const TableDetail(
        floorItemId: 'f1',
        label: 'A1',
        zoneId: 'z1',
        zoneName: 'Terrace',
        order: TableOrder(
          orderId: 'o1',
          orderNumber: 'ST-1',
          status: 'HELD',
          lines: [
            OrderLine(orderItemId: '1', skuId: 's', productName: 'Pad Thai', kitchenStatus: 'SENT'),
            OrderLine(orderItemId: '2', skuId: 's', productName: 'Tea', kitchenStatus: 'PENDING'),
            OrderLine(orderItemId: '3', skuId: 's', productName: 'Rice', kitchenStatus: 'HELD_BACK'),
          ],
        ),
      ),
    );
    await pumpHost(tester);
    await visit(tester);

    expect(find.text('ส่งเข้าครัวแล้ว'), findsOneWidget);
    expect(find.text('รอส่งเข้าครัว'), findsOneWidget);
    // Unknown to this app, so shown as sent by the server.
    expect(find.text('HELD_BACK'), findsOneWidget);
  });

  testWidgets('shows the failure rather than an older bill, and can retry', (tester) async {
    var offline = false;
    when(() => floor.table('f1')).thenAnswer((_) async {
      if (offline) throw const ApiFailure(code: 'NETWORK_UNREACHABLE', message: 'no connection');
      return _detail(['Pad Thai']);
    });
    await pumpHost(tester);
    await visit(tester);

    offline = true;
    // Back from the background with no signal.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Pad Thai'), findsNothing);
    expect(find.text('ลองใหม่'), findsOneWidget);

    offline = false;
    await tester.tap(find.text('ลองใหม่'));
    await tester.pumpAndSettle();
    expect(find.text('Pad Thai'), findsOneWidget);
  });

  testWidgets('the pay-at-POS bar reaches the bottom edge, its text above the home indicator',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.reset);
    when(() => floor.table('f1')).thenAnswer((_) async => _detail(['Pad Thai']));
    await pumpHost(tester);
    await visit(tester);

    final footnote = find.text('ชำระเงินที่เครื่อง POS เท่านั้น');
    final bar = find.ancestor(of: footnote, matching: find.byType(Container)).first;
    expect(tester.getBottomLeft(bar).dy, 852);
    // The bar's own 12 and the indicator's 34 below the row that holds the text.
    final row = find.ancestor(of: footnote, matching: find.byType(Row)).first;
    expect(tester.getBottomLeft(row).dy, 852 - 34 - 12);
  });

  testWidgets('lists a dish’s options one to a line, in the order they came', (tester) async {
    when(() => floor.table('f1')).thenAnswer(
      (_) async => const TableDetail(
        floorItemId: 'f1',
        label: 'A1',
        zoneId: 'z1',
        zoneName: 'Terrace',
        order: TableOrder(
          orderId: 'o1',
          orderNumber: 'ST-1',
          status: 'HELD',
          lines: [
            OrderLine(
              orderItemId: '1',
              skuId: 's',
              productName: 'Basil pork',
              skuName: 'Plate',
              options: [
                OrderLineOption(optionId: 'a', optionName: 'Very spicy'),
                OrderLineOption(optionId: 'b', optionName: 'Fried egg', priceAdjustment: 10),
                OrderLineOption(optionId: 'c', optionName: 'Crispy pork', priceAdjustment: 40, quantity: 2),
                OrderLineOption(optionId: 'd', optionName: 'No rice', priceAdjustment: -5),
              ],
            ),
          ],
        ),
      ),
    );
    await pumpHost(tester);
    await visit(tester);

    final lines = [
      '• Very spicy',
      '• Fried egg  +10.00',
      'x2 • Crispy pork  +40.00',
      '• No rice  -5.00',
    ];
    final tops = [for (final line in lines) tester.getTopLeft(find.text(line)).dy];
    expect(tops, [...tops]..sort());
    expect(tops.toSet(), hasLength(4));
    expect(find.byType(OptionLines), findsOneWidget);
    expect(find.text('Plate'), findsOneWidget);
  });

  group('marking dishes served', () {
    /// The kitchen stage of each dish, by name; the server's side of the table.
    late Map<String, String> stages;
    late List<List<String>> sent;

    TableDetail table() => TableDetail(
          floorItemId: 'f1',
          label: 'A1',
          zoneId: 'z1',
          zoneName: 'Terrace',
          session: const TableSessionDetail(sessionId: 'session-1', status: 'OPEN', openedAt: ''),
          order: TableOrder(
            orderId: 'o1',
            orderNumber: 'ST-1',
            status: 'HELD',
            lines: [
              for (final entry in stages.entries)
                OrderLine(
                  orderItemId: entry.key,
                  skuId: 's',
                  productName: entry.key,
                  roundNumber: entry.key.startsWith('Later') ? 2 : 1,
                  kitchenStatus: entry.value,
                ),
            ],
          ),
        );

    Future<void> serverServes(Invocation invocation) async {
      final ids = invocation.namedArguments[#orderItemIds] as List<String>;
      sent.add(ids);
      for (final id in ids) {
        stages[id] = 'SERVED';
      }
    }

    void whenServing(Future<void> Function(Invocation) answer) => when(
          () => floor.markServed(
            'f1',
            sessionId: 'session-1',
            orderItemIds: any(named: 'orderItemIds'),
          ),
        ).thenAnswer(answer);

    setUp(() {
      stages = {'Rice': 'SENT', 'Soup': 'PREPARING', 'Tea': 'READY'};
      sent = [];
      when(() => floor.table('f1')).thenAnswer((_) async => table());
      when(floor.zones).thenAnswer((_) async => const []);
      whenServing(serverServes);
    });

    Finder rowOf(String dish) => find
        .ancestor(of: find.text(dish), matching: find.byWidgetPredicate((w) => '${w.runtimeType}' == '_LineRow'))
        .first;
    Finder serveButton([String? dish]) {
      final button = find.widgetWithText(OutlinedButton, 'เสิร์ฟ');
      return dish == null ? button : find.descendant(of: rowOf(dish), matching: button);
    }

    testWidgets('is offered for every dish the kitchen has, whatever its stage', (tester) async {
      stages.addAll({'Cake': 'PENDING', 'Water': 'SERVED'});
      await pumpHost(tester);
      await visit(tester);

      expect(serveButton(), findsNWidgets(3));
      for (final dish in ['Rice', 'Soup', 'Tea']) {
        expect(serveButton(dish), findsOneWidget, reason: dish);
      }
    });

    testWidgets('one dish is served at once, and the bill and floor are fetched again', (tester) async {
      await pumpHost(tester);
      await visit(tester);

      await tester.tap(serveButton('Soup'));
      await tester.pumpAndSettle();

      expect(sent, [
        ['Soup'],
      ]);
      expect(find.byType(AlertDialog), findsNothing);
      expect(serveButton('Soup'), findsNothing);
      expect(find.text('เสิร์ฟแล้ว'), findsOneWidget);
      verify(() => floor.table('f1')).called(2);
      verify(floor.zones).called(greaterThanOrEqualTo(1));
    });

    testWidgets('a dish being saved cannot be sent twice', (tester) async {
      final answer = Completer<void>();
      var calls = 0;
      whenServing((_) {
        calls++;
        return answer.future;
      });
      await pumpHost(tester);
      await visit(tester);

      await tester.tap(serveButton('Rice'));
      await tester.pump();
      await tester.tap(find.byType(CircularProgressIndicator), warnIfMissed: false);
      await tester.pump();

      expect(calls, 1);
      // Its round cannot be served as a whole meanwhile; another dish can.
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'เสิร์ฟทั้งหมด')).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(serveButton('Tea')).onPressed, isNotNull);

      answer.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a whole round is asked about first, and only that round is sent', (tester) async {
      // Tall enough for both rounds at once: the list builds only what is near the screen.
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      stages.addAll({'Cake': 'PENDING', 'Later noodles': 'SENT'});
      await pumpHost(tester);
      await visit(tester);
      // Newest round first, so the first round's button is the second one.
      final serveFirstRound = find.widgetWithText(TextButton, 'เสิร์ฟทั้งหมด').last;

      await tester.tap(serveFirstRound);
      await tester.pumpAndSettle();
      expect(find.text('เสิร์ฟทั้งหมดของรอบที่ 1?'), findsOneWidget);
      expect(find.textContaining('3 รายการ'), findsOneWidget);
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(sent, isEmpty);

      await tester.tap(serveFirstRound);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'เสิร์ฟทั้งหมด'));
      await tester.pumpAndSettle();

      expect(sent, [
        ['Rice', 'Soup', 'Tea'],
      ]);
      // Only the later round still has something to serve.
      expect(find.widgetWithText(TextButton, 'เสิร์ฟทั้งหมด'), findsOneWidget);
    });

    testWidgets('a table that changed is explained and read again', (tester) async {
      whenServing((_) async {
        stages = {'Someone else’s dish': 'SENT'};
        throw const ApiFailure(code: 'TABLE_SESSION_CHANGED', message: 'changed');
      });
      await pumpHost(tester);
      await visit(tester);

      await tester.tap(serveButton('Rice'));
      await tester.pumpAndSettle();

      expect(find.text('โต๊ะนี้เปลี่ยนไปแล้ว กรุณาตรวจสอบอีกครั้ง'), findsOneWidget);
      expect(find.text('Someone else’s dish'), findsOneWidget);
    });

    testWidgets('with no signal it says so, and the bill stays as it was', (tester) async {
      whenServing((_) async => throw const ApiFailure(code: 'NETWORK_UNREACHABLE', message: 'offline'));
      await pumpHost(tester);
      await visit(tester);

      await tester.tap(serveButton('Rice'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Rice'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(serveButton('Rice')).onPressed, isNotNull);
      verify(() => floor.table('f1')).called(1);
    });

    testWidgets('a server without the feature says it does not support it', (tester) async {
      whenServing((_) async => throw const ApiFailure(code: 'NOT_FOUND', message: 'Route not found', statusCode: 404));
      await pumpHost(tester);
      await visit(tester);

      await tester.tap(serveButton('Rice'));
      await tester.pumpAndSettle();

      expect(find.text('เซิร์ฟเวอร์ยังไม่รองรับการใช้งานนี้ กรุณาติดต่อผู้ดูแลระบบ'), findsOneWidget);
    });

    testWidgets('fits the narrowest phone', (tester) async {
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpHost(tester);
      await visit(tester);

      expect(serveButton(), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });
  });
}
