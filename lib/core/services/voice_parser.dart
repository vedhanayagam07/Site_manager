import 'dart:developer' as dev;

// ─────────────────────────────────────────────────────────────────────────────
// Action types
// ─────────────────────────────────────────────────────────────────────────────
enum VoiceActionType {
  attendance,  // Mark worker present / absent / half day
  material,    // Stock IN / OUT
  navigation,  // Navigate to a screen
  query,       // Read/show data (stock level, site info, worker info)
  report,      // Generate or navigate to a report
  unknown,
}

// ─────────────────────────────────────────────────────────────────────────────
// VoiceAction model
// ─────────────────────────────────────────────────────────────────────────────
class VoiceAction {
  final VoiceActionType type;
  final String? targetName;    // Worker name / Material name / Site name
  final String? value;         // 'Present'/'Absent'/'Half Day' or 'IN'/'OUT' or site status
  final double? quantity;      // Qty for material
  final String rawText;
  final String? spokenReply;   // TTS response
  final bool needsFollowUp;    // True if a required param is missing
  final String? followUpQuestion; // Question to ask the user
  final String? navigationTarget; // GoRouter route e.g. '/attendance'
  final String? reportType;    // 'attendance'|'material'|'site'|'worker'

  const VoiceAction({
    required this.type,
    this.targetName,
    this.value,
    this.quantity,
    required this.rawText,
    this.spokenReply,
    this.needsFollowUp = false,
    this.followUpQuestion,
    this.navigationTarget,
    this.reportType,
  });

  @override
  String toString() =>
      'VoiceAction(type: $type, target: $targetName, value: $value, '
      'qty: $quantity, needsFollowUp: $needsFollowUp, navTarget: $navigationTarget)';
}

// ─────────────────────────────────────────────────────────────────────────────
// Local regex-based parser (fallback when Gemini is unavailable)
// Supports: English, Indian English (en-IN), Tamil (ta-IN), Tanglish (mixed)
// ─────────────────────────────────────────────────────────────────────────────
class VoiceParser {
  // ── Attendance keywords ────────────────────────────────────────────────────
  static const _presentKeywords = [
    // English / Indian English
    'present', 'came', 'come', 'attending', 'mark present',
    'attendance done', 'here today', 'came today', 'in site',
    // Tanglish
    'present pannuchu', 'present panni', 'mark panni',
    // Tamil
    'பிரசென்ட்', 'வருகை', 'வந்திருக்கிறார்', 'வந்தார்',
    'வந்தாங்க', 'வந்தாச்சு', 'உள்ளார்', 'இருக்கார்', 'வந்துட்டார்',
  ];
  static const _absentKeywords = [
    // English / Indian English
    'absent', 'not came', 'not come', 'not coming', 'not present',
    'leave today', 'on leave', 'did not come',
    // Tanglish
    'absent pannuchu', 'வரல pannuchu',
    // Tamil
    'ஆப்சென்ட்', 'இல்லை', 'வரவில்லை', 'வரல', 'வரல்ல',
    'வராத', 'வராங்க',
  ];
  static const _halfDayKeywords = [
    // English / Indian English
    'half day', 'halfday', 'half', 'half attendance',
    'morning only', 'afternoon only',
    // Tamil
    'அரை நாள்', 'அரைநாள்',
    'ஹாப் டே', 'அரை',
  ];

  // ── Material transaction keywords ──────────────────────────────────────────
  static const _addKeywords = [
    // English / Indian English
    'add', 'added', 'received', 'incoming', 'in', 'stock in',
    'brought', 'purchased', 'bought', 'arrived', 'delivered',
    // Tanglish
    'add pannu', 'add panni', 'add pannuchu',
    'வரவு பண்ணு', 'கொண்டு வந்தது',
    // Tamil
    'சேர்க்கவும்', 'சேர்', 'வரவு', 'ஏத்து', 'வாங்கு',
  ];
  static const _useKeywords = [
    // English / Indian English
    'use', 'used', 'consume', 'out', 'stock out', 'remove',
    'taken', 'utilized', 'spent', 'issued',
    // Tanglish
    'use pannu', 'use panni', 'use pannuchu',
    'எடுத்தாங்க', 'எடு பண்ணு',
    // Tamil
    'பயன்படுத்து', 'பயன்படுத்தப்பட்டது', 'செலவு', 'எடு', 'குடு', 'போடு',
    'வேண்டும்', 'தேவை',
  ];

