import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// What pairing and sign-in leave on the handset.
class StoredCredentials {
  const StoredCredentials({
    required this.deviceToken,
    required this.terminalId,
    required this.terminalCode,
    required this.terminalName,
    required this.businessId,
    required this.branchId,
    this.shiftToken,
    this.staffId,
    this.staffName,
    this.canTakeOverTables = false,
  });

  final String deviceToken;
  final String terminalId;
  final String terminalCode;
  final String terminalName;
  final String businessId;
  final String branchId;

  /// Null between shifts: the handset is paired but nobody is signed in.
  final String? shiftToken;
  final String? staffId;
  final String? staffName;
  final bool canTakeOverTables;

  bool get hasShift => shiftToken != null && shiftToken!.isNotEmpty;

  StoredCredentials copyWith({
    String? deviceToken,
    String? shiftToken,
    String? staffId,
    String? staffName,
    bool? canTakeOverTables,
    bool clearShift = false,
  }) =>
      StoredCredentials(
        deviceToken: deviceToken ?? this.deviceToken,
        terminalId: terminalId,
        terminalCode: terminalCode,
        terminalName: terminalName,
        businessId: businessId,
        branchId: branchId,
        shiftToken: clearShift ? null : (shiftToken ?? this.shiftToken),
        staffId: clearShift ? null : (staffId ?? this.staffId),
        staffName: clearShift ? null : (staffName ?? this.staffName),
        canTakeOverTables: clearShift ? false : (canTakeOverTables ?? this.canTakeOverTables),
      );
}

/// The only place tokens are written, and the only place the device install id comes from.
///
/// Both tokens live in the platform keystore/keychain. They are also mirrored in memory
/// ([cachedDeviceToken], [cachedShiftToken]) so the Dio interceptor can attach one without an
/// async read on every request — the same reason the kiosk app caches its token.
class CredentialStore {
  CredentialStore({FlutterSecureStorage? storage, Uuid? uuid})
        // The package's defaults are the hardened ones in v11 (AES-GCM with RSA-OAEP key
        // wrapping on Android, the keychain on iOS); naming them here would only risk drift.
      : _storage = storage ?? const FlutterSecureStorage(),
        _uuid = uuid ?? const Uuid();

  final FlutterSecureStorage _storage;
  final Uuid _uuid;

  StoredCredentials? _cached;
  bool _loaded = false;

  String? get cachedDeviceToken => _cached?.deviceToken;
  String? get cachedShiftToken => _cached?.shiftToken;
  StoredCredentials? get cached => _cached;

  Future<StoredCredentials?> load() async {
    if (_loaded) return _cached;
    final all = await _storage.readAll();
    _loaded = true;
    final deviceToken = all[_kDeviceToken];
    final terminalId = all[_kTerminalId];
    if (deviceToken == null || deviceToken.isEmpty || terminalId == null) {
      _cached = null;
      return null;
    }
    _cached = StoredCredentials(
      deviceToken: deviceToken,
      terminalId: terminalId,
      terminalCode: all[_kTerminalCode] ?? '',
      terminalName: all[_kTerminalName] ?? '',
      businessId: all[_kBusinessId] ?? '',
      branchId: all[_kBranchId] ?? '',
      shiftToken: all[_kShiftToken],
      staffId: all[_kStaffId],
      staffName: all[_kStaffName],
      canTakeOverTables: all[_kCanTakeOver] == 'true',
    );
    return _cached;
  }

  Future<void> savePairing(StoredCredentials credentials) async {
    await Future.wait([
      _storage.write(key: _kDeviceToken, value: credentials.deviceToken),
      _storage.write(key: _kTerminalId, value: credentials.terminalId),
      _storage.write(key: _kTerminalCode, value: credentials.terminalCode),
      _storage.write(key: _kTerminalName, value: credentials.terminalName),
      _storage.write(key: _kBusinessId, value: credentials.businessId),
      _storage.write(key: _kBranchId, value: credentials.branchId),
    ]);
    // Pairing to a (possibly different) terminal ends any shift the handset was in.
    await clearShift();
    _cached = credentials.copyWith(clearShift: true);
    _loaded = true;
  }

  Future<void> saveDeviceToken(String token) async {
    await _storage.write(key: _kDeviceToken, value: token);
    _cached = _cached?.copyWith(deviceToken: token);
  }

  Future<void> saveShift({
    required String shiftToken,
    required String staffId,
    required String staffName,
    required bool canTakeOverTables,
  }) async {
    await Future.wait([
      _storage.write(key: _kShiftToken, value: shiftToken),
      _storage.write(key: _kStaffId, value: staffId),
      _storage.write(key: _kStaffName, value: staffName),
      _storage.write(key: _kCanTakeOver, value: canTakeOverTables.toString()),
    ]);
    _cached = _cached?.copyWith(
      shiftToken: shiftToken,
      staffId: staffId,
      staffName: staffName,
      canTakeOverTables: canTakeOverTables,
    );
  }

  Future<void> clearShift() async {
    await Future.wait([
      _storage.delete(key: _kShiftToken),
      _storage.delete(key: _kStaffId),
      _storage.delete(key: _kStaffName),
      _storage.delete(key: _kCanTakeOver),
    ]);
    _cached = _cached?.copyWith(clearShift: true);
  }

  /// Unpairs the handset. The device install id is deliberately kept: re-pairing the same phone
  /// should find its old terminal again instead of consuming a second one.
  Future<void> clearPairing() async {
    final deviceInstallId = await _storage.read(key: _kDeviceInstallId);
    await _storage.deleteAll();
    if (deviceInstallId != null) {
      await _storage.write(key: _kDeviceInstallId, value: deviceInstallId);
    }
    _cached = null;
    _loaded = true;
  }

  /// Stable per-install UUID, sent as `pos_terminals.device_install_id`.
  Future<String> deviceInstallId() async {
    final existing = await _storage.read(key: _kDeviceInstallId);
    if (existing != null && existing.isNotEmpty) return existing;
    final generated = _uuid.v4();
    await _storage.write(key: _kDeviceInstallId, value: generated);
    return generated;
  }

  static const _kDeviceToken = 'staff_app_device_token';
  static const _kShiftToken = 'staff_app_shift_token';
  static const _kTerminalId = 'terminal_id';
  static const _kTerminalCode = 'terminal_code';
  static const _kTerminalName = 'terminal_name';
  static const _kBusinessId = 'business_id';
  static const _kBranchId = 'branch_id';
  static const _kStaffId = 'staff_id';
  static const _kStaffName = 'staff_name';
  static const _kCanTakeOver = 'can_take_over_tables';
  static const _kDeviceInstallId = 'device_install_id';
}
