import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/product_thumb.dart';
import '../../core/widgets/quantity_stepper.dart';
import '../../core/widgets/states.dart';
import '../../data/dto/cart_line.dart';
import '../../router/app_router.dart';
import '../bootstrap/session_controller.dart';
import '../menu/menu_catalog_controller.dart';
import '../tables/active_table_controller.dart';
import '../tables/table_exit_listener.dart';
import '../zones/zones_controller.dart';

/// What is about to be sent to the kitchen. The only action here is "send": payment happens at
/// the POS, and this app has no way to take money by design.
class CartScreen extends ConsumerWidget {
  const CartScreen({super.key, required this.floorItemId});

  final String floorItemId;

  Future<void> _send(BuildContext context, WidgetRef ref) async {
    final t = ref.read(stringsProvider);
    final round = await ref.read(activeTableProvider.notifier).sendToKitchen();
    if (!context.mounted) return;

    if (round == null) {
      final failure = ref.read(activeTableProvider).failure;
      // A lost claim, a bill opened at the POS or a party that has gone is handled by
      // TableExitListener, which shows a dialog and leaves the table; anything else is retryable
      // right here.
      if (failure != null && !failure.isClaimConflict && !failure.isTableGone) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failure.code == 'INSUFFICIENT_STOCK'
                  ? '${t('error.outOfStock')}\n${failure.message}'
                  : failure.code == 'CONCURRENT_MODIFICATION'
                      ? t('error.concurrent')
                      : failure.code == 'IDEMPOTENCY_KEY_REUSED'
                          ? t('cart.earlierSent')
                          : t.failure(failure),
            ),
            // The one about an earlier send asks for something to be done, so it stays longer.
            duration: Duration(seconds: failure.code == 'IDEMPOTENCY_KEY_REUSED' ? 10 : 5),
          ),
        );
        // Refused because the menu moved on: fetch it, so what is picked next is current.
        if (failure.isMenuOutdated) {
          unawaited(ref.read(menuCatalogProvider.notifier).refresh());
        }
        ref.read(activeTableProvider.notifier).acknowledgeFailure();
      }
      return;
    }

    final controller = ref.read(activeTableProvider.notifier);
    final floor = ref.read(zonesProvider.notifier);
    final printing = ref.read(configProvider).value?.ordering.kitchenPrintingEnabled ?? true;
    final message = round.idempotentReplay
        ? t('cart.alreadySent')
        : (printing ? t('cart.sentPrinting') : t('cart.noPrinter'));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
    // The round is in, so this table is done with: give it back and go to the floor, waiting for
    // neither. The floor is fetched once the claim is gone, so it shows neither it nor old totals.
    final released = controller.close();
    AppRoutes.goZones(context);
    unawaited(released.then((_) => floor.refreshAfterChange()));
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final t = ref.read(stringsProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('cart.clear')),
        content: Text(t('cart.clearConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t('cart.clear')),
          ),
        ],
      ),
    );
    if (confirmed == true) ref.read(activeTableProvider.notifier).clearCart();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final table = ref.watch(activeTableProvider);
    final controller = ref.read(activeTableProvider.notifier);

    return TableExitListener(
      floorItemId: floorItemId,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${t('cart.title')} · ${table.tableLabel}'),
          actions: [
            if (table.cart.isNotEmpty)
              IconButton(
                tooltip: t('cart.clear'),
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () => _confirmClear(context, ref),
              ),
          ],
        ),
        body: table.cart.isEmpty
            ? EmptyView(message: t('cart.empty'), icon: Icons.shopping_basket_outlined)
            : Column(
                children: [
                  _GuestCountRow(
                    t: t,
                    guestCount: table.guestCount,
                    // A session that is already open took its guest count when it was opened;
                    // changing it here would be ignored, so the row is read-only by then.
                    editable: table.detail?.session == null,
                    onChanged: controller.setGuestCount,
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      itemCount: table.cart.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) => _CartRow(
                        line: table.cart[index],
                        t: t,
                        onQuantityChanged: (value) =>
                            controller.setQuantity(table.cart[index].lineId, value),
                      ),
                    ),
                  ),
                ],
              ),
        bottomNavigationBar: table.cart.isEmpty
            ? null
            : _SendBar(
                t: t,
                total: table.cartTotal,
                itemCount: table.cartItemCount,
                sending: table.sending,
                enabled: table.canSend,
                onSend: () => _send(context, ref),
              ),
      ),
    );
  }
}

class _GuestCountRow extends StatelessWidget {
  const _GuestCountRow({
    required this.t,
    required this.guestCount,
    required this.editable,
    required this.onChanged,
  });

  final AppStrings t;
  final int guestCount;
  final bool editable;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            const Icon(Icons.groups_outlined, size: 20, color: MeedColors.inkSoft),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                t('cart.guests'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            if (editable)
              QuantityStepper(quantity: guestCount, onChanged: onChanged, compact: true)
            else
              Text(
                '$guestCount',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
          ],
        ),
      );
}

class _CartRow extends StatelessWidget {
  const _CartRow({required this.line, required this.t, required this.onQuantityChanged});

  final CartLine line;
  final AppStrings t;
  final ValueChanged<int> onQuantityChanged;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProductThumb(imageUrl: line.imageUrl, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.productName,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    if (line.sku.skuName.isNotEmpty)
                      Text(
                        line.sku.skuName,
                        style: const TextStyle(fontSize: 13.5, color: MeedColors.inkSoft),
                      ),
                    if (line.options.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        line.optionsLabel,
                        style: const TextStyle(fontSize: 13.5, color: MeedColors.inkSoft),
                      ),
                    ],
                    if (line.note != null && line.note!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.sticky_note_2_outlined, size: 14, color: MeedColors.accent),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              line.note!,
                              style: const TextStyle(fontSize: 13, color: MeedColors.ink),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        // min: 0 — stepping below one takes the dish off the order, which is what
                        // a waiter reaches for when a guest changes their mind.
                        QuantityStepper(
                          quantity: line.quantity,
                          min: 0,
                          onChanged: onQuantityChanged,
                          compact: true,
                        ),
                        const Spacer(),
                        Text(
                          t.money(line.lineTotal),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _SendBar extends StatelessWidget {
  const _SendBar({
    required this.t,
    required this.total,
    required this.itemCount,
    required this.sending,
    required this.enabled,
    required this.onSend,
  });

  final AppStrings t;
  final num total;
  final int itemCount;
  final bool sending;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => Container(
        // No SafeArea around the bar: its background runs to the bottom edge, and only what is
        // in it is lifted clear of the home indicator.
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
        decoration: const BoxDecoration(
          color: MeedColors.card,
          border: Border(top: BorderSide(color: MeedColors.line)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  '$itemCount ${t('common.items')}',
                  style: const TextStyle(fontSize: 14.5, color: MeedColors.inkSoft),
                ),
                const Spacer(),
                Text(
                  t.money(total),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: enabled ? onSend : null,
              icon: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(sending ? t('cart.sending') : t('cart.send')),
            ),
            const SizedBox(height: 6),
            Text(
              t('bill.payAtPos'),
              style: const TextStyle(fontSize: 12.5, color: MeedColors.inkSoft),
            ),
          ],
        ),
      );
}