  // ── Navigation keywords ────────────────────────────────────────────────────
  static const _navKeywords = <String, String>{
    // English
    'dashboard': '/dashboard',
    'home': '/dashboard',
    'sites': '/sites',
    'site': '/sites',
    'workers': '/workers',
    'worker': '/workers',
    'attendance': '/attendance',
    'materials': '/materials',
    'material': '/materials',
    'stock': '/materials',
    'reports': '/reports',
    'report': '/reports',
    'settings': '/settings',
    'profile': '/profile',
    // Indian English
    'show attendance': '/attendance',
    'open attendance': '/attendance',
    'show workers': '/workers',
    'open workers': '/workers',
    'show materials': '/materials',
    'open materials': '/materials',
    'show reports': '/reports',
    'open reports': '/reports',
    // Tanglish
    'வருகை பார்': '/attendance',
    'தொழிலாளர் பார்': '/workers',
    // Tamil
    'வருகை பட்டியல்': '/attendance',
    'தொழிலாளர்கள்': '/workers',
    'தளம்': '/sites',
    'பொருட்கள்': '/materials',
    'அறிக்கை': '/reports',
    'அமைப்புகள்': '/settings',
  };

  // ── Stock query keywords ───────────────────────────────────────────────────
  static const _queryKeywords = [
    // English / Indian English
    'how much', 'how many', 'stock level', 'check stock', 'show stock',
    'what is stock', 'stock available', 'available stock',
    'check', 'show', 'display', 'list', 'all', 'tell me',
    // Tanglish
    'stock பாரு', 'stock பார்', 'stock காட்டு',
    // Tamil
    'எவ்வளவு', 'எத்தனை', 'காட்டு', 'பார்',
    'இருப்பு', 'இருப்பு எவ்வளவு',
  ];

  // ── Report keywords ────────────────────────────────────────────────────────
  static const _reportKeywords = [
    // English / Indian English
    'report', 'download', 'export', 'generate', 'pdf',
    'print report', 'get report',
    // Tanglish
    'report download பண்ணு', 'report பண்ணு',
    // Tamil
    'அறிக்கை', 'டவுன்லோட்',
  ];

  // ── Tamil number words ─────────────────────────────────────────────────────
  static const Map<String, double> _tamilNumbers = {
    // Tamil Script
    'ஒன்று': 1, 'ஒன்னு': 1, 'ஒரு': 1,
    'இரண்டு': 2, 'ரெண்டு': 2,
    'மூன்று': 3, 'மூணு': 3,
    'நான்கு': 4, 'நாலு': 4,
    'ஐந்து': 5, 'அஞ்சு': 5,
    'ஆறு': 6, 'ஏழு': 7, 'எட்டு': 8, 'ஒன்பது': 9,
    'பத்து': 10, 'பதினஞ்சு': 15, 'இருபது': 20,
    'முப்பது': 30, 'நாற்பது': 40, 'ஐம்பது': 50,
    'அறுபது': 60, 'எழுபது': 70, 'எண்பது': 80,
    'தொண்ணூறு': 90, 'நூறு': 100,
    // Transliterated English/Tanglish Script
    'onnu': 1, 'oru': 1,
    'rendu': 2, 'rendu ': 2,
    'moonu': 3, 'moonu ': 3,
    'naalu': 4, 'naalu ': 4,
    'anju': 5, 'ainthu': 5,
    'aaru': 6,
    'ezhu': 7,
    'ettu': 8,
    'onbathu': 9,
    'pathu': 10,
    'pathinanchu': 15,
    'irubathu': 20,
    'muppathu': 30,
    'narpathu': 40,
    'aimbathu': 50,
    'nooru': 100,
  };

  // ── English number words ───────────────────────────────────────────────────
  static const Map<String, double> _englishNumbers = {
    'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
    'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
    'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14,
    'fifteen': 15, 'sixteen': 16, 'seventeen': 17, 'eighteen': 18,
    'nineteen': 19, 'twenty': 20, 'thirty': 30, 'forty': 40,
    'fifty': 50, 'sixty': 60, 'seventy': 70, 'eighty': 80,
    'ninety': 90, 'hundred': 100,
  };

