import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// One signed-in handset. A staff member signs in once and this is what keeps them signed in.
class StaffSession {
  const StaffSession({
    required this.accessToken,
    required this.accessTokenExpiresAt,
    required this.refreshToken,
    required this.terminalId,
    required this.terminalCode,
    required this.terminalName,
    required this.businessId,
    required this.branchId,
    required this.staffId,
    required this.staffName,
    this.canTakeOverTables = false,
    this.themeColor,
  });

  /// Sent as the bearer. Short-lived and replaced silently; never the thing that keeps the
  /// handset signed in.
  final String accessToken;
  final DateTime accessTokenExpiresAt;

  /// The credential that makes the sign-in permanent. Rotated on every use.
  final String refreshToken;

  final String terminalId;
  final String terminalCode;
  final String terminalName;
  final String businessId;
  final String branchId;
  final String staffId;
  final String staffName;
  final bool canTakeOverTables;

  /// The branch's `theme_color`, kept from sign-in so the app wears it again after a restart.
  final String? themeColor;

  /// Refresh when under this much life is left, rather than waiting for a 401 — the same
  /// 5-minute buffer the iPad POS uses. A handset in a dead-signal spot then has the rest of the
  /// token's life to keep retrying instead of looking signed out.
  static const Duration refreshBuffer = Duration(minutes: 5);

  bool get needsRefresh =>
      accessTokenExpiresAt.difference(DateTime.now()) <= refreshBuffer;

  StaffSession copyWith({
    String? accessToken,
    DateTime? accessTokenExpiresAt,
    String? refreshToken,
    String? staffId,
    String? staffName,
    bool? canTakeOverTables,
  }) =>
      StaffSession(
        accessToken: accessToken ?? this.accessToken,
        accessTokenExpiresAt: accessTokenExpiresAt ?? this.accessTokenExpiresAt,
        refreshToken: refreshToken ?? this.refreshToken,
        terminalId: terminalId,
        terminalCode: terminalCode,
        terminalName: terminalName,
        businessId: businessId,
        branchId: branchId,
        staffId: staffId ?? this.staffId,
        staffName: staffName ?? this.staffName,
        canTakeOverTables: canTakeOverTables ?? this.canTakeOverTables,
        themeColor: themeColor,
      );

  /// Separate from [copyWith] because null is a real value here: the branch has no colour.
  StaffSession withThemeColor(String? color) => StaffSession(
        accessToken: accessToken,
        accessTokenExpiresAt: accessTokenExpiresAt,
        refreshToken: refreshToken,
        terminalId: terminalId,
        terminalCode: terminalCode,
        terminalName: terminalName,
        businessId: businessId,
        branchId: branchId,
        staffId: staffId,
        staffName: staffName,
        canTakeOverTables: canTakeOverTables,
        themeColor: color,
      );
}

/// The only place the session is written, and the only source of the device install id.
///
/// Both tokens live in the platform keystore/keychain. The access token is mirrored in memory
/// ([cachedAccessToken]) so the Dio interceptor can attach one without an async read per request.
class CredentialStore {
  CredentialStore({FlutterSecureStorage? storage, Uuid? uuid})
        // The package's defaults are the hardened ones in v11 (AES-GCM with RSA-OAEP key
        // wrapping on Android, the keychain on iOS); naming them here would only risk drift.
      : _storage = storage ?? const FlutterSecureStorage(),
        _uuid = uuid ?? const Uuid();

  final FlutterSecureStorage _storage;
  final Uuid _uuid;

  StaffSession? _cached;
  bool _loaded = false;

  StaffSession? get cached => _cached;
  String? get cachedAccessToken => _cached?.accessToken;
  String? get cachedRefreshToken => _cached?.refreshToken;
  bool get hasSession => _cached != null;

  Future<StaffSession?> load() async {
    if (_loaded) return _cached;
    final all = await _storage.readAll();
    _loaded = true;
    final accessToken = all[_kAccessToken];
    final refreshToken = all[_kRefreshToken];
    final terminalId = all[_kTerminalId];
    if (accessToken == null || refreshToken == null || terminalId == null) {
      _cached = null;
      return null;
    }
    _cached = StaffSession(
      accessToken: accessToken,
      // A missing or unparsable expiry is treated as already due, so the app refreshes rather
      // than sending a token it cannot reason about.
      accessTokenExpiresAt:
          DateTime.tryParse(all[_kAccessExpiresAt] ?? '')?.toLocal() ?? DateTime.now(),
      refreshToken: refreshToken,
      terminalId: terminalId,
      terminalCode: all[_kTerminalCode] ?? '',
      terminalName: all[_kTerminalName] ?? '',
      businessId: all[_kBusinessId] ?? '',
      branchId: all[_kBranchId] ?? '',
      staffId: all[_kStaffId] ?? '',
      staffName: all[_kStaffName] ?? '',
      canTakeOverTables: all[_kCanTakeOver] == 'true',
      themeColor: all[_kThemeColor],
    );
    return _cached;
  }

