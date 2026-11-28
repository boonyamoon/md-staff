import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_staff/app.dart';
import 'package:md_staff/core/providers.dart';
import 'package:md_staff/core/storage/credential_store.dart';
import 'package:md_staff/data/dto/setup_dto.dart';
import 'package:md_staff/data/repositories/setup_repository.dart';
import 'package:mocktail/mocktail.dart';

import 'support/fakes.dart';

class _MockSetupRepository extends Mock implements SetupRepository {}

const _taken = 'เครื่องนี้ถูกผูกกับอุปกรณ์อื่นแล้ว';
const _allTaken = 'ไม่มีเครื่องว่าง ระบบจะใช้เครื่องที่ไม่ได้ใช้งานนานที่สุด และอุปกรณ์เดิมจะถูกออกจากระบบ';

const _freeTerminal = PairingTerminal(terminalId: 't1', terminalCode: 'S01', terminalName: 'Handset 1', isPaired: false);
const _takenTerminal = PairingTerminal(
  terminalId: 't2',
  terminalCode: 'S02',
  terminalName: 'Handset 2',
  isPaired: true,
  deviceName: 'Pixel 7',
);

void main() {
  late _MockSetupRepository setup;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
    setup = _MockSetupRepository();
    when(() => setup.staffLogin(email: any(named: 'email'), password: any(named: 'password')))
        .thenAnswer((_) async => 'staff-token');
    when(() => setup.access('staff-token')).thenAnswer(
      (_) async => const StaffAppAccess(
        branches: [BranchOption(id: testBranch, name: 'Main')],
        deniedByPermission: false,
      ),
    );
  });

  /// Signs in far enough to be looking at the branch's handset terminals.
  Future<void> openTerminalList(WidgetTester tester, List<PairingTerminal> terminals) async {
    when(() => setup.terminals(staffBearer: any(named: 'staffBearer'), branchId: any(named: 'branchId')))
        .thenAnswer((_) async => terminals);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          credentialStoreProvider.overrideWithValue(CredentialStore()),
          setupRepositoryProvider.overrideWithValue(setup),
          localCacheProvider.overrideWithValue(MemoryLocalCache()),
          deviceNameProvider.overrideWith((ref) async => 'Pixel 8'),
          appVersionProvider.overrideWith((ref) async => '1.0.0+1'),
        ],
        child: const MdStaffApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'waiter@example.com');
    await tester.enterText(find.byType(TextField).last, 'secret');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'ยืนยัน'));
    await tester.pumpAndSettle();
  }

  testWidgets('a free terminal says so, a taken one names the device on it', (tester) async {
    await openTerminalList(tester, const [_freeTerminal, _takenTerminal]);

    expect(find.text('ว่าง'), findsOneWidget);
    expect(find.text('$_taken • Pixel 7'), findsOneWidget);
    expect(find.text(_allTaken), findsNothing);
  });

  testWidgets('with every terminal taken, it warns that one will be taken over', (tester) async {
    await openTerminalList(tester, const [_takenTerminal]);

    expect(find.text(_allTaken), findsOneWidget);
    expect(find.text('ว่าง'), findsNothing);
    // Letting the server choose is still allowed.
    final finish = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'เข้าใช้งาน'));
    expect(finish.onPressed, isNotNull);
  });
}
