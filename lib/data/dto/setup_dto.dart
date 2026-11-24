import 'json.dart';

/// A branch this account may set a handset up for, from
/// `GET /api/v1/branches-access/snapshot?platform=staff_app`.
class BranchOption {
  const BranchOption({required this.id, required this.name, this.businessName});

  final String id;
  final String name;
  final String? businessName;
}

/// The snapshot, reduced to what the setup screen shows: the branches this account can pair for,
/// and whether it was POS access (`allow_pos_login`) that filtered them all out.
class StaffAppAccess {
  const StaffAppAccess({required this.branches, required this.deniedByPermission});

  final List<BranchOption> branches;
  final bool deniedByPermission;

  factory StaffAppAccess.fromSnapshot(Map<String, dynamic> json) {
    final activeBranchIds = <String>{
      for (final a in asList(json['user_branch_assignments'], (m) => m))
        if (asBool(a['is_active'], fallback: true)) asString(a['branch_id']).toLowerCase(),
    };
    final businessNames = <String, String?>{
      for (final b in asList(json['businesses'], (m) => m))
        asString(b['id']): asStringOrNull(b['business_name']),
    };
    final branches = <BranchOption>[
      for (final b in asList(json['branches'], (m) => m))
        if (activeBranchIds.contains(asString(b['id']).toLowerCase()))
          BranchOption(
            id: asString(b['id']),
            name: asStringOrNull(b['branch_name']) ?? asString(b['id']),
            businessName: businessNames[asString(b['business_id'])],
          ),
    ]..sort((a, b) {
      final byBusiness = (a.businessName ?? '').compareTo(b.businessName ?? '');
      return byBusiness != 0 ? byBusiness : a.name.compareTo(b.name);
    });
    return StaffAppAccess(
      branches: branches,
      deniedByPermission: asBool(json['platform_filtered']),
    );
  }
}

/// `GET /api/v1/staff-app/pairing/terminals?branch_id=…`
class PairingTerminal {
  const PairingTerminal({
    required this.terminalId,
    required this.terminalCode,
    required this.terminalName,
    required this.isPaired,
    this.deviceName,
  });

  final String terminalId;
  final String terminalCode;
  final String terminalName;
  final bool isPaired;
  final String? deviceName;

  factory PairingTerminal.fromJson(Map<String, dynamic> json) => PairingTerminal(
        terminalId: asString(json['terminal_id']),
        terminalCode: asString(json['terminal_code']),
        terminalName: asString(json['terminal_name']),
        isPaired: asBool(json['is_paired']),
        deviceName: asStringOrNull(json['device_name']),
      );
}

/// `POST /api/v1/staff-app/pair`
class PairResult {
  const PairResult({
    required this.terminalId,
    required this.terminalCode,
    required this.terminalName,
    required this.businessId,
    required this.branchId,
    required this.deviceToken,
    required this.deviceTokenExpiresAt,
  });

  final String terminalId;
  final String terminalCode;
  final String terminalName;
  final String businessId;
  final String branchId;
  final String deviceToken;
  final String deviceTokenExpiresAt;

  factory PairResult.fromJson(Map<String, dynamic> json) => PairResult(
        terminalId: asString(json['terminal_id']),
        terminalCode: asString(json['terminal_code']),
        terminalName: asString(json['terminal_name']),
        businessId: asString(json['business_id']),
        branchId: asString(json['branch_id']),
        deviceToken: asString(json['device_token']),
        deviceTokenExpiresAt: asString(json['device_token_expires_at']),
      );
}
