import 'package:flutter/material.dart';

import '../network/api_failure.dart';
import '../theme/app_theme.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            if (label != null) ...[
              const SizedBox(height: 16),
              Text(label!, style: const TextStyle(color: MeedColors.inkSoft)),
            ],
          ],
        ),
      );
}

/// Shown instead of a screen's content when the first load failed. Phrased from the failure's own
/// message, which the API writes for staff rather than for developers.
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.failure,
    this.onRetry,
    this.retryLabel,
  });

  final ApiFailure failure;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                failure.isOffline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
                size: 48,
                color: MeedColors.inkSoft,
              ),
              const SizedBox(height: 16),
              Text(
                failure.message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: MeedColors.ink),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 24),
                OutlinedButton(onPressed: onRetry, child: Text(retryLabel ?? 'Retry')),
              ],
            ],
          ),
        ),
      );
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.message, this.icon});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon ?? Icons.inbox_outlined, size: 44, color: MeedColors.inkSoft),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: MeedColors.inkSoft),
              ),
            ],
          ),
        ),
      );
}

/// A one-line explanation at the top of a screen — "this device was unpaired", "your shift ended".
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({super.key, required this.message, this.tone = NoticeTone.info});

  final String message;
  final NoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, icon) = switch (tone) {
      NoticeTone.info => (const Color(0xFFE8F1FB), const Color(0xFF1B4F72), Icons.info_outline),
      NoticeTone.warning => (MeedColors.tableBusy, const Color(0xFF7D5A1E), Icons.warning_amber_rounded),
      NoticeTone.danger => (MeedColors.tableLocked, MeedColors.danger, Icons.lock_outline),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: background,
      child: Row(
        children: [
          Icon(icon, size: 20, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: foreground, fontSize: 14.5, height: 1.3)),
          ),
        ],
      ),
    );
  }
}

enum NoticeTone { info, warning, danger }
