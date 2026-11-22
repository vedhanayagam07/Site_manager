import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Admin Management Contract & Validation Tests', () {
    const allowedRoles = ['admin', 'projectManager', 'supervisor'];
    const allowedStatuses = ['active', 'disabled'];

    test('Allowed roles include admin, projectManager, and supervisor only', () {
      expect(allowedRoles.contains('admin'), isTrue);
      expect(allowedRoles.contains('projectManager'), isTrue);
      expect(allowedRoles.contains('supervisor'), isTrue);
      expect(allowedRoles.contains('superadmin'), isFalse);
      expect(allowedRoles.contains('root'), isFalse);
    });

    test('Allowed statuses include active and disabled only', () {
      expect(allowedStatuses.contains('active'), isTrue);
      expect(allowedStatuses.contains('disabled'), isTrue);
      expect(allowedStatuses.contains('deleted'), isFalse);
      expect(allowedStatuses.contains('pending'), isFalse);
    });

    test('Validates UUID format strictly for target user operations', () {
      final uuidRegex = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$', caseSensitive: false);

      expect(uuidRegex.hasMatch('c4a7e93b-1234-4567-89ab-cdef01234567'), isTrue);
      expect(uuidRegex.hasMatch('a28bf5df-8b9e-4466-8304-e8e7b8ead7de'), isTrue);
      expect(uuidRegex.hasMatch('not-a-uuid'), isFalse);
      expect(uuidRegex.hasMatch('12345'), isFalse);
      expect(uuidRegex.hasMatch("'; DROP TABLE user_profiles; --"), isFalse);
      expect(uuidRegex.hasMatch('../../../etc/passwd'), isFalse);
      expect(uuidRegex.hasMatch(''), isFalse);
    });

    test('Validates email requirements and length bounds (max 255 chars)', () {
      final emailRegex = RegExp(r'^[a-zA-Z0-9.!#$%&’*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$');

      bool isValidEmail(String? email) {
        if (email == null || email.trim().isEmpty) return false;
        final clean = email.trim().toLowerCase();
        if (clean.length > 255) return false;
        return emailRegex.hasMatch(clean);
      }

      expect(isValidEmail('admin@tsrbuilders.com'), isTrue);
      expect(isValidEmail('supervisor@site.in'), isTrue);
      expect(isValidEmail('user.name+tag@sub.domain.co'), isTrue);
      expect(isValidEmail('invalid-email'), isFalse);
      expect(isValidEmail('missing@domain'), isFalse);
      expect(isValidEmail('@nodomain.com'), isFalse);
      expect(isValidEmail('spaces in@email.com'), isFalse);
      expect(isValidEmail(''), isFalse);
      expect(isValidEmail(null), isFalse);

      final overlongEmail = '${'a' * 250}@example.com';
      expect(isValidEmail(overlongEmail), isFalse);
    });

    test('Validates password length requirement (8 to 72 chars)', () {
      bool isValidPassword(String? pwd) {
        return pwd != null && pwd.length >= 8 && pwd.length <= 72;
      }

      expect(isValidPassword('Password123'), isTrue);
      expect(isValidPassword('12345678'), isTrue);
      expect(isValidPassword('a' * 72), isTrue);
      expect(isValidPassword('short'), isFalse);
      expect(isValidPassword('a' * 73), isFalse);
      expect(isValidPassword(''), isFalse);
      expect(isValidPassword(null), isFalse);
    });

    test('Validates full name length requirement (2 to 100 chars)', () {
      bool isValidName(String? name) {
        if (name == null) return false;
        final trimmed = name.trim();
        return trimmed.length >= 2 && trimmed.length <= 100;
      }

      expect(isValidName('John Doe'), isTrue);
      expect(isValidName('S. Kumar'), isTrue);
      expect(isValidName('A'), isFalse);
      expect(isValidName(''), isFalse);
      expect(isValidName('   '), isFalse);
      expect(isValidName('B' * 101), isFalse);
    });

    test('Create user payload validates role and status before sending', () {
      Map<String, dynamic> buildCreatePayload({
        required String email,
        required String password,
        required String name,
        required String role,
        required String status,
      }) {
        if (!allowedRoles.contains(role)) {
          throw ArgumentError('Invalid role: $role');
        }
        if (!allowedStatuses.contains(status)) {
          throw ArgumentError('Invalid status: $status');
        }
        return {
          'action': 'create_user',
          'email': email.trim().toLowerCase(),
          'password': password,
          'name': name.trim(),
          'role': role,
          'status': status,
        };
      }

      final payload = buildCreatePayload(
        email: 'newuser@tsr.com',
        password: 'SecurePassword123',
        name: 'Kumar Vel',
        role: 'supervisor',
        status: 'active',
      );

      expect(payload['action'], 'create_user');
      expect(payload['email'], 'newuser@tsr.com');
      expect(payload['role'], 'supervisor');
      expect(payload['status'], 'active');

      expect(
        () => buildCreatePayload(
          email: 'bad@tsr.com',
          password: 'Pass',
          name: 'Bad',
          role: 'unauthorized_role',
          status: 'active',
        ),
        throwsArgumentError,
      );
    });

    test('Prevents self-lockout actions on admin account', () {
      bool isSelfActionAllowed({
        required String callerId,
        required String targetUserId,
        required String action,
        String? newStatus,
        String? newRole,
      }) {
        if (callerId == targetUserId) {
          if (action == 'delete_user') return false;
          if (action == 'toggle_status' && newStatus == 'disabled') return false;
          if (action == 'update_user' && newStatus == 'disabled') return false;
          if (action == 'update_user' && newRole != null && newRole != 'admin') return false;
        }
        return true;
      }

      const adminId = 'c4a7e93b-1234-4567-89ab-cdef01234567';
      const otherId = 'd5b8f04c-5678-4321-98ba-fedc98765432';

      // Self delete is blocked
      expect(isSelfActionAllowed(callerId: adminId, targetUserId: adminId, action: 'delete_user'), isFalse);
      // Self disable is blocked
      expect(isSelfActionAllowed(callerId: adminId, targetUserId: adminId, action: 'toggle_status', newStatus: 'disabled'), isFalse);
      // Self demote is blocked
      expect(isSelfActionAllowed(callerId: adminId, targetUserId: adminId, action: 'update_user', newRole: 'supervisor'), isFalse);

      // Deleting another user is allowed
      expect(isSelfActionAllowed(callerId: adminId, targetUserId: otherId, action: 'delete_user'), isTrue);
      // Disabling another user is allowed
      expect(isSelfActionAllowed(callerId: adminId, targetUserId: otherId, action: 'toggle_status', newStatus: 'disabled'), isTrue);
    });

    test('Simulates non-atomic deletion failure and safe rollback handling', () {
      // Simulate state machine of deletion
      Map<String, dynamic>? mockProfile = {
        'id': 'user-123',
        'email': 'user@example.com',
        'name': 'Test User',
        'role': 'supervisor',
        'status': 'active',
      };
      bool authUserExists = true;

      bool attemptDelete({required bool lockFails, required bool authDeleteFails}) {
        if (lockFails) {
          // Concurrency lock failure aborts immediately
          return false;
        }

        // Step 2: Lock via status disabled
        final originalStatus = mockProfile!['status'];
        mockProfile!['status'] = 'disabled';

        // Step 3: Auth delete
        if (authDeleteFails) {
          // Rollback: revert status without losing profile row
          mockProfile!['status'] = originalStatus;
          return false;
        }

        // Step 4: Final cleanup
        authUserExists = false;
        mockProfile = null;
        return true;
      }

      // If lock fails (e.g. concurrent update), aborts cleanly
      final resA = attemptDelete(lockFails: true, authDeleteFails: false);
      expect(resA, isFalse);
      expect(mockProfile, isNotNull);
      expect(mockProfile!['status'], 'active');
      expect(authUserExists, isTrue);

      // If auth fails to delete, status is reverted to original without profile drop
      final resB = attemptDelete(lockFails: false, authDeleteFails: true);
      expect(resB, isFalse);
      expect(mockProfile, isNotNull);
      expect(mockProfile!['status'], 'active');
      expect(authUserExists, isTrue);

      // Normal path: both succeed
      final resC = attemptDelete(lockFails: false, authDeleteFails: false);
      expect(resC, isTrue);
      expect(mockProfile, isNull);
      expect(authUserExists, isFalse);
    });

    test('Caller authorization gate rejects non-admins and disabled accounts', () {
      bool isAuthorizedCaller({required String? role, required String? status}) {
        if (role == null || status == null) return false;
        return role == 'admin' && status == 'active';
      }

      expect(isAuthorizedCaller(role: 'admin', status: 'active'), isTrue);
      expect(isAuthorizedCaller(role: 'admin', status: 'disabled'), isFalse);
      expect(isAuthorizedCaller(role: 'projectManager', status: 'active'), isFalse);
      expect(isAuthorizedCaller(role: 'supervisor', status: 'active'), isFalse);
      expect(isAuthorizedCaller(role: 'unknown', status: 'active'), isFalse);
      expect(isAuthorizedCaller(role: null, status: null), isFalse);
    });

    test('Sanitizes auth error messages for safe client display', () {
      String sanitizeAuthError(String rawError) {
        final lower = rawError.toLowerCase();
        if (lower.contains('already registered') || lower.contains('already exists') || lower.contains('unique')) {
          return 'A user with this email address already exists.';
        }
        if (lower.contains('password')) {
          return 'Password does not meet security requirements (8-72 characters).';
        }
        return 'Operation failed. Please verify the input and try again.';
      }

      expect(
        sanitizeAuthError('User already registered with this email in auth.users'),
        'A user with this email address already exists.',
      );
      expect(
        sanitizeAuthError('duplicate key value violates unique constraint "user_profiles_email_key"'),
        'A user with this email address already exists.',
      );
      expect(
        sanitizeAuthError('Weak password: password should be at least 8 characters'),
        'Password does not meet security requirements (8-72 characters).',
      );
      expect(
        sanitizeAuthError('Internal database error on connection pool 5432'),
        'Operation failed. Please verify the input and try again.',
      );
    });
  });
}
