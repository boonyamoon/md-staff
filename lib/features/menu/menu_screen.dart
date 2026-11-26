import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/product_thumb.dart';
import '../../core/widgets/states.dart';
import '../../data/dto/menu_dto.dart';
import '../../router/app_router.dart';
import '../tables/active_table_controller.dart';
import '../tables/table_exit_listener.dart';
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
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 320) {
      ref.read(menuProvider.notifier).loadMore();
    }
  }

  /// Leaving the table gives its claim back, so the next waiter can take it at once.
  Future<void> _leaveTable() async {
    await ref.read(activeTableProvider.notifier).close();
    if (mounted) AppRoutes.goZones(context);
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
    final menu = ref.watch(menuProvider);
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
            title: _searching
                ? TextField(
                    controller: _searchController,
                    autofocus: true,
                    onChanged: ref.read(menuProvider.notifier).search,
                    decoration: InputDecoration(
                      hintText: t('menu.searchPlaceholder'),
                      border: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
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
            actions: [
              IconButton(
                icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
                onPressed: () {
                  setState(() => _searching = !_searching);
                  if (!_searching) {
                    _searchController.clear();
                    ref.read(menuProvider.notifier).search('');
                  }
                },
              ),
              IconButton(
                tooltip: t('bill.title'),
                icon: const Icon(Icons.receipt_long_outlined),
                onPressed: () => AppRoutes.goBill(context, widget.floorItemId),
              ),
            ],
          ),
          body: Column(
            children: [
              _CategoryBar(menu: menu, t: t),
              const Divider(height: 1),
              Expanded(
                child: switch (menu) {
                  MenuState(loading: true, products: []) => const LoadingView(),
                  MenuState(failure: final failure?, products: []) => ErrorView(
                      failure: failure,
                      retryLabel: t('common.retry'),
                      onRetry: ref.read(menuProvider.notifier).load,
                    ),
                  MenuState(products: []) =>
                    EmptyView(message: t('menu.empty'), icon: Icons.search_off_rounded),
                  _ => _ProductList(
                      menu: menu,
                      t: t,
                      scrollController: _scrollController,
                      onTap: _addProduct,
                    ),
                },
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

class _CategoryBar extends ConsumerWidget {
  const _CategoryBar({required this.menu, required this.t});

  final MenuState menu;
  final AppStrings t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (menu.categories.isEmpty) return const SizedBox.shrink();
    final controller = ref.read(menuProvider.notifier);
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _CategoryChip(
            label: t('menu.all'),
            selected: menu.categoryId == null,
            onTap: () => controller.selectCategory(null),
          ),
          for (final category in menu.categories)
            _CategoryChip(
              label: category.categoryName,
              selected: menu.categoryId == category.id,
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

class _ProductList extends StatelessWidget {
  const _ProductList({
    required this.menu,
    required this.t,
    required this.scrollController,
    required this.onTap,
  });

  final MenuState menu;
  final AppStrings t;
  final ScrollController scrollController;
  final ValueChanged<MenuProduct> onTap;

  @override
  Widget build(BuildContext context) => ListView.separated(
        controller: scrollController,
        // The list runs to the bottom edge, under the home indicator; the inset is added to the
        // scroll padding so the last product can still be scrolled clear of it. It is zero while
        // the cart bar is showing, which takes that space itself.
        padding: EdgeInsets.fromLTRB(16, 12, 16, 20 + MediaQuery.paddingOf(context).bottom),
        itemCount: menu.products.length + (menu.loadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index >= menu.products.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final product = menu.products[index];
          return _ProductRow(product: product, t: t, onTap: () => onTap(product));
        },
      );
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
                      Row(
                        children: [
                          Text(
                            t.money(price),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.primaryStrong,
                            ),
                          ),
                          if (product.hasMultipleSkus)
                            const Text(
                              ' +',
                              style: TextStyle(fontSize: 15, color: MeedColors.inkSoft),
                            ),
                          if (soldOut) ...[
                            const SizedBox(width: 10),
                            Text(
                              t('menu.soldOut'),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: MeedColors.danger,
                              ),
                            ),
                          ],
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${t('cart.title')} · $itemCount ${t('common.items')}'),
                Text(t.money(total)),
              ],
            ),
          ),
        ),
      );
}
