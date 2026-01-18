# Smart Billing - User Management Feature

## 📱 Overview

This feature implements a **Vyapar/BillBook-style staff management system** that allows business owners to invite, manage, and control access for their team members.

## ✨ Key Features

### For Business Owners
- **Invite Staff** with unique 6-digit codes
- **QR Code Sharing** for easy onboarding
- **Role-Based Access Control** (Manager, Sales Staff, Inventory Staff)
- **Granular Permissions** for each staff member
- **Activate/Deactivate** staff instantly
- **Activity Logging** for audit trails

### For Staff Members
- **Passwordless Login** - Just enter username!
- **Role-Based Dashboard** - See only what you need
- **Quick Access** to assigned features

## 🏗️ Architecture

### Database Structure (Firestore)

```
users/
└── {ownerId}/
    ├── staff/
    │   └── {staffId}/
    │       ├── name: string
    │       ├── email: string
    │       ├── phone: string
    │       ├── username: string
    │       ├── role: string ('manager' | 'salesStaff' | 'inventoryStaff')
    │       ├── status: string ('invited' | 'pending_approval' | 'active' | 'rejected')
    │       ├── invitationCode: string (6 chars)
    │       ├── invitationAccepted: boolean
    │       ├── isActive: boolean
    │       ├── permissions: map
    │       ├── createdAt: timestamp
    │       └── approvedAt: timestamp
    └── activity_log/
        └── {logId}/
            ├── userId: string
            ├── action: string
            ├── module: string
            ├── details: string
            └── timestamp: timestamp
```

### File Structure

```
lib/
├── models/
│   ├── user_role.dart         # UserRole enum & Permission class
│   └── app_user.dart          # AppUser model
├── services/
│   └── user_service.dart      # All user management logic
├── screens/
│   ├── manage_users_screen.dart    # Staff management UI
│   └── accept_invitation_screen.dart # Join team screen
├── widgets/
│   └── user_management/
│       └── user_actions.dart  # Action helper methods
└── login_screen.dart          # Dual login (Owner/Staff)
```

## 👥 User Roles

| Role | Access Level | Can Do |
|------|-------------|--------|
| **Owner** | Full | Everything |
| **Manager** | High | Most operations except user management |
| **Sales Staff** | Medium | Invoices, quotations, customers, payments |
| **Inventory Staff** | Medium | Products, purchases, suppliers |

## 🔐 Permissions Matrix

| Permission | Owner | Manager | Sales | Inventory |
|------------|-------|---------|-------|-----------|
| Create Invoice | ✅ | ✅ | ✅ | ❌ |
| View Reports | ✅ | ✅ | ❌ | ❌ |
| Manage Products | ✅ | ✅ | ❌ | ✅ |
| Create Purchase | ✅ | ✅ | ❌ | ✅ |
| Manage Customers | ✅ | ✅ | ✅ | ❌ |
| Manage Users | ✅ | ❌ | ❌ | ❌ |
| Edit Settings | ✅ | ❌ | ❌ | ❌ |

## 🚀 User Flows

### Flow 1: Owner Invites Staff

```
1. Owner opens "Manage Staff" screen
2. Taps "Add Staff" button
3. Enters staff name, email (optional), phone (optional)
4. Selects role (Manager/Sales/Inventory)
5. System generates 6-digit code (e.g., "ABC123")
6. Owner shares code via WhatsApp/SMS/QR
```

### Flow 2: Staff Joins Team

```
1. Staff downloads Smart Billing app
2. Opens app and taps "Join Team with Code"
3. Enters invitation code and their username
4. Request is sent to owner for approval
5. Staff sees "Waiting for approval" screen
```

### Flow 3: Owner Approves Staff

```
1. Owner sees pending request notification
2. Opens "Manage Staff" > "Pending" tab
3. Reviews request details
4. Taps "Approve" or "Reject"
5. If approved, staff can now login
```

### Flow 4: Staff Logs In

```
1. Staff opens app
2. Selects "Staff Login" tab
3. Enters their username (no password!)
4. System validates and grants access
5. Staff sees role-based dashboard
```

## 💻 Code Examples

### Check Permission Before Action

```dart
final userService = UserService();

// Before creating an invoice
if (await userService.checkPermission((p) => p.createInvoice)) {
  // Allow creating invoice
  Navigator.push(context, MaterialPageRoute(builder: (_) => AddInvoiceScreen()));
} else {
  // Show access denied
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('You don\'t have permission to create invoices')),
  );
}
```

### Invite a Staff Member

```dart
final userService = UserService();

try {
  final invitationCode = await userService.inviteUser(
    email: 'staff@example.com',
    name: 'John Doe',
    role: UserRole.salesStaff,
    phone: '9876543210',
  );
  
  print('Invitation code: $invitationCode');
} catch (e) {
  print('Error: $e');
}
```

### Get Staff Members Stream

```dart
StreamBuilder<List<AppUser>>(
  stream: userService.getStaffMembers(),
  builder: (context, snapshot) {
    if (snapshot.hasData) {
      final staff = snapshot.data!;
      return ListView.builder(
        itemCount: staff.length,
        itemBuilder: (context, index) {
          final user = staff[index];
          return ListTile(
            title: Text(user.name),
            subtitle: Text(user.role.displayName),
          );
        },
      );
    }
    return CircularProgressIndicator();
  },
)
```

## 🔧 Setup Instructions

### 1. Add Dependencies

Make sure these are in your `pubspec.yaml`:

```yaml
dependencies:
  shared_preferences: ^2.3.4
  app_links: ^6.3.3
  qr_flutter: ^4.1.0
  share_plus: ^10.0.2
```

### 2. Run Flutter Commands

```bash
flutter clean
flutter pub get
flutter run
```

### 3. Firebase Rules

Update your Firestore rules to allow staff subcollection access:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
      
      match /staff/{staffId} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }
      
      match /activity_log/{logId} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }
    }
  }
}
```

## 🐛 Troubleshooting

### Staff Can't Login
1. Check if status is `'active'`
2. Check if `isActive` is `true`
3. Verify username matches exactly (case-sensitive)

### Invitation Code Not Working
1. Ensure code is 6 characters
2. Check if code hasn't been used already
3. Verify code format (uppercase letters + numbers)

### Permissions Not Applying
1. Log out and log back in
2. Clear app data
3. Check Firestore for correct permission values

## 📞 Support

For issues or questions, check:
- `USER_MANAGEMENT_GUIDE.md` - Detailed technical guide
- `IMPLEMENTATION_STATUS.md` - What's implemented and pending

---

**Version:** 1.0.0  
**Last Updated:** 2024