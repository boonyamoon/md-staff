import 'package:dio/dio.dart';

/// Everything the UI needs to know about a failed call: a stable [code] to branch on, a message
/// safe to show a staff member, and the `data` the server attached (the claim holder's name on a
/// TABLE_CLAIM_HELD, for instance).
class ApiFailure implements Exception {
  const ApiFailure({
    required this.code,
    required this.message,
    this.statusCode,
    this.data,
  });

  final String code;
  final String message;
  final int? statusCode;
  final Map<String, dynamic>? data;

  /// No connection, a timeout, or a server that never answered.
  bool get isOffline =>
      code == 'NETWORK_UNREACHABLE' || code == 'TIMEOUT' || code == 'CONNECTION_FAILED';

  /// The server answered 404 for the path itself: it does not have this endpoint (yet), as
  /// opposed to not finding a table or a product.
  bool get isMissingRoute =>
      statusCode == 404 && message.toLowerCase().contains('route not found');

  /// The party an order was being built for is no longer there to receive it: the bill was
  /// cancelled or paid at the POS, or the party moved. Sending again cannot help.
  bool get isTableGone =>
      code == 'TABLE_SESSION_CHANGED' ||
      code == 'SESSION_CLOSED' ||
      code == 'ORDER_NOT_EDITABLE' ||
      code == 'ORDER_NOT_FOUND';

  /// The order was refused because the menu on this handset is out of date.
  bool get isMenuOutdated =>
      code == 'INSUFFICIENT_STOCK' ||
      code == 'INVALID_SKU' ||
      code == 'SKU_PRICE_NOT_CONFIGURED' ||
      code == 'OPTION_PRICE_NOT_CONFIGURED';

  /// The access token ran out. A refresh cue, NOT a sign-out: the handset's sign-in is permanent
  /// and only [endsSession] below means "ask someone to sign in again".
  bool get isTokenExpired => code == 'STAFF_APP_TOKEN_EXPIRED';

  /// The session is over for good — the handset was unpaired or moved, this staff member may no
  /// longer use it, or the refresh token is dead. Nothing the app can retry its way out of.
  bool get endsSession =>
      code == 'STAFF_APP_DEVICE_REVOKED' ||
      code == 'STAFF_APP_DEVICE_TYPE_INVALID' ||
      code == 'STAFF_APP_DEVICE_DISABLED' ||
      code == 'STAFF_APP_STAFF_REVOKED' ||
      code == 'STAFF_APP_SESSION_REVOKED' ||
      code == 'STAFF_APP_SESSION_EXPIRED' ||
      code == 'STAFF_APP_REFRESH_TOKEN_INVALID' ||
      code == 'STAFF_APP_TOKEN_REQUIRED' ||
      code == 'STAFF_APP_TOKEN_INVALID' ||
      code == 'STAFF_APP_UPGRADE_REQUIRED';

  /// Another handset holds this table, or took it while we were ordering.
  bool get isClaimConflict => code == 'TABLE_CLAIM_HELD' || code == 'TABLE_CLAIM_LOST';

  /// Worth retrying as-is: a serialisation conflict or a lock timeout on the server.
  bool get isRetryable => code == 'CONCURRENT_MODIFICATION' || statusCode == 503;

  /// The claim holder the server named, when it named one.
  ClaimHolderInfo? get holder {
    final raw = data?['holder'];
    if (raw is Map) return ClaimHolderInfo.fromJson(Map<String, dynamic>.from(raw));
    return null;
  }

  @override
  String toString() => 'ApiFailure($code, $statusCode): $message';

  /// Maps anything Dio throws into one failure type, so no screen has to know about Dio.
  factory ApiFailure.fromDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const ApiFailure(code: 'TIMEOUT', message: 'The server took too long to answer');
      case DioExceptionType.connectionError:
        return const ApiFailure(
          code: 'NETWORK_UNREACHABLE',
          message: 'No connection to the server',
        );
      case DioExceptionType.cancel:
        return const ApiFailure(code: 'CANCELLED', message: 'Request cancelled');
      case DioExceptionType.badCertificate:
        return const ApiFailure(
          code: 'CONNECTION_FAILED',
          message: 'Could not verify the server certificate',
        );
      case DioExceptionType.transformTimeout:
        return const ApiFailure(code: 'TIMEOUT', message: 'The server took too long to answer');
      case DioExceptionType.unknown:
      case DioExceptionType.badResponse:
        break;
    }

    final response = error.response;
    final body = response?.data;
    if (body is Map) {
      final map = Map<String, dynamic>.from(body);
      final data = map['data'];
      return ApiFailure(
        code: (map['code'] as String?) ?? _codeForStatus(response?.statusCode),
        message: (map['message'] as String?) ?? (map['error'] as String?) ?? 'Something went wrong',
        statusCode: response?.statusCode,
        data: data is Map ? Map<String, dynamic>.from(data) : null,
      );
    }
    return ApiFailure(
      code: _codeForStatus(response?.statusCode),
      message: error.message ?? 'Something went wrong',
      statusCode: response?.statusCode,
    );
  }

  static String _codeForStatus(int? status) {
    if (status == null) return 'CONNECTION_FAILED';
    if (status == 401) return 'UNAUTHORIZED';
    if (status == 403) return 'FORBIDDEN';
    if (status == 404) return 'NOT_FOUND';
    if (status == 409) return 'CONFLICT';
    if (status == 429) return 'RATE_LIMIT_EXCEEDED';
    if (status >= 500) return 'SERVER_ERROR';
    return 'REQUEST_FAILED';
  }
}

/// Who is holding a table, as the server reports it on a claim conflict.
class ClaimHolderInfo {
  const ClaimHolderInfo({
    required this.staffName,
    required this.terminalName,
    required this.terminalCode,
  });

  final String staffName;
  final String terminalName;
  final String terminalCode;

  factory ClaimHolderInfo.fromJson(Map<String, dynamic> json) => ClaimHolderInfo(
        staffName: (json['staff_name'] as String?) ?? '',
        terminalName: (json['terminal_name'] as String?) ?? '',
        terminalCode: (json['terminal_code'] as String?) ?? '',
      );
}
