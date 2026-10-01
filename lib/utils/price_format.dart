/// Price formatting for dish prices in ILS (architecture.md §6.1, §12).
///
/// Wolt reports prices in integer agorot and 10bis in decimal ILS; both
/// adapters convert to major units before a `Dish` is built (see
/// `Dish.price` in `lib/models/menu.dart`), so this file only formats an
/// already-converted major-unit amount for display.
library;

import 'package:intl/intl.dart';

/// Formats [amount] (already in major units, e.g. ILS not agorot) as a
/// currency string for [localeTag].
///
/// [currency] is an ISO 4217 code; it defaults to `'ILS'` because every
/// restaurant platform KetoClub reads from (README's Platform
/// Architectural Comparison table) prices in Israeli shekels. Symbol
/// placement and decimal grouping follow [localeTag] via `package:intl`
/// (`NumberFormat.simpleCurrency`), so `formatPrice(64, localeTag: 'en')`
/// reads `"₪64"` and `formatPrice(64, localeTag: 'he')` reads `"64 ₪"`
/// (with the locale's own bidi marks around each token). Whole-shekel
/// prices render without decimals (issue #169): every menu platform
/// today prices most dishes in whole shekels, so `.00` on every card
/// only added visual noise (audit M12). A fractional amount still renders
/// to two decimals, e.g. `formatPrice(12.5, localeTag: 'en')` → `"₪12.50"`.
String formatPrice(
  double amount, {
  required String localeTag,
  String currency = 'ILS',
}) {
  // Judge "whole" after rounding to agorot, so 141.999 (which prints as
  // 142.00) is shown as "₪142" rather than "₪142.00".
  final cents = (amount * 100).round();
  final isWhole = cents % 100 == 0;
  final format = NumberFormat.simpleCurrency(locale: localeTag, name: currency);
  if (isWhole) {
    format
      ..minimumFractionDigits = 0
      ..maximumFractionDigits = 0;
  }
  return format.format(amount);
}
