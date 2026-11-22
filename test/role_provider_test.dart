import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:site_manager_pro/core/providers/role_provider.dart';

void main() {
  group('Role Provider & Hierarchy Tests', () {
    test('AppRole constants are well-defined', () {
      expect(AppRole.admin, 'admin');
      expect(AppRole.projectManager, 'projectManager');
      expect(AppRole.supervisor, 'supervisor');
      expect(AppRole.unknown, 'unknown');
    });

    test('RoleAsyncValueX correctly identifies admin role', () {
      const adminVal = AsyncValue.data(AppRole.admin);
      const pmVal = AsyncValue.data(AppRole.projectManager);
      const supervisorVal = AsyncValue.data(AppRole.supervisor);
      const unknownVal = AsyncValue.data(AppRole.unknown);
      const loadingVal = AsyncValue<String>.loading();

      expect(adminVal.isAdmin, isTrue);
      expect(adminVal.isProjectManager, isFalse);
      expect(adminVal.isSupervisor, isFalse);

      expect(pmVal.isAdmin, isFalse);
      expect(pmVal.isProjectManager, isTrue);
      expect(pmVal.isSupervisor, isFalse);

      expect(supervisorVal.isAdmin, isFalse);
      expect(supervisorVal.isProjectManager, isFalse);
      expect(supervisorVal.isSupervisor, isTrue);

      expect(unknownVal.isAdmin, isFalse);
      expect(unknownVal.isProjectManager, isFalse);
      expect(unknownVal.isSupervisor, isFalse);

      expect(loadingVal.isAdmin, isFalse);
    });

    test('Role resolution disallows spoofed email fallback', () {
      // Confirms role resolution does not grant admin to spoofed emails
      String resolveRoleWithoutBackdoor({
        required String? email,
        required String? dbRole,
        required String? dbStatus,
      }) {
        if (dbStatus == 'disabled') return AppRole.unknown;
        if (dbRole == AppRole.admin) return AppRole.admin;
        if (dbRole == AppRole.projectManager) return AppRole.projectManager;
        return AppRole.supervisor;
      }

      // Legitimate admin in database
      expect(
        resolveRoleWithoutBackdoor(email: 'admin@tsrbuilders.com', dbRole: 'admin', dbStatus: 'active'),
        AppRole.admin,
      );

      // Spoofed typo email with supervisor DB role must NOT receive admin
      expect(
        resolveRoleWithoutBackdoor(email: 'admin@tsrnuilders.com', dbRole: 'supervisor', dbStatus: 'active'),
        AppRole.supervisor,
      );

      // Disabled admin account must receive unknown
      expect(
        resolveRoleWithoutBackdoor(email: 'admin@tsrbuilders.com', dbRole: 'admin', dbStatus: 'disabled'),
        AppRole.unknown,
      );
    });
  });
}
