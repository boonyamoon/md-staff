import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_staff/core/storage/credential_store.dart';
import 'package:md_staff/core/theme/app_theme.dart';
import 'package:md_staff/data/dto/setup_dto.dart';

void main() {
  test('uses the branch colour, and #FF471A when there is none or it is not a colour', () {
    expect(themeColorFrom('#d81b60'), const Color(0xFFD81B60));
    expect(themeColorFrom(null), const Color(0xFFFF471A));
    expect(themeColorFrom(''), const Color(0xFFFF471A));
    expect(themeColorFrom('pink'), const Color(0xFFFF471A));
    expect(themeColorFrom('#fff'), const Color(0xFFFF471A));
    expect(buildAppTheme().colorScheme.primary, const Color(0xFFFF471A));
  });

  test('text on a pale branch colour is dark, on a deep one white', () {
    expect(buildAppTheme(const Color(0xFFFFEB3B)).colorScheme.onPrimary, MeedColors.ink);
    expect(buildAppTheme(const Color(0xFFD81B60)).colorScheme.onPrimary, Colors.white);
  });

  test('reads theme_color from the access snapshot', () {
    final access = StaffAppAccess.fromSnapshot({
      'user_branch_assignments': [
        {'branch_id': 'b1', 'is_active': true},
        {'branch_id': 'b2', 'is_active': true},
      ],
      'branches': [
        {'id': 'b1', 'branch_name': 'A', 'theme_color': '#d81b60'},
        {'id': 'b2', 'branch_name': 'B', 'theme_color': null},
      ],
    });

    expect(access.branches.map((b) => b.themeColor), ['#d81b60', null]);
  });

  test('keeps the colour across a restart, and drops it for a branch without one', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});

    StaffSession session(String? color) => StaffSession(
          accessToken: 'a',
          accessTokenExpiresAt: DateTime(2030),
          refreshToken: 'r',
          terminalId: 't',
          terminalCode: 'S01',
          terminalName: 'Handset',
          businessId: 'biz',
          branchId: 'b1',
          staffId: 's',
          staffName: 'Dao',
          themeColor: color,
        );

    await CredentialStore().save(session('#d81b60'));
    final restarted = CredentialStore();
    expect((await restarted.load())?.themeColor, '#d81b60');

    // A token refresh must not lose it.
    await restarted.saveRotatedTokens(
      accessToken: 'a2',
      accessTokenExpiresAt: DateTime(2031),
      refreshToken: 'r2',
    );
    expect((await CredentialStore().load())?.themeColor, '#d81b60');

    await CredentialStore().save(session(null));
    expect((await CredentialStore().load())?.themeColor, isNull);
  });
}
