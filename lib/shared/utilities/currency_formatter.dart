// lib/shared/utils/currency_formatter.dart

/// Formats [amount] as a Malawian Kwacha string with thousands separators.
/// e.g. 25000.0 → "25,000"  |  1500.50 → "1,500.50"
String formatMwk(double amount) {
  final isWhole = amount == amount.truncateToDouble();
  final parts = (isWhole
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2))
      .split('.');
  final intPart = parts[0]
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return isWhole ? intPart : '$intPart.${parts[1]}';
}