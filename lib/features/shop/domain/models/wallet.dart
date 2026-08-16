import '../../../../shared/constants/valorant_constants.dart';

/// Valorant currency UUID constants (delegates to centralized [ValorantCurrencies]).
typedef ValorantCurrency = ValorantCurrencies;

/// Player's in-game currency balances.
class Wallet {
  final int valorantPoints;
  final int radianitePoints;
  final int kingdomCredits;
  final int freeAgentCurrency;

  const Wallet({
    required this.valorantPoints,
    required this.radianitePoints,
    required this.kingdomCredits,
    required this.freeAgentCurrency,
  });

  factory Wallet.fromJson(Map<String, dynamic> json) {
    final balances = json['Balances'] as Map<String, dynamic>? ?? {};
    return Wallet(
      valorantPoints: (balances[ValorantCurrency.vpUuid] as num?)?.toInt() ?? 0,
      radianitePoints:
          (balances[ValorantCurrency.rpUuid] as num?)?.toInt() ?? 0,
      kingdomCredits: (balances[ValorantCurrency.kcUuid] as num?)?.toInt() ?? 0,
      freeAgentCurrency:
          (balances[ValorantCurrency.freeAgentUuid] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'vp': valorantPoints,
        'rp': radianitePoints,
        'kc': kingdomCredits,
        'fa': freeAgentCurrency,
      };
}
