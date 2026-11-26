import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/strings.dart';
import '../network/api_failure.dart';
import '../providers.dart';
import 'states.dart';

/// Says that what is on screen is an older copy, why, and from when.
class StaleBanner extends ConsumerWidget {
  const StaleBanner({super.key, required this.failure, required this.fetchedAt});

  final ApiFailure failure;
  final DateTime? fetchedAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final reason = failure.isOffline ? t('common.offlineShort') : t.failure(failure);
    final at = fetchedAt;
    return NoticeBanner(
      tone: NoticeTone.warning,
      message: at == null
          ? reason
          : '$reason · ${t('common.dataAsOf')} ${t.time(at, now: ref.watch(clockProvider)())}',
    );
  }
}
