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
    test('a revoked handset is recognised, and is not read as a shift ending', () {
      const failure = ApiFailure(code: 'STAFF_APP_DEVICE_REVOKED', message: '');
      expect(failure.isDeviceRevoked, isTrue);
      expect(failure.isShiftOver, isFalse);
    });

    test('an expired shift is recognised, and is not read as an unpaired device', () {
      const failure = ApiFailure(code: 'STAFF_APP_SHIFT_TOKEN_EXPIRED', message: '');
      expect(failure.isShiftOver, isTrue);
      expect(failure.isDeviceRevoked, isFalse);
    });

    test('a deactivated staff account ends the shift', () {
      const failure = ApiFailure(code: 'STAFF_APP_STAFF_REVOKED', message: '');
      expect(failure.isShiftOver, isTrue);
    });

    test('a serialisation conflict is worth retrying as-is', () {
      const failure = ApiFailure(code: 'CONCURRENT_MODIFICATION', message: '');
      expect(failure.isRetryable, isTrue);
    });

    test('out of stock is none of those — it needs the waiter to change the order', () {
      const failure = ApiFailure(code: 'INSUFFICIENT_STOCK', message: '');
      expect(failure.isRetryable, isFalse);
      expect(failure.isClaimConflict, isFalse);
      expect(failure.isDeviceRevoked, isFalse);
      expect(failure.isShiftOver, isFalse);
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
