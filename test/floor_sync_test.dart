import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_staff/core/network/api_failure.dart';
import 'package:md_staff/core/providers.dart';
import 'package:md_staff/data/dto/floor_dto.dart';
import 'package:md_staff/data/local/floor_store.dart';
import 'package:md_staff/data/repositories/session_repository.dart';
import 'package:md_staff/features/bootstrap/session_controller.dart';
import 'package:md_staff/features/zones/zones_controller.dart';
import 'package:mocktail/mocktail.dart';

import 'support/fakes.dart';

class _MockSessionRepository extends Mock implements SessionRepository {}

List<FloorZone> _floor(String table, {bool? heldByMe}) => [
      FloorZone.fromJson({
        'zone_id': 'z1',
        'zone_name': 'Terrace',
        'tables': [tableJson(table, foodStatus: 'WAITING', heldByMe: heldByMe)],
      }),
    ];

const _offline = ApiFailure(code: 'NETWORK_UNREACHABLE', message: 'no connection');

void main() {
  late MockFloorRepository repository;
  late MemoryLocalCache cache;
  late DateTime now;
  late ProviderContainer container;

  setUp(() {
    repository = MockFloorRepository();
    cache = MemoryLocalCache();
    now = DateTime(2026, 1, 1, 12);
    final sessions = _MockSessionRepository();
    when(sessions.logout).thenAnswer((_) async {});
    container = ProviderContainer.test(
      overrides: [
        floorRepositoryProvider.overrideWithValue(repository),
        sessionRepositoryProvider.overrideWithValue(sessions),
        localCacheProvider.overrideWithValue(cache),
        clockProvider.overrideWithValue(() => now),
        sessionProvider.overrideWith(SignedInSession.new),
      ],
    );
  });

  /// Opens the floor and lets the launch-time refresh finish.
  Future<ZonesController> open() async {
    container.listen(zonesProvider, (_, _) {});
    await container.read(zonesProvider.future);
    await pumpEventQueue();
    return container.read(zonesProvider.notifier);
  }

  FloorState state() => container.read(zonesProvider).value!;

  test('first sign-in fetches once and keeps a copy', () async {
    when(repository.zones).thenAnswer((_) async => _floor('A1'));

    await open();

    verify(repository.zones).called(1);
    expect(state().table('A1'), isNotNull);
    expect((await FloorStore(cache).load(testBranch))!.zones.single.tables.single.label, 'A1');
  });

  test('a launch shows the stored floor first, then asks the server once', () async {
    await FloorStore(cache).save(testBranch, _floor('OLD'), now);
    final answer = Completer<List<FloorZone>>();
    when(repository.zones).thenAnswer((_) => answer.future);

    container.listen(zonesProvider, (_, _) {});
    await container.read(zonesProvider.future);
    expect(state().table('OLD'), isNotNull);
    await pumpEventQueue();
    expect(state().refreshing, isTrue);

    answer.complete(_floor('NEW'));
    await pumpEventQueue();
    expect(state().table('NEW'), isNotNull);
    expect(state().refreshing, isFalse);
    verify(repository.zones).called(1);
  });

  test('a failed refresh keeps the floor and records why', () async {
    await FloorStore(cache).save(testBranch, _floor('OLD'), now);
    when(repository.zones).thenThrow(_offline);

    await open();

    expect(state().table('OLD'), isNotNull);
    expect(state().failure!.isOffline, isTrue);
    expect(state().fetchedAt, now);
  });

  test('coming back refetches only once the floor is a minute old', () async {
    when(repository.zones).thenAnswer((_) async => _floor('A1'));
    final floor = await open();

    now = now.add(const Duration(seconds: 59));
    await floor.refreshIfStale();
    verify(repository.zones).called(1);

    now = now.add(const Duration(seconds: 1));
    await floor.refreshIfStale();
    verify(repository.zones).called(1);
  });

  test('refreshes asked for together share one request, but not one that predates a change',
      () async {
    when(repository.zones).thenAnswer((_) async => _floor('A1'));
    final floor = await open();
    clearInteractions(repository);

    final first = Completer<List<FloorZone>>();
    var calls = 0;
    when(repository.zones).thenAnswer((_) {
      calls += 1;
      return calls == 1 ? first.future : Future.value(_floor('AFTER'));
    });
    final pull = floor.refresh();
    final again = floor.refresh();
    final afterSend = floor.refreshAfterChange();
    expect(calls, 1);

    first.complete(_floor('BEFORE'));
    await Future.wait([pull, again, afterSend]);
    expect(calls, 2);
    expect(state().table('AFTER'), isNotNull);
  });

  test('giving a table back removes this handset\'s mark without asking the server', () async {
    when(repository.zones).thenAnswer((_) async => _floor('A1', heldByMe: true));
    final floor = await open();
    expect(state().table('A1')!.isHeldByMe, isTrue);

    await floor.tableReleased('A1');

    expect(state().table('A1')!.claim, isNull);
    verify(repository.zones).called(1);
  });

  test('after a takeover, giving the table back clears the previous holder\'s mark too', () async {
    when(repository.zones).thenAnswer((_) async => _floor('A1', heldByMe: false));
    final floor = await open();

    await floor.tableReleased('A1');

    expect(state().table('A1')!.claim, isNull);
  });

  test('never writes a claim or its lease to the device', () async {
    when(repository.zones).thenAnswer((_) async => _floor('A1', heldByMe: true));

    await open();

    expect('${cache.files['floor']!.entry.data}', isNot(contains('secret-lease')));
    expect((await FloorStore(cache).load(testBranch))!.zones.single.tables.single.claim, isNull);
  });

  test('signing out removes what was stored', () async {
    when(repository.zones).thenAnswer((_) async => _floor('A1'));
    await open();
    expect(cache.files, isNotEmpty);

    await container.read(sessionProvider.notifier).signOut();
    await pumpEventQueue();

    expect(cache.files, isEmpty);
    expect(state().zones, isEmpty);
  });
}
