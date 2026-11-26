import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_staff/core/network/api_failure.dart';
import 'package:md_staff/core/providers.dart';
import 'package:md_staff/core/theme/app_theme.dart';
import 'package:md_staff/data/local/menu_store.dart';
import 'package:md_staff/data/repositories/menu_repository.dart';
import 'package:md_staff/features/bootstrap/session_controller.dart';
import 'package:md_staff/features/menu/menu_catalog_controller.dart';
import 'package:md_staff/features/menu/menu_controller.dart';
import 'package:md_staff/features/menu/menu_screen.dart';
import 'package:mocktail/mocktail.dart';

import 'support/fakes.dart';

void main() {
  late MockMenuRepository repository;
  late MemoryLocalCache cache;
  late DateTime now;

  setUp(() {
    repository = MockMenuRepository();
    cache = MemoryLocalCache();
    now = DateTime(2026, 1, 1, 12);
    when(() => repository.snapshot(etag: any(named: 'etag')))
        .thenAnswer((_) async => MenuSnapshot(data: menuJson(), etag: 'W/"1"'));
    when(repository.unavailableProductIds).thenAnswer((_) async => {'p2'});
  });

  List<dynamic> overrides() => [
        menuRepositoryProvider.overrideWithValue(repository),
        localCacheProvider.overrideWithValue(cache),
        clockProvider.overrideWithValue(() => now),
        sessionProvider.overrideWith(SignedInSession.new),
      ];

  ProviderContainer container() => ProviderContainer.test(overrides: overrides().cast());

  Future<MenuCatalogController> open(ProviderContainer c) async {
    c.listen(menuCatalogProvider, (_, _) {});
    await pumpEventQueue();
    return c.read(menuCatalogProvider.notifier);
  }

  Future<void> store({required Duration age}) => MenuStore(cache).save(
        testBranch,
        StoredMenu(data: menuJson(), fetchedAt: now.subtract(age), etag: 'W/"1"'),
      );

  test('with no copy on the device, fetches and keeps one', () async {
    final c = container();
    await open(c);

    expect(c.read(menuCatalogProvider).catalog!.products, hasLength(3));
    expect((await MenuStore(cache).load(testBranch))!.etag, 'W/"1"');
    verify(() => repository.snapshot()).called(1);
  });

  test('a recent copy is used without asking the server', () async {
    await store(age: const Duration(hours: 5));
    final c = container();
    await open(c);

    expect(c.read(menuCatalogProvider).catalog!.products, hasLength(3));
    verifyNever(() => repository.snapshot(etag: any(named: 'etag')));
  });

  test('an old copy is checked with its ETag, and "unchanged" keeps it', () async {
    await store(age: const Duration(hours: 6));
    when(() => repository.snapshot(etag: 'W/"1"'))
        .thenAnswer((_) async => const MenuSnapshot(etag: 'W/"1"'));
    final c = container();
    await open(c);

    verify(() => repository.snapshot(etag: 'W/"1"')).called(1);
    expect(c.read(menuCatalogProvider).catalog!.products, hasLength(3));
    expect(c.read(menuCatalogProvider).fetchedAt, now);
    expect((await MenuStore(cache).load(testBranch))!.fetchedAt, now);
  });

  test('a failed refresh keeps the copy and records why', () async {
    await store(age: const Duration(days: 2));
    when(() => repository.snapshot(etag: any(named: 'etag')))
        .thenThrow(const ApiFailure(code: 'NETWORK_UNREACHABLE', message: 'no connection'));
    final c = container();
    await open(c);

    expect(c.read(menuCatalogProvider).catalog!.products, hasLength(3));
    expect(c.read(menuCatalogProvider).failure!.isOffline, isTrue);
  });

  test('sold-out dishes are checked at most every two minutes', () async {
    await store(age: const Duration(hours: 1));
    final c = container();
    final menu = await open(c);
    bool available(String id) =>
        c.read(menuCatalogProvider).catalog!.products.firstWhere((p) => p.id == id).isAvailable;

    await menu.refreshAvailabilityIfStale();
    expect(available('p2'), isFalse);
    expect(available('p1'), isTrue);

    now = now.add(const Duration(seconds: 119));
    await menu.refreshAvailabilityIfStale();
    verify(repository.unavailableProductIds).called(1);

    when(repository.unavailableProductIds).thenAnswer((_) async => <String>{});
    now = now.add(const Duration(seconds: 1));
    await menu.refreshAvailabilityIfStale();
    expect(available('p2'), isTrue);
  });

  test('a menu just fetched is not checked for sold-out dishes again', () async {
    final c = container();
    final menu = await open(c);

    await menu.refreshAvailabilityIfStale();

    verifyNever(repository.unavailableProductIds);
  });

  test('category, search and options come from the copy on the device', () async {
    final c = container();
    await open(c);
    c.listen(visibleProductsProvider, (_, _) {});
    c.listen(menuProvider, (_, _) {});
    List<String> shown() => [for (final p in c.read(visibleProductsProvider)) p.productName];

    expect(shown(), ['Pad Thai', 'Boat noodles', 'Thai tea']);
    c.read(menuProvider.notifier).selectCategory('c1');
    expect(shown(), ['Pad Thai', 'Boat noodles']);
    c.read(menuProvider.notifier).search('THAI');
    expect(shown(), ['Pad Thai']);
    c.read(menuProvider.notifier).selectCategory(null);
    expect(shown(), ['Pad Thai', 'Thai tea']);

    final detail = await c.read(productDetailProvider('p1').future);
    expect(detail.optionGroups.single.options.single.optionName, 'Hot');

    verify(() => repository.snapshot()).called(1);
    verifyNever(() => repository.productDetail(any()));
  });

  testWidgets('the menu screen polls nothing, however long it stays open', (tester) async {
    await store(age: const Duration(hours: 1));
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides().cast(),
        child: MaterialApp(theme: buildAppTheme(), home: const MenuScreen(floorItemId: 'f1')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pad Thai'), findsOneWidget);

    now = now.add(const Duration(minutes: 30));
    await tester.pump(const Duration(minutes: 30));

    // The one check on the way in; none since, and no timer left behind.
    verify(repository.unavailableProductIds).called(1);
    verifyNever(() => repository.snapshot(etag: any(named: 'etag')));
  });
}
