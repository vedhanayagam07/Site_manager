import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'voice_parser.dart';

class AiNluService {
  // ─────────────────────────────────────────────────────────────────────────────
  // Configuration: Cloud AI (Gemini) Flag
  // Set to false to avoid paid API calls and eliminate runtime API key dependence.
  //
  // HOW TO RE-ENABLE IN THE FUTURE:
  // 1. Recommended (Production): Route NLU requests through a Supabase Edge Function
  //    (e.g., 'ai-assistant') so the API key is kept server-side in Supabase secrets.
  // 2. Alternative (Direct): Set isGeminiEnabled = true and configure GEMINI_API_KEY
  //    in your backend or environment variables.
  // ─────────────────────────────────────────────────────────────────────────────
  static const bool isGeminiEnabled = false;

  GenerativeModel? _model;

  AiNluService() {
    if (!isGeminiEnabled) {
      debugPrint('[AiNluService] Cloud AI is on hold. Operating in deterministic local parsing mode.');
      return;
    }

    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (apiKey.isNotEmpty) {
      _model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          temperature: 0.1,
          maxOutputTokens: 512,
        ),
      );
    } else {
      debugPrint('[AiNluService] No GEMINI_API_KEY configured. Falling back to local parser.');
    }
  }

  /// Indicates whether the Cloud AI model is active and ready for inference.
  bool get isAiAvailable => isGeminiEnabled && _model != null;

  // ─────────────────────────────────────────────────────────────────────────
  /// Parse speech text into a structured [VoiceAction].
  /// When [isGeminiEnabled] is false, uses the fast, deterministic [VoiceParser].
  // ─────────────────────────────────────────────────────────────────────────
  Future<VoiceAction> parseSpokenText(
    String text, {
    List<String> workerNames = const [],
    List<String> materialNames = const [],
    List<String> siteNames = const [],
    bool isTamil = false,
  }) async {
    // 1. Try Cloud AI if enabled and initialized
    if (isAiAvailable) {
      try {
        return await _parseWithGemini(
          text,
          workerNames: workerNames,
          materialNames: materialNames,
          siteNames: siteNames,
          isTamil: isTamil,
        );
      } catch (e) {
        debugPrint('[AiNluService] Gemini error, falling back to local parser: $e');
      }
    }

    // 2. Safe deterministic local parser (supports English, Tamil, Tanglish)
    return VoiceParser.parse(
      text,
      workerNames: workerNames,
      materialNames: materialNames,
      siteNames: siteNames,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Preserved Gemini AI Implementation (for future server/client re-enablement)
  // ─────────────────────────────────────────────────────────────────────────
  Future<VoiceAction> _parseWithGemini(
    String text, {
    required List<String> workerNames,
    required List<String> materialNames,
    required List<String> siteNames,
    required bool isTamil,
  }) async {
    final workersCtx = workerNames.isNotEmpty
        ? 'Known workers: ${workerNames.join(', ')}'
        : 'No known workers loaded.';
    final matsCtx = materialNames.isNotEmpty
        ? 'Known materials: ${materialNames.join(', ')}'
        : 'No known materials loaded.';
    final sitesCtx = siteNames.isNotEmpty
        ? 'Known sites: ${siteNames.join(', ')}'
        : 'No known sites loaded.';
    final prompt = '''
You are an AI assistant for a construction site management app (TSR Site Manager Pro).
The user is a construction site manager or supervisor in India.
They may speak in Tamil, Indian English (en-IN), or a mix of Tamil + English (Tanglish).
Parse the spoken command and return a structured JSON response.

CONTEXT:
$workersCtx
$matsCtx
$sitesCtx

LANGUAGE NOTE:
- The spoken text may be in Tamil, Indian English, or Tanglish (mixed Tamil+English).
- Indian English patterns: "Mark attendance", "Do attendance", "Add cement bags", "Check stock"
- Tanglish patterns: "Cement stock காட்டு", "Raja attendance mark பண்ணு", "Material report download பண்ணு"
- Pure Tamil: "இன்று வருகை பதிவு செய்", "சிமெண்ட் இருப்பு எவ்வளவு?"
- Always match names case-insensitively and handle partial matches.

SUPPORTED ACTIONS:
1. ATTENDANCE - Mark worker attendance
   - Required: targetName (worker name, match closest from known workers), value ("Present" | "Absent" | "Half Day")
   - Indian English: "mark present", "attendance done", "came today", "not coming"
   - Tamil: வந்திருக்கிறார்→Present, வரவில்லை→Absent, அரை நாள்→Half Day
   - If worker name or value is missing, set needsFollowUp=true

2. MATERIAL - Stock transaction
   - Required: targetName (material name from known list), value ("IN" for received/added | "OUT" for used/consumed), quantity (number)
   - Indian English: "add", "received", "brought", "used", "consumed", "taken"
   - Tamil: சேர்க்கவும்/வரவு → IN; பயன்படுத்து/எடு → OUT
   - Tanglish: "cement add பண்ணு", "sand use பண்ணுச்சு"
   - If quantity missing, set needsFollowUp=true, followUpQuestion="How many units of [material]?"

3. NAVIGATION - Navigate to a screen
   - Set navigationTarget to one of: "/dashboard" | "/sites" | "/workers" | "/attendance" | "/materials" | "/reports" | "/settings" | "/profile"
   - Tamil: வருகை→attendance, தொழிலாளர்→workers, தளம்→sites, பொருட்கள்→materials, அறிக்கை→reports
   - Indian English: "show attendance", "open workers", "go to materials"

4. QUERY - Read/show data without modifying anything
   - "Cement stock எவ்வளவு?" → type=QUERY, targetName=cement
   - "How many bags of sand?" → type=QUERY, targetName=sand
   - "Low stock materials" → type=QUERY, value=lowStock
   - "Show all materials" → type=QUERY (no targetName)

5. REPORT - Generate or navigate to a report
   - reportType: "attendance" | "material" | "site" | "worker"
   - "Download attendance report", "அறிக்கை export பண்ணு"

6. UNKNOWN - Cannot understand the command

RULES:
- Match worker and material names case-insensitively using the known lists provided above
- Tamil numbers: ஒன்று=1, இரண்டு=2, மூன்று=3, நான்கு=4, ஐந்து=5, ஆறு=6, ஏழு=7, எட்டு=8, ஒன்பது=9, பத்து=10, ஐம்பது=50, நூறு=100
- If a number word is spoken (e.g., "fifty bags"), convert to numeric quantity
- spokenReply must be in the SAME language/mix as the input
- Keep spokenReply short and natural (max 20 words)
- For Indian English: reply naturally like "Attendance marked for Raja."
- For Tamil: reply in Tamil like "வருகை வெற்றிகரமாக பதிவு செய்யப்பட்டது."
- For Tanglish: reply naturally like "Cement stock updated successfully."

SPOKEN TEXT: "$text"

RESPOND WITH EXACTLY THIS JSON SCHEMA (no extra fields, no markdown):
{
  "action": "ATTENDANCE" | "MATERIAL" | "NAVIGATION" | "QUERY" | "REPORT" | "UNKNOWN",
  "targetName": string | null,
  "value": string | null,
  "quantity": number | null,
  "navigationTarget": string | null,
  "reportType": string | null,
  "needsFollowUp": boolean,
  "followUpQuestion": string | null,
  "spokenReply": string
}
''';

    final response = await _model!.generateContent([Content.text(prompt)]);
    final raw = response.text ?? '{}';
    debugPrint('[AiNluService] Raw response: $raw');

    return _parseGeminiJson(raw, text);
  }

  VoiceAction _parseGeminiJson(String raw, String originalText) {
    try {
      // Strip markdown code fences if present
      final cleaned = raw
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      final Map<String, dynamic> json = jsonDecode(cleaned);
      final actionStr = (json['action'] as String? ?? 'UNKNOWN').toUpperCase();

      VoiceActionType type;
      switch (actionStr) {
        case 'ATTENDANCE':
          type = VoiceActionType.attendance;
        case 'MATERIAL':
          type = VoiceActionType.material;
        case 'NAVIGATION':
          type = VoiceActionType.navigation;
        case 'QUERY':
          type = VoiceActionType.query;
        case 'REPORT':
          type = VoiceActionType.report;
        default:
          type = VoiceActionType.unknown;
      }

      return VoiceAction(
        type: type,
        targetName: json['targetName'] as String?,
        value: json['value'] as String?,
        quantity: (json['quantity'] as num?)?.toDouble(),
        rawText: originalText,
        spokenReply: json['spokenReply'] as String?,
        needsFollowUp: json['needsFollowUp'] as bool? ?? false,
        followUpQuestion: json['followUpQuestion'] as String?,
        navigationTarget: json['navigationTarget'] as String?,
        reportType: json['reportType'] as String?,
      );
    } catch (e) {
      debugPrint('[AiNluService] JSON parse error: $e\nRaw: $raw');
      return VoiceAction(type: VoiceActionType.unknown, rawText: originalText);
    }
  }
}
