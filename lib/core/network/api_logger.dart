import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Prints every API call to the debug console: the request, then the answer (or the failure) with
/// how long it took.
///
/// Debug builds only — [kDebugMode] is a compile-time constant, so a release build neither prints
/// nor keeps any of this. Secrets never reach the console even in debug: passwords, tokens, PINs
/// and the Authorization header are masked, because a console log gets pasted into chats and bug
/// reports.
///
///     → POST https://api.meedeepos.com/api/v1/auth/login
///       body: {"email":"a@b.com","password":"***"}
///     ← 200 POST https://api.meedeepos.com/api/v1/auth/login (212 ms)
///       body: {"access_token":"***", ...}
class ApiLogger extends Interceptor {
  ApiLogger({this.enabled = kDebugMode, void Function(String line)? sink})
      : _sink = sink ?? _print;

  final bool enabled;
  final void Function(String line) _sink;

  static const _startedAt = 'api_logger_started_at';
  static const _maxBodyLength = 2000;
  static const _mask = '***';

  /// Any JSON key or header whose name contains one of these is masked.
  static final _secretKey = RegExp(
    r'pass(word)?|(^|[_-])pin($|[_-])|[a-z]pin$|token|secret|authorization|cookie',
    caseSensitive: false,
  );

  static void _print(String line) => debugPrint(line, wrapWidth: 1024);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (enabled) {
      options.extra[_startedAt] = DateTime.now().microsecondsSinceEpoch;
      final lines = <String>['→ ${options.method} ${options.uri}'];
      final auth = options.headers['Authorization'];
      if (auth != null) lines.add('  auth: ${_maskAuthorization('$auth')}');
      if (options.data != null) lines.add('  body: ${_render(options.data)}');
      _sink(lines.join('\n'));
    }
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    if (enabled) {
      final options = response.requestOptions;
      _sink(
        '← ${response.statusCode} ${options.method} ${options.uri} (${_elapsed(options)})\n'
        '  body: ${_render(response.data)}',
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (enabled) {
      final options = err.requestOptions;
      final status = err.response?.statusCode;
      final lines = <String>[
        '✗ ${status ?? err.type.name} ${options.method} ${options.uri} (${_elapsed(options)})',
      ];
      final inner = err.error;
      if (inner != null) lines.add('  failure: $inner');
      if (err.response?.data != null) lines.add('  body: ${_render(err.response!.data)}');
      if (status == null && err.message != null) lines.add('  cause: ${err.message}');
      _sink(lines.join('\n'));
    }
    handler.next(err);
  }

  static String _elapsed(RequestOptions options) {
    final started = options.extra[_startedAt];
    if (started is! int) return '? ms';
    final micros = DateTime.now().microsecondsSinceEpoch - started;
    return '${(micros / 1000).round()} ms';
  }

  static String _maskAuthorization(String value) {
    final space = value.indexOf(' ');
    return space == -1 ? _mask : '${value.substring(0, space)} $_mask';
  }

  static String _render(Object? body) {
    String text;
    try {
      text = body is String ? body : jsonEncode(_redact(body));
    } on Object {
      text = '$body';
    }
    return text.length <= _maxBodyLength
        ? text
        : '${text.substring(0, _maxBodyLength)}… (${text.length} chars)';
  }

  /// Copies [value] with every secret-looking key's value replaced. Exposed for tests.
  @visibleForTesting
  static Object? redact(Object? value) => _redact(value);

  static Object? _redact(Object? value) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          '${entry.key}': _secretKey.hasMatch('${entry.key}') && entry.value != null
              ? _mask
              : _redact(entry.value),
      };
    }
    if (value is List) return value.map(_redact).toList();
    return value;
  }
}
