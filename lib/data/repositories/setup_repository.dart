import '../../core/network/api_client.dart';
import '../../core/network/api_failure.dart';
import '../../core/storage/credential_store.dart';
import '../dto/json.dart';
import '../dto/setup_dto.dart';

/// Pairing a handset: the one-time setup a manager does before the phone goes on the floor.
///
/// The staff JWT this flow obtains is held in memory by the setup screen and never written to
/// disk — only the device token pairing returns is stored. Same rule as the kiosk app.
class SetupRepository {
  SetupRepository({required ApiClient api, required CredentialStore credentials})
      : _api = api,
        _credentials = credentials;

  final ApiClient _api;
  final CredentialStore _credentials;

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

  /// Binds this phone to a STAFF terminal and stores the device token it returns.
  ///
  /// `terminalId` null lets the server pick any free handset terminal in the branch.
  Future<PairResult> pair({
    required String staffBearer,
    required String branchId,
    required String deviceName,
    required String appVersion,
    String? terminalId,
  }) async {
    final deviceInstallId = await _credentials.deviceInstallId();
    final body = await _api.post(
      'api/v1/staff-app/pair',
      staffBearer: staffBearer,
      body: {
        'branch_id': branchId,
        'device_install_id': deviceInstallId,
        'device_name': deviceName.trim(),
        'app_version': appVersion,
        'terminal_id': ?terminalId,
      },
    );
    final result = PairResult.fromJson(envelopeData(body));
    await _credentials.savePairing(
      StoredCredentials(
        deviceToken: result.deviceToken,
        terminalId: result.terminalId,
        terminalCode: result.terminalCode,
        terminalName: result.terminalName,
        businessId: result.businessId,
        branchId: result.branchId,
      ),
    );
    return result;
  }
}
