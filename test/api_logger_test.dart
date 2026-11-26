import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_staff/core/network/api_logger.dart';

/// Answers every request with a canned status and JSON body, so no network is involved.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.status, this.body);

  final int status;
  final Map<String, dynamic> body;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  void close({bool force = false}) {}
}

Dio _dio(List<String> lines, {int status = 200, Map<String, dynamic> body = const {}, bool enabled = true}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test/', validateStatus: (s) => s != null && s < 300))
    ..httpClientAdapter = _StubAdapter(status, body)
    ..interceptors.add(ApiLogger(enabled: enabled, sink: lines.add));
  return dio;
}

void main() {
  test('logs the request and the answer, with secrets masked', () async {
    final lines = <String>[];
    final dio = _dio(lines, body: {
      'data': {'access_token': 'abc.def.ghi', 'name': 'Somchai'},
    });

    await dio.post<dynamic>(
      'api/v1/auth/login',
      data: {'email': 'a@b.com', 'password': 'hunter2'},
      options: Options(headers: {'Authorization': 'Bearer top-secret'}),
    );

    final log = lines.join('\n');
    expect(log, contains('→ POST https://example.test/api/v1/auth/login'));
    expect(log, contains('← 200 POST https://example.test/api/v1/auth/login'));
    expect(log, contains('a@b.com'));
    expect(log, contains('Somchai'));
    expect(log, contains('auth: Bearer ***'));
    expect(log, isNot(contains('hunter2')));
    expect(log, isNot(contains('top-secret')));
    expect(log, isNot(contains('abc.def.ghi')));
  });

  test('logs a failing call with its status and the server body', () async {
    final lines = <String>[];
    final dio = _dio(lines, status: 404, body: {'error': 'Route not found'});

    await expectLater(dio.get<dynamic>('api/v1/staff-app/pairing/terminals'), throwsA(isA<DioException>()));

    final log = lines.join('\n');
    expect(log, contains('✗ 404 GET https://example.test/api/v1/staff-app/pairing/terminals'));
    expect(log, contains('Route not found'));
  });

  test('masks PINs but leaves look-alike words alone', () {
    final redacted = ApiLogger.redact({
      'manager_pin': '1234',
      'pin': '9999',
      'shipping': 'express',
      'nested': [
        {'refresh_token': 'r', 'qty': 2},
      ],
    });

    expect(redacted, {
      'manager_pin': '***',
      'pin': '***',
      'shipping': 'express',
      'nested': [
        {'refresh_token': '***', 'qty': 2},
      ],
    });
  });

  test('prints nothing when disabled', () async {
    final lines = <String>[];
    await _dio(lines, enabled: false).get<dynamic>('x');
    expect(lines, isEmpty);
  });
}