  // ────────────────────────────────────────────────────────────────────────────
  /// Main parse entry point — returns a VoiceAction from raw transcribed text.
  /// Supports English, Indian English (en-IN), Tamil (ta-IN), Tanglish (mixed)
  // ────────────────────────────────────────────────────────────────────────────
  static VoiceAction parse(
    String text, {
    List<String> workerNames = const [],
    List<String> materialNames = const [],
    List<String> siteNames = const [],
  }) {
    final clean = text.trim().toLowerCase();
    dev.log('VoiceParser.parse: "$clean"');

    if (clean.isEmpty) {
      return VoiceAction(type: VoiceActionType.unknown, rawText: text);
    }

    // ── 1. Navigation intent ─────────────────────────────────────────────────
    for (final entry in _navKeywords.entries) {
      if (clean.contains(entry.key)) {
        return VoiceAction(
          type: VoiceActionType.navigation,
          rawText: text,
          navigationTarget: entry.value,
          spokenReply: 'Navigating to ${entry.key}…',
        );
      }
    }

    // ── 2. Report intent ─────────────────────────────────────────────────────
    if (_reportKeywords.any((kw) => clean.contains(kw))) {
      String? rType;
      if (clean.contains('attendance') || clean.contains('வருகை')) rType = 'attendance';
      if (clean.contains('material') || clean.contains('stock') || clean.contains('பொருட்')) rType = 'material';
      if (clean.contains('site') || clean.contains('தளம்')) rType = 'site';
      if (clean.contains('worker') || clean.contains('தொழிலாளர்')) rType = 'worker';
      return VoiceAction(
        type: VoiceActionType.report,
        rawText: text,
        reportType: rType,
        navigationTarget: '/reports',
        spokenReply: 'Opening reports…',
      );
    }

    // ── 3. Attendance intent ─────────────────────────────────────────────────
    String? matchedWorker;
    for (final name in workerNames) {
      if (clean.contains(name.toLowerCase())) {
        matchedWorker = name;
        break;
      }
    }

    // Also try fuzzy: if text contains first name
    if (matchedWorker == null) {
      for (final name in workerNames) {
        final parts = name.toLowerCase().split(' ');
        for (final part in parts) {
          if (part.length >= 3 && clean.contains(part)) {
            matchedWorker = name;
            break;
          }
        }
        if (matchedWorker != null) break;
      }
    }

    if (matchedWorker != null) {
      String? status;
      if (_presentKeywords.any((kw) => clean.contains(kw))) status = 'Present';
      if (_absentKeywords.any((kw) => clean.contains(kw))) status = 'Absent';
      if (_halfDayKeywords.any((kw) => clean.contains(kw))) status = 'Half Day';

      if (status != null) {
        return VoiceAction(
          type: VoiceActionType.attendance,
          targetName: matchedWorker,
          value: status,
          rawText: text,
          spokenReply: '$matchedWorker marked as $status.',
        );
      }
      // Worker found but no status keyword — ask follow-up
      return VoiceAction(
        type: VoiceActionType.attendance,
        targetName: matchedWorker,
        rawText: text,
        needsFollowUp: true,
        followUpQuestion: 'Is $matchedWorker Present, Absent, or Half Day?',
        spokenReply: 'Is $matchedWorker Present, Absent, or Half Day?',
      );
    }

    // ── 4. Material query intent ─────────────────────────────────────────────
    if (_queryKeywords.any((kw) => clean.contains(kw))) {
      String? matchedMat;
      for (final mat in materialNames) {
        if (clean.contains(mat.toLowerCase())) {
          matchedMat = mat;
          break;
        }
      }
      if (matchedMat != null) {
        return VoiceAction(
          type: VoiceActionType.query,
          targetName: matchedMat,
          rawText: text,
          spokenReply: 'Checking stock for $matchedMat…',
        );
      }
      // Query without specific material — show all
      return VoiceAction(
        type: VoiceActionType.query,
        rawText: text,
        spokenReply: 'Fetching stock levels…',
      );
    }

    // ── 5. Material transaction intent ───────────────────────────────────────
    String? matchedMaterial;
    for (final mat in materialNames) {
      if (clean.contains(mat.toLowerCase())) {
        matchedMaterial = mat;
        break;
      }
    }

    // Fallback: search parts if no exact match (e.g. "cement" matches "Ramco Cement")
    if (matchedMaterial == null) {
      for (final mat in materialNames) {
        final matLower = mat.toLowerCase();
        final parts = matLower.split(' ');
        for (final part in parts) {
          if (part.length >= 4 && clean.contains(part)) {
            matchedMaterial = mat;
            break;
          }
        }
        if (matchedMaterial != null) break;
      }
    }

    if (matchedMaterial != null) {
      String txType = 'OUT'; // default to used if material is mentioned
      if (_addKeywords.any((kw) => clean.contains(kw))) txType = 'IN';
      if (_useKeywords.any((kw) => clean.contains(kw))) txType = 'OUT';

      final qty = _extractQuantity(clean);

      if (qty == null) {
        return VoiceAction(
          type: VoiceActionType.material,
          targetName: matchedMaterial,
          value: txType,
          rawText: text,
          needsFollowUp: true,
          followUpQuestion: 'How many units of $matchedMaterial?',
          spokenReply: 'How many units of $matchedMaterial?',
        );
      }

      final typeLabel = txType == 'IN' ? 'Stock In' : 'Stock Out';
      return VoiceAction(
        type: VoiceActionType.material,
        targetName: matchedMaterial,
        value: txType,
        quantity: qty,
        rawText: text,
        spokenReply:
            '$typeLabel: ${qty.toInt()} units of $matchedMaterial confirmed.',
      );
    }

    return VoiceAction(type: VoiceActionType.unknown, rawText: text);
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Helpers
  // ────────────────────────────────────────────────────────────────────────────
  static double? _extractQuantity(String text) {
    // Digits first
    final digitMatch = RegExp(r'\d+(\.\d+)?').firstMatch(text);
    if (digitMatch != null) return double.tryParse(digitMatch.group(0)!);

    // Tamil number words
    for (final entry in _tamilNumbers.entries) {
      if (text.contains(entry.key)) return entry.value;
    }

    // English number words
    for (final entry in _englishNumbers.entries) {
      if (text.contains(entry.key)) return entry.value;
    }

    return null;
  }
}