  Future<void> save(StaffSession session) async {
    await Future.wait([
      _storage.write(key: _kAccessToken, value: session.accessToken),
      _storage.write(key: _kAccessExpiresAt, value: session.accessTokenExpiresAt.toIso8601String()),
      _storage.write(key: _kRefreshToken, value: session.refreshToken),
      _storage.write(key: _kTerminalId, value: session.terminalId),
      _storage.write(key: _kTerminalCode, value: session.terminalCode),
      _storage.write(key: _kTerminalName, value: session.terminalName),
      _storage.write(key: _kBusinessId, value: session.businessId),
      _storage.write(key: _kBranchId, value: session.branchId),
      _storage.write(key: _kStaffId, value: session.staffId),
      _storage.write(key: _kStaffName, value: session.staffName),
      _storage.write(key: _kCanTakeOver, value: session.canTakeOverTables.toString()),
      // A null value removes the key, so a previous branch's colour does not linger.
      _storage.write(key: _kThemeColor, value: session.themeColor),
    ]);
    _cached = session;
    _loaded = true;
  }

  /// Persists a rotated pair. Written before the new token is used, so a crash mid-refresh
  /// leaves the handset holding the token the server now expects rather than a dead one.
  Future<void> saveRotatedTokens({
    required String accessToken,
    required DateTime accessTokenExpiresAt,
    required String refreshToken,
    String? staffName,
    bool? canTakeOverTables,
  }) async {
    final current = _cached;
    if (current == null) return;
    await save(current.copyWith(
      accessToken: accessToken,
      accessTokenExpiresAt: accessTokenExpiresAt,
      refreshToken: refreshToken,
      staffName: staffName,
      canTakeOverTables: canTakeOverTables,
    ));
  }

  /// Remembers the colour `staff-app/config` reported, for the next launch. Writes that one key
  /// only: rewriting the whole session here could put back a token a refresh had just rotated.
  /// Ignored when [branchId] is no longer the signed-in branch.
  Future<void> saveThemeColor({required String branchId, required String? color}) async {
    final current = _cached;
    if (current == null || current.branchId != branchId || current.themeColor == color) return;
    await _storage.write(key: _kThemeColor, value: color);
    final latest = _cached;
    if (latest != null && latest.branchId == branchId) _cached = latest.withThemeColor(color);
  }

  /// Signing out for good. The device install id is deliberately kept: signing back in on the
  /// same phone should find its own terminal again rather than consume a second one.
  Future<void> clear() async {
    final deviceInstallId = await _storage.read(key: _kDeviceInstallId);
    await _storage.deleteAll();
    if (deviceInstallId != null) {
      await _storage.write(key: _kDeviceInstallId, value: deviceInstallId);
    }
    _cached = null;
    _loaded = true;
  }

  /// Stable per-install UUID, sent as `pos_terminals.device_install_id` and required on every
  /// refresh so a token lifted onto another phone cannot be redeemed.
  Future<String> deviceInstallId() async {
    final existing = await _storage.read(key: _kDeviceInstallId);
    if (existing != null && existing.isNotEmpty) return existing;
    final generated = _uuid.v4();
    await _storage.write(key: _kDeviceInstallId, value: generated);
    return generated;
  }

  static const _kAccessToken = 'staff_app_access_token';
  static const _kAccessExpiresAt = 'staff_app_access_expires_at';
  static const _kRefreshToken = 'staff_app_refresh_token';
  static const _kTerminalId = 'terminal_id';
  static const _kTerminalCode = 'terminal_code';
  static const _kTerminalName = 'terminal_name';
  static const _kBusinessId = 'business_id';
  static const _kBranchId = 'branch_id';
  static const _kStaffId = 'staff_id';
  static const _kStaffName = 'staff_name';
  static const _kCanTakeOver = 'can_take_over_tables';
  static const _kThemeColor = 'branch_theme_color';
  static const _kDeviceInstallId = 'device_install_id';
}
