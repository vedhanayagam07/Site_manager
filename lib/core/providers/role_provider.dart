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
  static const String unknown = 'unknown';
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
// Provider — resolves the current user's role from public.user_profiles
// ─────────────────────────────────────────────────────────────────────────────
final currentUserRoleProvider = FutureProvider<String>((ref) async {
  final userAsync = ref.watch(authStateProvider);
  final user = userAsync.value ?? Supabase.instance.client.auth.currentUser;
  
  // Unauthenticated visitors have no role
  if (user == null) return AppRole.unknown;

  try {
    final profile = await Supabase.instance.client
        .from('user_profiles')
        .select('role, status')
        .eq('id', user.id)
        .maybeSingle();

    if (profile == null) return AppRole.supervisor;

    // Disabled accounts should not have active privileges
    final status = profile['status'] as String? ?? 'active';
    if (status == 'disabled') return AppRole.unknown;

    final role = profile['role'] as String?;
    if (role == AppRole.admin ||
        role == AppRole.projectManager ||
        role == AppRole.supervisor) {
      return role!;
    }

    return AppRole.supervisor;
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
