import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/voice_service.dart';
import '../services/voice_parser.dart';
import '../services/ai_nlu_service.dart';
import '../services/tts_service.dart';
import '../services/activity_log_service.dart';
import '../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Sheet state machine
// ─────────────────────────────────────────────────────────────────────────────
enum _SheetState { idle, listening, parsing, followUp, executing, success, error, queryResult }

class VoiceAssistantSheet extends StatefulWidget {
  final List<String> workerNames;
  final List<String> materialNames;
  final List<String> siteNames;
  /// Called after a data-modifying action so the caller can refresh.
  final VoidCallback? onRefresh;
  /// Called for navigation intents (after sheet closes).
  final Function(String route)? onNavigate;
  /// Called when an action is parsed, if the caller wants to handle it instead of the sheet.
  final Function(VoiceAction)? onActionConfirmed;

  const VoiceAssistantSheet({
    super.key,
    this.workerNames = const [],
    this.materialNames = const [],
    this.siteNames = const [],
    this.onRefresh,
    this.onNavigate,
    this.onActionConfirmed,
  });

  static Future<void> show(
    BuildContext context, {
    List<String> workerNames = const [],
    List<String> materialNames = const [],
    List<String> siteNames = const [],
    VoidCallback? onRefresh,
    Function(String route)? onNavigate,
    Function(VoiceAction)? onActionConfirmed,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VoiceAssistantSheet(
        workerNames: workerNames,
        materialNames: materialNames,
        siteNames: siteNames,
        onRefresh: onRefresh,
        onNavigate: onNavigate,
        onActionConfirmed: onActionConfirmed,
      ),
    );
  }

  @override
  State<VoiceAssistantSheet> createState() => _VoiceAssistantSheetState();
}

