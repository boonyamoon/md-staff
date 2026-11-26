import 'dart:async';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/credential_store.dart';
import 'api_failure.dart';
import 'api_logger.dart';

/// Why the handset had to go back to the sign-in screen.
enum SessionEvent {
  /// The session is gone for good: the handset was unpaired, or this staff member may no longer
  /// use it. Nothing the app can do but ask someone to sign in again.
  signedOut,
}

/// One Dio instance for the whole app, with the token rules in one interceptor.
///
/// A handset signs in once and stays signed in, which the app earns by refreshing its own token:
///
///  * **Proactively**, before a request, when under 5 minutes of access-token life is left. Doing
///    it here rather than waiting for a 401 means a handset that drops off the network still has
///    most of a token's life to keep retrying in, instead of looking signed out.
///  * **Single-flight**: concurrent requests await one refresh rather than each starting their
///    own, so a screen that fires four calls at once does not rotate the token four times.
///  * **With a 60-second cooldown** after a refresh fails, so a server that is down does not have
///    every request re-awaiting a failing refresh. Same policy as the iPad POS.
///  * **Once reactively**, if a request still comes back `STAFF_APP_TOKEN_EXPIRED` — then retried.
///
/// Only a revoked device or a revoked staff member ends the session; an expired token never does.
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
      validateStatus: (status) => status != null && status >= 200 && status < 300,
    );
    _dio.interceptors.add(
      InterceptorsWrapper(onRequest: _onRequest, onError: _onError),
    );
    // After the token interceptor on the way out (so the log shows the real call, with its masked
    // Authorization) and after its error handling on the way back. Silent outside debug builds.
    _dio.interceptors.add(ApiLogger());
  }

  final Dio _dio;
  final CredentialStore _credentials;
  final _sessionEvents = StreamController<SessionEvent>.broadcast();

  /// Set by [attachRefresher] once the repository that can rotate tokens exists. Kept as a hook
  /// rather than a dependency so the client does not have to know about the repository layer.
  Future<bool> Function()? _refresher;

  Future<void>? _inFlightRefresh;
  DateTime? _lastFailedRefreshAt;

  static const Duration _refreshCooldown = Duration(seconds: 60);

  Stream<SessionEvent> get sessionEvents => _sessionEvents.stream;

  void dispose() => _sessionEvents.close();

  /// Wires in the thing that can actually rotate the token pair.
  void attachRefresher(Future<bool> Function() refresher) => _refresher = refresher;

  Future<void> _onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // The sign-in flow passes the staff JWT itself, and the refresh call carries its credential
    // in the body — neither wants the access token attached.
    if (options.headers.containsKey('Authorization') || _isRefreshPath(options.path)) {
      handler.next(options);
      return;
    }

    if (_isStaffAppPath(options.path) && (_credentials.cached?.needsRefresh ?? false)) {
      await _refreshOnce();
    }

    final token = _isStaffAppPath(options.path) ? _credentials.cachedAccessToken : null;
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  Future<void> _onError(DioException error, ErrorInterceptorHandler handler) async {
    final failure = ApiFailure.fromDio(error);
    final status = error.response?.statusCode;

    // An expired token is a refresh cue, never a sign-out. Retry the call once behind a refresh.
    if (status == 401 &&
        failure.isTokenExpired &&
        _isStaffAppPath(error.requestOptions.path) &&
        error.requestOptions.extra['staff_app_retried'] != true) {
      final refreshed = await _refreshOnce();
      if (refreshed) {
        try {
          final options = error.requestOptions;
          options.extra = {...options.extra, 'staff_app_retried': true};
          final token = _credentials.cachedAccessToken;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.resolve(await _dio.fetch<dynamic>(options));
          return;
        } on DioException catch (retryError) {
          handler.reject(_wrap(retryError));
          return;
        }
      }
    }

    if ((status == 401 || status == 403) && failure.endsSession) {
      _emit(SessionEvent.signedOut);
    }
    handler.reject(_wrap(error, failure));
  }

  DioException _wrap(DioException error, [ApiFailure? failure]) => DioException(
        requestOptions: error.requestOptions,
        error: failure ?? ApiFailure.fromDio(error),
        response: error.response,
      );

  /// Single-flight, cooled down. Returns whether the handset now holds a usable access token.
  Future<bool> _refreshOnce() async {
    final refresher = _refresher;
    if (refresher == null || _credentials.cachedRefreshToken == null) return false;

    final lastFailure = _lastFailedRefreshAt;
    if (lastFailure != null && DateTime.now().difference(lastFailure) < _refreshCooldown) {
      return false;
    }

    final inFlight = _inFlightRefresh;
    if (inFlight != null) {
      await inFlight;
      return !(_credentials.cached?.needsRefresh ?? true);
    }

    final completer = Completer<void>();
    _inFlightRefresh = completer.future;
    var ok = false;
    try {
      ok = await refresher();
      _lastFailedRefreshAt = ok ? null : DateTime.now();
    } on Object {
      _lastFailedRefreshAt = DateTime.now();
      ok = false;
    } finally {
      _inFlightRefresh = null;
      completer.complete();
    }
    return ok;
  }

  void _emit(SessionEvent event) {
    if (!_sessionEvents.isClosed) _sessionEvents.add(event);
  }

  static bool _isStaffAppPath(String path) => path.contains('api/v1/staff-app/');

  static bool _isRefreshPath(String path) => path.contains('api/v1/staff-app/token/refresh');

  // ── Verbs ──

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
