import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/api_failure.dart';
import '../../core/providers.dart';
import '../../data/dto/cart_line.dart';
import '../../data/dto/floor_dto.dart';
import '../../data/dto/menu_dto.dart';
import '../../data/dto/order_dto.dart';
import '../bootstrap/session_controller.dart';

/// Why the app had to drop the table it was working on.
enum TableExitReason {
  /// A manager took the table over mid-order. The cart was never sent.
  claimLost,

  /// The cashier opened this table's bill at the POS.
  pendingPayment,

  /// The party was cancelled, paid for or moved while this handset was ordering for it. The cart
  /// was never sent, and goes with the table.
  tableChanged,
}

class ActiveTableState {
  const ActiveTableState({
    this.floorItemId,
    this.detail,
    this.claim,
    this.cart = const <CartLine>[],
    this.guestCount = 1,
    this.loading = false,
    this.sending = false,
    this.failure,
    this.exitReason,
    this.lastRound,
  });

  final String? floorItemId;
  final TableDetail? detail;

  /// Our lease on this table. Null means we are not holding it.
  final TableClaim? claim;
  final List<CartLine> cart;
  final int guestCount;
  final bool loading;
  final bool sending;

  /// The last error worth showing, cleared as soon as it has been shown.
  final ApiFailure? failure;

  /// Set when the table had to be abandoned; the UI pops back to the floor and explains why.
  final TableExitReason? exitReason;

  /// The round just accepted by the kitchen, for the confirmation the waiter sees.
  final PlacedRound? lastRound;

  bool get isOpen => floorItemId != null;
  bool get holdsClaim => claim != null;
  String get tableLabel => detail?.label ?? '';
  num get cartTotal => cart.total;
  int get cartItemCount => cart.itemCount;
  bool get canSend => holdsClaim && cart.isNotEmpty && !sending;

  ActiveTableState copyWith({
    String? floorItemId,
    TableDetail? detail,
    TableClaim? claim,
    List<CartLine>? cart,
    int? guestCount,
    bool? loading,
    bool? sending,
    ApiFailure? failure,
    TableExitReason? exitReason,
    PlacedRound? lastRound,
    bool clearFailure = false,
    bool clearClaim = false,
    bool clearExitReason = false,
    bool clearLastRound = false,
  }) =>
      ActiveTableState(
        floorItemId: floorItemId ?? this.floorItemId,
        detail: detail ?? this.detail,
        claim: clearClaim ? null : (claim ?? this.claim),
        cart: cart ?? this.cart,
        guestCount: guestCount ?? this.guestCount,
        loading: loading ?? this.loading,
        sending: sending ?? this.sending,
        failure: clearFailure ? null : (failure ?? this.failure),
        exitReason: clearExitReason ? null : (exitReason ?? this.exitReason),
        lastRound: clearLastRound ? null : (lastRound ?? this.lastRound),
      );
}

final activeTableProvider = NotifierProvider<ActiveTableController, ActiveTableState>(
  ActiveTableController.new,
);

/// The table a waiter currently has open: the claim on it, the cart being built, and the round
/// being sent. One at a time by design — a waiter works one table, then the next.
///
/// Two invariants this class exists to keep:
///
///  1. **The lease stays alive while the screen is open.** A renew timer runs from the moment the
///     table is claimed until it is released. A renew that fails with TABLE_CLAIM_LOST means a
///     manager took the table, and the app leaves the ordering screen rather than letting a
///     waiter keep building a cart they can no longer send.
///  2. **One round, one idempotency key.** The key is minted when the waiter presses send and
///     kept until that round is accepted, so a retry after a lost response replays the same round
///     instead of adding it twice. It belongs to that table and party: no other round may use it.
class ActiveTableController extends Notifier<ActiveTableState> {
  Timer? _renewTimer;

  /// A release still on its way. [open] waits for it: a table taken again at once could otherwise
  /// be handed back the very lease that is about to be dropped.
  Future<void>? _releasing;

  /// Rounds sent but never confirmed, by table: the key each went out under, and the party it was
  /// for. Kept after leaving the table, so that sending the same dishes there again replays the
  /// first attempt rather than cooking them twice.
  final _unconfirmed = <String, ({String key, String? sessionId})>{};
  final _uuid = const Uuid();

  @override
  ActiveTableState build() {
    ref.onDispose(_stopRenewTimer);
    // A shift ending must not leave a lease renewing in the background.
    ref.listen(sessionProvider, (previous, next) {
      if (next.phase != AppPhase.ready) {
        _stopRenewTimer();
        _unconfirmed.clear();
        state = const ActiveTableState();
      }
    });
    return const ActiveTableState();
  }

