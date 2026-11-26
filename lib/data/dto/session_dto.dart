import 'json.dart';

class StaffProfile {
  const StaffProfile({
    required this.staffId,
    required this.staffName,
    this.username,
    this.position,
    this.canTakeOverTables = false,
  });

  final String staffId;
  final String staffName;
  final String? username;
  final String? position;

  /// Whether this account may take a table another handset is holding.
  final bool canTakeOverTables;

  factory StaffProfile.fromJson(Map<String, dynamic> json) => StaffProfile(
        staffId: asString(json['staff_id']),
        staffName: asString(json['staff_name']),
        username: asStringOrNull(json['username']),
        position: asStringOrNull(json['position']),
        canTakeOverTables: asBool(json['can_take_over_tables']),
      );
}

class TerminalInfo {
  const TerminalInfo({
    required this.terminalId,
    required this.terminalCode,
    required this.terminalName,
    this.businessId,
    this.branchId,
  });

  final String terminalId;
  final String terminalCode;
  final String terminalName;
  final String? businessId;
  final String? branchId;

  factory TerminalInfo.fromJson(Map<String, dynamic> json) => TerminalInfo(
        terminalId: asString(json['terminal_id']),
        terminalCode: asString(json['terminal_code']),
        terminalName: asString(json['terminal_name']),
        businessId: asStringOrNull(json['business_id']),
        branchId: asStringOrNull(json['branch_id']),
      );
}

/// What `POST /api/v1/staff-app/login` and `/token/refresh` both answer with.
///
/// The sign-in is permanent: there is no expiry on the session itself, only on the access token,
/// which the app replaces silently. `refreshTokenExpiresAt` is the abandoned-handset cutoff and
/// rolls forward on every refresh.
class StaffAppSession {
  const StaffAppSession({
    required this.accessToken,
    required this.accessTokenExpiresAt,
    required this.refreshToken,
    required this.refreshTokenExpiresAt,
    required this.staff,
    required this.terminal,
  });

  final String accessToken;
  final DateTime accessTokenExpiresAt;
  final String refreshToken;
  final DateTime refreshTokenExpiresAt;
  final StaffProfile staff;
  final TerminalInfo terminal;

  factory StaffAppSession.fromJson(Map<String, dynamic> json) => StaffAppSession(
        accessToken: asString(json['access_token']),
        // A missing or unparsable expiry is treated as already due, so the app refreshes rather
        // than sending a token it cannot reason about.
        accessTokenExpiresAt:
            DateTime.tryParse(asString(json['access_token_expires_at']))?.toLocal() ?? DateTime.now(),
        refreshToken: asString(json['refresh_token']),
        refreshTokenExpiresAt:
            DateTime.tryParse(asString(json['refresh_token_expires_at']))?.toLocal() ??
                DateTime.now(),
        staff: StaffProfile.fromJson(asMapOrNull(json['staff']) ?? const {}),
        terminal: TerminalInfo.fromJson(asMapOrNull(json['terminal']) ?? const {}),
      );
}

class BranchConfig {
  const BranchConfig({
    required this.businessId,
    required this.branchId,
    required this.branchName,
    required this.businessName,
    this.branchCode = '',
    this.logoUrl,
    this.currency = 'THB',
    this.taxRate = 0,
    this.taxIncluded = true,
    this.serviceChargeRate = 0,
    this.timeZone = 'Asia/Bangkok',
    this.themeColor,
    this.reportsThemeColor = false,
  });

  final String businessId;
  final String branchId;
  final String branchName;
  final String businessName;
  final String branchCode;
  final String? logoUrl;
  final String currency;
  final num taxRate;
  final bool taxIncluded;
  final num serviceChargeRate;
  final String timeZone;

  /// `#RRGGBB`, or null when the branch has none.
  final String? themeColor;

  /// Whether the server sent `theme_color` at all. A server without the field says nothing about
  /// the colour, which must not be read as "this branch has none".
  final bool reportsThemeColor;

  factory BranchConfig.fromJson(Map<String, dynamic> json) => BranchConfig(
        businessId: asString(json['business_id']),
        branchId: asString(json['branch_id']),
        branchName: asString(json['branch_name']),
        businessName: asString(json['business_name']),
        branchCode: asString(json['branch_code']),
        logoUrl: asStringOrNull(json['logo_url']),
        currency: asString(json['currency'], fallback: 'THB'),
        taxRate: asNum(json['tax_rate']),
        taxIncluded: asBool(json['tax_included'], fallback: true),
        serviceChargeRate: asNum(json['service_charge_rate']),
        timeZone: asString(json['time_zone'], fallback: 'Asia/Bangkok'),
        themeColor: asStringOrNull(json['theme_color']),
        reportsThemeColor: json.containsKey('theme_color'),
      );
}

class OrderingConfig {
  const OrderingConfig({
    this.paymentAtPosOnly = true,
    this.kitchenPrintingEnabled = true,
    this.claimLeaseMs = 180000,
    this.claimRenewAfterMs = 60000,
  });

  /// Always true. The server states it so the app can tell staff where to pay.
  final bool paymentAtPosOnly;

  /// False when the shop has no order-slip printer: rounds still reach the kitchen screen, but no
  /// paper comes out of the POS.
  final bool kitchenPrintingEnabled;
  final int claimLeaseMs;
  final int claimRenewAfterMs;

  Duration get renewInterval => Duration(milliseconds: claimRenewAfterMs);

  factory OrderingConfig.fromJson(Map<String, dynamic> json) => OrderingConfig(
        paymentAtPosOnly: asBool(json['payment_at_pos_only'], fallback: true),
        kitchenPrintingEnabled: asBool(json['kitchen_printing_enabled'], fallback: true),
        claimLeaseMs: asInt(json['claim_lease_ms'], fallback: 180000),
        claimRenewAfterMs: asInt(json['claim_renew_after_ms'], fallback: 60000),
      );
}

/// `GET /api/v1/staff-app/config`
class StaffAppConfig {
  const StaffAppConfig({required this.terminal, required this.branch, required this.ordering});

  final TerminalInfo terminal;
  final BranchConfig branch;
  final OrderingConfig ordering;

  factory StaffAppConfig.fromJson(Map<String, dynamic> json) => StaffAppConfig(
        terminal: TerminalInfo.fromJson(asMapOrNull(json['terminal']) ?? const {}),
        branch: BranchConfig.fromJson(asMapOrNull(json['branch']) ?? const {}),
        ordering: OrderingConfig.fromJson(asMapOrNull(json['ordering']) ?? const {}),
      );
}
