import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'demo_session_provider.g.dart';

/// Simple demo user for testing without Supabase
class DemoUser {
  final String id;
  final String email;
  final String name;

  DemoUser({
    required this.id,
    required this.email,
    required this.name,
  });
}

@riverpod
class DemoSessionNotifier extends _$DemoSessionNotifier {
  @override
  DemoUser? build() {
    return null; // Not logged in initially
  }

  void loginDemo() {
    state = DemoUser(
      id: 'demo-user-001',
      email: 'demo@sitemanager.com',
      name: 'Demo User',
    );
  }

  void logout() {
    state = null;
  }
}
