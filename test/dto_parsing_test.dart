import 'package:flutter_test/flutter_test.dart';
import 'package:md_staff/data/dto/floor_dto.dart';
import 'package:md_staff/data/dto/menu_dto.dart';
import 'package:md_staff/data/dto/order_dto.dart';
import 'package:md_staff/data/dto/setup_dto.dart';

void main() {
  group('FloorTable', () {
    test('reads a free table', () {
      final table = FloorTable.fromJson({
        'floor_item_id': 'f1',
        'label': 'A1',
        'status': 'AVAILABLE',
        'capacity': 4,
      });
      expect(table.isOccupied, isFalse);
      expect(table.isHeldByMe, isFalse);
      expect(table.isHeldByOther, isFalse);
      expect(table.capacity, 4);
    });

    test('a claim of ours carries its lease token', () {
      final table = FloorTable.fromJson({
        'floor_item_id': 'f1',
        'label': 'A1',
        'claim': {
          'is_mine': true,
          'lease_token': 'lease-1',
          'expires_at': '2026-01-01T00:00:00Z',
          'holder': {
            'terminal_id': 't1',
            'terminal_code': 'S01',
            'terminal_name': 'Handset 1',
            'staff_id': 's1',
            'staff_name': 'Nok',
          },
        },
      });
      expect(table.isHeldByMe, isTrue);
      expect(table.claim!.leaseToken, 'lease-1');
    });

    test("another handset's claim names the holder but carries no lease token", () {
      final table = FloorTable.fromJson({
        'floor_item_id': 'f1',
        'label': 'A1',
        'claim': {
          'is_mine': false,
          'lease_token': null,
          'expires_at': '2026-01-01T00:00:00Z',
          'holder': {
            'terminal_id': 't2',
            'terminal_code': 'S02',
            'terminal_name': 'Handset 2',
            'staff_id': 's2',
            'staff_name': 'Dao',
          },
        },
      });
      expect(table.isHeldByOther, isTrue);
      expect(table.claim!.leaseToken, isNull);
      expect(table.claim!.holder.staffName, 'Dao');
    });

    test('a table being paid for at the POS is flagged, not treated as free', () {
      final table = FloorTable.fromJson({
        'floor_item_id': 'f1',
        'label': 'A1',
        'status': 'PENDING_PAYMENT',
        'session': {
          'session_id': 'sess-1',
          'status': 'PENDING_PAYMENT',
          'opened_at': '2026-01-01T00:00:00Z',
          'item_count': 3,
          'total_amount': 450,
        },
      });
      expect(table.isOccupied, isTrue);
      expect(table.session!.isPendingPayment, isTrue);
      expect(table.session!.totalAmount, 450);
    });

    test('missing optional fields fall back instead of throwing', () {
      final table = FloorTable.fromJson({'floor_item_id': 'f1', 'label': 'A1'});
      expect(table.status, 'AVAILABLE');
      expect(table.itemType, 'TABLE');
      expect(table.capacity, isNull);
      expect(table.session, isNull);
      expect(table.claim, isNull);
    });
  });

  group('FloorZone', () {
    test('counts free tables from the totals the server sent', () {
      final zone = FloorZone.fromJson({
        'zone_id': 'z1',
        'zone_name': 'Terrace',
        'table_count': 8,
        'occupied_count': 3,
        'tables': [
          {'floor_item_id': 'f1', 'label': 'A1'},
          {'floor_item_id': 'f2', 'label': 'A2'},
        ],
      });
      expect(zone.freeCount, 5);
      expect(zone.tables, hasLength(2));
    });

    test('a malformed tables entry is skipped rather than failing the zone', () {
      final zone = FloorZone.fromJson({
        'zone_id': 'z1',
        'zone_name': 'Terrace',
        'tables': [
          'not an object',
          {'floor_item_id': 'f1', 'label': 'A1'},
        ],
      });
      expect(zone.tables, hasLength(1));
    });
  });

  group('TableClaim', () {
    test('reads the renew interval the server set', () {
      final claim = TableClaim.fromJson({
        'floor_item_id': 'f1',
        'lease_token': 'lease-1',
        'expires_at': '2026-01-01T00:00:00Z',
        'renew_after_ms': 45000,
      });
      expect(claim.renewInterval, const Duration(milliseconds: 45000));
      expect(claim.tookOverFrom, isNull);
    });

    test('a takeover reports who the table came from', () {
      final claim = TableClaim.fromJson({
        'floor_item_id': 'f1',
        'lease_token': 'lease-2',
        'expires_at': '2026-01-01T00:00:00Z',
        'took_over_from': {
          'terminal_id': 't2',
          'terminal_code': 'S02',
          'terminal_name': 'Handset 2',
          'staff_id': 's2',
          'staff_name': 'Dao',
        },
      });
      expect(claim.tookOverFrom!.staffName, 'Dao');
    });
  });

  group('TableOrder', () {
    final order = TableOrder.fromJson({
      'order_id': 'o1',
      'order_number': 'ST-ABCD1234',
      'status': 'HELD',
      'total_amount': 310,
      'lines': [
        {
          'order_item_id': 'i1',
          'sku_id': 'sku-1',
          'product_name': 'Pad Thai',
          'quantity': 2,
          'line_total': 200,
          'round_number': 1,
        },
        {
          'order_item_id': 'i2',
          'sku_id': 'sku-2',
          'product_name': 'Tom Yum',
          'quantity': 1,
          'line_total': 110,
          'round_number': 2,
        },
        {
          'order_item_id': 'i3',
          'sku_id': 'sku-3',
          'product_name': 'Cancelled dish',
          'quantity': 1,
          'round_number': 1,
          'is_cancelled': true,
        },
      ],
    });

    test('hides cancelled lines from the bill', () {
      expect(order.activeLines, hasLength(2));
    });

    test('groups lines by round, newest first', () {
      expect(order.linesByRound.keys.toList(), [2, 1]);
      expect(order.linesByRound[1], hasLength(1));
    });
  });

  group('PlacedRound', () {
    test('reads a fresh round', () {
      final round = PlacedRound.fromJson({
        'order_id': 'o1',
        'order_number': 'ST-ABCD1234',
        'session_id': 'sess-1',
        'items_added': 3,
        'is_new_order': true,
        'total_amount': 450,
      });
      expect(round.itemsAdded, 3);
      expect(round.isNewOrder, isTrue);
      expect(round.idempotentReplay, isFalse);
    });

    test('flags a retry answered from the ledger', () {
      final round = PlacedRound.fromJson({
        'order_id': 'o1',
        'order_number': 'ST-ABCD1234',
        'session_id': 'sess-1',
        'idempotent_replay': true,
      });
      expect(round.idempotentReplay, isTrue);
    });
  });

  group('MenuProduct', () {
    test('a product with one SKU and no options can be added in one tap', () {
      final product = MenuProduct.fromJson({
        'id': 'p1',
        'product_name': 'Iced tea',
        'skus': [
          {'id': 'sku-1', 'sku_name': 'Regular', 'default_price': 45, 'is_default': true},
        ],
      });
      expect(product.needsChoices, isFalse);
      expect(product.defaultSku!.id, 'sku-1');
    });

    test('options or several SKUs mean the sheet has to open first', () {
      final withOptions = MenuProduct.fromJson({
        'id': 'p1',
        'product_name': 'Coffee',
        'skus': [
          {'id': 'sku-1', 'sku_name': 'Regular', 'default_price': 60},
        ],
        'option_group_assignments': [
          {'option_group_id': 'g1'},
        ],
      });
      expect(withOptions.needsChoices, isTrue);

      final twoSkus = MenuProduct.fromJson({
        'id': 'p2',
        'product_name': 'Noodles',
        'skus': [
          {'id': 'sku-1', 'sku_name': 'Regular', 'default_price': 60},
          {'id': 'sku-2', 'sku_name': 'Large', 'default_price': 80},
        ],
      });
      expect(twoSkus.needsChoices, isTrue);
    });

    test('falls back to the first SKU when none is marked default', () {
      final product = MenuProduct.fromJson({
        'id': 'p1',
        'product_name': 'Noodles',
        'skus': [
          {'id': 'sku-1', 'sku_name': 'Regular', 'default_price': 60},
          {'id': 'sku-2', 'sku_name': 'Large', 'default_price': 80},
        ],
      });
      expect(product.defaultSku!.id, 'sku-1');
    });
  });

  group('ProductOptionGroup', () {
    test('a required single-choice group needs one selection', () {
      final group = ProductOptionGroup.fromJson({
        'id': 'g1',
        'group_name': 'Broth',
        'is_required': true,
        'selection_type': 'SINGLE',
      });
      expect(group.effectiveMin, 1);
      expect(group.isMultiple, isFalse);
    });

    test('an explicit minimum wins over the required flag', () {
      final group = ProductOptionGroup.fromJson({
        'id': 'g1',
        'group_name': 'Toppings',
        'is_required': true,
        'selection_type': 'MULTIPLE',
        'min_selections': 2,
        'max_selections': 3,
      });
      expect(group.effectiveMin, 2);
      expect(group.maxSelections, 3);
      expect(group.isMultiple, isTrue);
    });

    test('an optional group needs nothing', () {
      final group = ProductOptionGroup.fromJson({'id': 'g1', 'group_name': 'Extras'});
      expect(group.effectiveMin, 0);
    });
  });

  group('MenuPage', () {
    test('reads the page and whether more follow', () {
      final page = MenuPage.fromJson({
        'success': true,
        'data': [
          {'id': 'p1', 'product_name': 'A'},
          {'id': 'p2', 'product_name': 'B'},
        ],
        'pagination': {'page': 2, 'has_next_page': true},
      });
      expect(page.products, hasLength(2));
      expect(page.page, 2);
      expect(page.hasNextPage, isTrue);
    });
  });

  group('StaffAppAccess', () {
    test('keeps only branches with an active assignment, named by their business', () {
      final access = StaffAppAccess.fromSnapshot({
        'user_branch_assignments': [
          {'branch_id': 'B1', 'is_active': true},
          {'branch_id': 'b2', 'is_active': false},
        ],
        'branches': [
          {'id': 'b1', 'business_id': 'biz1', 'branch_name': 'Main'},
          {'id': 'b2', 'business_id': 'biz1', 'branch_name': 'Closed one'},
        ],
        'businesses': [
          {'id': 'biz1', 'business_name': 'Som Tam Co'},
        ],
        'platform_filtered': false,
      });
      expect(access.branches, hasLength(1));
      expect(access.branches.single.name, 'Main');
      expect(access.branches.single.businessName, 'Som Tam Co');
      expect(access.deniedByPermission, isFalse);
    });

    test('reports a permission filter so setup can say why the list is empty', () {
      final access = StaffAppAccess.fromSnapshot({
        'user_branch_assignments': <Object>[],
        'branches': <Object>[],
        'businesses': <Object>[],
        'platform_filtered': true,
      });
      expect(access.branches, isEmpty);
      expect(access.deniedByPermission, isTrue);
    });
  });
}
