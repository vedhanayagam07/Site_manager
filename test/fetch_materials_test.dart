import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_manager_pro/core/services/voice_parser.dart';

class RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

void main() {
  test('Fetch materials to debug stock discrepancy', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    HttpOverrides.global = RealHttpOverrides();

    await Supabase.initialize(
      url: 'https://yrgsgjiqijccunisqzqz.supabase.co',
      anonKey: 'sb_publishable_waARL7U1mTW6lIEAtVzKuA__qxQtrkl',
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
      ),
    );

    final client = Supabase.instance.client;

    try {
      final data = await client.from('site_attendance').select().limit(1);
      if (data.isNotEmpty) {
        print('SITE ATTENDANCE KEYS: ' + data.first.keys.toList().toString());
      } else {
        print('SITE ATTENDANCE TABLE IS EMPTY');
      }
    } catch (e) {
      print('ERROR QUERYING SITE ATTENDANCE: ' + e.toString());
    }
  }, skip: 'Live network calls are disabled in local pre-production test suites');

  test('VoiceParser Tanglish test - "anju mooda ramco cement used"', () {
    final action = VoiceParser.parse(
      'anju mooda ramco cement used',
      materialNames: ['Ramco Cement', 'Ultratech Cement'],
    );
    print('PARSED ACTION TYPE: ${action.type}');
    print('PARSED TARGET NAME: ${action.targetName}');
    print('PARSED QUANTITY: ${action.quantity}');
    print('PARSED VALUE: ${action.value}');

    expect(action.type, VoiceActionType.material);
    expect(action.targetName, 'Ramco Cement');
    expect(action.quantity, 5.0);
    expect(action.value, 'OUT');
  });
}
