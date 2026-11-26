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
    expect(find.text('53'), findsNWidgets(2));
    expect(send, findsOneWidget);
    expect(tester.getTopLeft(product).dy, greaterThan(0));
    expect(
      tester.getTopLeft(find.text('53').last).dy,
      greaterThan(tester.getBottomLeft(product).dy),
    );
    expect(
      tester.getTopLeft(send).dy,
      greaterThan(tester.getBottomLeft(product).dy),
    );
    expect(tester.getBottomLeft(send).dy, lessThan(852));
  });
}
