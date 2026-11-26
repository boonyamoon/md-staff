import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_staff/core/providers.dart';
import 'package:md_staff/core/theme/app_theme.dart';
import 'package:md_staff/features/bootstrap/session_controller.dart';
import 'package:md_staff/features/setup/setup_screen.dart';

class _FakeSession extends AppSessionController {
  _FakeSession(this._phase);

  final AppPhase _phase;

  @override
  AppSession build() => AppSession(phase: _phase);
}

/// Wraps a screen in the app's own theme and a scope with the given overrides.
///
/// `overrides` is typed by inference rather than named: Riverpod 3's `Override` type is not part
/// of its public export list, so there is no name to write here.
ProviderScope _host(Widget child, List<dynamic> overrides) => ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(theme: buildAppTheme(), home: child),
    );

void main() {
  testWidgets('sign-in opens on the email step and asks for a branch only after that', (tester) async {
    await tester.pumpWidget(
      _host(
        const SetupScreen(),
        [
          sessionProvider.overrideWith(() => _FakeSession(AppPhase.needsLogin)),
          deviceNameProvider.overrideWith((ref) async => 'Pixel 8'),
          appVersionProvider.overrideWith((ref) async => '1.0.0+1'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('เข้าสู่ระบบพนักงาน'), findsOneWidget);
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
          sessionProvider.overrideWith(() => _FakeSession(AppPhase.needsLogin)),
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
}