class _VoiceAssistantSheetState extends State<VoiceAssistantSheet>
    with SingleTickerProviderStateMixin {
  final _voiceService = VoiceService();
  final _aiNluService = AiNluService();
  final _ttsService = TtsService();
  final _supabase = Supabase.instance.client;
  late AnimationController _pulseController;

  String _currentLocale = 'en-IN'; // Default to Indian English
  String _transcribedText = '';
  _SheetState _sheetState = _SheetState.idle;
  String _statusMessage = 'Tap the microphone to start speaking…';
  String? _errorMessage;
  String? _successMessage;
  List<Map<String, dynamic>> _queryResults = [];

  bool _showTextInput = false;
  final _textInputController = TextEditingController();
  final _followUpController = TextEditingController();

  // For follow-up flow
  String? _pendingFollowUpQuestion;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _toggleListening());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _voiceService.stopListening();
    _ttsService.stop();
    _textInputController.dispose();
    _followUpController.dispose();
    super.dispose();
  }

  bool get _isTamil => _currentLocale == 'ta-IN';
  bool get _isIndianEnglish => _currentLocale == 'en-IN';
  bool get _isListening => _sheetState == _SheetState.listening;

  // ────────────────────────────────────────────────────────────────────────────
  // Voice
  // ────────────────────────────────────────────────────────────────────────────
  Future<void> _toggleListening() async {
    if (_isListening) {
      await _voiceService.stopListening();
      _pulseController.stop();
      _setState(_SheetState.parsing, _isTamil ? 'கட்டளை பகுப்பாய்வு செய்யப்படுகிறது…' : 'Analyzing command…');
      await _parseText(_transcribedText);
    } else {
      setState(() {
        _transcribedText = '';
        _errorMessage = null;
        _successMessage = null;
        _queryResults = [];
      });
      _setState(
        _SheetState.listening,
        _isTamil ? 'கேட்கிறேன்… பேசவும்.' : 'Listening… please speak.',
      );
      _pulseController.repeat(reverse: true);

      await _voiceService.startListening(
        localeId: _currentLocale,
        onResult: (text, isFinal) {
          if (mounted) setState(() => _transcribedText = text);
          if (isFinal) {
            _voiceService.stopListening();
            _pulseController.stop();
            _setState(_SheetState.parsing, _isTamil ? 'கட்டளை பகுப்பாய்வு…' : 'Analyzing…');
            _parseText(text);
          }
        },
        onDone: () async {
          if (!mounted) return;
          _pulseController.stop();
          if (_sheetState == _SheetState.listening) {
            _setState(_SheetState.parsing, _isTamil ? 'கட்டளை பகுப்பாய்வு…' : 'Analyzing…');
            await _parseText(_transcribedText);
          }
        },
        onError: (err) {
          if (!mounted) return;
          _setState(_SheetState.idle, '');
          setState(() => _errorMessage = err);
          _pulseController.stop();
        },
      );
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Parsing
  // ────────────────────────────────────────────────────────────────────────────
  Future<void> _parseText(String text) async {
    if (!mounted) return;
    if (text.trim().isEmpty) {
      _setState(_SheetState.idle, _isTamil
          ? 'பேச்சு கண்டறியப்படவில்லை. மீண்டும் முயற்சிக்கவும்.'
          : 'No speech detected. Please try again.');
      return;
    }

    try {
      final action = await _aiNluService.parseSpokenText(
        text,
        workerNames: widget.workerNames,
        materialNames: widget.materialNames,
        siteNames: widget.siteNames,
        isTamil: _isTamil,
      );

      if (!mounted) return;

      if (action.spokenReply != null && action.spokenReply!.isNotEmpty) {
        _ttsService.speak(action.spokenReply!, languageCode: _currentLocale);
      }

      if (action.needsFollowUp) {
        _pendingFollowUpQuestion = action.followUpQuestion;
        _setState(_SheetState.followUp, action.followUpQuestion ?? '');
        return;
      }

      if (action.type == VoiceActionType.unknown) {
        _setState(_SheetState.idle,
            _isTamil ? 'கட்டளை புரியவில்லை. மீண்டும் முயற்சிக்கவும்.' : 'Command not understood. Please try again.');
        return;
      }

      if (widget.onActionConfirmed != null) {
        Navigator.pop(context);
        widget.onActionConfirmed!(action);
        return;
      }

      await _executeAction(action);
    } catch (e) {
      debugPrint('[VoiceAssistantSheet] Parse error: $e');
      if (!mounted) return;
      _setState(_SheetState.idle, '');
      setState(() => _errorMessage = _isTamil ? 'பிழை: $e' : 'Error: $e');
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Follow-up question flow
  // ────────────────────────────────────────────────────────────────────────────
  Future<void> _submitFollowUp() async {
    final answer = _followUpController.text.trim();
    if (answer.isEmpty) return;
    _followUpController.clear();

    // Combine original text + answer and re-parse
    final combined = '$_transcribedText $answer';
    setState(() => _transcribedText = combined);
    _setState(_SheetState.parsing, _isTamil ? 'கட்டளை பகுப்பாய்வு…' : 'Analyzing…');
    await _parseText(combined);
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Action execution router
  // ────────────────────────────────────────────────────────────────────────────
  Future<void> _executeAction(VoiceAction action) async {
    switch (action.type) {
      case VoiceActionType.attendance:
        await _executeAttendance(action);
      case VoiceActionType.material:
        await _executeMaterial(action);
      case VoiceActionType.navigation:
        _executeNavigation(action);
      case VoiceActionType.query:
        await _executeQuery(action);
      case VoiceActionType.report:
        _executeReport(action);
      default:
        _setState(_SheetState.idle,
            _isTamil ? 'கட்டளை புரியவில்லை.' : 'Command not understood.');
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Attendance execution
  // ────────────────────────────────────────────────────────────────────────────
  Future<void> _executeAttendance(VoiceAction action) async {
    _setState(_SheetState.executing,
        _isTamil ? 'வருகை பதிவு செய்கிறது…' : 'Marking attendance…');

    try {
      final workerName = action.targetName ?? '';
      final status = action.value ?? 'Present';
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // Find worker by name
      final workers = await _supabase
          .from('workers')
          .select('id, name, site_id')
          .ilike('name', '%$workerName%')
          .limit(1);

      if (!mounted) return;

      if ((workers as List).isEmpty) {
        _setState(_SheetState.error, '');
        setState(() => _errorMessage =
            _isTamil ? '"$workerName" என்ற தொழிலாளர் இல்லை.' : 'Worker "$workerName" not found.');
        return;
      }

      final worker = workers.first;
      final workerId = worker['id'];
      final siteId = worker['site_id'];

      await _supabase.from('site_attendance').upsert(
        {
          'worker_id': workerId,
          'site_id': siteId,
          'attendance_date': today,
          'status': status,
        },
        onConflict: 'worker_id,attendance_date',
      );

      if (!mounted) return;

      final successMsg = _isTamil
          ? '${worker['name']} — $status பதிவு செய்யப்பட்டது ✓'
          : '${worker['name']} marked as $status ✓';

      _setState(_SheetState.success, successMsg);
      setState(() => _successMessage = successMsg);

      await activityLog.log(
        action: 'Attendance Marked',
        module: 'Attendance',
        description: 'Voice: ${worker['name']} → $status on $today',
        newValue: status,
      );

      widget.onRefresh?.call();
      _autoClose();
    } catch (e) {
      if (!mounted) return;
      _setState(_SheetState.error, '');
      setState(() => _errorMessage = e.toString());
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Material execution
  // ────────────────────────────────────────────────────────────────────────────
  Future<void> _executeMaterial(VoiceAction action) async {
    _setState(_SheetState.executing,
        _isTamil ? 'பொருட்கள் புதுப்பிக்கிறது…' : 'Updating stock…');

    try {
      final matName = action.targetName ?? '';
      final txType = action.value == 'IN' ? 'RECEIVED' : 'USED';
      final qty = action.quantity ?? 1.0;

      // Find material
      final mats = await _supabase
          .from('materials')
          .select()
          .ilike('name', '%$matName%')
          .limit(1);

      if (!mounted) return;

      if ((mats as List).isEmpty) {
        _setState(_SheetState.error, '');
        setState(() => _errorMessage =
            _isTamil ? '"$matName" என்ற பொருள் இல்லை.' : 'Material "$matName" not found.');
        return;
      }

      final material = mats.first;
      final matId = material['id'];
      final currentStock = (material['balance_qty'] ?? 0).toDouble();
      final newStock = txType == 'RECEIVED' ? currentStock + qty : currentStock - qty;

      if (newStock < 0) {
        _setState(_SheetState.error, '');
        setState(() => _errorMessage = _isTamil
            ? 'போதுமான இருப்பு இல்லை. தற்போதைய: ${currentStock.toInt()}'
            : 'Insufficient stock. Current: ${currentStock.toInt()}');
        return;
      }

      // Insert transaction
      await _supabase.from('material_transactions').insert({
        'material_id': matId,
        'transaction_type': txType,
        'quantity': qty,
        'remarks': 'Voice command',
        'site_name': '',
      });

      // Update balance
      await _supabase.from('materials').update({'balance_qty': newStock}).eq('id', matId);

      if (!mounted) return;

      final typeLabel = txType == 'RECEIVED'
          ? (_isTamil ? 'சேர்க்கப்பட்டது' : 'Added')
          : (_isTamil ? 'பயன்படுத்தப்பட்டது' : 'Used');
      final successMsg =
          '${material['name']}: ${qty.toInt()} ${_isTamil ? 'அலகு' : 'units'} $typeLabel ✓';

      _setState(_SheetState.success, successMsg);
      setState(() => _successMessage = successMsg);

      await activityLog.log(
        action: txType == 'RECEIVED' ? 'Stock In' : 'Stock Out',
        module: 'Materials',
        description: 'Voice: ${material['name']} × ${qty.toInt()} ($typeLabel)',
        oldValue: currentStock.toStringAsFixed(1),
        newValue: newStock.toStringAsFixed(1),
      );

      widget.onRefresh?.call();
      _autoClose();
    } catch (e) {
      if (!mounted) return;
      _setState(_SheetState.error, '');
      setState(() => _errorMessage = e.toString());
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Navigation execution
  // ────────────────────────────────────────────────────────────────────────────
  void _executeNavigation(VoiceAction action) {
    final route = action.navigationTarget;
    if (route == null) return;

    Navigator.pop(context);
    Future.microtask(() => widget.onNavigate?.call(route));

    activityLog.log(
      action: 'Voice Navigation',
      module: 'Navigation',
      description: 'Voice: navigated to $route',
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Query execution
  // ────────────────────────────────────────────────────────────────────────────
  Future<void> _executeQuery(VoiceAction action) async {
    _setState(_SheetState.executing,
        _isTamil ? 'தகவல் தேடுகிறது…' : 'Fetching data…');

    try {
      List<Map<String, dynamic>> results = [];

      if (action.targetName != null) {
        // Specific material stock query
        final mats = await _supabase
            .from('materials')
            .select('name, balance_qty, unit, minimum_stock')
            .ilike('name', '%${action.targetName}%');
        results = List<Map<String, dynamic>>.from(mats);
      } else if (action.value == 'lowStock') {
        // Low stock query
        final mats = await _supabase
            .from('materials')
            .select('name, balance_qty, unit, minimum_stock')
            .order('balance_qty');
        final all = List<Map<String, dynamic>>.from(mats);
        results = all.where((m) {
          final bal = (m['balance_qty'] ?? 0) as num;
          final min = (m['minimum_stock'] ?? 10) as num;
          return bal <= min;
        }).toList();
      } else {
        // Generic material list
        final mats = await _supabase
            .from('materials')
            .select('name, balance_qty, unit')
            .order('name')
            .limit(10);
        results = List<Map<String, dynamic>>.from(mats);
      }

      if (!mounted) return;
      setState(() {
        _queryResults = results;
        _sheetState = _SheetState.queryResult;
        _statusMessage = _isTamil
            ? '${results.length} பொருட்கள் கண்டறியப்பட்டன'
            : '${results.length} item(s) found';
      });

      if (results.isNotEmpty) {
        final reply = '${results.first['name']}: ${(results.first['balance_qty'] ?? 0)} ${results.first['unit'] ?? ''}';
        _ttsService.speak(reply, languageCode: _currentLocale);
      }
    } catch (e) {
      if (!mounted) return;
      _setState(_SheetState.error, '');
      setState(() => _errorMessage = e.toString());
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Report navigation
  // ────────────────────────────────────────────────────────────────────────────
  void _executeReport(VoiceAction action) {
    Navigator.pop(context);
    Future.microtask(() => widget.onNavigate?.call('/reports'));

    activityLog.log(
      action: 'Voice Navigation',
      module: 'Reports',
      description: 'Voice: navigated to reports (${action.reportType ?? 'all'})',
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Auto-close after success
  // ────────────────────────────────────────────────────────────────────────────
  void _autoClose() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.pop(context);
    });
  }

  void _setState(_SheetState state, String message) {
    if (!mounted) return;
    setState(() {
      _sheetState = state;
      _statusMessage = message;
      if (state != _SheetState.error) _errorMessage = null;
    });
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Reset to idle
  // ────────────────────────────────────────────────────────────────────────────
  void _reset() {
    setState(() {
      _sheetState = _SheetState.idle;
      _transcribedText = '';
      _errorMessage = null;
      _successMessage = null;
      _queryResults = [];
      _pendingFollowUpQuestion = null;
      _statusMessage = _isTamil ? 'மீண்டும் பேசவும்…' : 'Tap mic to try again…';
    });
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Text input submit
  // ────────────────────────────────────────────────────────────────────────────
  Future<void> _submitTextInput() async {
    final text = _textInputController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _transcribedText = text;
      _textInputController.clear();
      _showTextInput = false;
    });
    _setState(_SheetState.parsing, _isTamil ? 'கட்டளை பகுப்பாய்வு…' : 'Analyzing…');
    await _parseText(text);
  }

  // ════════════════════════════════════════════════════════════════════════════
  // Build
  // ════════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.9),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.border, width: 1.5)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: _MainAxisSizeListener(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header Row 1: Title & Close Button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Voice Assistant',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white60),
                          onPressed: () => Navigator.pop(context),
                          tooltip: 'Close',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Header Row 2: Controls (Text/Voice toggle and Language selector)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Text/Voice toggle
                        IconButton(
                          icon: Icon(
                            _showTextInput ? Icons.mic_none : Icons.keyboard_outlined,
                            color: AppColors.roseGold,
                          ),
                          tooltip: _showTextInput ? 'Switch to Voice' : 'Switch to Text',
                          onPressed: () {
                            if (_isListening) _toggleListening();
                            setState(() {
                              _showTextInput = !_showTextInput;
                              _statusMessage = _showTextInput
                                  ? (_isTamil ? 'கட்டளையை தட்டச்சு செய்யவும்…' : 'Type your command…')
                                  : (_isTamil ? 'மைக்ரோஃபோனை தட்டவும்…' : 'Tap the mic to start…');
                            });
                          },
                        ),
                        // Language toggle
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          padding: const EdgeInsets.all(2),
                          child: Row(
                            children: [
                              _buildLangBtn('தமிழ்', 'ta-IN'),
                              _buildLangBtn('EN-IN', 'en-IN'),
                              _buildLangBtn('EN-US', 'en-US'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Status message
                    if (_statusMessage.isNotEmpty)
                      Text(
                        _statusMessage,
                        style: TextStyle(
                          color: _sheetState == _SheetState.success
                              ? AppColors.success
                              : _sheetState == _SheetState.error
                                  ? AppColors.danger
                                  : AppColors.textSecondary,
                          fontSize: 14,
                          fontWeight: _sheetState == _SheetState.success ||
                                  _sheetState == _SheetState.error
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                        textAlign: TextAlign.center,
                      ),

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: AppColors.danger, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Transcribed text panel
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 70),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        _transcribedText.isEmpty
                            ? (_isListening
                                ? (_isTamil ? 'பேசவும்…' : 'Listening…')
                                : (_isTamil
                                    ? '"ராமன் present" அல்லது "சிமெண்ட் 50 சேர்க்கவும்"'
                                    : _isIndianEnglish
                                        ? 'e.g. "Mark Raman present" or "Add 50 cement bags"'
                                        : 'e.g. "Raman Present" or "Add 50 Cement"'))
                            : _transcribedText,
                        style: TextStyle(
                          color: _transcribedText.isEmpty ? Colors.white30 : Colors.white,
                          fontSize: 15,
                          fontStyle: _transcribedText.isEmpty ? FontStyle.italic : FontStyle.normal,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // State-specific UI
                    _buildStateWidget(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Bottom action button
            _buildBottomButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildStateWidget() {
    switch (_sheetState) {
      case _SheetState.listening:
        return _buildPulseMic();
      case _SheetState.parsing:
      case _SheetState.executing:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: CircularProgressIndicator(color: AppColors.roseGold, strokeWidth: 2.5),
        );
      case _SheetState.followUp:
        return _buildFollowUpWidget();
      case _SheetState.success:
        return _buildSuccessCard();
      case _SheetState.error:
        return _buildRetryButton();
      case _SheetState.queryResult:
        return _buildQueryResults();
      default:
        return _showTextInput ? _buildTextInputWidget() : _buildIdleMic();
    }
  }

  Widget _buildIdleMic() {
    return GestureDetector(
      onTap: _toggleListening,
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.roseGold, AppColors.roseGoldLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.roseGold.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.mic_none, color: Colors.white, size: 32),
      ),
    );
  }

  Widget _buildPulseMic() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final scale = 1.0 + (_pulseController.value * 0.25);
        final opacity = 0.2 - (_pulseController.value * 0.15);
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 90 * scale,
              height: 90 * scale,
              decoration: BoxDecoration(
                color: AppColors.roseGold.withValues(alpha: opacity),
                shape: BoxShape.circle,
              ),
            ),
            GestureDetector(
              onTap: _toggleListening,
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.roseGold, AppColors.roseGoldLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.roseGold.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.mic, color: Colors.white, size: 32),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTextInputWidget() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _textInputController,
            decoration: InputDecoration(
              hintText: _isTamil ? 'கட்டளை தட்டச்சு செய்யவும்…' : 'Type your command…',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              filled: true,
              fillColor: AppColors.background,
            ),
            style: const TextStyle(color: Colors.white),
            onSubmitted: (_) => _submitTextInput(),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          decoration: const BoxDecoration(color: AppColors.roseGold, shape: BoxShape.circle),
          child: IconButton(
            icon: const Icon(Icons.send, color: Colors.white),
            onPressed: _submitTextInput,
          ),
        ),
      ],
    );
  }

  Widget _buildFollowUpWidget() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.roseGold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.roseGold.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.help_outline, color: AppColors.roseGold, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _pendingFollowUpQuestion ?? '',
                  style: const TextStyle(color: AppColors.roseGold, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _followUpController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: _isTamil ? 'பதிலை தட்டச்சு செய்யவும்…' : 'Type your answer…',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  filled: true,
                  fillColor: AppColors.background,
                ),
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.text,
                onSubmitted: (_) => _submitFollowUp(),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              decoration: const BoxDecoration(color: AppColors.roseGold, shape: BoxShape.circle),
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white),
                onPressed: _submitFollowUp,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSuccessCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: AppColors.success, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _successMessage ?? (_isTamil ? 'வெற்றிகரமாக செய்யப்பட்டது!' : 'Action completed!'),
              style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRetryButton() {
    return OutlinedButton.icon(
      onPressed: _reset,
      icon: const Icon(Icons.refresh, size: 18),
      label: Text(_isTamil ? 'மீண்டும் முயற்சி' : 'Try Again'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.roseGold,
        side: const BorderSide(color: AppColors.roseGold),
        minimumSize: const Size(double.infinity, 44),
      ),
    );
  }

  Widget _buildQueryResults() {
    if (_queryResults.isEmpty) {
      return Text(
        _isTamil ? 'தகவல் இல்லை.' : 'No data found.',
        style: const TextStyle(color: AppColors.textSecondary),
        textAlign: TextAlign.center,
      );
    }
    return Column(
      children: _queryResults.take(5).map((item) {
        final name = item['name'] as String? ?? '';
        final qty = item['balance_qty'] ?? 0;
        final unit = item['unit'] as String? ?? '';
        final minStock = (item['minimum_stock'] ?? 10) as num;
        final isLow = (qty as num) <= minStock;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isLow
                ? AppColors.warning.withValues(alpha: 0.1)
                : AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isLow ? AppColors.warning.withValues(alpha: 0.3) : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
              Row(
                children: [
                  if (isLow)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.warning_amber, color: AppColors.warning, size: 16),
                    ),
                  Text('$qty $unit',
                      style: TextStyle(
                        color: isLow ? AppColors.warning : AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      )),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBottomButton() {
    if (_sheetState == _SheetState.success) {
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton.icon(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.success,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          icon: const Icon(Icons.check),
          label: Text(_isTamil ? 'மூடு' : 'Close'),
        ),
      );
    }

    if (_sheetState == _SheetState.queryResult ||
        _sheetState == _SheetState.error ||
        _sheetState == _SheetState.idle) {
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: OutlinedButton(
          onPressed: _reset,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.roseGold,
            side: const BorderSide(color: AppColors.roseGold),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: Text(
            _isTamil ? 'மீண்டும் முயற்சி' : 'Try Again',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      );
    }

    return const SizedBox(height: 52); // Placeholder to maintain layout
  }

  Widget _buildLangBtn(String label, String code) {
    final isSelected = _currentLocale == code;
    return GestureDetector(
      onTap: () {
        if (_isListening) _toggleListening();
        setState(() => _currentLocale = code);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.roseGold : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _MainAxisSizeListener extends StatelessWidget {
  final Widget child;
  const _MainAxisSizeListener({required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: child,
    );
  }
}
