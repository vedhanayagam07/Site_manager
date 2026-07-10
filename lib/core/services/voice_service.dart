import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'dart:developer' as dev;

class VoiceService {
  final SpeechToText _speech = SpeechToText();
  bool _isInitialized = false;

  Future<bool> initSpeech() async {
    if (_isInitialized) return true;

    try {
      // Request microphone permissions
      final status = await Permission.microphone.status;
      if (status.isDenied) {
        final result = await Permission.microphone.request();
        if (!result.isGranted) {
          dev.log('Microphone permission denied by user.');
          return false;
        }
      }

      _isInitialized = await _speech.initialize(
        onError: (errorNotification) {
          dev.log('Speech Recognition Error: ${errorNotification.errorMsg}');
        },
        onStatus: (status) {
          dev.log('Speech Recognition Status: $status');
        },
      );
      return _isInitialized;
    } catch (e) {
      dev.log('Error initializing voice service: $e');
      return false;
    }
  }

  Future<void> startListening({
    required Function(String text, bool isFinal) onResult,
    required Function() onDone,
    required Function(String error) onError,
    String localeId = 'en-IN', // Default to Indian English
  }) async {
    final hasPermission = await initSpeech();
    if (!hasPermission) {
      onError('Microphone permission required');
      return;
    }

    try {
      await _speech.listen(
        onResult: (result) {
          onResult(result.recognizedWords, result.finalResult);
          if (result.finalResult) {
            onDone();
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          listenFor: const Duration(seconds: 15),
          pauseFor: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      onError(e.toString());
    }
  }

  Future<void> stopListening() async {
    try {
      await _speech.stop();
    } catch (e) {
      dev.log('Error stopping voice service: $e');
    }
  }

  bool get isListening => _speech.isListening;
}
