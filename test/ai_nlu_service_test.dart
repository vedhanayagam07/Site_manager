import 'package:flutter_test/flutter_test.dart';
import 'package:site_manager_pro/core/services/ai_nlu_service.dart';
import 'package:site_manager_pro/core/services/voice_parser.dart';

void main() {
  group('AiNluService - Disabled Gemini Configuration', () {
    test('isGeminiEnabled flag is false to prevent paid API calls', () {
      expect(AiNluService.isGeminiEnabled, isFalse);
    });

    test('isAiAvailable reports false when Gemini integration is disabled', () {
      final service = AiNluService();
      expect(service.isAiAvailable, isFalse);
    });
  });

  group('AiNluService - Deterministic Local Fallback Parsing', () {
    late AiNluService service;
    final workers = ['Ramesh', 'Suresh', 'ரமேஷ்'];
    final materials = ['Cement', 'Sand', 'சிமெண்ட்'];
    final sites = ['Tower A', 'Site Alpha'];

    setUp(() {
      service = AiNluService();
    });

    test('Parses English attendance command deterministically without Gemini API call', () async {
      final action = await service.parseSpokenText(
        'Mark Ramesh present',
        workerNames: workers,
        materialNames: materials,
        siteNames: sites,
      );

      expect(action.type, VoiceActionType.attendance);
      expect(action.targetName, 'Ramesh');
      expect(action.value, 'Present');
    });

    test('Parses Tamil attendance command deterministically', () async {
      final action = await service.parseSpokenText(
        'ரமேஷ் வருகை',
        workerNames: workers,
        materialNames: materials,
        siteNames: sites,
        isTamil: true,
      );

      expect(action.type, VoiceActionType.attendance);
      expect(action.targetName, 'ரமேஷ்');
      expect(action.value, 'Present');
    });

    test('Parses material addition command deterministically', () async {
      final action = await service.parseSpokenText(
        'Add 50 bags of Cement',
        workerNames: workers,
        materialNames: materials,
        siteNames: sites,
      );

      expect(action.type, VoiceActionType.material);
      expect(action.targetName, 'Cement');
      expect(action.value, 'IN');
      expect(action.quantity, 50.0);
    });

    test('Returns VoiceActionType.unknown without fabricating results for unrecognized input', () async {
      final action = await service.parseSpokenText(
        'Play jazz music',
        workerNames: workers,
        materialNames: materials,
        siteNames: sites,
      );

      expect(action.type, VoiceActionType.unknown);
      expect(action.targetName, isNull);
      expect(action.value, isNull);
    });

    test('Parses navigation command deterministically', () async {
      final action = await service.parseSpokenText(
        'Open materials',
        workerNames: workers,
        materialNames: materials,
        siteNames: sites,
      );

      expect(action.type, VoiceActionType.navigation);
      expect(action.navigationTarget, '/materials');
    });
  });
}
