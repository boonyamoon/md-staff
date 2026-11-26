import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_staff/core/network/api_client.dart';
import 'package:md_staff/core/storage/credential_store.dart';
import 'package:md_staff/data/repositories/menu_repository.dart';

/// A server made of one function, so no network is involved.
class _Server implements HttpClientAdapter {
  _Server(this.answer);

  final ResponseBody Function(RequestOptions request) answer;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return answer(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, {int status = 200, String? etag}) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        if (etag != null) 'etag': [etag],
      },
    );

MenuRepository _repository(_Server server) => MenuRepository(
      api: ApiClient(credentials: CredentialStore(), dio: Dio()..httpClientAdapter = server),
    );

void main() {
  test('takes the whole menu in one call and remembers its ETag', () async {
    final server = _Server(
      (_) => _json({
        'success': true,
        'data': {'categories': <Object>[], 'products': <Object>[]},
      }, etag: 'W/"abc"'),
    );

    final snapshot = await _repository(server).snapshot();

    expect(snapshot.etag, 'W/"abc"');
    expect(snapshot.data, {'categories': <Object>[], 'products': <Object>[]});
    expect(server.requests.single.path, 'api/v1/staff-app/menu/snapshot');
    expect(server.requests.single.headers.containsKey('If-None-Match'), isFalse);
  });

  test('sends the ETag it holds, and takes 304 to mean unchanged', () async {
    final server = _Server((_) => ResponseBody.fromString('', 304));

    final snapshot = await _repository(server).snapshot(etag: 'W/"abc"');

    expect(snapshot.notModified, isTrue);
    expect(snapshot.etag, 'W/"abc"');
    expect(server.requests.single.headers['If-None-Match'], 'W/"abc"');
  });

  test('assembles the menu from the listing on a server without the snapshot', () async {
    final server = _Server((request) {
      if (request.path.endsWith('menu/snapshot')) {
        return _json({'error': 'Route not found'}, status: 404);
      }
      if (request.path.endsWith('menu/categories')) {
        return _json({
          'success': true,
          'data': [
            {'id': 'c1'},
          ],
        });
      }
      final page = request.queryParameters['page'] as int;
      return _json({
        'success': true,
        'data': [
          {'id': 'p$page'},
        ],
        'pagination': {'page': page, 'has_next_page': page < 2},
      });
    });

    final snapshot = await _repository(server).snapshot();

    expect(snapshot.etag, isNull);
    expect(snapshot.data!['categories'], [
      {'id': 'c1'},
    ]);
    expect(snapshot.data!['products'], [
      {'id': 'p1'},
      {'id': 'p2'},
    ]);
  });
}
