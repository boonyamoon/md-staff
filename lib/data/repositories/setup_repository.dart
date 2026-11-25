import '../../core/network/api_client.dart';
import '../../core/network/api_failure.dart';
import '../dto/json.dart';
import '../dto/setup_dto.dart';

/// The staff-JWT half of signing in: the password check, then the branches and terminals the
/// account may use.
///
/// The JWT this returns is held in memory by the sign-in screen and never written to disk — only
/// the session that SessionRepository.login returns is persisted. Same rule as the kiosk app.
class SetupRepository {
  SetupRepository({required ApiClient api}) : _api = api;

  final ApiClient _api;

  /// Signs the setting-up staff member in. Note this hits the ordinary staff `auth/login`, which
  /// answers without the `{success, data}` envelope.
  Future<String> staffLogin({required String email, required String password}) async {
    final body = await _api.post(
      'api/v1/auth/login',
      body: {'email': email.trim(), 'password': password},
    );
    final token = asStringOrNull(body['access_token']);
    if (token == null) {
      throw const ApiFailure(code: 'INVALID_CREDENTIALS', message: 'Wrong email or password');
    }
    return token;
  }

  /// Branches this account may pair a handset for.
  Future<StaffAppAccess> access(String staffBearer) async {
    final body = await _api.get(
      'api/v1/branches-access/snapshot',
      query: {'platform': 'staff_app'},
      staffBearer: staffBearer,
    );
    return StaffAppAccess.fromSnapshot(envelopeData(body));
  }

  Future<List<PairingTerminal>> terminals({
    required String staffBearer,
    required String branchId,
  }) async {
    final body = await _api.get(
      'api/v1/staff-app/pairing/terminals',
      query: {'branch_id': branchId},
      staffBearer: staffBearer,
    );
    return envelopeList(body).map(PairingTerminal.fromJson).toList();
  }
}
