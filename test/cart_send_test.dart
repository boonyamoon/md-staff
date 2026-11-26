import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:md_staff/core/network/api_failure.dart';
import 'package:md_staff/core/providers.dart';
import 'package:md_staff/core/theme/app_theme.dart';
import 'package:md_staff/data/dto/cart_line.dart';
import 'package:md_staff/data/dto/floor_dto.dart';
import 'package:md_staff/data/dto/menu_dto.dart';
import 'package:md_staff/data/dto/order_dto.dart';
import 'package:md_staff/data/dto/session_dto.dart';
import 'package:md_staff/features/bootstrap/session_controller.dart';
import 'package:md_staff/features/cart/cart_screen.dart';
import 'package:md_staff/features/tables/active_table_controller.dart';
import 'package:md_staff/router/app_router.dart';
import 'package:mocktail/mocktail.dart';

import 'support/fakes.dart';

void main() {
  late MockFloorRepository floor;

  setUpAll(() => registerFallbackValue(<Map<String, dynamic>>[]));

  setUp(() {
    floor = MockFloorRepository();
    when(floor.zones).thenAnswer((_) async => <FloorZone>[]);
    when(() => floor.table('f1')).thenAnswer(
      (_) async => const TableDetail(floorItemId: 'f1', label: 'A1', zoneId: 'z', zoneName: 'Z'),
    );
    when(() => floor.claim('f1')).thenAnswer(
      (_) async => const TableClaim(
        floorItemId: 'f1',
        leaseToken: 'lease-1',
        expiresAt: '2026-01-01T00:00:00Z',
        renewAfterMs: 600000,
      ),
    );
    when(() => floor.releaseClaim('f1', 'lease-1')).thenAnswer((_) async {});
  });

  void answerSend(Future<PlacedRound> Function() answer) => when(
        () => floor.placeOrder(
          floorItemId: any(named: 'floorItemId'),
          leaseToken: any(named: 'leaseToken'),
          idempotencyKey: any(named: 'idempotencyKey'),
          items: any(named: 'items'),
          guestCount: any(named: 'guestCount'),
        ),
      ).thenAnswer((_) => answer());

  /// The cart of an open table, on the app's own paths, with a stand-in for the floor.
  Future<ProviderContainer> pumpCart(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(SignedInSession.new),
        floorRepositoryProvider.overrideWithValue(floor),
        localCacheProvider.overrideWithValue(MemoryLocalCache()),
        configProvider.overrideWith((ref) async => StaffAppConfig.fromJson(const {})),
      ],
    );
    addTearDown(container.dispose);
    final table = container.read(activeTableProvider.notifier);
    await table.open('f1');
    table.addLine(
      CartLine(
        lineId: 'l1',
        productId: 'p1',
        productName: 'Pad Thai',
        sku: const MenuSku(id: 'sku-1', skuName: '', defaultPrice: 60),
        quantity: 1,
      ),
    );
    final router = GoRouter(
      initialLocation: AppRoutes.cart('f1'),
      routes: [
        GoRoute(path: AppRoutes.zones, builder: (_, _) => const Scaffold(body: Text('FLOOR'))),
        GoRoute(
          path: '/table/:id',
          builder: (_, _) => const Scaffold(body: Text('MENU')),
          routes: [
            GoRoute(path: 'cart', builder: (_, _) => const CartScreen(floorItemId: 'f1')),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    clearInteractions(floor);
    return container;
  }

  testWidgets('sending goes straight to the floor and gives the table back', (tester) async {
    answerSend(
      () async => const PlacedRound(
        orderId: 'o1',
        orderNumber: 'ST-1',
        sessionId: 's1',
        itemsAdded: 1,
        idempotentReplay: false,
      ),
    );
    final container = await pumpCart(tester);

    await tester.tap(find.text('ส่งเข้าครัว'));
    await tester.pumpAndSettle();

    expect(find.text('FLOOR'), findsOneWidget);
    expect(find.text('MENU'), findsNothing);
    // The confirmation follows the waiter there.
    expect(find.byType(SnackBar), findsOneWidget);
    expect(container.read(activeTableProvider).isOpen, isFalse);
    // The floor is read after the claim has gone, and the table is not read again at all.
    verifyInOrder([() => floor.releaseClaim('f1', 'lease-1'), floor.zones]);
    verifyNever(() => floor.table(any()));
  });

  testWidgets('a send that fails stays on the cart, table still held', (tester) async {
    answerSend(
      () async => throw const ApiFailure(code: 'NETWORK_UNREACHABLE', message: 'no connection'),
    );
    final container = await pumpCart(tester);

    await tester.tap(find.text('ส่งเข้าครัว'));
    await tester.pumpAndSettle();

    expect(find.text('FLOOR'), findsNothing);
    expect(find.text('Pad Thai'), findsOneWidget);
    expect(container.read(activeTableProvider).holdsClaim, isTrue);
    verifyNever(() => floor.releaseClaim(any(), any()));
    // Stops the lease renewal the held table keeps running.
    await container.read(activeTableProvider.notifier).close();
  });
}
