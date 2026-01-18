# Smart Billing - User Management System Guide

## Overview

This document outlines the enhanced User Management System for Smart Billing, designed similar to Vyapar and BillBook apps.

## Features

### 1. Staff Roles
- **Owner**: Full access to all features
- **Manager**: Can manage most operations except user management and settings
- **Sales Staff**: Create invoices, quotations, manage customers
- **Inventory Staff**: Manage products, purchases, suppliers

### 2. Invitation Flow
1. Owner creates invitation with staff details
2. System generates unique 6-character code
3. Owner shares code via WhatsApp/SMS/QR
4. Staff enters code in app
5. Owner approves/rejects request
6. Staff gets username-based login (no password needed)

### 3. Permissions System
Each role has granular permissions:
- Dashboard & Reports
- Invoices & Quotations
- Purchases
- Customers & Suppliers
- Products & Inventory
- Payments
- Settings & Users

## Database Structure

### Firestore Collections

```
users/{ownerId}/
├── staff/{staffId}
│   ├── name: string
│   ├── email: string
│   ├── phone: string
│   ├── username: string
│   ├── role: string
│   ├── status: 'invited' | 'pending_approval' | 'active' | 'rejected'
│   ├── invitationCode: string
│   ├── invitationAccepted: boolean
│   ├── isActive: boolean
│   ├── permissions: map
│   ├── createdAt: timestamp
│   ├── approvedAt: timestamp
│   └── lastLogin: timestamp
├── activity_log/{logId}
│   ├── userId: string
│   ├── userName: string
│   ├── action: string
│   ├── module: string
│   ├── details: string
│   └── timestamp: timestamp
```

## Staff Login Flow

### For Staff (Username Login)
1. Staff opens app
2. Selects "Staff Login" tab
3. Enters username
4. App validates username against all businesses
5. If valid & active, stores session locally
6. Redirects to dashboard with role-based access

### For Owner (Email/Password Login)
1. Standard Firebase Auth login
2. Full access to all features

## Implementation Files

### Models
- `lib/models/user_role.dart` - UserRole enum and Permission class
- `lib/models/app_user.dart` - AppUser model

### Services
- `lib/services/user_service.dart` - All user management logic

### Screens
- `lib/screens/manage_users_screen.dart` - Staff management UI
- `lib/screens/accept_invitation_screen.dart` - Join team screen
- `lib/login_screen.dart` - Dual login (Owner/Staff)

## Key Methods in UserService

```dart
// Invite new staff
Future<String> inviteUser({email, name, role, phone})

// Staff submits join request
Future<void> submitJoinRequest(code, username)

// Owner approves request
Future<void> approveJoinRequest(staffId)

// Owner rejects request
Future<void> rejectJoinRequest(staffId)

// Get all staff members
Stream<List<AppUser>> getStaffMembers()

// Update staff role
Future<void> updateUserRole(userId, newRole)

// Activate/deactivate staff
Future<void> setUserActive(userId, isActive)

// Remove staff
Future<void> removeStaff(userId)

// Find staff by username (for login)
Future<Map?> findStaffByUsername(username)

// Check permission
Future<bool> checkPermission(check)
```

## UI Features

### Manage Users Screen
- **3 Tabs**: Active, Pending, Invited
- **Stats Summary**: Count badges for each status
- **Search**: Filter by name or username
- **Staff Cards**: Show role, permissions preview, status

### Staff Actions
- View Details
- Edit Permissions
- Change Role
- Activate/Deactivate
- Remove

### Add Staff Flow
1. Bottom sheet form
2. Enter name, email (optional), phone (optional)
3. Select role with description
4. Generate invitation code
5. Show QR code + share options

## Permission Checking in App

```dart
// In any screen, check permission before action
final userService = UserService();
final canCreateInvoice = await userService.checkPermission(
  (p) => p.createInvoice
);

if (canCreateInvoice) {
  // Allow action
} else {
  // Show access denied message
}
```

## Best Practices

1. **Always check permissions** before sensitive operations
2. **Log all activities** for audit trail
3. **Use streams** for real-time staff list updates
4. **Handle offline** scenarios gracefully
5. **Validate invitation codes** server-side

## Future Enhancements

- [ ] Push notifications for approval requests
- [ ] Email notifications
- [ ] Time-based access (working hours)
- [ ] Location-based access
- [ ] Two-factor authentication for owners
- [ ] Staff performance analytics
- [ ] Bulk staff import via Excel

## Troubleshooting

### Staff can't login
1. Check if status is 'active'
2. Check if isActive is true
3. Verify username is correct (case-sensitive)

### Invitation code not working
1. Check if code exists
2. Check if not already accepted
3. Verify 6-character format (uppercase)

### Permissions not applying
1. Clear app cache
2. Re-login
3. Check Firestore rules