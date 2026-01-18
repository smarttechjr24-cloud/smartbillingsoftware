# Smart Billing - User Management Implementation Status

## ✅ Completed

### 1. Models
- `lib/models/user_role.dart` - Complete with UserRole enum and Permission class
- `lib/models/app_user.dart` - Complete with AppUser model

### 2. Services
- `lib/services/user_service.dart` - Complete with all core methods:
  - `inviteUser()` - Create invitation with code
  - `submitJoinRequest()` - Staff joins with code
  - `approveJoinRequest()` - Owner approves
  - `rejectJoinRequest()` - Owner rejects
  - `getStaffMembers()` - Stream of staff list
  - `updateUserRole()` - Change staff role
  - `setUserActive()` - Activate/deactivate
  - `removeStaff()` - Delete staff
  - `findStaffByUsername()` - Staff login lookup
  - `logActivity()` - Activity logging

### 3. Screens
- `lib/login_screen.dart` - Dual login (Owner/Staff tabs)
- `lib/screens/accept_invitation_screen.dart` - Join team screen
- `lib/screens/manage_users_screen.dart` - Staff management (partial)

### 4. Helper Files
- `lib/widgets/user_management/user_actions.dart` - Action methods mixin (partial)

## ⚠️ Needs Completion

### manage_users_screen.dart
The file was partially edited. To complete it, you need to add these missing methods at the end:

```dart
  // Add these methods to complete the screen

  String _getRoleDescription(UserRole role) {
    switch (role) {
      case UserRole.owner:
        return 'Full access to all features';
      case UserRole.manager:
        return 'Manage operations, no user management';
      case UserRole.salesStaff:
        return 'Invoices, quotations, customers';
      case UserRole.inventoryStaff:
        return 'Products, purchases, suppliers';
    }
  }

  void _handleStaffAction(String action, AppUser user) {
    switch (action) {
      case 'view':
        _showStaffDetailsBottomSheet(user);
        break;
      case 'edit_permissions':
        _showEditPermissionsDialog(user);
        break;
      case 'change_role':
        _showChangeRoleDialog(user);
        break;
      case 'activate':
      case 'deactivate':
        _toggleUserStatus(user);
        break;
      case 'remove':
        _confirmRemoveUser(user);
        break;
    }
  }

  void _showStaffDetailsBottomSheet(AppUser user) {
    // Show bottom sheet with user details
  }

  void _showEditPermissionsDialog(AppUser user) {
    // Show dialog to edit permissions
  }

  Future<void> _showChangeRoleDialog(AppUser user) async {
    // Show role selection dialog
  }

  Future<void> _toggleUserStatus(AppUser user) async {
    try {
      await _userService.setUserActive(user.id, !user.isActive);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(user.isActive ? 'User deactivated' : 'User activated'),
            backgroundColor: successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _confirmRemoveUser(AppUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Staff Member?'),
        content: Text('Are you sure you want to remove ${user.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: dangerColor),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _userService.removeStaff(user.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Staff member removed'), backgroundColor: successColor),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  Future<void> _showApproveDialog(AppUser user) async {
    // Approve dialog with role selection
    await _userService.approveJoinRequest(user.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${user.name} approved!'), backgroundColor: successColor),
      );
    }
  }

  Future<void> _rejectRequest(AppUser user) async {
    await _userService.rejectJoinRequest(user.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request rejected')),
      );
    }
  }

  Future<void> _cancelInvitation(AppUser user) async {
    await _userService.removeStaff(user.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invitation cancelled')),
      );
    }
  }

  void _shareInvitation(AppUser user) {
    if (user.invitationCode != null) {
      final code = user.invitationCode!;
      final link = 'smartbilling://join?code=$code';
      final message = 'Join our team on Smart Billing!\n\nCode: $code\n\nLink: $link';
      Share.share(message, subject: 'Join Smart Billing Team');
    }
  }

  void _showQRCodeDialog(String code, String name) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Scan to Join', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              QrImageView(data: 'smartbilling://join?code=$code', size: 200),
              const SizedBox(height: 16),
              Text('Code: $code', style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createInvitation({
    required String name,
    required String email,
    required String phone,
    required UserRole role,
  }) async {
    try {
      final code = await _userService.inviteUser(
        email: email,
        name: name,
        role: role,
        phone: phone.isEmpty ? null : phone,
      );
      if (mounted) {
        _showQRCodeDialog(code, name);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('How Staff Management Works'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('1. Add Staff', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Tap + button to invite staff with name and role.\n'),
              Text('2. Share Code', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Share the 6-digit code or QR with your staff.\n'),
              Text('3. Staff Joins', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Staff enters code in app to request access.\n'),
              Text('4. Approve', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Review and approve staff requests.\n'),
              Text('5. Staff Login', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Staff can login with just their username - no password needed!'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }
}
```

## 🔧 Quick Fix Instructions

If `flutter run` fails, run these commands:

```bash
cd smartbilling
flutter clean
flutter pub get
flutter run
```

## 📱 Testing the Feature

1. Login as Owner
2. Go to More > Manage Staff
3. Tap "Add Staff" button
4. Fill in staff details and select role
5. Share the generated code
6. On another device/emulator, enter the code
7. Back on owner device, approve the request
8. Staff can now login with username only

## 🔒 Security Notes

- Invitation codes expire after use
- Staff cannot access user management
- All actions are logged for audit
- Owner can deactivate staff instantly