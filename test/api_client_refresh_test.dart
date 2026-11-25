import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_staff/core/network/api_client.dart';
import 'package:md_staff/core/network/api_failure.dart';
import 'package:md_staff/core/storage/credential_store.dart';

/// An in-memory stand-in for the platform keystore, so the client's refresh behaviour can be
/// exercised without a device.
class _FakeStore extends CredentialStore {
  // Every method that would touch the platform keystore is overridden below, so the inherited
  // storage is never reached.
  _FakeStore(this._session);

  StaffSession? _session;
  int saveCount = 0;

  @override
  StaffSession? get cached => _session;

  @override
  String? get cachedAccessToken => _session?.accessToken;

  @override
  String? get cachedRefreshToken => _session?.refreshToken;

  @override
  Future<StaffSession?> load() async => _session;

  @override
  Future<void> save(StaffSession session) async {
    _session = session;
    saveCount += 1;
  }

  @override
  Future<void> saveRotatedTokens({
    required String accessToken,
    required DateTime accessTokenExpiresAt,
    required String refreshToken,
    String? staffName,
    bool? canTakeOverTables,
  }) async {
    final current = _session;
    if (current == null) return;
    await save(current.copyWith(
      accessToken: accessToken,
      accessTokenExpiresAt: accessTokenExpiresAt,
      refreshToken: refreshToken,
    ));
  }

  @override
  Future<void> clear() async => _session = null;

  @override
  Future<String> deviceInstallId() async => 'device-1';
}

StaffSession session({required Duration remaining, String accessToken = 'access-1'}) => StaffSession(
      accessToken: accessToken,
      accessTokenExpiresAt: DateTime.now().add(remaining),
      refreshToken: 'msa_refresh-1',
      terminalId: 'terminal-1',
      terminalCode: 'S01',
      terminalName: 'Handset 1',
      businessId: 'biz-1',
      branchId: 'branch-1',
      staffId: 'staff-1',
      staffName: 'Nok',
    );

/// Records every request and answers from a queue, so a test can assert ordering and headers.
class _Recorder extends Interceptor {
  _Recorder(this.handlers);

  /// path → the responses to give, in order.
  final Map<String, List<Response<dynamic> Function(RequestOptions)>> handlers;
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    final queue = handlers[options.path];
    if (queue == null || queue.isEmpty) {
      handler.reject(
        DioException(requestOptions: options, error: 'no stub for ${options.path}'),
        true,
      );
      return;
    }
    final build = queue.length == 1 ? queue.first : queue.removeAt(0);
    final response = build(options);
    if (response.statusCode != null && response.statusCode! >= 400) {
      handler.reject(
        DioException(requestOptions: options, response: response, type: DioExceptionType.badResponse),
        true,
      );
      return;
    }
    handler.resolve(response);
  }
}

Response<dynamic> ok(RequestOptions options, Object body) =>
    Response<dynamic>(requestOptions: options, statusCode: 200, data: body);

Response<dynamic> fail(RequestOptions options, int status, String code) =>
    Response<dynamic>(
      requestOptions: options,
      statusCode: status,
      data: {'success': false, 'code': code, 'message': code},
    );

Map<String, dynamic> rotatedBody(String access) => {
      'success': true,
      'data': {
        'access_token': access,
        'access_token_expires_at': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
        'refresh_token': 'msa_refresh-2',
        'refresh_token_expires_at': DateTime.now().add(const Duration(days: 180)).toIso8601String(),
        'staff': {'staff_id': 'staff-1', 'staff_name': 'Nok'},
        'terminal': {'terminal_id': 'terminal-1', 'terminal_code': 'S01', 'terminal_name': 'Handset 1'},
      },
    };

const _zonesPath = 'api/v1/staff-app/zones';
const _refreshPath = 'api/v1/staff-app/token/refresh';

({ApiClient client, _Recorder recorder, _FakeStore store}) build({
  required Duration remaining,
  required Map<String, List<Response<dynamic> Function(RequestOptions)>> handlers,
  int refreshFailures = 0,
}) {
  final store = _FakeStore(session(remaining: remaining));
  final dio = Dio();
  final recorder = _Recorder(handlers);
  final client = ApiClient(credentials: store, dio: dio);
  // The recorder must run last so the client's own interceptor sees the request first.
  dio.interceptors.add(recorder);
  var failures = refreshFailures;
  client.attachRefresher(() async {
    if (failures > 0) {
      failures -= 1;
      return false;
    }
    await store.saveRotatedTokens(
      accessToken: 'access-2',
      accessTokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
      refreshToken: 'msa_refresh-2',
    );
    return true;
  });
  return (client: client, recorder: recorder, store: store);
}

