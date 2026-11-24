import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n/strings.dart';
import 'core/theme/app_theme.dart';
import 'router/app_router.dart';

class MdStaffApp extends ConsumerWidget {
  const MdStaffApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final language = ref.watch(languageProvider);

    return MaterialApp.router(
      title: 'MeeD Staff',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: router,
      locale: language.locale,
      supportedLocales: AppLanguage.values.map((l) => l.locale).toList(),
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        // A handset is read at arm's length in a dim room, so the app's own type is already
        // large; letting the OS scale it past 1.3 pushes table tiles and the send bar off screen.
        maxScaleFactor: 1.3,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
