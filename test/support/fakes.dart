import 'dart:convert';

import 'package:md_staff/core/storage/credential_store.dart';
import 'package:md_staff/data/local/local_cache.dart';
import 'package:md_staff/data/repositories/floor_repository.dart';
import 'package:md_staff/data/repositories/menu_repository.dart';
import 'package:md_staff/features/bootstrap/session_controller.dart';
import 'package:mocktail/mocktail.dart';

class MockFloorRepository extends Mock implements FloorRepository {}

class MockMenuRepository extends Mock implements MenuRepository {}

/// The offline cache without a disk. Entries pass through JSON, as they would in a file.
class MemoryLocalCache implements LocalCache {
  final files = <String, ({String branchId, CacheEntry entry})>{};

  @override
  Future<CacheEntry?> read(String name, {required String branchId}) async {
    final file = files[name];
    return file == null || file.branchId != branchId ? null : file.entry;
  }

  @override
  Future<void> write(String name, CacheEntry entry, {required String branchId}) async {
    files[name] = (
      branchId: branchId,
      entry: CacheEntry(
        data: jsonDecode(jsonEncode(entry.data)) as Object,
        fetchedAt: entry.fetchedAt,
        etag: entry.etag,
      ),
    );
  }

  @override
  Future<void> clear() async => files.clear();
}

const testBranch = 'b1';

StaffSession testStaffSession() => StaffSession(
      accessToken: 'a',
      accessTokenExpiresAt: DateTime(2030),
      refreshToken: 'r',
      terminalId: 't1',
      terminalCode: 'S01',
      terminalName: 'Handset 1',
      businessId: 'biz',
      branchId: testBranch,
      staffId: 's1',
      staffName: 'Nok',
    );

/// A handset signed in to [testBranch], without the keystore or API client the real one opens.
class SignedInSession extends AppSessionController {
  @override
  AppSession build() => AppSession(phase: AppPhase.ready, session: testStaffSession());
}

/// A `staff-app/zones` row for one table.
Map<String, dynamic> tableJson(
  String id, {
  String? foodStatus,
  String sessionStatus = 'OPEN',
  String status = 'AVAILABLE',
  bool? heldByMe,
}) =>
    {
      'floor_item_id': id,
      'label': id,
      'capacity': 4,
      'status': status,
      if (foodStatus != null)
        'session': {
          'session_id': 'session-$id',
          'status': sessionStatus,
          'opened_at': '2026-01-01T00:00:00Z',
          'item_count': foodStatus == 'NOT_ORDERED' ? 0 : 2,
          'food_status': foodStatus,
        },
      if (heldByMe != null)
        'claim': {
          'is_mine': heldByMe,
          'lease_token': heldByMe ? 'secret-lease' : null,
          'expires_at': '2026-01-01T00:00:00Z',
          'holder': {
            'terminal_id': 't2',
            'terminal_code': 'S02',
            'terminal_name': 'Handset 2',
            'staff_id': 's2',
            'staff_name': 'Dao',
          },
        },
    };

/// A `staff-app/menu/snapshot` document: two categories, three dishes, one with options.
Map<String, dynamic> menuJson() => {
      'categories': [
        {'id': 'c1', 'category_name': 'Noodles'},
        {'id': 'c2', 'category_name': 'Drinks'},
      ],
      'products': [
        _product('p1', 'Pad Thai', 'c1', optionGroups: [
          {
            'id': 'g1',
            'group_name': 'Spice',
            'options': [
              {'id': 'o1', 'option_name': 'Hot'},
            ],
          },
        ]),
        _product('p2', 'Boat noodles', 'c1'),
        _product('p3', 'Thai tea', 'c2'),
      ],
    };

Map<String, dynamic> _product(
  String id,
  String name,
  String category, {
  List<Map<String, dynamic>> optionGroups = const [],
}) =>
    {
      'id': id,
      'product_name': name,
      'category_id': category,
      'is_available': true,
      'skus': [
        {'id': '$id-sku', 'sku_name': 'Regular', 'default_price': 50, 'is_default': true},
      ],
      'option_group_assignments': [
        for (final group in optionGroups) {'option_group_id': group['id']},
      ],
      'option_groups': optionGroups,
    };
