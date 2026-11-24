import 'dart:async';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/credential_store.dart';
import 'api_failure.dart';

/// Why the app had to leave the screen it was on.
enum SessionEvent {
  /// This handset is no longer paired — back to setup.
  deviceRevoked,

  /// The shift ended, or the account lost access to this branch — back to sign-in.
  shiftEnded,
}

/// One Dio instance for the whole app, with the token rules in one interceptor.
///
/// Which token a request carries is decided by its path, not by the caller:
///
///   * `auth/*`, `branches-access/*`, `staff-app/pairing/*`, `staff-app/pair` — the staff JWT,
///     passed explicitly by the setup flow and never stored (exactly as the kiosk app does it).
///   * `staff-app/token/refresh`, `staff-app/login` — the device token.
///   * every other `staff-app/*` path — the shift token.
///
/// A 401/403 that means "this handset or shift is finished" is turned into a [SessionEvent] so any
/// screen can react, rather than each call site having to recognise those codes.
class ApiClient {
  ApiClient({required CredentialStore credentials, Dio? dio})
      : _credentials = credentials,
        _dio = dio ?? Dio() {
    _dio.options = _dio.options.copyWith(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      contentType: Headers.jsonContentType,
      // Non-2xx is handled below as an ApiFailure, never as a silent success.
      validateStatus: (status) => status != null && status >= 200 && status < 300,
    );
    _dio.interceptors.add(
      InterceptorsWrapper(onRequest: _onRequest, onError: _onError),
    );
  }

  final Dio _dio;
  final CredentialStore _credentials;
  final _sessionEvents = StreamController<SessionEvent>.broadcast();

  Stream<SessionEvent> get sessionEvents => _sessionEvents.stream;

  void dispose() => _sessionEvents.close();

  void _onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // The setup flow passes the staff JWT itself; never override it.
    if (options.headers.containsKey('Authorization')) {
      handler.next(options);
      return;
    }
    final path = options.path;
    final token = _usesDeviceToken(path)
        ? _credentials.cachedDeviceToken
        : (_isStaffAppPath(path) ? _credentials.cachedShiftToken : null);
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  void _onError(DioException error, ErrorInterceptorHandler handler) {
    final failure = ApiFailure.fromDio(error);
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      // Device first: a revoked handset must send the app back to pairing, not to a sign-in
      // screen it can never get past.
      if (failure.isDeviceRevoked) {
        _emit(SessionEvent.deviceRevoked);
      } else if (failure.isShiftOver) {
        _emit(SessionEvent.shiftEnded);
      }
    }
    handler.reject(
      DioException(requestOptions: error.requestOptions, error: failure, response: error.response),
    );
  }

  void _emit(SessionEvent event) {
    if (!_sessionEvents.isClosed) _sessionEvents.add(event);
  }

  static bool _isStaffAppPath(String path) => path.contains('api/v1/staff-app/');

  static bool _usesDeviceToken(String path) =>
      path.contains('api/v1/staff-app/token/refresh') || path.contains('api/v1/staff-app/login');

  // ── Verbs ──
  //
  // Each returns the decoded body and converts any Dio failure into an [ApiFailure], so callers
  // only ever have to catch one type.

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    String? staffBearer,
  }) =>
      _send(() => _dio.get<dynamic>(
            path,
            queryParameters: query,
            options: _options(staffBearer: staffBearer),
          ));

  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    Map<String, String>? headers,
    String? staffBearer,
  }) =>
      _send(() => _dio.post<dynamic>(
            path,
            data: body,
            options: _options(staffBearer: staffBearer, headers: headers),
          ));

  Options _options({String? staffBearer, Map<String, String>? headers}) {
    final merged = <String, dynamic>{...?headers};
    if (staffBearer != null && staffBearer.isNotEmpty) {
      merged['Authorization'] = 'Bearer $staffBearer';
    }
    return Options(headers: merged.isEmpty ? null : merged);
  }

  Future<Map<String, dynamic>> _send(Future<Response<dynamic>> Function() request) async {
    try {
      final response = await request();
      final body = response.data;
      if (body is Map<Object?, Object?>) return Map<String, dynamic>.from(body);
      // Every endpoint this app calls answers with a JSON object; anything else is a server bug.
      throw const ApiFailure(code: 'MALFORMED_RESPONSE', message: 'Unexpected answer from the server');
    } on DioException catch (error) {
      final inner = error.error;
      throw inner is ApiFailure ? inner : ApiFailure.fromDio(error);
    }
  }
}

/// Unwraps the `{ success, data }` envelope the staff-app endpoints answer with.
Map<String, dynamic> envelopeData(Map<String, dynamic> body) {
  final data = body['data'];
  if (data is Map<Object?, Object?>) return Map<String, dynamic>.from(data);
  throw const ApiFailure(code: 'MALFORMED_RESPONSE', message: 'Unexpected answer from the server');
}

List<Map<String, dynamic>> envelopeList(Map<String, dynamic> body) {
  final data = body['data'];
  if (data is List) {
    return data
        .whereType<Map<Object?, Object?>>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  throw const ApiFailure(code: 'MALFORMED_RESPONSE', message: 'Unexpected answer from the server');
}
