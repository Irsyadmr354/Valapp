/// Utility functions for price and discount formatting.
library;

/// Converts a discount value from the Riot API to a percentage integer
/// suitable for display (e.g. `0.15 → 15`, `15.0 → 15`).
///
/// The Riot API consistently returns discount fields (e.g. `totalDiscountPercent`,
/// `discountPercent`) as **fractional values** in the range [0.0, 1.0].
/// Values observed in production are always ≤ 1.0.
///
/// The previous guard `value > 1 ? value : value * 100` was ambiguous for
/// the edge case of exactly 1% discount. This helper always multiplies by 100
/// and rounds, which is correct for the fractional format Riot uses.
@Deprecated('''Use normalizeDiscountPercent for all endpoints''')
int discountPercent(double value) => (value * 100).round();

/// Normalises a raw discount value from ANY Riot endpoint into 0–100 percent.
///
/// Endpoint formats differ in the wild:
/// - `TotalDiscountPercent` (featured bundles) is consistently a FRACTION ≤ 1.0;
/// - `DiscountPercent` (night-market BonusStore offers) has been observed BOTH
///   as a whole-number percent (e.g. `22`) and as a fraction depending on
///   rotation/region payloads.
///
/// Rule: values > 1 can only mean "already a percent" (a fraction cannot
/// exceed 1.0); anything else is treated as a fraction and scaled ×100.
/// This keeps both endpoint shapes correct through a single code path.
int normalizeDiscountPercent(num value) {
  final v = value.toDouble();
  return v > 1 ? v.round() : (v * 100).round();
}
