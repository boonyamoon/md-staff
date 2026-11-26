import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/api_failure.dart';
import '../../core/providers.dart';
import '../../data/dto/order_dto.dart';

/// A table asked of the server as its menu opens, and again after each change made from it.
final tableSheetProvider = FutureProvider.autoDispose.family<TableDetail, String>(
  (ref, floorItemId) => ref.watch(floorRepositoryProvider).table(floorItemId),
  retry: (_, _) => null,
);

/// One idempotency key per intended change, kept until the change goes through or is refused — so
/// that pressing again after a lost answer replays it instead of doing it twice.
class IdempotencyKeys {
  final _keys = <String, String>{};
  final _uuid = const Uuid();

  /// [intent] names the change and what it is aimed at, such as `transfer:<session>:<table>`.
  Future<T> run<T>(String intent, Future<T> Function(String key) send) async {
    final key = _keys.putIfAbsent(intent, _uuid.v4);
    try {
      final result = await send(key);
      _keys.remove(intent);
      return result;
    } on ApiFailure catch (failure) {
      // Unanswered, so it may have happened: the same key must go again.
      if (!failure.isOffline && !failure.isRetryable) _keys.remove(intent);
      rethrow;
    }
  }
}

/// Kept for the life of the app, so closing and reopening a table's menu still retries safely.
final idempotencyKeysProvider = Provider<IdempotencyKeys>((ref) => IdempotencyKeys());
