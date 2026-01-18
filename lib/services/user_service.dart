import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_user.dart';
import '../models/user_role.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Get current user ID
  String? get currentUserId => _auth.currentUser?.uid;

  /// Get current user's business ID (owner's UID)
  Future<String?> getCurrentBusinessId() async {
    final uid = currentUserId;
    if (uid == null) return null;

    try {
      // Check if user is owner
      final userDoc = await _firestore.collection('users').doc(uid).get();
      if (userDoc.exists) {
        final data = userDoc.data();
        if (data?['role'] == 'owner' || !data!.containsKey('businessId')) {
          return uid; // User is owner
        }
      }

      // Check staff membership
      final membershipDoc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('business_membership')
          .limit(1)
          .get();

      if (membershipDoc.docs.isNotEmpty) {
        return membershipDoc.docs.first.data()['businessId'];
      }

      return uid; // Default to own UID
    } catch (e) {
      debugPrint('Error getting business ID: $e');
      return uid;
    }
  }

  /// Get current user's app user data
  Future<AppUser?> getCurrentUser() async {
    final uid = currentUserId;
    if (uid == null) return null;

    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) return null;

      return AppUser.fromFirestore(doc);
    } catch (e) {
      debugPrint('Error getting current user: $e');
      return null;
    }
  }

  /// Get current user's permissions
  Future<Permission> getCurrentUserPermissions() async {
    final user = await getCurrentUser();
    if (user == null) {
      // Default to owner permissions for backward compatibility
      return Permission.forRole(UserRole.owner);
    }
    return user.permissions;
  }

  /// Check if current user has a specific permission
  Future<bool> checkPermission(bool Function(Permission) check) async {
    final permissions = await getCurrentUserPermissions();
    return check(permissions);
  }

  /// Generate a random 6-character invitation code
  String _generateInvitationCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return List.generate(
      6,
      (index) => chars[random.nextInt(chars.length)],
    ).join();
  }

  /// Invite a new user (staff member)
  Future<String> inviteUser({
    required String email,
    required String name,
    required UserRole role,
    String? phone,
  }) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('Not authenticated');

    // Generate unique invitation code
    String invitationCode = '';
    bool codeExists = true;

    while (codeExists) {
      invitationCode = _generateInvitationCode();

      // Check if code already exists
      final existing = await _firestore
          .collection('users')
          .doc(uid)
          .collection('staff')
          .where('invitationCode', isEqualTo: invitationCode)
          .where('invitationAccepted', isEqualTo: false)
          .get();

      codeExists = existing.docs.isNotEmpty;
    }

    // Create staff invitation
    final staffRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('staff');

    await staffRef.add({
      'email': email,
      'name': name,
      'phone': phone,
      'role': role.toFirestore(),
      'isActive': true,
      'status': 'invited',
      'invitationCode': invitationCode,
      'invitationAccepted': false,
      'createdAt': FieldValue.serverTimestamp(),
      'permissions': Permission.forRole(role).toMap(),
    });

    // Log activity
    await logActivity(
      action: 'invited_user',
      module: 'users',
      details: 'Invited $name as ${role.displayName}',
    );

    return invitationCode;
  }

  /// Submit join request (User enters code and username)
  Future<void> submitJoinRequest(
    String invitationCode, {
    required String username,
  }) async {
    // Find invitation across all businesses
    final allUsers = await _firestore.collection('users').get();

    for (var userDoc in allUsers.docs) {
      final staffQuery = await userDoc.reference
          .collection('staff')
          .where('invitationCode', isEqualTo: invitationCode)
          .where('invitationAccepted', isEqualTo: false)
          .limit(1)
          .get();

      if (staffQuery.docs.isNotEmpty) {
        final staffDoc = staffQuery.docs.first;
        final businessId = userDoc.id;

        // Update staff document to pending status with username
        await staffDoc.reference.update({
          'username': username,
          'status': 'pending_approval',
          'invitationAccepted': true,
          'requestedAt': FieldValue.serverTimestamp(),
        });

        return;
      }
    }

    throw Exception('Invalid or expired invitation code');
  }

  /// Approve join request (Owner action)
  Future<void> approveJoinRequest(String staffId) async {
    final businessId = await getCurrentBusinessId();
    if (businessId == null) throw Exception('Business ID not found');

    final staffRef = _firestore
        .collection('users')
        .doc(businessId)
        .collection('staff')
        .doc(staffId);

    final staffDoc = await staffRef.get();
    if (!staffDoc.exists) throw Exception('Request not found');

    final staffData = staffDoc.data()!;

    // Simply mark staff as active
    await staffRef.update({
      'status': 'active',
      'approvedAt': FieldValue.serverTimestamp(),
      'isActive': true,
    });

    // Log activity
    await logActivity(
      action: 'approved_user',
      module: 'users',
      details:
          'Approved join request for ${staffData['username'] ?? staffData['name']}',
      documentId: staffId,
    );
  }

  /// Reject join request (Owner action)
  Future<void> rejectJoinRequest(String staffId) async {
    final businessId = await getCurrentBusinessId();
    if (businessId == null) throw Exception('Business ID not found');

    final staffRef = _firestore
        .collection('users')
        .doc(businessId)
        .collection('staff')
        .doc(staffId);

    final staffDoc = await staffRef.get();
    if (!staffDoc.exists) throw Exception('Request not found');

    final userId = staffDoc.data()!['userId'];

    // Update staff document (or delete?)
    // Let's mark as rejected so we have a record, or reset invitation?
    // User wants to "reject", usually implies blocking access.
    await staffRef.update({
      'status': 'rejected',
      'rejectedAt': FieldValue.serverTimestamp(),
      'isActive': false,
    });

    // Update user document to remove pending status
    if (userId != null) {
      await _firestore.collection('users').doc(userId).update({
        'pendingBusinessId': FieldValue.delete(),
      });
    }

    // Log activity
    await logActivity(
      action: 'rejected_user',
      module: 'users',
      details: 'Rejected join request',
      documentId: staffId,
    );
  }

  /// Get all staff members for current business
  Stream<List<AppUser>> getStaffMembers() {
    final uid = currentUserId;
    if (uid == null) return Stream.value([]);

    return _firestore
        .collection('users')
        .doc(uid)
        .collection('staff')
        .where(
          'status',
          whereIn: ['active', 'invited', 'pending_approval'],
        ) // Fetch all relevant statuses
        .snapshots()
        .asyncMap((snapshot) async {
          List<AppUser> staff = [];

          for (var doc in snapshot.docs) {
            final data = doc.data();
            final userId = data['userId'];
            final status = data['status'];

            // For pending requests, create AppUser from staff data directly
            if (status == 'pending_approval') {
              final role = UserRoleExtension.fromFirestore(
                data['role'] ?? 'salesStaff',
              );
              staff.add(
                AppUser(
                  id: doc.id, // Use staff document ID for pending requests
                  email: data['requestEmail'] ?? data['email'] ?? '',
                  name: data['requestName'] ?? data['name'] ?? '',
                  phone: data['phone'],
                  photoUrl: null,
                  role: role,
                  businessId: uid,
                  isActive: false,
                  createdAt:
                      (data['createdAt'] as Timestamp?)?.toDate() ??
                      DateTime.now(),
                  status: status,
                  permissions: data['permissions'] != null
                      ? Permission.fromMap(data['permissions'])
                      : Permission.forRole(role),
                ),
              );
            } else if (userId != null) {
              // For active/invited staff, fetch from user document
              final userDoc = await _firestore
                  .collection('users')
                  .doc(userId)
                  .get();
              if (userDoc.exists) {
                staff.add(AppUser.fromFirestore(userDoc));
              }
            }
          }

          return staff;
        });
  }

  /// Update user role
  Future<void> updateUserRole(String userId, UserRole newRole) async {
    final businessId = await getCurrentBusinessId();
    if (businessId == null) throw Exception('Business ID not found');

    final newPermissions = Permission.forRole(newRole);

    // Update user document
    await _firestore.collection('users').doc(userId).update({
      'role': newRole.toFirestore(),
      'permissions': newPermissions.toMap(),
    });

    // Update staff document
    final staffQuery = await _firestore
        .collection('users')
        .doc(businessId)
        .collection('staff')
        .where('userId', isEqualTo: userId)
        .limit(1)
        .get();

    if (staffQuery.docs.isNotEmpty) {
      await staffQuery.docs.first.reference.update({
        'role': newRole.toFirestore(),
        'permissions': newPermissions.toMap(),
      });
    }

    // Update business membership
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('business_membership')
        .doc(businessId)
        .update({
          'role': newRole.toFirestore(),
          'permissions': newPermissions.toMap(),
        });

    // Log activity
    await logActivity(
      action: 'updated_user_role',
      module: 'users',
      details: 'Changed role to ${newRole.displayName}',
      documentId: userId,
    );
  }

  /// Activate/Deactivate user
  Future<void> setUserActive(String userId, bool isActive) async {
    final businessId = await getCurrentBusinessId();
    if (businessId == null) throw Exception('Business ID not found');

    // Update user document
    await _firestore.collection('users').doc(userId).update({
      'isActive': isActive,
    });

    // Update staff document
    final staffQuery = await _firestore
        .collection('users')
        .doc(businessId)
        .collection('staff')
        .where('userId', isEqualTo: userId)
        .limit(1)
        .get();

    if (staffQuery.docs.isNotEmpty) {
      await staffQuery.docs.first.reference.update({'isActive': isActive});
    }

    // Update business membership
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('business_membership')
        .doc(businessId)
        .update({'isActive': isActive});

    // Log activity
    await logActivity(
      action: isActive ? 'activated_user' : 'deactivated_user',
      module: 'users',
      details: isActive ? 'User activated' : 'User deactivated',
      documentId: userId,
    );
  }

  /// Delete/Remove staff member
  Future<void> removeStaff(String userId) async {
    final businessId = await getCurrentBusinessId();
    if (businessId == null) throw Exception('Business ID not found');

    // Remove staff document
    final staffQuery = await _firestore
        .collection('users')
        .doc(businessId)
        .collection('staff')
        .where('userId', isEqualTo: userId)
        .limit(1)
        .get();

    if (staffQuery.docs.isNotEmpty) {
      await staffQuery.docs.first.reference.delete();
    }

    // Remove business membership
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('business_membership')
        .doc(businessId)
        .delete();

    // Log activity
    await logActivity(
      action: 'removed_user',
      module: 'users',
      details: 'Staff member removed',
      documentId: userId,
    );
  }

  /// Log user activity
  Future<void> logActivity({
    required String action,
    required String module,
    required String details,
    String? documentId,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;

    final businessId = await getCurrentBusinessId();
    if (businessId == null) return;

    final user = await getCurrentUser();

    await _firestore
        .collection('users')
        .doc(businessId)
        .collection('activity_log')
        .add({
          'userId': uid,
          'userName': user?.name ?? 'Unknown',
          'action': action,
          'module': module,
          'documentId': documentId,
          'details': details,
          'timestamp': FieldValue.serverTimestamp(),
        });
  }

  /// Get activity log
  Stream<QuerySnapshot<Map<String, dynamic>>> getActivityLog({
    String? userId,
    String? module,
    int limit = 50,
  }) {
    final businessId = currentUserId;
    if (businessId == null)
      return Stream.value(null as QuerySnapshot<Map<String, dynamic>>);

    Query<Map<String, dynamic>> query = _firestore
        .collection('users')
        .doc(businessId)
        .collection('activity_log')
        .orderBy('timestamp', descending: true)
        .limit(limit);

    if (userId != null) {
      query = query.where('userId', isEqualTo: userId);
    }

    if (module != null) {
      query = query.where('module', isEqualTo: module);
    }

    return query.snapshots();
  }

  /// Initialize current user as owner (for existing users)
  Future<void> initializeAsOwner() async {
    final uid = currentUserId;
    if (uid == null) return;

    final userDoc = await _firestore.collection('users').doc(uid).get();

    if (!userDoc.exists || !userDoc.data()!.containsKey('role')) {
      await _firestore.collection('users').doc(uid).set({
        'role': UserRole.owner.toFirestore(),
        'businessId': uid,
        'isActive': true,
        'permissions': Permission.forRole(UserRole.owner).toMap(),
        'lastLogin': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// Find staff member by username across all businesses
  Future<Map<String, dynamic>?> findStaffByUsername(String username) async {
    final allUsers = await _firestore.collection('users').get();

    for (var userDoc in allUsers.docs) {
      final staffQuery = await userDoc.reference
          .collection('staff')
          .where('username', isEqualTo: username)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (staffQuery.docs.isNotEmpty) {
        final staffDoc = staffQuery.docs.first;
        return {
          'staffId': staffDoc.id,
          'businessId': userDoc.id,
          'data': staffDoc.data(),
        };
      }
    }

    return null;
  }

  /// Get current staff ID from local storage
  Future<String?> getCurrentStaffId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('current_staff_id');
  }

  /// Set current staff ID in local storage
  Future<void> setCurrentStaffId(String? staffId) async {
    final prefs = await SharedPreferences.getInstance();
    if (staffId == null) {
      await prefs.remove('current_staff_id');
      await prefs.remove('current_business_id');
    } else {
      await prefs.setString('current_staff_id', staffId);
    }
  }

  /// Set current business ID for staff
  Future<void> setStaffBusinessId(String businessId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_business_id', businessId);
  }

  /// Get staff details by ID
  Future<Map<String, dynamic>?> getStaffById(
    String businessId,
    String staffId,
  ) async {
    final staffDoc = await _firestore
        .collection('users')
        .doc(businessId)
        .collection('staff')
        .doc(staffId)
        .get();

    if (staffDoc.exists) {
      return staffDoc.data();
    }
    return null;
  }
}
