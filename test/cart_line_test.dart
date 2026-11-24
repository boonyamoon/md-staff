import 'package:flutter_test/flutter_test.dart';
import 'package:md_staff/data/dto/cart_line.dart';
import 'package:md_staff/data/dto/menu_dto.dart';

const _sku = MenuSku(id: 'sku-1', skuName: 'Regular', defaultPrice: 100);
const _largeSku = MenuSku(id: 'sku-2', skuName: 'Large', defaultPrice: 130);

CartLine line({
  String lineId = 'l1',
  String productId = 'p1',
  MenuSku sku = _sku,
  int quantity = 1,
  String? note,
  List<CartOption> options = const <CartOption>[],
}) =>
    CartLine(
      lineId: lineId,
      productId: productId,
      productName: 'Pad Thai',
      sku: sku,
      quantity: quantity,
      note: note,
      options: options,
    );

const _extraShot = CartOption(
  optionGroupId: 'g1',
  optionId: 'o1',
  optionName: 'Extra shot',
  groupName: 'Add-ons',
  priceAdjustment: 15,
);
const _noChilli = CartOption(
  optionGroupId: 'g2',
  optionId: 'o2',
  optionName: 'No chilli',
  groupName: 'Spice',
  priceAdjustment: 0,
);

void main() {
  group('pricing', () {
    test('a line with no options costs the SKU price times the quantity', () {
      expect(line(quantity: 3).lineTotal, 300);
    });

    test('option adjustments are added per unit, not once per line', () {
      final withOption = line(quantity: 2, options: const [_extraShot]);
      expect(withOption.unitPrice, 115);
      expect(withOption.lineTotal, 230);
    });

    test('an option chosen more than once multiplies its adjustment', () {
      const twice = CartOption(
        optionGroupId: 'g1',
        optionId: 'o1',
        optionName: 'Extra shot',
        groupName: 'Add-ons',
        priceAdjustment: 15,
        quantity: 2,
      );
      expect(line(options: const [twice]).unitPrice, 130);
    });
  });

  group('merging', () {
    test('two identical lines share a merge key', () {
      expect(line(lineId: 'a').mergeKey, line(lineId: 'b').mergeKey);
    });

    test('a different SKU does not merge', () {
      expect(line(sku: _sku).mergeKey, isNot(line(sku: _largeSku).mergeKey));
    });

    test('a different note does not merge — "no chilli" must not be lost', () {
      expect(line().mergeKey, isNot(line(note: 'no chilli').mergeKey));
    });

    test('the same options in a different order still merge', () {
      final first = line(options: const [_extraShot, _noChilli]);
      final second = line(options: const [_noChilli, _extraShot]);
      expect(first.mergeKey, second.mergeKey);
    });

    test('a different option set does not merge', () {
      expect(line(options: const [_extraShot]).mergeKey, isNot(line().mergeKey));
    });
  });

  group('request payload', () {
    test('sends the sku, quantity and options the server needs', () {
      final json = line(quantity: 2, options: const [_extraShot], note: 'spicy').toRequestJson();
      expect(json['sku_id'], 'sku-1');
      expect(json['quantity'], 2);
      expect(json['note'], 'spicy');
      expect(json['selected_options'], [
        {'option_group_id': 'g1', 'option_id': 'o1', 'option_name': 'Extra shot', 'quantity': 1},
      ]);
    });

    test('omits an empty note rather than sending an empty string', () {
      expect(line().toRequestJson().containsKey('note'), isFalse);
    });

    test('never sends a seat_letter — a waiter orders for the table, not a seat', () {
      expect(line().toRequestJson().containsKey('seat_letter'), isFalse);
    });
  });

  group('totals', () {
    test('sums line totals and counts every unit', () {
      final cart = [line(lineId: 'a', quantity: 2), line(lineId: 'b', sku: _largeSku)];
      expect(cart.total, 330);
      expect(cart.itemCount, 3);
    });

    test('an empty cart totals zero', () {
      expect(<CartLine>[].total, 0);
      expect(<CartLine>[].itemCount, 0);
    });
  });
}
