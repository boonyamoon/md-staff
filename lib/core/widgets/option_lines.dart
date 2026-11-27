import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';

/// One chosen option as a line of an order shows it. [price] is for all [quantity] of it together.
typedef OptionLine = ({String name, int quantity, num price});

/// The options of one dish, one to a row and in the order they were chosen, written the way the
/// POS writes them: `• Fried egg  +10.00`, `x2 • Crispy pork  +40.00`.
class OptionLines extends StatelessWidget {
  const OptionLines({super.key, required this.options, required this.t});

  final List<OptionLine> options;
  final AppStrings t;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final option in options)
            Text.rich(
              TextSpan(
                text: option.quantity > 1 ? 'x${option.quantity} • ${option.name}' : '• ${option.name}',
                children: [
                  if (option.price != 0)
                    TextSpan(
                      text: '  ${option.price > 0 ? '+' : ''}${t.money(option.price)}',
                      style: const TextStyle(color: MeedColors.ink, fontWeight: FontWeight.w600),
                    ),
                ],
              ),
              style: const TextStyle(fontSize: 13.5, height: 1.4, color: MeedColors.inkSoft),
            ),
        ],
      );
}
