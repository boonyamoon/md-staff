import '../../core/network/api_client.dart';
import '../../core/storage/credential_store.dart';
import '../dto/floor_dto.dart';
import '../dto/session_dto.dart';

/// The handset's one sign-in, and keeping it alive.
class SessionRepository {
  SessionRepository({required ApiClient api, required CredentialStore credentials})
      : _api = api,
        _credentials = credentials;

  final ApiClient _api;
  final CredentialStore _credentials;

  /// Signs a waiter in and pairs the handset in one step — the only login md-staff has.
  ///
  /// [staffBearer] is the staff JWT from `POST /api/v1/auth/login`, held in memory by the sign-in
  /// screen and never written to disk. Everything persisted afterwards is the session this
  /// returns.
  Future<StaffAppSession> login({
    required String staffBearer,
    required String branchId,
    required String deviceName,
    required String appVersion,
    String? terminalId,
    String? themeColor,
  }) async {
    final deviceInstallId = await _credentials.deviceInstallId();
    final body = await _api.post(
      'api/v1/staff-app/login',
      staffBearer: staffBearer,
      body: {
        'branch_id': branchId,
        'device_install_id': deviceInstallId,
        'device_name': deviceName.trim(),
        'app_version': appVersion,
        'terminal_id': ?terminalId,
      },
    );
    final session = StaffAppSession.fromJson(envelopeData(body));
    await _persist(session, themeColor: themeColor);
    return session;
  }

  /// Rotates the token pair. Called by the Dio interceptor, not by screens.
  ///
  /// The new pair is written to the keystore **before** this returns, so a crash between the
  /// server rotating and the handset storing cannot leave the app holding a dead token — and the
  /// server's grace window covers the opposite case, where this response never arrives.
  Future<bool> refresh() async {
    final refreshToken = _credentials.cachedRefreshToken;
    if (refreshToken == null) return false;
    final deviceInstallId = await _credentials.deviceInstallId();
    final body = await _api.post(
      'api/v1/staff-app/token/refresh',
      body: {
        'refresh_token': refreshToken,
        'device_install_id': deviceInstallId,
      },
    );
    final session = StaffAppSession.fromJson(envelopeData(body));
    await _credentials.saveRotatedTokens(
      accessToken: session.accessToken,
      accessTokenExpiresAt: session.accessTokenExpiresAt,
      refreshToken: session.refreshToken,
      staffName: session.staff.staffName.isEmpty ? null : session.staff.staffName,
      canTakeOverTables: session.staff.canTakeOverTables,
    );
    return true;
  }

  /// Signs the handset out for good: the server revokes the session and releases any tables it
  /// was holding. The local session is dropped either way, so signing out works with no signal.
  Future<void> logout() async {
    try {
      await _api.post('api/v1/staff-app/logout');
    } finally {
      await _credentials.clear();
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

  Future<void> _persist(StaffAppSession session, {String? themeColor}) => _credentials.save(
        StaffSession(
          accessToken: session.accessToken,
          accessTokenExpiresAt: session.accessTokenExpiresAt,
          refreshToken: session.refreshToken,
          terminalId: session.terminal.terminalId,
          terminalCode: session.terminal.terminalCode,
          terminalName: session.terminal.terminalName,
          businessId: session.terminal.businessId ?? '',
          branchId: session.terminal.branchId ?? '',
          staffId: session.staff.staffId,
          staffName: session.staff.staffName,
          canTakeOverTables: session.staff.canTakeOverTables,
          themeColor: themeColor,
        ),
      );
}
