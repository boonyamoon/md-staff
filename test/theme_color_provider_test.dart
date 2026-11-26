import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_staff/core/providers.dart';
import 'package:md_staff/core/storage/credential_store.dart';
import 'package:md_staff/data/dto/session_dto.dart';
import 'package:md_staff/data/repositories/session_repository.dart';
import 'package:md_staff/features/bootstrap/session_controller.dart';
import 'package:md_staff/features/bootstrap/theme_color_provider.dart';
import 'package:mocktail/mocktail.dart';

class _MockSessionRepository extends Mock implements SessionRepository {}

class _SignedIn extends AppSessionController {
  _SignedIn(this._session);

  final StaffSession _session;

  @override
  AppSession build() => AppSession(phase: AppPhase.ready, session: _session);
}

const _stored = Color(0xFF112233);

StaffSession _session() => StaffSession(
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
      themeColor: '#112233',
    );

StaffAppConfig _config(Map<String, dynamic> branch) => StaffAppConfig.fromJson({
      'branch': {'branch_id': 'b1', ...branch},
    });

void main() {
  late CredentialStore store;
  late _MockSessionRepository repository;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
    store = CredentialStore();
    await store.save(_session());
    repository = _MockSessionRepository();
  });

  ProviderContainer container() {
    final container = ProviderContainer.test(
      overrides: [
        credentialStoreProvider.overrideWithValue(store),
        sessionRepositoryProvider.overrideWithValue(repository),
        sessionProvider.overrideWith(() => _SignedIn(_session())),
      ],
    );
    container.listen(themeColorProvider, (_, _) {});
    return container;
  }

  Future<String?> colorAfterRestart() async => (await CredentialStore().load())?.themeColor;

  test('wears the remembered colour until config answers, then the one config reports', () async {
    final answer = Completer<StaffAppConfig>();
    when(repository.config).thenAnswer((_) => answer.future);
    final c = container();

    expect(c.read(themeColorProvider), _stored);

    answer.complete(_config({'theme_color': '#d81b60'}));
    await c.read(configProvider.future);

    expect(c.read(themeColorProvider), const Color(0xFFD81B60));
    expect(await colorAfterRestart(), '#d81b60');
  });

  test('goes back to the default when the branch no longer has a colour', () async {
    when(repository.config).thenAnswer((_) async => _config({'theme_color': null}));
    final c = container();
    await c.read(configProvider.future);

    expect(c.read(themeColorProvider), const Color(0xFFFF471A));
    expect(await colorAfterRestart(), isNull);
  });

  test('keeps the remembered colour on a server that does not send the field', () async {
    when(repository.config).thenAnswer((_) async => _config({}));
    final c = container();
    await c.read(configProvider.future);

    expect(c.read(themeColorProvider), _stored);
    expect(await colorAfterRestart(), '#112233');
  });

  test('ignores a config that belongs to another branch', () async {
    when(repository.config).thenAnswer(
      (_) async => _config({'branch_id': 'b2', 'theme_color': '#d81b60'}),
    );
    final c = container();
    await c.read(configProvider.future);

    expect(c.read(themeColorProvider), _stored);
    expect(await colorAfterRestart(), '#112233');
  });
}
