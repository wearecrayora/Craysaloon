import 'package:craysalon/core/format/money.dart';
import 'package:flutter_test/flutter_test.dart';

/// Indian digit grouping is not "thousands separators with a different symbol":
/// it groups the last three, then twos. ₹1,20,500 - not ₹120,500. Getting this
/// wrong makes every price in the app look foreign (`DESIGN.md` 6.1).
void main() {
  test('Indian grouping, not Western', () {
    expect(rupees(12050000), '₹1,20,500');
    expect(rupees(100000000), '₹10,00,000');
    expect(rupees(1000000000), '₹1,00,00,000');
  });

  test('small amounts', () {
    expect(rupees(0), '₹0');
    expect(rupees(100), '₹1');
    expect(rupees(99900), '₹999');
    expect(rupees(100000), '₹1,000');
  });

  test('paise appear only when there are any', () {
    // "₹550.00" on a price list reads like a form field, not a price.
    expect(rupees(55000), '₹550');
    expect(rupees(55050), '₹550.50');
    expect(rupees(55005), '₹550.05');
  });

  test('a reversal is shown as negative, never as a positive in red', () {
    expect(rupees(-55000), '-₹550');
    expect(rupees(-55050), '-₹550.50');
  });

  test('paise are integers all the way through - no float rounding', () {
    // 0.1 + 0.2 in paise is 30, and stays 30.
    expect(rupees(10 + 20), '₹0.30');
    // A rupee value that a double would render as 8.299999...
    expect(rupees(830), '₹8.30');
  });
}
