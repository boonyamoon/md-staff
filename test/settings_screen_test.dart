import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_staff/core/l10n/strings.dart';
import 'package:md_staff/core/providers.dart';
import 'package:md_staff/core/theme/app_theme.dart';
import 'package:md_staff/data/dto/session_dto.dart';
import 'package:md_staff/data/repositories/menu_repository.dart';
import 'package:md_staff/features/bootstrap/session_controller.dart';
import 'package:md_staff/features/settings/settings_screen.dart';
import 'package:mocktail/mocktail.dart';

import 'support/fakes.dart';

final _config = StaffAppConfig.fromJson({
  'branch': {
    'branch_id': testBranch,
    'branch_name': 'Sukhumvit',
    'business_name': 'A shop with a rather long registered name Co., Ltd.',
  },
  'ordering': {'kitchen_printing_enabled': false},
});

void main() {
  late MockMenuRepository menu;
  late ProviderContainer container;

  setUp(() {
    menu = MockMenuRepository();
    when(() => menu.snapshot(etag: any(named: 'etag')))
        .thenAnswer((_) async => const MenuSnapshot(data: {'categories': <Object>[], 'products': <Object>[]}));
  });

  Future<void> pumpScreen(WidgetTester tester, {Size screen = const Size(390, 844)}) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith(SignedInSession.new),
          configProvider.overrideWith((ref) async => _config),
          menuRepositoryProvider.overrideWithValue(menu),
          localCacheProvider.overrideWithValue(MemoryLocalCache()),
          appVersionProvider.overrideWith((ref) async => '1.0.0+1'),
        ],
        child: MaterialApp(theme: buildAppTheme(), home: const SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)));
  }

  double leftOf(WidgetTester tester, String text) => tester.getTopLeft(find.text(text)).dx;
  double rightOf(WidgetTester tester, String text) => tester.getTopRight(find.text(text)).dx;

  testWidgets('titles share one left edge and values one right edge, in every card', (tester) async {
    await pumpScreen(tester);

    final titles = ['พนักงาน', 'สาขา', 'เครื่อง', 'พิมพ์ใบออเดอร์ที่ POS', 'ข้อมูลเมนู', 'ไทย', 'English'];
    // 16 of page, 16 of row, 24 of icon and 12 of gap.
    for (final title in titles) {
      expect(leftOf(tester, title), closeTo(68, 0.5), reason: title);
    }

    for (final value in ['Nok', 'Sukhumvit', 'Handset 1', 'S01', 'สาขานี้ยังไม่ได้ตั้งเครื่องพิมพ์']) {
      expect(rightOf(tester, value), closeTo(390 - 16 - 16, 0.5), reason: value);
    }
  });

  testWidgets('a value starts level with its title', (tester) async {
    await pumpScreen(tester);

    expect(tester.getTopLeft(find.text('Sukhumvit')).dy, tester.getTopLeft(find.text('สาขา')).dy);
  });

  testWidgets('fits the narrowest phone, long names and all', (tester) async {
    await pumpScreen(tester, screen: const Size(320, 568));
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('the list runs to the bottom edge and ends clear of the home indicator', (tester) async {
    await pumpScreen(tester);

    expect(tester.getBottomLeft(find.byType(ListView)).dy, 844);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(find.textContaining('http')).dy, lessThanOrEqualTo(844 - 34));
  });

  testWidgets('tapping a language switches to it and moves the tick', (tester) async {
    await pumpScreen(tester);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(container.read(languageProvider), AppLanguage.en);
    expect(find.text('Account and device'), findsOneWidget);
    final tick = tester.getCenter(find.byIcon(Icons.check_rounded));
    expect(tick.dy, closeTo(tester.getCenter(find.text('English')).dy, 1));
  });
}
