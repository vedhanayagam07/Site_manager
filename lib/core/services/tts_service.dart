import 'package:flutter_tts/flutter_tts.dart';
import 'dart:developer' as dev;

class TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;
  String _currentLanguage = '';

  Future<void> initTts({String languageCode = 'en-IN'}) async {
    if (_isInitialized && _currentLanguage == languageCode) return;
    try {
      await _flutterTts.setLanguage(languageCode);
      await _flutterTts.setSpeechRate(0.5); // Normal speaking rate
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      _isInitialized = true;
      _currentLanguage = languageCode;
    } catch (e) {
      dev.log('Error initializing TTS: $e');
    }
  }

  /// Speak text in the given language.
  /// Supported: 'en-IN' (Indian English), 'ta-IN' (Tamil), 'en-US' (US English)
  Future<void> speak(String text, {String languageCode = 'en-IN'}) async {
    if (text.trim().isEmpty) return;
    try {
      // Re-initialize if language changes
      if (!_isInitialized || _currentLanguage != languageCode) {
        await initTts(languageCode: languageCode);
      }
      // Set language for this utterance
      await _flutterTts.setLanguage(languageCode);
      await _flutterTts.speak(text);
      dev.log("TTS speaking: '$text' in $languageCode");
    } catch (e) {
      dev.log('Error speaking text: $e');
      // Try fallback to en-US if the requested language is not available
      try {
        await _flutterTts.setLanguage('en-US');
        await _flutterTts.speak(text);
      } catch (_) {
        dev.log('TTS fallback also failed');
      }
    }
  }

  Future<void> stop() async {
    try {
      await _flutterTts.stop();
    } catch (e) {
      dev.log('Error stopping TTS: $e');
    }
  }
}
