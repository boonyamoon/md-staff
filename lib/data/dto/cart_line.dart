import 'package:collection/collection.dart';

import 'menu_dto.dart';

/// One chosen option on a cart line.
class CartOption {
  const CartOption({
    required this.optionGroupId,
    required this.optionId,
    required this.optionName,
    required this.groupName,
    required this.priceAdjustment,
    this.quantity = 1,
  });

  final String optionGroupId;
  final String optionId;
  final String optionName;
  final String groupName;
  final num priceAdjustment;
  final int quantity;

  num get total => priceAdjustment * quantity;

  Map<String, dynamic> toRequestJson() => {
        'option_group_id': optionGroupId,
        'option_id': optionId,
        'option_name': optionName,
        'quantity': quantity,
      };
}

/// A line in the handset's local cart, before it is sent to the kitchen.
///
/// Nothing here is authoritative: the prices are what the menu showed, and the server re-resolves
/// every one of them when the round is sent. They exist so a waiter can read a total to a guest.
class CartLine {
  CartLine({
    required this.lineId,
    required this.productId,
    required this.productName,
    required this.sku,
    required this.quantity,
    this.note,
    this.options = const <CartOption>[],
    this.imageUrl,
  });

  final String lineId;
  final String productId;
  final String productName;
  final MenuSku sku;
  final int quantity;
  final String? note;
  final List<CartOption> options;
  final String? imageUrl;

  num get unitPrice => sku.defaultPrice + options.fold<num>(0, (sum, o) => sum + o.total);

  num get lineTotal => unitPrice * quantity;

  /// Two lines merge only when the product, SKU, options and note all match — otherwise "no
  /// chilli" on one of three identical bowls would be lost.
  String get mergeKey {
    final optionKey = (options.map((o) => '${o.optionId}:${o.quantity}').toList()..sort()).join(',');
    return '$productId|${sku.id}|$optionKey|${note ?? ''}';
  }

  CartLine copyWith({int? quantity, String? note, List<CartOption>? options}) => CartLine(
        lineId: lineId,
        productId: productId,
        productName: productName,
        sku: sku,
        quantity: quantity ?? this.quantity,
        note: note ?? this.note,
        options: options ?? this.options,
        imageUrl: imageUrl,
      );

  Map<String, dynamic> toRequestJson() => {
        'product_id': productId,
        'sku_id': sku.id,
        'product_name': productName,
        'sku_name': sku.skuName,
        'quantity': quantity,
        'unit_price': sku.defaultPrice,
        if (note != null && note!.isNotEmpty) 'note': note,
        'selected_options': options.map((o) => o.toRequestJson()).toList(),
      };
}

extension CartLineListX on List<CartLine> {
  num get total => fold<num>(0, (sum, line) => sum + line.lineTotal);

  int get itemCount => fold<int>(0, (sum, line) => sum + line.quantity);

  CartLine? firstMatching(String mergeKey) => firstWhereOrNull((l) => l.mergeKey == mergeKey);
}
