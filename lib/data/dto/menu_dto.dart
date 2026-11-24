import 'json.dart';

class MenuCategory {
  const MenuCategory({
    required this.id,
    required this.categoryName,
    this.parentCategoryId,
    this.sequence = 0,
    this.colorHex,
  });

  final String id;
  final String categoryName;
  final String? parentCategoryId;
  final int sequence;
  final String? colorHex;

  factory MenuCategory.fromJson(Map<String, dynamic> json) => MenuCategory(
        id: asString(json['id']),
        categoryName: asString(json['category_name']),
        parentCategoryId: asStringOrNull(json['parent_category_id']),
        sequence: asInt(json['sequence']),
        colorHex: asStringOrNull(json['color_hex']),
      );
}

class MenuSku {
  const MenuSku({
    required this.id,
    required this.skuName,
    this.defaultPrice = 0,
    this.isDefault = false,
  });

  final String id;
  final String skuName;
  final num defaultPrice;
  final bool isDefault;

  factory MenuSku.fromJson(Map<String, dynamic> json) => MenuSku(
        id: asString(json['id']),
        skuName: asString(json['sku_name']),
        defaultPrice: asNum(json['default_price']),
        isDefault: asBool(json['is_default']),
      );
}

/// A row in the menu grid. The option-group assignments only say *whether* a product has options;
/// the groups themselves come from the product detail call, as in the kiosk app.
class MenuProduct {
  const MenuProduct({
    required this.id,
    required this.productName,
    this.categoryId,
    this.categoryName,
    this.descriptionText,
    this.imageUrl,
    this.isAvailable = true,
    this.skus = const <MenuSku>[],
    this.optionGroupIds = const <String>[],
  });

  final String id;
  final String productName;
  final String? categoryId;
  final String? categoryName;
  final String? descriptionText;
  final String? imageUrl;
  final bool isAvailable;
  final List<MenuSku> skus;
  final List<String> optionGroupIds;

  bool get hasOptions => optionGroupIds.isNotEmpty;
  bool get hasMultipleSkus => skus.length > 1;

  /// Whether tapping the tile has to open the option sheet, or can add straight to the cart.
  bool get needsChoices => hasOptions || hasMultipleSkus;

  MenuSku? get defaultSku {
    if (skus.isEmpty) return null;
    for (final sku in skus) {
      if (sku.isDefault) return sku;
    }
    return skus.first;
  }

  factory MenuProduct.fromJson(Map<String, dynamic> json) => MenuProduct(
        id: asString(json['id']),
        productName: asString(json['product_name']),
        categoryId: asStringOrNull(json['category_id']),
        categoryName: asStringOrNull(json['category_name']),
        descriptionText: asStringOrNull(json['description_text']),
        imageUrl: asStringOrNull(json['image_url']),
        isAvailable: asBool(json['is_available'], fallback: true),
        skus: asList(json['skus'], MenuSku.fromJson),
        optionGroupIds: <String>[
          for (final a in asList(json['option_group_assignments'], (m) => m))
            asString(a['option_group_id']),
        ],
      );

  MenuProduct copyWith({bool? isAvailable}) => MenuProduct(
        id: id,
        productName: productName,
        categoryId: categoryId,
        categoryName: categoryName,
        descriptionText: descriptionText,
        imageUrl: imageUrl,
        isAvailable: isAvailable ?? this.isAvailable,
        skus: skus,
        optionGroupIds: optionGroupIds,
      );
}

/// One page of `GET /api/v1/staff-app/menu/products`.
class MenuPage {
  const MenuPage({required this.products, required this.hasNextPage, required this.page});

  final List<MenuProduct> products;
  final bool hasNextPage;
  final int page;

  factory MenuPage.fromJson(Map<String, dynamic> json) {
    final pagination = asMapOrNull(json['pagination']) ?? const {};
    return MenuPage(
      products: asList(json['data'], MenuProduct.fromJson),
      hasNextPage: asBool(pagination['has_next_page']),
      page: asInt(pagination['page'], fallback: 1),
    );
  }
}

class ProductOption {
  const ProductOption({
    required this.id,
    required this.optionName,
    this.optionNameEn,
    this.priceAdjustment = 0,
    this.isDefault = false,
    this.sortOrder = 0,
  });

  final String id;
  final String optionName;
  final String? optionNameEn;
  final num priceAdjustment;
  final bool isDefault;
  final int sortOrder;

  factory ProductOption.fromJson(Map<String, dynamic> json) => ProductOption(
        id: asString(json['id']),
        optionName: asString(json['option_name']),
        optionNameEn: asStringOrNull(json['option_name_en']),
        priceAdjustment: asNum(json['price_adjustment']),
        isDefault: asBool(json['is_default']),
        sortOrder: asInt(json['sort_order']),
      );
}

class ProductOptionGroup {
  const ProductOptionGroup({
    required this.id,
    required this.groupName,
    this.groupNameEn,
    this.selectionType = 'SINGLE',
    this.isRequired = false,
    this.minSelections,
    this.maxSelections,
    this.sortOrder = 0,
    this.options = const <ProductOption>[],
  });

  final String id;
  final String groupName;
  final String? groupNameEn;
  final String selectionType;
  final bool isRequired;
  final int? minSelections;
  final int? maxSelections;
  final int sortOrder;
  final List<ProductOption> options;

  bool get isMultiple => selectionType.toUpperCase() == 'MULTIPLE';

  /// How many choices this group needs before the line can be added.
  int get effectiveMin => minSelections ?? (isRequired ? 1 : 0);

  factory ProductOptionGroup.fromJson(Map<String, dynamic> json) => ProductOptionGroup(
        id: asString(json['id']),
        groupName: asString(json['group_name']),
        groupNameEn: asStringOrNull(json['group_name_en']),
        selectionType: asString(json['selection_type'], fallback: 'SINGLE'),
        isRequired: asBool(json['is_required']),
        minSelections: asIntOrNull(json['min_selections']),
        maxSelections: asIntOrNull(json['max_selections']),
        sortOrder: asInt(json['sort_order']),
        options: asList(json['options'], ProductOption.fromJson),
      );
}

class ProductDetail {
  const ProductDetail({
    required this.id,
    required this.productName,
    this.descriptionText,
    this.imageUrl,
    this.isAvailable = true,
    this.skus = const <MenuSku>[],
    this.optionGroups = const <ProductOptionGroup>[],
  });

  final String id;
  final String productName;
  final String? descriptionText;
  final String? imageUrl;
  final bool isAvailable;
  final List<MenuSku> skus;
  final List<ProductOptionGroup> optionGroups;

  MenuSku? get defaultSku {
    if (skus.isEmpty) return null;
    for (final sku in skus) {
      if (sku.isDefault) return sku;
    }
    return skus.first;
  }

  factory ProductDetail.fromJson(Map<String, dynamic> json) => ProductDetail(
        id: asString(json['id']),
        productName: asString(json['product_name']),
        descriptionText: asStringOrNull(json['description_text']),
        imageUrl: asStringOrNull(json['image_url']),
        isAvailable: asBool(json['is_available'], fallback: true),
        skus: asList(json['skus'], MenuSku.fromJson),
        optionGroups: asList(json['option_groups'], ProductOptionGroup.fromJson),
      );
}
