import 'dart:ui';

import 'package:intl/intl.dart';

/// Money, the way it is written in India.
///
/// `DESIGN.md` 6.1 and `RULES.md` 5.1.2: integer **paise** in, Indian digit
/// grouping out - ₹1,20,500, not ₹120,500. Paise appear only when there are
/// any, because "₹550.00" on a price list reads like a form field, not a price.
///
/// Never used to *compute* anything. Formatting is the last thing that happens
/// to a number; arithmetic stays in integers.
String rupees(int paise) {
  final negative = paise < 0;
  final absolute = paise.abs();
  final whole = absolute ~/ 100;
  final fraction = absolute % 100;

  final digits = NumberFormat.decimalPattern('en_IN').format(whole);
  final text = fraction == 0
      ? '₹$digits'
      : '₹$digits.${fraction.toString().padLeft(2, '0')}';

  return negative ? '-$text' : text;
}

/// Tabular figures, so a column of money does not shift as its digits change
/// (`DESIGN.md` 6.1). Paired with [rupees] wherever amounts are listed.
const moneyFeatures = [FontFeature.tabularFigures()];
