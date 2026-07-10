import 'package:flutter_test/flutter_test.dart';
import 'package:site_manager_pro/core/services/voice_parser.dart';

void main() {
  group('VoiceParser - Attendance Commands', () {
    final workers = ['Ramesh', 'Suresh', 'Kumar', 'செல்வம்', 'ரமேஷ்'];

    test('Parses English Present', () {
      final action = VoiceParser.parse('Ramesh is present today', workerNames: workers);
      expect(action.type, VoiceActionType.attendance);
      expect(action.targetName, 'Ramesh');
      expect(action.value, 'Present');
    });

    test('Parses Tamil Present', () {
      final action = VoiceParser.parse('ரமேஷ் வருகை', workerNames: workers);
      expect(action.type, VoiceActionType.attendance);
      expect(action.targetName, 'ரமேஷ்');
      expect(action.value, 'Present');
    });

    test('Parses Tamil Absent', () {
      final action = VoiceParser.parse('செல்வம் வரவில்லை', workerNames: workers);
      expect(action.type, VoiceActionType.attendance);
      expect(action.targetName, 'செல்வம்');
      expect(action.value, 'Absent');
    });
  });

  group('VoiceParser - Material Commands', () {
    final materials = ['Cement', 'Sand', 'Steel', 'சிமெண்ட்'];

    test('Parses English Stock In', () {
      final action = VoiceParser.parse('Add 50 bags of Cement', materialNames: materials);
      expect(action.type, VoiceActionType.material);
      expect(action.targetName, 'Cement');
      expect(action.value, 'IN');
      expect(action.quantity, 50.0);
    });

    test('Parses Tamil Stock Out', () {
      final action = VoiceParser.parse('சிமெண்ட் பத்து பயன்படுத்தப்பட்டது', materialNames: materials);
      expect(action.type, VoiceActionType.material);
      expect(action.targetName, 'சிமெண்ட்');
      expect(action.value, 'OUT');
      expect(action.quantity, 10.0);
    });
  });
}
