import 'package:flutter_test/flutter_test.dart';
import 'package:valorant_app/features/rank/domain/models/player_mmr.dart';

void main() {
  group('CompetitiveUpdate W/L/D tests', () {
    test('isWin is true when rankedRatingEarned > 0', () {
      const update = CompetitiveUpdate(
        matchId: 'match-1',
        tierAfterUpdate: 15,
        tierBeforeUpdate: 15,
        rankedRatingAfterUpdate: 45,
        rankedRatingBeforeUpdate: 25,
        rankedRatingEarned: 20,
        afkPenalty: 0,
        gameStartMillis: 1600000000000,
      );

      expect(update.isWin, isTrue);
      expect(update.isLoss, isFalse);
      expect(update.isDraw, isFalse);
    });

    test('isLoss is true when rankedRatingEarned < 0', () {
      const update = CompetitiveUpdate(
        matchId: 'match-2',
        tierAfterUpdate: 15,
        tierBeforeUpdate: 15,
        rankedRatingAfterUpdate: 10,
        rankedRatingBeforeUpdate: 25,
        rankedRatingEarned: -15,
        afkPenalty: 0,
        gameStartMillis: 1600000000000,
      );

      expect(update.isWin, isFalse);
      expect(update.isLoss, isTrue);
      expect(update.isDraw, isFalse);
    });

    test('isDraw is true when rankedRatingEarned == 0 and afkPenalty == 0', () {
      const update = CompetitiveUpdate(
        matchId: 'match-3',
        tierAfterUpdate: 15,
        tierBeforeUpdate: 15,
        rankedRatingAfterUpdate: 25,
        rankedRatingBeforeUpdate: 25,
        rankedRatingEarned: 0,
        afkPenalty: 0,
        gameStartMillis: 1600000000000,
      );

      expect(update.isWin, isFalse);
      expect(update.isLoss, isFalse);
      expect(update.isDraw, isTrue);
    });
  });
}
