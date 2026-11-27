import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/fitted_amount.dart';
import '../../core/widgets/product_thumb.dart';
import '../../core/widgets/stale_banner.dart';
import '../../core/widgets/states.dart';
import '../../data/dto/menu_dto.dart';
import '../../router/app_router.dart';
import '../tables/active_table_controller.dart';
import '../tables/table_exit_listener.dart';
import '../zones/zones_controller.dart';
import 'menu_catalog_controller.dart';
import 'menu_controller.dart';
import 'product_options_sheet.dart';

/// Ordering for one table: the menu, with a cart bar across the bottom.
///
/// Reaching this screen means the handset holds the table's claim. If that claim is lost while the
/// waiter is here, [TableExitListener] pops back to the floor and says why.
class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key, required this.floorItemId});

  final String floorItemId;

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  final _searchController = TextEditingController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    // Sold-out dishes are checked on the way in, when the last check is old — not on a timer.
    Future.microtask(() {
      if (mounted) {
        unawaited(ref.read(menuCatalogProvider.notifier).refreshAvailabilityIfStale());
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Leaving the table gives its claim back, so the next waiter can take it at once.
  Future<void> _leaveTable() async {
    final floor = ref.read(zonesProvider.notifier);
    await ref.read(activeTableProvider.notifier).close();
    unawaited(floor.tableReleased(widget.floorItemId));
    if (mounted) AppRoutes.goZones(context);
  }

  void _closeSearch() {
    setState(() => _searching = false);
    _searchController.clear();
    ref.read(menuProvider.notifier).search('');
  }

  Future<void> _addProduct(MenuProduct product) async {
    final controller = ref.read(activeTableProvider.notifier);
    if (!product.needsChoices) {
      controller.addProduct(product);
      return;
    }
    final line = await showProductOptionsSheet(context, product: product);
    if (line != null) controller.addLine(line);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final menu = ref.watch(menuCatalogProvider);
    final filter = ref.watch(menuProvider);
    final table = ref.watch(activeTableProvider);

    return TableExitListener(
      floorItemId: widget.floorItemId,
      child: PopScope(
        // Back from here means "done with this table", so the claim is released rather than
        // left to expire while another waiter waits for it.
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _leaveTable();
        },
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: _leaveTable,
            ),
            // The search box starts right after the back arrow and takes the width.
            titleSpacing: _searching ? 0 : null,
            title: _searching
                ? _SearchField(
                    controller: _searchController,
                    hint: t('menu.searchPlaceholder'),
                    onChanged: ref.read(menuProvider.notifier).search,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(table.tableLabel.isEmpty ? t('menu.title') : table.tableLabel),
                      if (table.detail?.session != null)
                        Text(
                          '${t('tables.round')} ${table.detail!.session!.currentRound}',
                          style: const TextStyle(fontSize: 12.5, color: MeedColors.inkSoft),
                        ),
                    ],
                  ),
            actions: _searching
                ? [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: TextButton(onPressed: _closeSearch, child: Text(t('common.cancel'))),
                    ),
                  ]
                : [
                    IconButton(
                      tooltip: t('common.search'),
                      icon: const Icon(Icons.search_rounded),
                      onPressed: () => setState(() => _searching = true),
                    ),
                    IconButton(
                      tooltip: t('bill.title'),
                      icon: const Icon(Icons.receipt_long_outlined),
                      onPressed: () => AppRoutes.goBill(context, widget.floorItemId),
                    ),
                  ],
          ),
          body: menu.catalog == null
              ? (menu.failure != null && !menu.refreshing
                  ? ErrorView(
                      failure: menu.failure!,
                      retryLabel: t('common.retry'),
                      onRetry: () => ref.read(menuCatalogProvider.notifier).refresh(),
                    )
                  : const LoadingView())
              : Column(
                  children: [
                    _CategoryBar(
                      categories: menu.catalog!.categories,
                      selectedId: filter.categoryId,
                      t: t,
                    ),
                    const Divider(height: 1),
                    if (menu.failure != null)
                      StaleBanner(failure: menu.failure!, fetchedAt: menu.fetchedAt),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () => ref.read(menuCatalogProvider.notifier).refresh(),
                        child: _ProductList(
                          // A new category starts at the top of its list.
                          key: ValueKey(filter.categoryId),
                          t: t,
                          onTap: _addProduct,
                        ),
                      ),
                    ),
                  ],
                ),
          bottomNavigationBar: table.cart.isEmpty
              ? null
              : _CartBar(
                  t: t,
                  itemCount: table.cartItemCount,
                  total: table.cartTotal,
                  onTap: () => AppRoutes.goCart(context, widget.floorItemId),
                ),
        ),
      ),
    );
  }
}

