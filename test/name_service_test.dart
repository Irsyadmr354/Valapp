import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Name Service v3 Response Parsing Tests', () {
    test('parses name-service v3 array response correctly', () {
      final rawResponse = [
        {
          'Subject': '4705f38e-2750-53c3-904a-b61c7d89568e',
          'GameName': 'JettMain',
          'TagLine': 'KR1',
        },
        {
          'Subject': '11111111-2222-3333-4444-555555555555',
          'GameName': 'ReynaGod',
          'TagLine': 'SEA',
        }
      ];

      final result = <String, String>{};
      for (final entry in rawResponse) {
        final subject = entry['Subject']?.toString() ?? '';
        final gameName = entry['GameName']?.toString() ?? '';
        final tagLine = entry['TagLine']?.toString() ?? '';
        if (subject.isNotEmpty && gameName.isNotEmpty) {
          result[subject] = '$gameName#$tagLine';
        }
      }

      expect(result['4705f38e-2750-53c3-904a-b61c7d89568e'], 'JettMain#KR1');
      expect(result['11111111-2222-3333-4444-555555555555'], 'ReynaGod#SEA');
    });
  });
}
