import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_staff/data/dto/cart_line.dart';
import 'package:md_staff/data/dto/menu_dto.dart';
import 'package:md_staff/features/cart/cart_screen.dart';
import 'package:md_staff/features/tables/active_table_controller.dart';

class _CartWithOneItem extends ActiveTableController {
  @override
  ActiveTableState build() => ActiveTableState(
    guestCount: 2,
    cart: [
      CartLine(
        lineId: 'line-1',
        productId: 'product-1',
        productName: 'สินค้าทดสอบ',
        sku: const MenuSku(id: 'sku-1', skuName: '', defaultPrice: 53),
        quantity: 1,
      ),
    ],
  );
}

void main() {
  testWidgets('a nonempty cart keeps its contents above the send bar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [activeTableProvider.overrideWith(_CartWithOneItem.new)],
        child: const MaterialApp(home: CartScreen(floorItemId: 'table-1')),
      ),
    );
    await tester.pumpAndSettle();

    final product = find.text('สินค้าทดสอบ');
    final send = find.text('ส่งเข้าครัว');
    expect(find.text('จำนวนลูกค้า'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(product, findsOneWidget);
    expect(find.text('53.00'), findsNWidgets(2));
    expect(send, findsOneWidget);
    expect(tester.getTopLeft(product).dy, greaterThan(0));
    expect(
      tester.getTopLeft(find.text('53.00').last).dy,
      greaterThan(tester.getBottomLeft(product).dy),
    );
    expect(
      tester.getTopLeft(send).dy,
      greaterThan(tester.getBottomLeft(product).dy),
    );
    expect(tester.getBottomLeft(send).dy, lessThan(852));
  });

  testWidgets('the send bar reaches the bottom edge, its contents above the home indicator', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [activeTableProvider.overrideWith(_CartWithOneItem.new)],
        child: const MaterialApp(home: CartScreen(floorItemId: 'table-1')),
      ),
    );
    await tester.pumpAndSettle();

    final footnote = find.text('ชำระเงินที่เครื่อง POS เท่านั้น');
    final bar = find.ancestor(of: footnote, matching: find.byType(Container)).first;
    expect(tester.getBottomLeft(bar).dy, 852);
    // 34 for the indicator and the bar's own 12.
    expect(tester.getBottomLeft(footnote).dy, 852 - 34 - 12);
  });
}