/// The menu's search box: a rounded, filled field with room around what is typed.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.hint, required this.onChanged});

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  static const _shape = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(22)),
    borderSide: BorderSide(color: MeedColors.line),
  );

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => TextField(
          controller: controller,
          autofocus: true,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          textAlignVertical: TextAlignVertical.center,
          // The line height leaves room for Thai vowel and tone marks.
          style: const TextStyle(fontSize: 16, height: 1.3, color: MeedColors.ink),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: MeedColors.inkSoft),
            isDense: true,
            filled: true,
            fillColor: MeedColors.surface,
            // 40 high in the 56 bar, leaving 8 above and below.
            contentPadding: const EdgeInsets.fromLTRB(2, 9, 14, 9),
            prefixIcon: const Icon(Icons.search_rounded, size: 21, color: MeedColors.inkSoft),
            prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                    icon: const Icon(Icons.cancel_rounded, size: 20, color: MeedColors.inkSoft),
                    // Fitted to the field, whose height it must not stretch.
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
            suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            border: _shape,
            enabledBorder: _shape,
            focusedBorder: _shape.copyWith(
              borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
            ),
          ),
        ),
      );
}

class _CategoryBar extends ConsumerWidget {
  const _CategoryBar({required this.categories, required this.selectedId, required this.t});

  final List<MenuCategory> categories;
  final String? selectedId;
  final AppStrings t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (categories.isEmpty) return const SizedBox.shrink();
    final controller = ref.read(menuProvider.notifier);
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _CategoryChip(
            label: t('menu.all'),
            selected: selectedId == null,
            onTap: () => controller.selectCategory(null),
          ),
          for (final category in categories)
            _CategoryChip(
              label: category.categoryName,
              selected: selectedId == category.id,
              onTap: () => controller.selectCategory(category.id),
            ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: selected ? Theme.of(context).colorScheme.primary : MeedColors.card,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              // The bar fixes the capsule's height, so the label is centred in it rather than
              // pushed down by vertical padding — which left no room for Thai vowel marks.
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : MeedColors.line),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                  leadingDistribution: TextLeadingDistribution.even,
                  color: selected ? Theme.of(context).colorScheme.onPrimary : MeedColors.ink,
                ),
              ),
            ),
          ),
        ),
      );
}

class _ProductList extends ConsumerWidget {
  const _ProductList({super.key, required this.t, required this.onTap});

  final AppStrings t;
  final ValueChanged<MenuProduct> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(visibleProductsProvider);
    if (products.isEmpty) {
      // Still scrollable, so it can be pulled down to ask the server again.
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyView(message: t('menu.empty'), icon: Icons.search_off_rounded),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      // The list runs to the bottom edge, under the home indicator; the inset is added to the
      // scroll padding so the last product can still be scrolled clear of it. It is zero while
      // the cart bar is showing, which takes that space itself.
      padding: EdgeInsets.fromLTRB(16, 12, 16, 20 + MediaQuery.paddingOf(context).bottom),
      itemCount: products.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final product = products[index];
        return _ProductRow(product: product, t: t, onTap: () => onTap(product));
      },
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.t, required this.onTap});

  final MenuProduct product;
  final AppStrings t;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final price = product.defaultSku?.defaultPrice ?? 0;
    final soldOut = !product.isAvailable;
    return Opacity(
      opacity: soldOut ? 0.45 : 1,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: soldOut ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ProductThumb(imageUrl: product.imageUrl, size: 58),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.productName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      // "Sold out" drops below the price where there is no room beside it.
                      Wrap(
                        spacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text.rich(
                              TextSpan(
                                text: t.money(price),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(context).colorScheme.primaryStrong,
                                ),
                                children: [
                                  if (product.hasMultipleSkus)
                                    const TextSpan(
                                      text: ' +',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w400,
                                        color: MeedColors.inkSoft,
                                      ),
                                    ),
                                ],
                              ),
                              maxLines: 1,
                            ),
                          ),
                          if (soldOut)
                            Text(
                              t('menu.soldOut'),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: MeedColors.danger,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  product.needsChoices ? Icons.tune_rounded : Icons.add_circle_outline_rounded,
                  color: soldOut ? MeedColors.line : Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CartBar extends StatelessWidget {
  const _CartBar({
    required this.t,
    required this.itemCount,
    required this.total,
    required this.onTap,
  });

  final AppStrings t;
  final int itemCount;
  final num total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: onTap,
            // The total takes its own line where it does not fit beside the title.
            child: SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                children: [
                  Text('${t('cart.title')} · $itemCount ${t('common.items')}'),
                  FittedAmount(t.money(total)),
                ],
              ),
            ),
          ),
        ),
      );
}
