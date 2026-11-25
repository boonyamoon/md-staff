import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_staff/core/network/api_failure.dart';

DioException _badResponse(int status, Map<String, dynamic> body) {
  final options = RequestOptions(path: '/api/v1/staff-app/zones');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<dynamic>(requestOptions: options, statusCode: status, data: body),
  );
}

void main() {
  group('server answers', () {
    test('keeps the code, message and data the API sent', () {
      final failure = ApiFailure.fromDio(
        _badResponse(409, {
          'success': false,
          'code': 'TABLE_CLAIM_HELD',
          'message': 'Dao is taking orders at A1',
          'data': {
            'holder': {
              'staff_name': 'Dao',
              'terminal_name': 'Handset 2',
              'terminal_code': 'S02',
            },
          },
        }),
      );
      expect(failure.code, 'TABLE_CLAIM_HELD');
      expect(failure.statusCode, 409);
      expect(failure.isClaimConflict, isTrue);
      expect(failure.holder!.staffName, 'Dao');
      expect(failure.holder!.terminalCode, 'S02');
    });

    test('falls back to a code derived from the status when the body has none', () {
      final failure = ApiFailure.fromDio(_badResponse(429, {'success': false}));
      expect(failure.code, 'RATE_LIMIT_EXCEEDED');
    });

    test('has no holder when the server named none', () {
      final failure = ApiFailure.fromDio(
        _badResponse(409, {'code': 'TABLE_CLAIM_LOST', 'message': 'gone'}),
      );
      expect(failure.isClaimConflict, isTrue);
      expect(failure.holder, isNull);
    });
  });

  group('classification', () {
    test('an expired access token is a refresh cue, NOT the end of the session', () {
      const failure = ApiFailure(code: 'STAFF_APP_TOKEN_EXPIRED', message: '');
      expect(failure.isTokenExpired, isTrue);
      // The whole point of a permanent sign-in: a lapsed token must never show a login form.
      expect(failure.endsSession, isFalse);
    });

    test('a revoked handset ends the session', () {
      const failure = ApiFailure(code: 'STAFF_APP_DEVICE_REVOKED', message: '');
      expect(failure.endsSession, isTrue);
      expect(failure.isTokenExpired, isFalse);
    });

    test('a deactivated staff account ends the session', () {
      const failure = ApiFailure(code: 'STAFF_APP_STAFF_REVOKED', message: '');
      expect(failure.endsSession, isTrue);
    });

    test('a dead refresh token ends the session', () {
      for (final code in [
        'STAFF_APP_REFRESH_TOKEN_INVALID',
        'STAFF_APP_SESSION_REVOKED',
        'STAFF_APP_SESSION_EXPIRED',
      ]) {
        expect(ApiFailure(code: code, message: '').endsSession, isTrue, reason: code);
      }
    });

    test('an app too old for this server ends the session rather than looping', () {
      const failure = ApiFailure(code: 'STAFF_APP_UPGRADE_REQUIRED', message: '');
      expect(failure.endsSession, isTrue);
    });

    test('a serialisation conflict is worth retrying as-is', () {
      const failure = ApiFailure(code: 'CONCURRENT_MODIFICATION', message: '');
      expect(failure.isRetryable, isTrue);
    });

    test('out of stock is none of those — it needs the waiter to change the order', () {
      const failure = ApiFailure(code: 'INSUFFICIENT_STOCK', message: '');
      expect(failure.isRetryable, isFalse);
      expect(failure.isClaimConflict, isFalse);
      expect(failure.endsSession, isFalse);
      expect(failure.isTokenExpired, isFalse);
    });
  });

  group('transport', () {
    test('a dropped connection reads as offline', () {
      final failure = ApiFailure.fromDio(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionError,
        ),
      );
      expect(failure.code, 'NETWORK_UNREACHABLE');
      expect(failure.isOffline, isTrue);
    });

    test('every timeout kind reads as offline', () {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        final failure = ApiFailure.fromDio(
          DioException(requestOptions: RequestOptions(path: '/'), type: type),
        );
        expect(failure.isOffline, isTrue, reason: '$type');
      }
    });

    test('an HTML error page is not mistaken for an envelope', () {
      final options = RequestOptions(path: '/');
      final failure = ApiFailure.fromDio(
        DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: options,
            statusCode: 502,
            data: '<html>Bad gateway</html>',
          ),
        ),
      );
      expect(failure.code, 'SERVER_ERROR');
      expect(failure.statusCode, 502);
    });
  });
}
