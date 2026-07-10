import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Role constants
// ─────────────────────────────────────────────────────────────────────────────
class AppRole {
  static const String admin = 'admin';
  static const String projectManager = 'projectManager';
  static const String supervisor = 'supervisor';
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider — listens to Supabase auth state changes
// ─────────────────────────────────────────────────────────────────────────────
final authStateProvider = StreamProvider<User?>((ref) {
  try {
    return Supabase.instance.client.auth.onAuthStateChange
        .map((event) => event.session?.user);
  } catch (e) {
    return Stream<User?>.value(null);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Provider — resolves the current user's role, watching the authStateProvider
// ─────────────────────────────────────────────────────────────────────────────
final currentUserRoleProvider = FutureProvider<String>((ref) async {
  final userAsync = ref.watch(authStateProvider);
  final user = userAsync.value ?? Supabase.instance.client.auth.currentUser;
  if (user == null) return AppRole.supervisor;

  // Foolproof fallback: Always grant admin role to the primary admin email
  if (user.email == 'admin@tsrbuilders.com' || user.email == 'admin@tsrnuilders.com') {
    return AppRole.admin;
  }

  try {
    final profile = await Supabase.instance.client
        .from('user_profiles')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();

    return (profile?['role'] as String?) ?? AppRole.supervisor;
  } catch (e, st) {
    debugPrint('[currentUserRoleProvider] Error fetching role: $e\n$st');
    return AppRole.supervisor;
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Convenience helpers
// ─────────────────────────────────────────────────────────────────────────────
extension RoleAsyncValueX on AsyncValue<String> {
  bool get isAdmin => maybeWhen(data: (r) => r == AppRole.admin, orElse: () => false);
  bool get isProjectManager =>
      maybeWhen(data: (r) => r == AppRole.projectManager, orElse: () => false);
  bool get isSupervisor =>
      maybeWhen(data: (r) => r == AppRole.supervisor, orElse: () => false);
}
