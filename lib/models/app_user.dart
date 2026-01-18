import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_role.dart';

/// Represents a user in the system (owner or staff member)
class AppUser {
  final String id;
  final String email;
  final String name;
  final String? phone;
  final String? photoUrl;
  final UserRole role;
  final String businessId; // Owner's UID (for staff) or own UID (for owner)
  final bool isActive;
  final DateTime createdAt;
  final DateTime? lastLogin;
  final String? invitationCode;
  final bool invitationAccepted;
  final String status; // 'active', 'invited', 'pending_approval', 'rejected'
  final Permission permissions;

  AppUser({
    required this.id,
    required this.email,
    required this.name,
    this.phone,
    this.photoUrl,
    required this.role,
    required this.businessId,
    this.isActive = true,
    required this.createdAt,
    this.lastLogin,
    this.invitationCode,
    this.invitationAccepted = false,
    this.status = 'active',
    required this.permissions,
  });

  /// Check if user is the business owner
  bool get isOwner => role == UserRole.owner;

  /// Check if user has a specific permission
  bool hasPermission(bool Function(Permission) check) {
    return check(permissions);
  }

  /// Convert to Firestore map
  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'phone': phone,
      'photoUrl': photoUrl,
      'role': role.toFirestore(),
      'businessId': businessId,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastLogin': lastLogin != null ? Timestamp.fromDate(lastLogin!) : null,
      'invitationCode': invitationCode,
      'invitationAccepted': invitationAccepted,
      'status': status,
      'permissions': permissions.toMap(),
    };
  }

  /// Create from Firestore document
  factory AppUser.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final role = UserRoleExtension.fromFirestore(data['role'] ?? 'salesStaff');

    return AppUser(
      id: doc.id,
      email: data['email'] ?? '',
      name: data['name'] ?? '',
      phone: data['phone'],
      photoUrl: data['photoUrl'],
      role: role,
      businessId: data['businessId'] ?? '',
      isActive: data['isActive'] ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastLogin: (data['lastLogin'] as Timestamp?)?.toDate(),
      invitationCode: data['invitationCode'],
      invitationAccepted: data['invitationAccepted'] ?? false,
      status: data['status'] ?? 'active',
      permissions: data['permissions'] != null
          ? Permission.fromMap(data['permissions'])
          : Permission.forRole(role),
    );
  }

  /// Create from map
  factory AppUser.fromMap(Map<String, dynamic> data, String id) {
    final role = UserRoleExtension.fromFirestore(data['role'] ?? 'salesStaff');

    return AppUser(
      id: id,
      email: data['email'] ?? '',
      name: data['name'] ?? '',
      phone: data['phone'],
      photoUrl: data['photoUrl'],
      role: role,
      businessId: data['businessId'] ?? '',
      isActive: data['isActive'] ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastLogin: (data['lastLogin'] as Timestamp?)?.toDate(),
      invitationCode: data['invitationCode'],
      invitationAccepted: data['invitationAccepted'] ?? false,
      status: data['status'] ?? 'active',
      permissions: data['permissions'] != null
          ? Permission.fromMap(data['permissions'])
          : Permission.forRole(role),
    );
  }

  /// Copy with method for updates
  AppUser copyWith({
    String? id,
    String? email,
    String? name,
    String? phone,
    String? photoUrl,
    UserRole? role,
    String? businessId,
    bool? isActive,
    DateTime? createdAt,
    DateTime? lastLogin,
    String? invitationCode,
    bool? invitationAccepted,
    String? status,
    Permission? permissions,
  }) {
    return AppUser(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      photoUrl: photoUrl ?? this.photoUrl,
      role: role ?? this.role,
      businessId: businessId ?? this.businessId,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      lastLogin: lastLogin ?? this.lastLogin,
      invitationCode: invitationCode ?? this.invitationCode,
      invitationAccepted: invitationAccepted ?? this.invitationAccepted,
      status: status ?? this.status,
      permissions: permissions ?? this.permissions,
    );
  }
}
