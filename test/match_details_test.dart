import 'package:flutter_test/flutter_test.dart';
import 'package:valorant_app/features/match/domain/models/match_details.dart';
import 'package:valorant_app/features/match/domain/models/match_history.dart';

void main() {
  group('MatchDetails.resultForPlayer', () {
    test('ignores rounds without a winner', () {
      final details = MatchDetails.fromJson({
        'players': [
          {'subject': 'player', 'teamId': 'Red'},
        ],
        'roundResults': [
          {'winningTeam': 'Red'},
          {'winningTeam': 'Blue'},
          {'winningTeam': 'Red'},
          {'winningTeam': ''},
        ],
      });

      expect(details.resultForPlayer('player'), MatchResult.victory);
    });

    test('returns unknown for a player without a team', () {
      final details = MatchDetails.fromJson({
        'players': [
          {'subject': 'player', 'teamId': ''},
        ],
        'roundResults': [
          {'winningTeam': ''},
        ],
      });

      expect(details.resultForPlayer('player'), MatchResult.unknown);
    });
  });

  group('MatchDetails.scoreStringForPlayer', () {
    test('builds the win – loss score string for a player', () {
      final details = MatchDetails.fromJson({
        'players': [
          {'subject': 'player', 'teamId': 'Red'},
          {'subject': 'other', 'teamId': 'Blue'},
        ],
        'roundResults': [
          {'winningTeam': 'Red'},
          {'winningTeam': 'Red'},
          {'winningTeam': 'Blue'},
          {'winningTeam': 'Blue'},
          {'winningTeam': 'Red'},
        ],
      });

      expect(details.scoreStringForPlayer('player'), '3 – 2');
    });

    test('ignores rounds without a winner in the score', () {
      final details = MatchDetails.fromJson({
        'players': [
          {'subject': 'player', 'teamId': 'Red'},
        ],
        'roundResults': [
          {'winningTeam': 'Red'},
          {'winningTeam': 'Blue'},
          {'winningTeam': 'Red'},
          {'winningTeam': ''},
        ],
      });

      expect(details.scoreStringForPlayer('player'), '2 – 1');
    });

    test('returns null when the player is not in the match', () {
      final details = MatchDetails.fromJson({
        'players': [
          {'subject': 'player', 'teamId': 'Red'},
        ],
        'roundResults': [
          {'winningTeam': 'Red'},
        ],
      });

      expect(details.scoreStringForPlayer('stranger'), isNull);
    });

    test('returns null when there are no round results', () {
      final details = MatchDetails.fromJson({
        'players': [
          {'subject': 'player', 'teamId': 'Red'},
        ],
        'roundResults': [],
      });

      expect(details.scoreStringForPlayer('player'), isNull);
    });
  });
}
