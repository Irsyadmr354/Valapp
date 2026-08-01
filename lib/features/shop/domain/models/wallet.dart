/// Valorant currency UUID constants.
class ValorantCurrency {
  ValorantCurrency._();
  static const vpUuid = '85ad13f7-3d1b-5128-9eb2-7cd8ee0b5741';
  static const rpUuid = 'e59aa87c-4cbf-517a-5983-6e81511be9b7';
  static const kcUuid = '85ca954a-41f2-ce94-9b45-8ca3dd39a00d';
  static const freeAgentUuid = 'f08d4ae3-939c-4576-ab26-09ce1f23bb37';
}

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
      valorantPoints:
          (balances[ValorantCurrency.vpUuid] as num?)?.toInt() ?? 0,
      radianitePoints:
          (balances[ValorantCurrency.rpUuid] as num?)?.toInt() ?? 0,
      kingdomCredits:
          (balances[ValorantCurrency.kcUuid] as num?)?.toInt() ?? 0,
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