  /// Opens a table: loads it, then takes the claim if we do not already hold it.
  ///
  /// Reuses an existing claim of ours (after an app restart, the server still remembers it) rather
  /// than claiming again, so the waiter's lease and round history survive a crash.
  Future<bool> open(String floorItemId) async {
    _stopRenewTimer();
    state = ActiveTableState(floorItemId: floorItemId, loading: true);

    final floor = ref.read(floorRepositoryProvider);
    try {
      await _releasing;
      final detail = await floor.table(floorItemId);
      if (detail.session?.isPendingPayment ?? false) {
        state = state.copyWith(
          detail: detail,
          loading: false,
          exitReason: TableExitReason.pendingPayment,
        );
        return false;
      }

      final theirs = detail.claim;
      if (theirs != null && !theirs.isMine) {
        // Known to be someone else's already. Asking to claim it would only be refused, and the
        // server counts refused claims against the manager-PIN rate limit.
        state = state.copyWith(
          detail: detail,
          loading: false,
          failure: ApiFailure(
            code: 'TABLE_CLAIM_HELD',
            message: '${theirs.holder.staffName} is taking orders at ${detail.label}',
            statusCode: 409,
            data: {
              'holder': {
                'staff_name': theirs.holder.staffName,
                'terminal_name': theirs.holder.terminalName,
                'terminal_code': theirs.holder.terminalCode,
              },
            },
          ),
        );
        return false;
      }

      final existingLease = detail.myLeaseToken;
      final claim = existingLease != null
          ? TableClaim(
              floorItemId: floorItemId,
              leaseToken: existingLease,
              expiresAt: detail.claim!.expiresAt,
              sessionId: detail.session?.sessionId,
            )
          : await floor.claim(floorItemId);

      state = state.copyWith(
        detail: detail,
        claim: claim,
        loading: false,
        guestCount: detail.session?.guestCount ?? state.guestCount,
        clearFailure: true,
      );
      _startRenewTimer();
      return true;
    } on ApiFailure catch (failure) {
      state = state.copyWith(loading: false, failure: failure);
      return false;
    }
  }

  /// Takes a table off another handset with a manager PIN.
  Future<TableClaim?> takeOver(String floorItemId, String managerPin) async {
    state = state.copyWith(floorItemId: floorItemId, loading: true, clearFailure: true);
    try {
      final floor = ref.read(floorRepositoryProvider);
      final claim = await floor.claim(floorItemId, managerPin: managerPin);
      final detail = await floor.table(floorItemId);
      state = state.copyWith(
        detail: detail,
        claim: claim,
        loading: false,
        guestCount: detail.session?.guestCount ?? state.guestCount,
      );
      _startRenewTimer();
      return claim;
    } on ApiFailure catch (failure) {
      state = state.copyWith(loading: false, failure: failure);
      return null;
    }
  }

  /// Leaves the table, giving the claim back so the next waiter can take it immediately.
  Future<void> close() async {
    _stopRenewTimer();
    final claim = state.claim;
    final floorItemId = state.floorItemId;
    state = const ActiveTableState();
    if (claim == null || floorItemId == null) return;
    await (_releasing = _release(floorItemId, claim.leaseToken));
  }

  Future<void> _release(String floorItemId, String leaseToken) async {
    try {
      await ref.read(floorRepositoryProvider).releaseClaim(floorItemId, leaseToken);
    } on ApiFailure {
      // The lease expires on its own within minutes; a failed release is not worth telling a
      // waiter who has already walked to the next table.
    }
  }

  /// A fresher read of the open table, fetched by the bill screen.
  void adoptDetail(TableDetail detail) {
    if (detail.floorItemId == state.floorItemId) state = state.copyWith(detail: detail);
  }

  // ── Cart ──

  /// Adds a line, merging into an identical one (same product, SKU, options and note) so three of
  /// the same dish read as "x3" rather than three rows.
  void addLine(CartLine line) {
    final existing = state.cart.firstMatching(line.mergeKey);
    if (existing == null) {
      state = state.copyWith(cart: [...state.cart, line]);
      return;
    }
    state = state.copyWith(
      cart: [
        for (final l in state.cart)
          if (l.lineId == existing.lineId) l.copyWith(quantity: l.quantity + line.quantity) else l,
      ],
    );
  }

  /// Convenience for a tile tap on a product with no options and one SKU.
  void addProduct(MenuProduct product, {int quantity = 1}) {
    final sku = product.defaultSku;
    if (sku == null) return;
    addLine(
      CartLine(
        lineId: _uuid.v4(),
        productId: product.id,
        productName: product.productName,
        sku: sku,
        quantity: quantity,
        imageUrl: product.imageUrl,
      ),
    );
  }

  void setQuantity(String lineId, int quantity) {
    if (quantity <= 0) {
      removeLine(lineId);
      return;
    }
    state = state.copyWith(
      cart: [
        for (final l in state.cart) if (l.lineId == lineId) l.copyWith(quantity: quantity) else l,
      ],
    );
  }

  void removeLine(String lineId) =>
      state = state.copyWith(cart: state.cart.where((l) => l.lineId != lineId).toList());

