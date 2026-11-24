import '../../core/network/api_client.dart';
import '../../core/storage/credential_store.dart';
import '../dto/floor_dto.dart';
import '../dto/json.dart';
import '../dto/shift_dto.dart';

/// Starting, reading and ending a shift on a paired handset.
class ShiftRepository {
  ShiftRepository({required ApiClient api, required CredentialStore credentials})
      : _api = api,
        _credentials = credentials;

  final ApiClient _api;
  final CredentialStore _credentials;

  /// Email + password on this handset. Stores the shift token on success.
  Future<ShiftSession> login({required String email, required String password}) async {
    final body = await _api.post(
      'api/v1/staff-app/login',
      body: {'email': email.trim(), 'password': password},
    );
    final session = ShiftSession.fromJson(envelopeData(body));
    await _credentials.saveShift(
      shiftToken: session.shiftToken,
      staffId: session.staff.staffId,
      staffName: session.staff.staffName,
      canTakeOverTables: session.staff.canTakeOverTables,
    );
    return session;
  }

  /// Ends the shift. Releasing the handset's table claims is the point — a waiter signing off must
  /// not leave tables locked for whoever is on next. The local token is dropped either way, so a
  /// sign-out still works with no signal.
  Future<void> logout() async {
    try {
      await _api.post('api/v1/staff-app/logout');
    } finally {
      await _credentials.clearShift();
    }
  }

  Future<StaffAppConfig> config() async {
    final body = await _api.get('api/v1/staff-app/config');
    return StaffAppConfig.fromJson(envelopeData(body));
  }

  /// Who is signed in and which table this handset is still holding — read when the app resumes.
  Future<StaffAppSessionState> session() async {
    final body = await _api.get('api/v1/staff-app/session');
    return StaffAppSessionState.fromJson(envelopeData(body));
  }

  /// Extends the long-lived device token. Called on launch so a handset that stays in the shop
  /// never reaches its expiry and need re-pairing.
  Future<void> refreshDeviceToken() async {
    final body = await _api.post('api/v1/staff-app/token/refresh');
    final token = asStringOrNull(envelopeData(body)['device_token']);
    if (token != null) await _credentials.saveDeviceToken(token);
  }
}
