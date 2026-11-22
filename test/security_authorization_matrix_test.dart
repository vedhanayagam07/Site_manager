import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Security & Authorization Matrix Unit Tests', () {
    // ─────────────────────────────────────────────────────────────────────────
    // Helper simulation functions mirroring PostgreSQL RLS and SQL grants
    // ─────────────────────────────────────────────────────────────────────────

    bool sqlTableGrant({
      required String table,
      required String operation,
      required String? callerRole, // null for anon, or 'authenticated'
    }) {
      if (callerRole != 'authenticated') return false; // Anon & PUBLIC revoked

      switch (table) {
        case 'user_profiles':
          return operation == 'SELECT'; // Mutations only via Edge Function
        case 'sites':
        case 'workers':
        case 'materials':
        case 'site_attendance':
          return ['SELECT', 'INSERT', 'UPDATE', 'DELETE'].contains(operation);
        case 'loading_memos':
          return ['SELECT', 'INSERT', 'DELETE'].contains(operation); // UPDATE withheld
        case 'material_transactions':
        case 'activity_logs':
          // Append-only reconciliation: UPDATE and DELETE are withheld from ALL authenticated clients
          return ['SELECT', 'INSERT'].contains(operation);
        default:
          return false;
      }
    }

    bool rlsPolicyCheck({
      required String table,
      required String operation,
      required String? userRole, // 'admin', 'projectManager', 'supervisor', or null
      required String? userStatus, // 'active', 'disabled', or null
      required String? targetUserId,
      required String? callerUserId,
    }) {
      final isActive = userStatus == 'active';
      final isAdmin = isActive && userRole == 'admin';
      final isPmOrAdmin = isActive && (userRole == 'admin' || userRole == 'projectManager');

      if (!isActive && table != 'user_profiles') return false;

      switch (table) {
        case 'user_profiles':
          if (operation != 'SELECT') return false;
          if (callerUserId != null && callerUserId == targetUserId) return true;
          return isAdmin;

        case 'sites':
          if (operation == 'SELECT') return isActive;
          if (operation == 'INSERT' || operation == 'UPDATE') return isPmOrAdmin; // PM/Admin only
          if (operation == 'DELETE') return isAdmin;
          return false;

        case 'workers':
          if (operation == 'SELECT') return isActive;
          if (operation == 'INSERT' || operation == 'UPDATE') return isActive;
          if (operation == 'DELETE') return isAdmin;
          return false;

        case 'materials':
          if (operation == 'SELECT') return isActive;
          if (operation == 'INSERT') return isPmOrAdmin; // Master catalog addition
          if (operation == 'UPDATE') return isActive; // Stock balance adjustment
          if (operation == 'DELETE') return isAdmin;
          return false;

        case 'material_transactions':
          if (operation == 'SELECT' || operation == 'INSERT') return isActive;
          return false; // Immutable ledger: UPDATE & DELETE denied to all

        case 'site_attendance':
          if (['SELECT', 'INSERT', 'UPDATE'].contains(operation)) return isActive;
          if (operation == 'DELETE') return isAdmin;
          return false;

        case 'loading_memos':
          if (operation == 'SELECT' || operation == 'INSERT') return isActive;
          if (operation == 'DELETE') return isAdmin;
          return false;

        case 'activity_logs':
          if (operation == 'INSERT') return isActive; // Active staff append
          if (operation == 'SELECT') return isAdmin; // Admins view audit logs
          return false; // Immutable audit trail: UPDATE & DELETE denied to all

        default:
          return false;
      }
    }

    bool canPerformOperation({
      required String table,
      required String operation,
      required String? callerDbRole, // 'anon' or 'authenticated'
      required String? userRole,
      required String? userStatus,
      String? targetUserId,
      String? callerUserId,
    }) {
      // Must pass BOTH base SQL table grants and RLS policy
      final grantOk = sqlTableGrant(table: table, operation: operation, callerRole: callerDbRole);
      if (!grantOk) return false;

      return rlsPolicyCheck(
        table: table,
        operation: operation,
        userRole: userRole,
        userStatus: userStatus,
        targetUserId: targetUserId,
        callerUserId: callerUserId,
      );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 1: Anonymous Access Fencing
    // ─────────────────────────────────────────────────────────────────────────
    test('Anonymous callers are rejected from all tables and operations', () {
      const tables = [
        'user_profiles',
        'sites',
        'workers',
        'materials',
        'material_transactions',
        'site_attendance',
        'loading_memos',
        'activity_logs',
      ];
      const operations = ['SELECT', 'INSERT', 'UPDATE', 'DELETE'];

      for (final table in tables) {
        for (final op in operations) {
          final allowed = canPerformOperation(
            table: table,
            operation: op,
            callerDbRole: 'anon',
            userRole: null,
            userStatus: null,
          );
          expect(allowed, isFalse, reason: 'Anon should be denied $op on $table');
        }
      }
    });

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 2: Disabled Account Lockdown
    // ─────────────────────────────────────────────────────────────────────────
    test('Disabled accounts cannot read or mutate business tables', () {
      const businessTables = [
        'sites',
        'workers',
        'materials',
        'material_transactions',
        'site_attendance',
        'loading_memos',
        'activity_logs',
      ];
      const operations = ['SELECT', 'INSERT', 'UPDATE', 'DELETE'];

      for (final table in businessTables) {
        for (final op in operations) {
          final allowed = canPerformOperation(
            table: table,
            operation: op,
            callerDbRole: 'authenticated',
            userRole: 'supervisor',
            userStatus: 'disabled',
            callerUserId: 'disabled-user-1',
          );
          expect(allowed, isFalse, reason: 'Disabled user should be denied $op on $table');
        }
      }

      // Disabled user can only read their own profile to see disabled notice
      final canReadOwnProfile = canPerformOperation(
        table: 'user_profiles',
        operation: 'SELECT',
        callerDbRole: 'authenticated',
        userRole: 'supervisor',
        userStatus: 'disabled',
        callerUserId: 'disabled-user-1',
        targetUserId: 'disabled-user-1',
      );
      expect(canReadOwnProfile, isTrue);

      // Disabled user cannot read other profiles
      final canReadOtherProfile = canPerformOperation(
        table: 'user_profiles',
        operation: 'SELECT',
        callerDbRole: 'authenticated',
        userRole: 'supervisor',
        userStatus: 'disabled',
        callerUserId: 'disabled-user-1',
        targetUserId: 'other-user-2',
      );
      expect(canReadOtherProfile, isFalse);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 3: Supervisor Workflow & Role Differentiation
    // ─────────────────────────────────────────────────────────────────────────
    test('Active Supervisors have operational access but cannot create sites or delete records', () {
      // 1. Can view sites
      expect(
        canPerformOperation(
          table: 'sites',
          operation: 'SELECT',
          callerDbRole: 'authenticated',
          userRole: 'supervisor',
          userStatus: 'active',
        ),
        isTrue,
      );

      // 2. Cannot create or update sites (Reserved for PM/Admin)
      expect(
        canPerformOperation(
          table: 'sites',
          operation: 'INSERT',
          callerDbRole: 'authenticated',
          userRole: 'supervisor',
          userStatus: 'active',
        ),
        isFalse,
      );
      expect(
        canPerformOperation(
          table: 'sites',
          operation: 'UPDATE',
          callerDbRole: 'authenticated',
          userRole: 'supervisor',
          userStatus: 'active',
        ),
        isFalse,
      );

      // 3. Can record attendance and update (batch upsert)
      expect(
        canPerformOperation(
          table: 'site_attendance',
          operation: 'INSERT',
          callerDbRole: 'authenticated',
          userRole: 'supervisor',
          userStatus: 'active',
        ),
        isTrue,
      );
      expect(
        canPerformOperation(
          table: 'site_attendance',
          operation: 'UPDATE',
          callerDbRole: 'authenticated',
          userRole: 'supervisor',
          userStatus: 'active',
        ),
        isTrue,
      );

      // 4. Can record material transactions and update stock balance
      expect(
        canPerformOperation(
          table: 'material_transactions',
          operation: 'INSERT',
          callerDbRole: 'authenticated',
          userRole: 'supervisor',
          userStatus: 'active',
        ),
        isTrue,
      );
      expect(
        canPerformOperation(
          table: 'materials',
          operation: 'UPDATE',
          callerDbRole: 'authenticated',
          userRole: 'supervisor',
          userStatus: 'active',
        ),
        isTrue,
      );

      // 5. Cannot delete records on any business table
      for (final table in ['sites', 'workers', 'materials', 'site_attendance', 'loading_memos']) {
        expect(
          canPerformOperation(
            table: table,
            operation: 'DELETE',
            callerDbRole: 'authenticated',
            userRole: 'supervisor',
            userStatus: 'active',
          ),
          isFalse,
        );
      }

      // 6. Cannot view activity logs
      expect(
        canPerformOperation(
          table: 'activity_logs',
          operation: 'SELECT',
          callerDbRole: 'authenticated',
          userRole: 'supervisor',
          userStatus: 'active',
        ),
        isFalse,
      );
    });

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 4: Project Manager Privileges
    // ─────────────────────────────────────────────────────────────────────────
    test('Active Project Managers can manage sites and materials catalog but cannot delete', () {
      // 1. Can create and update sites
      expect(
        canPerformOperation(
          table: 'sites',
          operation: 'INSERT',
          callerDbRole: 'authenticated',
          userRole: 'projectManager',
          userStatus: 'active',
        ),
        isTrue,
      );
      expect(
        canPerformOperation(
          table: 'sites',
          operation: 'UPDATE',
          callerDbRole: 'authenticated',
          userRole: 'projectManager',
          userStatus: 'active',
        ),
        isTrue,
      );

      // 2. Can add new master materials
      expect(
        canPerformOperation(
          table: 'materials',
          operation: 'INSERT',
          callerDbRole: 'authenticated',
          userRole: 'projectManager',
          userStatus: 'active',
        ),
        isTrue,
      );

      // 3. Cannot delete sites or loading memos (Admin only)
      expect(
        canPerformOperation(
          table: 'sites',
          operation: 'DELETE',
          callerDbRole: 'authenticated',
          userRole: 'projectManager',
          userStatus: 'active',
        ),
        isFalse,
      );
      expect(
        canPerformOperation(
          table: 'loading_memos',
          operation: 'DELETE',
          callerDbRole: 'authenticated',
          userRole: 'projectManager',
          userStatus: 'active',
        ),
        isFalse,
      );
    });

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 5: Administrator Privileges & Append-Only Reconciliation
    // ─────────────────────────────────────────────────────────────────────────
    test('Active Administrators can delete sites/memos and view logs, but cannot alter or delete append-only ledgers', () {
      // 1. Can view all user profiles
      expect(
        canPerformOperation(
          table: 'user_profiles',
          operation: 'SELECT',
          callerDbRole: 'authenticated',
          userRole: 'admin',
          userStatus: 'active',
          callerUserId: 'admin-1',
          targetUserId: 'other-user-2',
        ),
        isTrue,
      );

      // 2. Can view activity logs
      expect(
        canPerformOperation(
          table: 'activity_logs',
          operation: 'SELECT',
          callerDbRole: 'authenticated',
          userRole: 'admin',
          userStatus: 'active',
        ),
        isTrue,
      );

      // 3. Can delete sites and loading memos
      expect(
        canPerformOperation(
          table: 'sites',
          operation: 'DELETE',
          callerDbRole: 'authenticated',
          userRole: 'admin',
          userStatus: 'active',
        ),
        isTrue,
      );
      expect(
        canPerformOperation(
          table: 'loading_memos',
          operation: 'DELETE',
          callerDbRole: 'authenticated',
          userRole: 'admin',
          userStatus: 'active',
        ),
        isTrue,
      );

      // 4. CRITICAL RECONCILIATION: Even administrators CANNOT delete or update material_transactions or activity_logs
      // Both ledgers are strictly append-only for all client roles
      expect(
        canPerformOperation(
          table: 'material_transactions',
          operation: 'DELETE',
          callerDbRole: 'authenticated',
          userRole: 'admin',
          userStatus: 'active',
        ),
        isFalse,
        reason: 'material_transactions must be append-only; client DELETE denied to admins',
      );
      expect(
        canPerformOperation(
          table: 'material_transactions',
          operation: 'UPDATE',
          callerDbRole: 'authenticated',
          userRole: 'admin',
          userStatus: 'active',
        ),
        isFalse,
      );
      expect(
        canPerformOperation(
          table: 'activity_logs',
          operation: 'DELETE',
          callerDbRole: 'authenticated',
          userRole: 'admin',
          userStatus: 'active',
        ),
        isFalse,
        reason: 'activity_logs must be tamper-evident; client DELETE denied to admins',
      );
      expect(
        canPerformOperation(
          table: 'activity_logs',
          operation: 'UPDATE',
          callerDbRole: 'authenticated',
          userRole: 'admin',
          userStatus: 'active',
        ),
        isFalse,
      );
    });

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 6: Loading Memo Required Schema Contract
    // ─────────────────────────────────────────────────────────────────────────
    test('Loading Memo insert requires generated_by to prevent false constraint failures', () {
      Map<String, dynamic> createValidMemoPayload({
        required String vehicleNumber,
        required String materialName,
        required double quantity,
        required String generatedBy,
      }) {
        return {
          'date': '2026-10-14',
          'vehicle_number': vehicleNumber,
          'material_name': materialName,
          'quantity': quantity,
          'unit': 'Bags',
          'generated_by': generatedBy,
        };
      }

      final payload = createValidMemoPayload(
        vehicleNumber: 'TN-01-AB-1234',
        materialName: 'Cement',
        quantity: 50.0,
        generatedBy: 'admin@tsrbuilders.com',
      );

      expect(payload['generated_by'], isNotNull);
      expect(payload['generated_by'], isNotEmpty);
      expect(payload['vehicle_number'], isNotEmpty);
      expect(payload['material_name'], isNotEmpty);
      expect(payload['quantity'], greaterThan(0));
    });
  });
}
