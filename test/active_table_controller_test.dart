import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_staff/core/network/api_failure.dart';
import 'package:md_staff/core/providers.dart';
import 'package:md_staff/data/dto/cart_line.dart';
import 'package:md_staff/data/dto/floor_dto.dart';
import 'package:md_staff/data/dto/menu_dto.dart';
import 'package:md_staff/data/dto/order_dto.dart';
import 'package:md_staff/data/repositories/floor_repository.dart';
import 'package:md_staff/features/bootstrap/session_controller.dart';
import 'package:md_staff/features/tables/active_table_controller.dart';
import 'package:mocktail/mocktail.dart';

class _MockFloorRepository extends Mock implements FloorRepository {}

/// A shift that is simply already running. The real controller reads the keystore and opens an
/// API client on build, neither of which exists in a unit test — and the only thing the table
/// controller asks of it is the phase.
class _ReadySession extends AppSessionController {
  @override
  AppSession build() => const AppSession(phase: AppPhase.ready);
}

const _table = 'f1';
const _lease = 'lease-1';
const _otherLease = 'lease-2';

TableDetail detail({ClaimSummary? claim, TableSessionDetail? session, TableOrder? order}) =>
    TableDetail(
      floorItemId: _table,
      label: 'A1',
      zoneId: 'z1',
      zoneName: 'Terrace',
      claim: claim,
      session: session,
      order: order,
    );

ClaimSummary mineClaim({String leaseToken = _lease}) => ClaimSummary(
      isMine: true,
      expiresAt: '2026-01-01T00:00:00Z',
      leaseToken: leaseToken,
      holder: const ClaimHolder(
        terminalId: 't1',
        terminalCode: 'S01',
        terminalName: 'Handset 1',
        staffId: 's1',
        staffName: 'Nok',
      ),
    );

const _theirs = ClaimSummary(
  isMine: false,
  expiresAt: '2026-01-01T00:00:00Z',
  holder: ClaimHolder(
    terminalId: 't2',
    terminalCode: 'S02',
    terminalName: 'Handset 2',
    staffId: 's2',
    staffName: 'Dao',
  ),
);

TableClaim freshClaim({String leaseToken = _lease, ClaimHolder? tookOverFrom}) => TableClaim(
      floorItemId: _table,
      leaseToken: leaseToken,
      expiresAt: '2026-01-01T00:00:00Z',
      // Long enough that the periodic renew never fires inside a test.
      renewAfterMs: 600000,
      tookOverFrom: tookOverFrom,
    );

PlacedRound round({bool replay = false}) => PlacedRound(
      orderId: 'o1',
      orderNumber: 'ST-ABCD1234',
      sessionId: 'sess-1',
      itemsAdded: 1,
      idempotentReplay: replay,
    );

CartLine cartLine({String lineId = 'l1'}) => CartLine(
      lineId: lineId,
      productId: 'p1',
      productName: 'Pad Thai',
      sku: const MenuSku(id: 'sku-1', skuName: 'Regular', defaultPrice: 100),
      quantity: 1,
    );

