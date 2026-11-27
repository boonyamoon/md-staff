import 'package:flutter/material.dart';

/// An amount of money that is shrunk to fit the room it has, rather than being cut short or
/// pushed off the screen.
class FittedAmount extends StatelessWidget {
  const FittedAmount(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Text(text, maxLines: 1, style: style),
      );
}
