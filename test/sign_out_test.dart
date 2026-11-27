import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_staff/app.dart';
import 'package:md_staff/core/network/api_client.dart';
import 'package:md_staff/core/network/api_failure.dart';
import 'package:md_staff/core/providers.dart';
import 'package:md_staff/core/storage/credential_store.dart';
import 'package:md_staff/core/theme/app_theme.dart';
import 'package:md_staff/data/dto/session_dto.dart';
import 'package:md_staff/data/dto/setup_dto.dart';
import 'package:md_staff/data/repositories/menu_repository.dart';
import 'package:md_staff/data/repositories/session_repository.dart';
import 'package:md_staff/data/repositories/setup_repository.dart';
import 'package:md_staff/features/settings/settings_screen.dart';
import 'package:md_staff/features/setup/setup_screen.dart';
import 'package:md_staff/features/zones/floor_screen.dart';
import 'package:mocktail/mocktail.dart';

import 'support/fakes.dart';

class _MockSetupRepository extends Mock implements SetupRepository {}

class _MockSessionRepository extends Mock implements SessionRepository {}

/// An API client whose "you were signed out" the test can raise itself.
class _RevocableApi extends ApiClient {
  _RevocableApi(CredentialStore credentials) : super(credentials: credentials);

  final events = <void Function(SessionEvent)>[];

  @override
  Stream<SessionEvent> get sessionEvents => Stream.multi((controller) => events.add(controller.add));
}

const _branchColor = Color(0xFF2255AA);

void main() {
  late CredentialStore credentials;
  late _RevocableApi api;
  late _MockSetupRepository setup;
  late _MockSessionRepository session;
  late MockFloorRepository floor;
  late MockMenuRepository menu;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
    credentials = CredentialStore();
    api = _RevocableApi(credentials);
    setup = _MockSetupRepository();
    session = _MockSessionRepository();
    floor = MockFloorRepository();
    menu = MockMenuRepository();

    when(() => setup.staffLogin(email: any(named: 'email'), password: any(named: 'password')))
        .thenAnswer((_) async => 'staff-token');
    when(() => setup.access('staff-token')).thenAnswer(
      (_) async => const StaffAppAccess(
        branches: [BranchOption(id: testBranch, name: 'Main', themeColor: '#2255AA')],
        deniedByPermission: false,
      ),
    );
    when(() => setup.terminals(staffBearer: any(named: 'staffBearer'), branchId: any(named: 'branchId')))
        .thenAnswer((_) async => const <PairingTerminal>[]);
    when(
      () => session.login(
        staffBearer: any(named: 'staffBearer'),
        branchId: any(named: 'branchId'),
        deviceName: any(named: 'deviceName'),
        appVersion: any(named: 'appVersion'),
        terminalId: any(named: 'terminalId'),
        themeColor: any(named: 'themeColor'),
      ),
    ).thenAnswer((_) async {
      await credentials.save(testStaffSession());
      return StaffAppSession.fromJson(const {});
    });
    when(session.config).thenThrow(const ApiFailure(code: 'NETWORK_UNREACHABLE', message: 'offline'));
    when(session.logout).thenAnswer((_) => credentials.clear());
    when(floor.zones).thenAnswer((_) async => const []);
    when(() => menu.snapshot(etag: any(named: 'etag')))
        .thenAnswer((_) async => const MenuSnapshot(data: {'categories': <Object>[], 'products': <Object>[]}));
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          credentialStoreProvider.overrideWithValue(credentials),
          apiClientProvider.overrideWithValue(api),
          setupRepositoryProvider.overrideWithValue(setup),
          sessionRepositoryProvider.overrideWithValue(session),
          floorRepositoryProvider.overrideWithValue(floor),
          menuRepositoryProvider.overrideWithValue(menu),
          localCacheProvider.overrideWithValue(MemoryLocalCache()),
          deviceNameProvider.overrideWith((ref) async => 'Pixel 8'),
          appVersionProvider.overrideWith((ref) async => '1.0.0+1'),
        ],
        child: const MdStaffApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> signIn(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, 'waiter@example.com');
    await tester.enterText(find.byType(TextField).last, 'secret');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'ยืนยัน'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'เข้าใช้งาน'));
    await tester.pumpAndSettle();
    expect(find.byType(FloorScreen), findsOneWidget);
  }

  Future<void> signOutFromSettings(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('ออกจากระบบ'), 200);
    await tester.tap(find.text('ออกจากระบบ'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'ออกจากระบบ'));
    await tester.pumpAndSettle();
  }

  void expectEmptySignIn(WidgetTester tester) {
    expect(find.byType(SetupScreen), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'), findsOneWidget);
    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields.map((f) => f.controller!.text), ['', '']);
    // Not the colour of the branch just left.
    final theme = Theme.of(tester.element(find.byType(SetupScreen)));
    expect(theme.colorScheme.primary, MeedColors.defaultPrimary);
  }

  testWidgets('signing out lands on an empty sign-in form, ready to be used again', (tester) async {
    await pumpApp(tester);
    await signIn(tester);

    await signOutFromSettings(tester);
    expectEmptySignIn(tester);

    await signIn(tester);
  });

  testWidgets('signing out works with no signal', (tester) async {
    when(session.logout).thenAnswer((_) async {
      await credentials.clear();
      throw const ApiFailure(code: 'NETWORK_UNREACHABLE', message: 'offline');
    });
    await pumpApp(tester);
    await signIn(tester);

    await signOutFromSettings(tester);

    expectEmptySignIn(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('being signed out by the server lands there too, and says why', (tester) async {
    await pumpApp(tester);
    await signIn(tester);

    for (final emit in api.events) {
      emit(SessionEvent.signedOut);
    }
    await tester.pumpAndSettle();

    expectEmptySignIn(tester);
    expect(find.text('เครื่องนี้ถูกออกจากระบบแล้ว กรุณาเข้าสู่ระบบใหม่'), findsOneWidget);
  });

  testWidgets('the form does show the chosen branch’s colour while signing in', (tester) async {
    await pumpApp(tester);
    await tester.enterText(find.byType(TextField).first, 'waiter@example.com');
    await tester.enterText(find.byType(TextField).last, 'secret');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'));
    await tester.pumpAndSettle();

    final theme = Theme.of(tester.element(find.byType(SetupScreen)));
    expect(theme.colorScheme.primary, _branchColor);
  });
}
