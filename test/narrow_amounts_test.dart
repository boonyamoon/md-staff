import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_staff/core/providers.dart';
import 'package:md_staff/core/theme/app_theme.dart';
import 'package:md_staff/data/dto/cart_line.dart';
import 'package:md_staff/data/dto/menu_dto.dart';
import 'package:md_staff/data/dto/order_dto.dart';
import 'package:md_staff/data/repositories/menu_repository.dart';
import 'package:md_staff/features/bootstrap/session_controller.dart';
import 'package:md_staff/features/cart/cart_screen.dart';
import 'package:md_staff/features/menu/menu_controller.dart';
import 'package:md_staff/features/menu/menu_screen.dart';
import 'package:md_staff/features/menu/product_options_sheet.dart';
import 'package:md_staff/features/tables/active_table_controller.dart';
import 'package:md_staff/features/tables/table_bill_screen.dart';
import 'package:mocktail/mocktail.dart';

import 'support/fakes.dart';

/// Amounts are the longest they are likely to get, on the narrowest phone, with the largest type
/// the app allows. Nothing may run off the screen or be cut short.
class _BigCart extends ActiveTableController {
  @override
  ActiveTableState build() => ActiveTableState(
        floorItemId: 'f1',
        cart: [
          CartLine(
            lineId: '1',
            productId: 'p',
            productName: 'Basil pork',
            sku: const MenuSku(id: 's', skuName: 'Plate', defaultPrice: 12345.5),
            quantity: 99,
          ),
        ],
      );
}

const _total = '1,222,204.50';

void main() {
  Future<void> show(WidgetTester tester, Widget home, List<dynamic> overrides) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides.cast(),
        child: MaterialApp(
          theme: buildAppTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectOnScreen(WidgetTester tester, Finder finder) {
    for (final element in finder.evaluate()) {
      final rect = tester.getRect(find.byElementPredicate((e) => e == element));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
    }
  }

  testWidgets('the cart', (tester) async {
    await show(tester, const CartScreen(floorItemId: 'f1'), [activeTableProvider.overrideWith(_BigCart.new)]);

    expect(tester.takeException(), isNull);
    expect(find.text(_total), findsNWidgets(2));
    expectOnScreen(tester, find.text(_total));
  });

  testWidgets('the menu’s tiles and its cart bar', (tester) async {
    final menu = MockMenuRepository();
    when(() => menu.snapshot(etag: any(named: 'etag'))).thenAnswer(
      (_) async => const MenuSnapshot(data: {
        'categories': <Object>[],
        'products': [
          {
            'id': 'p1',
            'product_name': 'Basil pork',
            'is_available': false,
            'skus': [
              {'id': 'a', 'sku_name': 'x', 'default_price': 123456.75, 'is_default': true},
              {'id': 'b', 'sku_name': 'y', 'default_price': 123456.75},
            ],
          },
        ],
      }),
    );
    when(menu.unavailableProductIds).thenAnswer((_) async => {'p1'});
    await show(tester, const MenuScreen(floorItemId: 'f1'), [
      sessionProvider.overrideWith(SignedInSession.new),
      menuRepositoryProvider.overrideWithValue(menu),
      localCacheProvider.overrideWithValue(MemoryLocalCache()),
      activeTableProvider.overrideWith(_BigCart.new),
    ]);

    expect(tester.takeException(), isNull);
    expectOnScreen(tester, find.text(_total));
    expectOnScreen(tester, find.textContaining('123,456.75'));
  });

  testWidgets('the bill', (tester) async {
    final floor = MockFloorRepository();
    when(() => floor.table('f1')).thenAnswer(
      (_) async => const TableDetail(
        floorItemId: 'f1',
        label: 'A1',
        zoneId: 'z',
        zoneName: 'Z',
        order: TableOrder(
          orderId: 'o',
          orderNumber: 'ST-1',
          status: 'HELD',
          subtotal: 1222204.5,
          discountAmount: 1222204.5,
          totalAmount: 1222204.5,
          lines: [
            OrderLine(orderItemId: '1', skuId: 's', productName: 'Basil pork', quantity: 99, lineTotal: 1222204.5),
          ],
        ),
      ),
    );
    await show(tester, const TableBillScreen(floorItemId: 'f1'), [
      sessionProvider.overrideWith(SignedInSession.new),
      floorRepositoryProvider.overrideWithValue(floor),
      localCacheProvider.overrideWithValue(MemoryLocalCache()),
    ]);

    expect(tester.takeException(), isNull);
    expectOnScreen(tester, find.textContaining(_total));
  });

  testWidgets('the add-to-cart button', (tester) async {
    const detail = ProductDetail(
      id: 'p1',
      productName: 'Basil pork',
      skus: [MenuSku(id: 'a', skuName: 'Plate', defaultPrice: 12345.5)],
    );
    await show(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showProductOptionsSheet(context, product: const MenuProduct(id: 'p1', productName: 'x')),
          child: const Text('open'),
        ),
      ),
      [productDetailProvider.overrideWith((ref, id) async => detail)],
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final button = tester.getRect(find.byType(FilledButton));
    final amount = tester.getRect(find.text('12,345.50'));
    expect(button.contains(amount.topLeft) && button.contains(amount.bottomRight - const Offset(1, 1)), isTrue);
  });
}
