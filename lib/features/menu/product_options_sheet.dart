import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/l10n/strings.dart';
import '../../core/network/api_failure.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/quantity_stepper.dart';
import '../../core/widgets/states.dart';
import '../../data/dto/cart_line.dart';
import '../../data/dto/menu_dto.dart';
import 'menu_controller.dart';

/// Picks the size, the options and the note for one dish, then returns the cart line.
///
/// Required groups are enforced here so a waiter cannot send "noodles" with no broth chosen and
/// have the kitchen come back asking. The prices shown are the menu's; the server re-resolves
/// every one of them when the round is sent.
Future<CartLine?> showProductOptionsSheet(
  BuildContext context, {
  required MenuProduct product,
}) =>
    showModalBottomSheet<CartLine>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _ProductOptionsSheet(product: product),
    );

class _ProductOptionsSheet extends ConsumerStatefulWidget {
  const _ProductOptionsSheet({required this.product});

  final MenuProduct product;

  @override
  ConsumerState<_ProductOptionsSheet> createState() => _ProductOptionsSheetState();
}

class _ProductOptionsSheetState extends ConsumerState<_ProductOptionsSheet> {
  final _noteController = TextEditingController();
  final _uuid = const Uuid();

  MenuSku? _sku;
  // group id → chosen option ids, in the order they were tapped.
  final Map<String, List<ProductOption>> _choices = {};
  int _quantity = 1;
  bool _initialised = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  /// Preselects the default SKU and every group's default options, so a dish whose defaults are
  /// already right can be added with one more tap.
  void _initialise(ProductDetail detail) {
    if (_initialised) return;
    _initialised = true;
    _sku = detail.defaultSku;
    for (final group in detail.optionGroups) {
      final defaults = group.options.where((o) => o.isDefault).toList();
      if (defaults.isEmpty) continue;
      _choices[group.id] = group.isMultiple ? defaults : [defaults.first];
    }
  }

  bool _isChosen(ProductOptionGroup group, ProductOption option) =>
      _choices[group.id]?.any((o) => o.id == option.id) ?? false;

  void _toggle(ProductOptionGroup group, ProductOption option) {
    setState(() {
      final chosen = [...?_choices[group.id]];
      final already = chosen.indexWhere((o) => o.id == option.id);
      if (group.isMultiple) {
        if (already >= 0) {
          chosen.removeAt(already);
        } else {
          final max = group.maxSelections;
          // At the cap, the newest choice replaces the oldest rather than being ignored —
          // silently doing nothing reads as a broken button.
          if (max != null && chosen.length >= max && max > 0) chosen.removeAt(0);
          chosen.add(option);
        }
        _choices[group.id] = chosen;
      } else {
        _choices[group.id] = already >= 0 && !group.isRequired ? <ProductOption>[] : [option];
      }
    });
  }

  List<ProductOptionGroup> _unsatisfied(ProductDetail detail) => detail.optionGroups
      .where((group) => (_choices[group.id]?.length ?? 0) < group.effectiveMin)
      .toList();

  num _unitPrice(ProductDetail detail) {
    final base = _sku?.defaultPrice ?? 0;
    final extras = _choices.values
        .expand((options) => options)
        .fold<num>(0, (sum, option) => sum + option.priceAdjustment);
    return base + extras;
  }

  void _add(ProductDetail detail) {
    final sku = _sku;
    if (sku == null) return;
    final options = <CartOption>[
      for (final group in detail.optionGroups)
        for (final option in _choices[group.id] ?? const <ProductOption>[])
          CartOption(
            optionGroupId: group.id,
            optionId: option.id,
            optionName: option.optionName,
            groupName: group.groupName,
            priceAdjustment: option.priceAdjustment,
          ),
    ];
    Navigator.of(context).pop(
      CartLine(
        lineId: _uuid.v4(),
        productId: detail.id,
        productName: detail.productName,
        sku: sku,
        quantity: _quantity,
        note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        options: options,
        imageUrl: detail.imageUrl ?? widget.product.imageUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final detail = ref.watch(productDetailProvider(widget.product.id));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scrollController) => switch (detail) {
        AsyncError(:final error) => Padding(
            padding: const EdgeInsets.all(24),
            child: ErrorView(
              failure: error is ApiFailure
                  ? error
                  : ApiFailure(code: 'UNKNOWN', message: error.toString()),
              retryLabel: t('common.retry'),
              onRetry: () => ref.invalidate(productDetailProvider(widget.product.id)),
            ),
          ),
        AsyncData(:final value) => _body(context, t, value, scrollController),
        _ => const SizedBox(height: 240, child: LoadingView()),
      },
    );
  }

  Widget _body(
    BuildContext context,
    AppStrings t,
    ProductDetail detail,
    ScrollController scrollController,
  ) {
    _initialise(detail);
    final unsatisfied = _unsatisfied(detail);
    final canAdd = _sku != null && unsatisfied.isEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  detail.productName,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            children: [
              if (detail.skus.length > 1) ...[
                _GroupHeader(title: t('menu.chooseSize'), required: true),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final sku in detail.skus)
                      _Chip(
                        label: '${sku.skuName} · ${t.money(sku.defaultPrice)}',
                        selected: _sku?.id == sku.id,
                        onTap: () => setState(() => _sku = sku),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
              for (final group in detail.optionGroups) ...[
                _GroupHeader(
                  title: group.groupName,
                  required: group.effectiveMin > 0,
                  hint: _groupHint(t, group),
                  unsatisfied: unsatisfied.any((g) => g.id == group.id),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in group.options)
                      _Chip(
                        label: option.priceAdjustment == 0
                            ? option.optionName
                            : '${option.optionName} +${t.money(option.priceAdjustment)}',
                        selected: _isChosen(group, option),
                        onTap: () => _toggle(group, option),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
              _GroupHeader(title: t('common.note'), required: false),
              const SizedBox(height: 8),
              TextField(
                controller: _noteController,
                maxLength: 200,
                decoration: InputDecoration(
                  hintText: t('menu.notePlaceholder'),
                  counterText: '',
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Row(
            children: [
              QuantityStepper(
                quantity: _quantity,
                onChanged: (value) => setState(() => _quantity = value),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: FilledButton(
                  onPressed: canAdd ? () => _add(detail) : null,
                  child: Text(
                    '${t('menu.addToCart')} · ${t.money(_unitPrice(detail) * _quantity)}',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String? _groupHint(AppStrings t, ProductOptionGroup group) {
    if (!group.isMultiple) return null;
    final min = group.effectiveMin;
    final max = group.maxSelections;
    if (min == 0 && max == null) return null;
    if (max == null) return '${t('common.required')} $min+';
    if (min == max) return '$min';
    return '$min-$max';
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.title,
    required this.required,
    this.hint,
    this.unsatisfied = false,
  });

  final String title;
  final bool required;
  final String? hint;
  final bool unsatisfied;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: unsatisfied ? MeedColors.danger : MeedColors.ink,
            ),
          ),
          if (required) ...[
            const SizedBox(width: 6),
            Icon(Icons.star_rounded, size: 10, color: unsatisfied ? MeedColors.danger : MeedColors.accent),
          ],
          if (hint != null) ...[
            const SizedBox(width: 8),
            Text(hint!, style: const TextStyle(fontSize: 13, color: MeedColors.inkSoft)),
          ],
        ],
      );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? MeedColors.brand : MeedColors.card,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: selected ? MeedColors.brand : MeedColors.line),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : MeedColors.ink,
              ),
            ),
          ),
        ),
      );
}