  void clearCart() => state = state.copyWith(cart: const <CartLine>[]);

  void setGuestCount(int count) => state = state.copyWith(guestCount: count.clamp(1, 99));

  // ── Sending ──

  /// Sends the cart to the kitchen. The POS prints the slip; nothing is paid here.
  ///
  /// Returns the accepted round, or null when it failed (the reason is in `state.failure`, or
  /// `state.exitReason` when the table was lost).
  Future<PlacedRound?> sendToKitchen() async {
    final floorItemId = state.floorItemId;
    final claim = state.claim;
    if (floorItemId == null || claim == null || state.cart.isEmpty || state.sending) return null;

    final sessionId = state.detail?.session?.sessionId;
    final idempotencyKey = _roundKey(floorItemId, sessionId);
    state = state.copyWith(sending: true, clearFailure: true, clearLastRound: true);

    try {
      final round = await ref.read(floorRepositoryProvider).placeOrder(
            floorItemId: floorItemId,
            leaseToken: claim.leaseToken,
            idempotencyKey: idempotencyKey,
            items: state.cart.map((l) => l.toRequestJson()).toList(),
            guestCount: state.guestCount,
            sessionId: sessionId,
          );
      _unconfirmed.remove(floorItemId);
      state = state.copyWith(
        sending: false,
        cart: const <CartLine>[],
        lastRound: round,
      );
      return round;
    } on ApiFailure catch (failure) {
      // A lost claim is terminal for this screen: the cart stays, but it can no longer be sent
      // here, so the UI pops back to the floor and says so.
      if (failure.code == 'TABLE_CLAIM_LOST') {
        _stopRenewTimer();
        state = state.copyWith(
          sending: false,
          failure: failure,
          exitReason: TableExitReason.claimLost,
          clearClaim: true,
        );
        return null;
      }
      if (failure.code == 'SESSION_PENDING_PAYMENT') {
        _stopRenewTimer();
        state = state.copyWith(
          sending: false,
          failure: failure,
          exitReason: TableExitReason.pendingPayment,
        );
        return null;
      }
      // Nobody left to cook these for: the screen closes the table, cart and all.
      if (failure.isTableGone) {
        _stopRenewTimer();
        _unconfirmed.remove(floorItemId);
        state = state.copyWith(
          sending: false,
          failure: failure,
          exitReason: TableExitReason.tableChanged,
        );
        return null;
      }
      // The server holds a different round under this key: an earlier attempt did arrive. It is
      // settled now, so the next press — once the waiter has checked the bill — is a new round.
      if (failure.code == 'IDEMPOTENCY_KEY_REUSED') _unconfirmed.remove(floorItemId);
      // Everything else — no stock, no connection, a rate limit — keeps the cart and the claim so
      // the waiter can simply press send again. The idempotency key is deliberately kept too.
      state = state.copyWith(sending: false, failure: failure);
      return null;
    }
  }

  /// The key to send this round under: the one an unconfirmed attempt on this table used, or a new
  /// one. Reusing it is what makes a lost response safe.
  String _roundKey(String floorItemId, String? sessionId) {
    final earlier = _unconfirmed[floorItemId];
    // An attempt made at a free table may be what opened the party now seated, so its key stands.
    // One made for another party is not spent on this one.
    if (earlier != null && (earlier.sessionId == null || earlier.sessionId == sessionId)) {
      return earlier.key;
    }
    final key = _uuid.v4();
    _unconfirmed[floorItemId] = (key: key, sessionId: sessionId);
    return key;
  }

  void acknowledgeFailure() {
    if (state.failure != null) state = state.copyWith(clearFailure: true);
  }

  void acknowledgeExit() {
    if (state.exitReason != null) state = state.copyWith(clearExitReason: true);
  }

  // ── Lease renewal ──

  void _startRenewTimer() {
    _stopRenewTimer();
    final interval = state.claim?.renewInterval;
    if (interval == null || interval.inSeconds < 5) return;
    _renewTimer = Timer.periodic(interval, (_) => unawaited(_renew()));
  }

  void _stopRenewTimer() {
    _renewTimer?.cancel();
    _renewTimer = null;
  }

  Future<void> _renew() async {
    final floorItemId = state.floorItemId;
    final claim = state.claim;
    if (floorItemId == null || claim == null) {
      _stopRenewTimer();
      return;
    }
    try {
      final renewed = await ref.read(floorRepositoryProvider).renewClaim(
            floorItemId,
            claim.leaseToken,
          );
      state = state.copyWith(claim: renewed);
    } on ApiFailure catch (failure) {
      if (failure.code == 'TABLE_CLAIM_LOST') {
        _stopRenewTimer();
        state = state.copyWith(
          failure: failure,
          exitReason: TableExitReason.claimLost,
          clearClaim: true,
        );
        return;
      }
      // A dropped connection must not cost the waiter the table: the lease outlives one missed
      // renew, and the next tick will try again.
    }
  }
}