void main() {
  group('proactive refresh', () {
    test('does not refresh while the token has plenty of life left', () async {
      final h = build(
        remaining: const Duration(minutes: 55),
        handlers: {_zonesPath: [(o) => ok(o, {'success': true, 'data': <Object>[]})]},
      );

      await h.client.get(_zonesPath);

      expect(h.store.saveCount, 0);
      expect(h.recorder.requests.single.headers['Authorization'], 'Bearer access-1');
    });

    test('refreshes before the request once under five minutes are left', () async {
      final h = build(
        remaining: const Duration(minutes: 2),
        handlers: {_zonesPath: [(o) => ok(o, {'success': true, 'data': <Object>[]})]},
      );

      await h.client.get(_zonesPath);

      // Refreshed first, and the request carried the NEW token — not the nearly-dead one.
      expect(h.store.saveCount, 1);
      expect(h.recorder.requests.single.headers['Authorization'], 'Bearer access-2');
    });

    test('refreshes once for several concurrent requests, not once each', () async {
      final h = build(
        remaining: const Duration(minutes: 1),
        handlers: {_zonesPath: [(o) => ok(o, {'success': true, 'data': <Object>[]})]},
      );

      await Future.wait([
        h.client.get(_zonesPath),
        h.client.get(_zonesPath),
        h.client.get(_zonesPath),
        h.client.get(_zonesPath),
      ]);

      // Single-flight: one rotation for four calls. Without it the server would see four
      // rotations and three of them would land in the grace window.
      expect(h.store.saveCount, 1);
      expect(h.recorder.requests, hasLength(4));
    });

    test('holds off for a minute after a failed refresh instead of retrying every request', () async {
      final h = build(
        remaining: const Duration(minutes: 1),
        refreshFailures: 1,
        handlers: {_zonesPath: [(o) => ok(o, {'success': true, 'data': <Object>[]})]},
      );

      // First call tries to refresh, fails, and goes out with the token it has.
      await h.client.get(_zonesPath);
      expect(h.store.saveCount, 0);

      // The second must NOT try again — a server that is down would otherwise have every
      // request re-awaiting a failing refresh.
      await h.client.get(_zonesPath);
      expect(h.store.saveCount, 0);
      expect(h.recorder.requests, hasLength(2));
    });

    test('never attaches the access token to the refresh call itself', () async {
      final h = build(
        remaining: const Duration(minutes: 1),
        handlers: {_refreshPath: [(o) => ok(o, rotatedBody('access-2'))]},
      );

      await h.client.post(_refreshPath, body: {'refresh_token': 'msa_refresh-1'});

      expect(h.recorder.requests.single.headers.containsKey('Authorization'), isFalse);
      // And it must not have triggered a refresh of its own, which would recurse.
      expect(h.store.saveCount, 0);
    });
  });

  group('reactive refresh', () {
    test('refreshes and retries once when a request reports an expired token', () async {
      final h = build(
        remaining: const Duration(minutes: 55),
        handlers: {
          _zonesPath: [
            (o) => fail(o, 401, 'STAFF_APP_TOKEN_EXPIRED'),
            (o) => ok(o, {'success': true, 'data': <Object>[]}),
          ],
        },
      );

      final body = await h.client.get(_zonesPath);

      expect(body['success'], true);
      expect(h.store.saveCount, 1);
      expect(h.recorder.requests, hasLength(2));
      expect(h.recorder.requests.last.headers['Authorization'], 'Bearer access-2');
    });

    test('gives up after one retry rather than looping', () async {
      final h = build(
        remaining: const Duration(minutes: 55),
        handlers: {_zonesPath: [(o) => fail(o, 401, 'STAFF_APP_TOKEN_EXPIRED')]},
      );

      await expectLater(
        h.client.get(_zonesPath),
        throwsA(isA<ApiFailure>().having((f) => f.code, 'code', 'STAFF_APP_TOKEN_EXPIRED')),
      );
      expect(h.recorder.requests, hasLength(2));
    });

    test('does not retry a revoked handset — that is not something a refresh fixes', () async {
      final h = build(
        remaining: const Duration(minutes: 55),
        handlers: {_zonesPath: [(o) => fail(o, 401, 'STAFF_APP_DEVICE_REVOKED')]},
      );

      await expectLater(h.client.get(_zonesPath), throwsA(isA<ApiFailure>()));
      expect(h.recorder.requests, hasLength(1));
      expect(h.store.saveCount, 0);
    });
  });

  group('session events', () {
    test('announces a signed-out handset so the app can show the sign-in screen', () async {
      final h = build(
        remaining: const Duration(minutes: 55),
        handlers: {_zonesPath: [(o) => fail(o, 401, 'STAFF_APP_STAFF_REVOKED')]},
      );
      final events = <SessionEvent>[];
      h.client.sessionEvents.listen(events.add);

      await expectLater(h.client.get(_zonesPath), throwsA(isA<ApiFailure>()));
      await Future<void>.delayed(Duration.zero);

      expect(events, [SessionEvent.signedOut]);
    });

    test('stays quiet for an expired token, which is not a sign-out', () async {
      final h = build(
        remaining: const Duration(minutes: 55),
        handlers: {
          _zonesPath: [
            (o) => fail(o, 401, 'STAFF_APP_TOKEN_EXPIRED'),
            (o) => ok(o, {'success': true, 'data': <Object>[]}),
          ],
        },
      );
      final events = <SessionEvent>[];
      h.client.sessionEvents.listen(events.add);

      await h.client.get(_zonesPath);
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
    });
  });
}
