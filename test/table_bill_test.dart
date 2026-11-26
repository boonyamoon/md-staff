import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_staff/core/network/api_failure.dart';
import 'package:md_staff/core/providers.dart';
import 'package:md_staff/core/theme/app_theme.dart';
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
}
