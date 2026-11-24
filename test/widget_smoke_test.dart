import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_staff/core/providers.dart';
import 'package:md_staff/core/theme/app_theme.dart';
import 'package:md_staff/data/dto/floor_dto.dart';
import 'package:md_staff/data/repositories/floor_repository.dart';
import 'package:md_staff/features/bootstrap/session_controller.dart';
import 'package:md_staff/features/setup/setup_screen.dart';
import 'package:md_staff/features/tables/tables_screen.dart';
import 'package:mocktail/mocktail.dart';

class _MockFloorRepository extends Mock implements FloorRepository {}

class _FakeSession extends AppSessionController {
  _FakeSession(this._phase);

  final AppPhase _phase;

  @override
  AppSession build() => AppSession(phase: _phase);
}

/// The floor the tile tests render: one free table, one busy, one held by another handset.
final _zone = FloorZone.fromJson({
  'zone_id': 'z1',
  'zone_name': 'Terrace',
  'table_count': 3,
  'occupied_count': 2,
  'tables': [
    {'floor_item_id': 'f1', 'label': 'A1', 'capacity': 4},
    {
      'floor_item_id': 'f2',
      'label': 'A2',
      'session': {
        'session_id': 'sess-1',
        'status': 'OPEN',
        'opened_at': '2026-01-01T00:00:00Z',
        'item_count': 3,
        'total_amount': 1250,
      },
    },
    {
      'floor_item_id': 'f3',
      'label': 'A3',
      'claim': {
        'is_mine': false,
        'expires_at': '2026-01-01T00:00:00Z',
        'holder': {
          'terminal_id': 't2',
          'terminal_code': 'S02',
          'terminal_name': 'Handset 2',
          'staff_id': 's2',
          'staff_name': 'Dao',
        },
      },
    },
  ],
});

/// Wraps a screen in the app's own theme and a scope with the given overrides.
///
/// `overrides` is typed by inference rather than named: Riverpod 3's `Override` type is not part
/// of its public export list, so there is no name to write here.
ProviderScope _host(Widget child, List<dynamic> overrides) => ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(theme: buildAppTheme(), home: child),
    );

void main() {
  testWidgets('setup opens on the sign-in step and asks for a branch only after login', (tester) async {
    await tester.pumpWidget(
      _host(
        const SetupScreen(),
        [
          sessionProvider.overrideWith(() => _FakeSession(AppPhase.needsPairing)),
          deviceNameProvider.overrideWith((ref) async => 'Pixel 8'),
          appVersionProvider.overrideWith((ref) async => '1.0.0+1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ตั้งค่าเครื่อง'), findsOneWidget);
    expect(find.text('อีเมล'), findsOneWidget);
    expect(find.text('รหัสผ่าน'), findsOneWidget);
    // Sign-in stays disabled until both fields are filled, so a blank tap cannot fire a request.
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('the sign-in button enables once an email and password are typed', (tester) async {
    await tester.pumpWidget(
      _host(
        const SetupScreen(),
        [
          sessionProvider.overrideWith(() => _FakeSession(AppPhase.needsPairing)),
          deviceNameProvider.overrideWith((ref) async => 'Pixel 8'),
          appVersionProvider.overrideWith((ref) async => '1.0.0+1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'manager@example.com');
    await tester.enterText(find.byType(TextField).last, 'secret');
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('the table grid shows a free table, a busy one with its total, and who holds a locked one',
      (tester) async {
    final floor = _MockFloorRepository();
    when(floor.zones).thenAnswer((_) async => [_zone]);

    await tester.pumpWidget(
      _host(
        const TablesScreen(zoneId: 'z1'),
        [
          sessionProvider.overrideWith(() => _FakeSession(AppPhase.ready)),
          floorRepositoryProvider.overrideWithValue(floor),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Terrace'), findsOneWidget);
    expect(find.text('A1'), findsOneWidget);
    expect(find.text('ว่าง'), findsOneWidget);
    expect(find.text('มีลูกค้า'), findsOneWidget);
    // The busy table's running total, formatted with a thousands separator.
    expect(find.text('1,250'), findsOneWidget);
    // The locked table names its holder, so a waiter knows who to ask.
    expect(find.text('Dao'), findsOneWidget);
  });

  testWidgets('an empty zone says so instead of showing a blank grid', (tester) async {
    final floor = _MockFloorRepository();
    when(floor.zones).thenAnswer((_) async => [
          FloorZone.fromJson({'zone_id': 'z1', 'zone_name': 'Empty zone', 'tables': <Object>[]}),
        ]);

    await tester.pumpWidget(
      _host(
        const TablesScreen(zoneId: 'z1'),
        [
          sessionProvider.overrideWith(() => _FakeSession(AppPhase.ready)),
          floorRepositoryProvider.overrideWithValue(floor),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('โซนนี้ยังไม่มีโต๊ะ'), findsOneWidget);
  });

  testWidgets('the zone list survives a floor that fails to load', (tester) async {
    final floor = _MockFloorRepository();
    when(floor.zones).thenThrow(Exception('boom'));

    await tester.pumpWidget(
      _host(
        const TablesScreen(zoneId: 'z1'),
        [
          sessionProvider.overrideWith(() => _FakeSession(AppPhase.ready)),
          floorRepositoryProvider.overrideWithValue(floor),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // An error view with a retry, not a red screen.
    expect(find.text('ลองใหม่'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