void main() {
  late _MockFloorRepository floor;
  late ProviderContainer container;

  setUpAll(() {
    registerFallbackValue(<Map<String, dynamic>>[]);
  });

  setUp(() {
    floor = _MockFloorRepository();
    when(floor.newIdempotencyKey).thenReturn('idem-1');
    container = ProviderContainer(
      overrides: [
        floorRepositoryProvider.overrideWithValue(floor),
        sessionProvider.overrideWith(_ReadySession.new),
      ],
    );
    addTearDown(container.dispose);
  });

  ActiveTableController controller() => container.read(activeTableProvider.notifier);
  ActiveTableState state() => container.read(activeTableProvider);

  group('open', () {
    test('claims a free table and holds the lease', () async {
      when(() => floor.table(_table)).thenAnswer((_) async => detail());
      when(() => floor.claim(_table)).thenAnswer((_) async => freshClaim());

      expect(await controller().open(_table), isTrue);
      expect(state().holdsClaim, isTrue);
      expect(state().claim!.leaseToken, _lease);
      verify(() => floor.claim(_table)).called(1);
    });

    test('reuses a claim the server still remembers instead of claiming again', () async {
      when(() => floor.table(_table))
          .thenAnswer((_) async => detail(claim: mineClaim(leaseToken: _otherLease)));

      expect(await controller().open(_table), isTrue);
      expect(state().claim!.leaseToken, _otherLease);
      verifyNever(() => floor.claim(any()));
    });

    test('refuses to open a table whose bill is open at the POS', () async {
      when(() => floor.table(_table)).thenAnswer(
        (_) async => detail(
          session: const TableSessionDetail(
            sessionId: 'sess-1',
            status: 'PENDING_PAYMENT',
            openedAt: '2026-01-01T00:00:00Z',
          ),
        ),
      );

      expect(await controller().open(_table), isFalse);
      expect(state().exitReason, TableExitReason.pendingPayment);
      verifyNever(() => floor.claim(any()));
    });

    test('does not try to claim a table already shown as another handset\'s', () async {
      when(() => floor.table(_table)).thenAnswer((_) async => detail(claim: _theirs));

      expect(await controller().open(_table), isFalse);
      expect(state().failure!.code, 'TABLE_CLAIM_HELD');
      expect(state().failure!.holder!.staffName, 'Dao');
      expect(state().holdsClaim, isFalse);
      // A refused claim would count against the manager-PIN rate limit.
      verifyNever(() => floor.claim(any()));
    });

    test('surfaces the holder when another handset wins the claim', () async {
      when(() => floor.table(_table)).thenAnswer((_) async => detail());
      when(() => floor.claim(_table)).thenThrow(
        const ApiFailure(
          code: 'TABLE_CLAIM_HELD',
          message: 'Dao is taking orders at A1',
          statusCode: 409,
          data: {
            'holder': {'staff_name': 'Dao', 'terminal_name': 'Handset 2', 'terminal_code': 'S02'},
          },
        ),
      );

      expect(await controller().open(_table), isFalse);
      expect(state().holdsClaim, isFalse);
      expect(state().failure!.holder!.staffName, 'Dao');
    });

    test('carries the session guest count onto the cart screen', () async {
      when(() => floor.table(_table)).thenAnswer(
        (_) async => detail(
          claim: mineClaim(),
          session: const TableSessionDetail(
            sessionId: 'sess-1',
            status: 'OPEN',
            openedAt: '2026-01-01T00:00:00Z',
            guestCount: 4,
          ),
        ),
      );

      await controller().open(_table);
      expect(state().guestCount, 4);
    });
  });

  group('takeOver', () {
    test('a manager PIN hands the table over and names the previous holder', () async {
      when(() => floor.claim(_table, managerPin: '4321')).thenAnswer(
        (_) async => freshClaim(
          tookOverFrom: const ClaimHolder(
            terminalId: 't2',
            terminalCode: 'S02',
            terminalName: 'Handset 2',
            staffId: 's2',
            staffName: 'Dao',
          ),
        ),
      );
      when(() => floor.table(_table)).thenAnswer((_) async => detail(claim: mineClaim()));

      final claim = await controller().takeOver(_table, '4321');
      expect(claim!.tookOverFrom!.staffName, 'Dao');
      expect(state().holdsClaim, isTrue);
    });

    test('a wrong PIN leaves the table alone', () async {
      when(() => floor.claim(_table, managerPin: '1111')).thenThrow(
        const ApiFailure(code: 'INVALID_MANAGER_PIN', message: 'Wrong PIN', statusCode: 401),
      );

      expect(await controller().takeOver(_table, '1111'), isNull);
      expect(state().holdsClaim, isFalse);
      expect(state().failure!.code, 'INVALID_MANAGER_PIN');
    });
  });

  group('cart', () {
    setUp(() {
      when(() => floor.table(_table)).thenAnswer((_) async => detail());
      when(() => floor.claim(_table)).thenAnswer((_) async => freshClaim());
    });

    test('merges an identical line instead of adding a second row', () async {
      await controller().open(_table);
      controller()
        ..addLine(cartLine(lineId: 'a'))
        ..addLine(cartLine(lineId: 'b'));

      expect(state().cart, hasLength(1));
      expect(state().cart.single.quantity, 2);
      expect(state().cartItemCount, 2);
    });

    test('stepping a line to zero removes it', () async {
      await controller().open(_table);
      controller().addLine(cartLine());
      controller().setQuantity(state().cart.single.lineId, 0);

      expect(state().cart, isEmpty);
    });

    test('guest count is clamped to something a table could seat', () async {
      await controller().open(_table);
      controller().setGuestCount(0);
      expect(state().guestCount, 1);
      controller().setGuestCount(500);
      expect(state().guestCount, 99);
    });
  });

  group('sendToKitchen', () {
    setUp(() {
      when(() => floor.table(_table)).thenAnswer((_) async => detail());
      when(() => floor.claim(_table)).thenAnswer((_) async => freshClaim());
    });

    Future<void> openWithOneLine() async {
      await controller().open(_table);
      controller().addLine(cartLine());
    }

    test('sends the cart under the claim lease and clears it on success', () async {
      when(() => floor.placeOrder(
            floorItemId: any(named: 'floorItemId'),
            leaseToken: any(named: 'leaseToken'),
            idempotencyKey: any(named: 'idempotencyKey'),
            items: any(named: 'items'),
            guestCount: any(named: 'guestCount'),
            sessionId: any(named: 'sessionId'),
          )).thenAnswer((_) async => round());

      await openWithOneLine();
      final sent = await controller().sendToKitchen();

      expect(sent, isNotNull);
      expect(state().cart, isEmpty);
      final call = verify(() => floor.placeOrder(
            floorItemId: captureAny(named: 'floorItemId'),
            leaseToken: captureAny(named: 'leaseToken'),
            idempotencyKey: captureAny(named: 'idempotencyKey'),
            items: captureAny(named: 'items'),
            guestCount: captureAny(named: 'guestCount'),
            sessionId: any(named: 'sessionId'),
          ))
        ..called(1);
      expect(call.captured[0], _table);
      expect(call.captured[1], _lease);
    });

    test('a retry after a failure reuses the same idempotency key', () async {
      var attempt = 0;
      when(() => floor.placeOrder(
            floorItemId: any(named: 'floorItemId'),
            leaseToken: any(named: 'leaseToken'),
            idempotencyKey: any(named: 'idempotencyKey'),
            items: any(named: 'items'),
            guestCount: any(named: 'guestCount'),
            sessionId: any(named: 'sessionId'),
          )).thenAnswer((_) async {
        attempt += 1;
        if (attempt == 1) {
          throw const ApiFailure(code: 'NETWORK_UNREACHABLE', message: 'no connection');
        }
        return round(replay: true);
      });

      await openWithOneLine();
      expect(await controller().sendToKitchen(), isNull);
      // The cart survives a failed send, so the waiter can simply press send again.
      expect(state().cart, hasLength(1));

      expect(await controller().sendToKitchen(), isNotNull);
      final call = verify(() => floor.placeOrder(
            floorItemId: any(named: 'floorItemId'),
            leaseToken: any(named: 'leaseToken'),
            idempotencyKey: captureAny(named: 'idempotencyKey'),
            items: any(named: 'items'),
            guestCount: any(named: 'guestCount'),
            sessionId: any(named: 'sessionId'),
          ))
        ..called(2);
      expect(call.captured[0], call.captured[1]);
    });

    test('a lost claim ends the screen and keeps the cart unsent', () async {
      when(() => floor.placeOrder(
            floorItemId: any(named: 'floorItemId'),
            leaseToken: any(named: 'leaseToken'),
            idempotencyKey: any(named: 'idempotencyKey'),
            items: any(named: 'items'),
            guestCount: any(named: 'guestCount'),
            sessionId: any(named: 'sessionId'),
          )).thenThrow(
        const ApiFailure(code: 'TABLE_CLAIM_LOST', message: 'Dao has this table now', statusCode: 409),
      );

      await openWithOneLine();
      expect(await controller().sendToKitchen(), isNull);
      expect(state().exitReason, TableExitReason.claimLost);
      expect(state().holdsClaim, isFalse);
      expect(state().cart, hasLength(1));
    });

    test('names the party the round is for, so it cannot land on a new bill', () async {
      when(() => floor.table(_table)).thenAnswer(
        (_) async => detail(
          claim: mineClaim(),
          session: const TableSessionDetail(
            sessionId: 'sess-1',
            status: 'OPEN',
            openedAt: '2026-01-01T00:00:00Z',
          ),
        ),
      );
      when(() => floor.placeOrder(
            floorItemId: any(named: 'floorItemId'),
            leaseToken: any(named: 'leaseToken'),
            idempotencyKey: any(named: 'idempotencyKey'),
            items: any(named: 'items'),
            guestCount: any(named: 'guestCount'),
            sessionId: any(named: 'sessionId'),
          )).thenAnswer((_) async => round());

      await openWithOneLine();
      await controller().sendToKitchen();

      final named = verify(() => floor.placeOrder(
            floorItemId: any(named: 'floorItemId'),
            leaseToken: any(named: 'leaseToken'),
            idempotencyKey: any(named: 'idempotencyKey'),
            items: any(named: 'items'),
            guestCount: any(named: 'guestCount'),
            sessionId: captureAny(named: 'sessionId'),
          )).captured.single;
      expect(named, 'sess-1');
    });

    for (final code in [
      'TABLE_SESSION_CHANGED',
      'SESSION_CLOSED',
      'ORDER_NOT_EDITABLE',
      'ORDER_NOT_FOUND',
    ]) {
      test('$code ends the screen: there is nobody to send to', () async {
        when(() => floor.placeOrder(
              floorItemId: any(named: 'floorItemId'),
              leaseToken: any(named: 'leaseToken'),
              idempotencyKey: any(named: 'idempotencyKey'),
              items: any(named: 'items'),
              guestCount: any(named: 'guestCount'),
              sessionId: any(named: 'sessionId'),
            )).thenThrow(ApiFailure(code: code, message: 'gone', statusCode: 409));

        await openWithOneLine();

        expect(await controller().sendToKitchen(), isNull);
        expect(state().exitReason, TableExitReason.tableChanged);
      });
    }

    test('sends nothing without a claim', () async {
      expect(await controller().sendToKitchen(), isNull);
      verifyNever(() => floor.placeOrder(
            floorItemId: any(named: 'floorItemId'),
            leaseToken: any(named: 'leaseToken'),
            idempotencyKey: any(named: 'idempotencyKey'),
            items: any(named: 'items'),
            guestCount: any(named: 'guestCount'),
            sessionId: any(named: 'sessionId'),
          ));
    });

    test('sends nothing when the cart is empty', () async {
      await controller().open(_table);
      expect(await controller().sendToKitchen(), isNull);
      verifyNever(() => floor.placeOrder(
            floorItemId: any(named: 'floorItemId'),
            leaseToken: any(named: 'leaseToken'),
            idempotencyKey: any(named: 'idempotencyKey'),
            items: any(named: 'items'),
            guestCount: any(named: 'guestCount'),
            sessionId: any(named: 'sessionId'),
          ));
    });
  });

  group('the key a round is sent under', () {
    const other = 'f2';
    late List<String> keys;
    late List<Object> answers;
    String? seated;

    setUp(() {
      keys = [];
      answers = [];
      seated = null;
      for (final table in [_table, other]) {
        when(() => floor.table(table)).thenAnswer(
          (_) async => detail(
            session: seated == null
                ? null
                : TableSessionDetail(
                    sessionId: seated!,
                    status: 'OPEN',
                    openedAt: '2026-01-01T00:00:00Z',
                  ),
          ),
        );
        when(() => floor.claim(table)).thenAnswer((_) async => freshClaim());
        when(() => floor.releaseClaim(table, _lease)).thenAnswer((_) async {});
      }
      when(() => floor.placeOrder(
            floorItemId: any(named: 'floorItemId'),
            leaseToken: any(named: 'leaseToken'),
            idempotencyKey: any(named: 'idempotencyKey'),
            items: any(named: 'items'),
            guestCount: any(named: 'guestCount'),
            sessionId: any(named: 'sessionId'),
          )).thenAnswer((call) async {
        keys.add(call.namedArguments[#idempotencyKey] as String);
        // Whatever the test queued; otherwise the answer is lost on the way back.
        final answer = answers.isEmpty
            ? const ApiFailure(code: 'NETWORK_UNREACHABLE', message: 'no connection')
            : answers.removeAt(0);
        if (answer is ApiFailure) throw answer;
        return answer as PlacedRound;
      });
    });

    /// Takes [table], sends one dish there and leaves again.
    Future<void> sendAt(String table) async {
      await controller().open(table);
      controller().addLine(cartLine());
      await controller().sendToKitchen();
      await controller().close();
    }

    test('is not carried to another table', () async {
      await sendAt(_table);
      await sendAt(other);

      expect(keys[1], isNot(keys[0]));
    });

    test('is used again on the same table, so the dishes cannot be cooked twice', () async {
      await sendAt(_table);
      await sendAt(other);
      await sendAt(_table);

      expect(keys[2], keys[0]);
    });

    test('made at a free table, still stands once that attempt has opened it', () async {
      await sendAt(_table);
      seated = 'sess-1';
      await sendAt(_table);

      expect(keys[1], keys[0]);
    });

    test('is not spent on the next party to sit at the table', () async {
      seated = 'sess-1';
      await sendAt(_table);
      seated = 'sess-2';
      await sendAt(_table);

      expect(keys[1], isNot(keys[0]));
    });

    test('is replaced once the server says an earlier round already arrived under it', () async {
      answers = [
        const ApiFailure(code: 'NETWORK_UNREACHABLE', message: 'no connection'),
        const ApiFailure(code: 'IDEMPOTENCY_KEY_REUSED', message: 'used', statusCode: 409),
        round(),
      ];
      await controller().open(_table);
      controller().addLine(cartLine());
      await controller().sendToKitchen();
      // A dish added before trying again: no longer the round the server may hold.
      controller().addLine(cartLine(lineId: 'l2'));
      await controller().sendToKitchen();
      expect(state().cart, isNotEmpty);
      expect(await controller().sendToKitchen(), isNotNull);

      expect(keys[1], keys[0]);
      expect(keys[2], isNot(keys[1]));
    });
  });

  group('close', () {
    test('gives the claim back and forgets the table', () async {
      when(() => floor.table(_table)).thenAnswer((_) async => detail());
      when(() => floor.claim(_table)).thenAnswer((_) async => freshClaim());
      when(() => floor.releaseClaim(_table, _lease)).thenAnswer((_) async {});

      await controller().open(_table);
      await controller().close();

      verify(() => floor.releaseClaim(_table, _lease)).called(1);
      expect(state().isOpen, isFalse);
      expect(state().holdsClaim, isFalse);
    });

    test('opening again waits for a release still on its way', () async {
      when(() => floor.table(_table)).thenAnswer((_) async => detail());
      when(() => floor.claim(_table)).thenAnswer((_) async => freshClaim());
      final released = Completer<void>();
      when(() => floor.releaseClaim(_table, _lease)).thenAnswer((_) => released.future);

      await controller().open(_table);
      final closing = controller().close();
      clearInteractions(floor);
      final reopening = controller().open(_table);
      await pumpEventQueue();
      // Reading the table now could hand back the lease that is about to be dropped.
      verifyNever(() => floor.table(_table));

      released.complete();
      await Future.wait([closing, reopening]);
      verify(() => floor.table(_table)).called(1);
      expect(state().holdsClaim, isTrue);
    });

    test('a failed release is not worth bothering the waiter about', () async {
      when(() => floor.table(_table)).thenAnswer((_) async => detail());
      when(() => floor.claim(_table)).thenAnswer((_) async => freshClaim());
      when(() => floor.releaseClaim(_table, _lease))
          .thenThrow(const ApiFailure(code: 'NETWORK_UNREACHABLE', message: 'no connection'));

      await controller().open(_table);
      await expectLater(controller().close(), completes);
      expect(state().isOpen, isFalse);
    });
  });
}
