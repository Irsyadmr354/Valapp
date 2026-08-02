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
int discountPercent(double value) => (value * 100).round();
