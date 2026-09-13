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
/// reads `"₪64.00"` and `formatPrice(64, localeTag: 'he')` reads
/// `"64.00 ₪"` (with the locale's own bidi marks around each token).
String formatPrice(
  double amount, {
  required String localeTag,
  String currency = 'ILS',
}) {
  final format = NumberFormat.simpleCurrency(locale: localeTag, name: currency);
  return format.format(amount);
}
