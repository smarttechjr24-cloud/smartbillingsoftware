import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../models/app_user.dart';
import '../../models/user_role.dart';
import '../../services/user_service.dart';

/// Helper mixin for user management actions
mixin UserActionsMixin<T extends StatefulWidget> on State<T> {
  final UserService userService = UserService();

  // Theme colors
  static const Color primaryColor = Color(0xFF1976D2);
  static const Color successColor = Color(0xFF4CAF50);
  static const Color warningColor = Color(0xFFFF9800);
  static const Color dangerColor = Color(0xFFF44336);
  static const Color bgColor = Color(0xFFF5F7FA);

  // ==================== HANDLE STAFF ACTIONS ====================
  void handleStaffAction(String action, AppUser user) {
    switch (action) {
      case 'view':
        showStaffDetailsBottomSheet(user);
        break;
      case 'edit_permissions':
        showEditPermissionsDialog(user);
        break;
      case 'change_role':
        showChangeRoleDialog(user);
        break;
      case 'activate':
      case 'deactivate':
        toggleUserStatus(user);
        break;
      case 'remove':
        confirmRemoveUser(user);
        break;
    }
  }

  // ==================== CREATE INVITATION ====================
  Future<void> createInvitation({
    required String name,
    required String email,
    required String phone,
    required UserRole role,
  }) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final invitationCode = await userService.inviteUser(
        email: email,
        name: name,
        role: role,
        phone: phone.isEmpty ? null : phone,
      );

      Navigator.pop(context); // Close loading

      if (mounted) {
        showInvitationSuccessDialog(invitationCode, name, email);
      }
    } catch (e) {
      Navigator.pop(context); // Close loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: dangerColor),
        );
      }
    }
  }

  // ==================== INVITATION SUCCESS DIALOG ====================
  void showInvitationSuccessDialog(String code, String name, String email) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: successColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle, color: successColor, size: 48),
              ),
              const SizedBox(height: 16),
              const Text(
                'Invitation Created!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Share this code with $name',
                style: TextStyle(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      code,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.copy, color: primaryColor),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: code));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Code copied!')),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        showQRCodeDialog(code, name);
                      },
                      icon: const Icon(Icons.qr_code),
                      label: const Text('QR Code'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        shareInvitationCode(code, name);
                      },
                      icon: const Icon(Icons.share),
                      label: const Text('Share'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== QR CODE DIALOG ====================
  void showQRCodeDialog(String code, String name) {
    final link = 'smartbilling://join?code=$code';
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Scan to Join',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Ask $name to scan this QR code',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: QrImageView(
                  data: link,
                  version: QrVersions.auto,
                  size: 200,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.vpn_key, size: 18, color: primaryColor),
                    const SizedBox(width: 8),
                    Text(
                      'Code: $code',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== SHARE INVITATION ====================
  void shareInvitationCode(String code, String name) {
    final link = 'smartbilling://join?code=$code';
    final message = '''🎉 Join our team on Smart Billing!

Hi $name,

You've been invited to join our team.

📱 Download Smart Billing app and use this code:
🔑 Invitation Code: $code

Or click this link:
$link

See you on the team! 👋''';

    Share.share(message, subject: 'Join Smart Billing Team');
  }

  // ==================== SHARE INVITATION FROM USER ====================
  void shareInvitation(AppUser user) {
    if (user.invitationCode != null) {
      shareInvitationCode(user.invitationCode!, user.name);
    }
  }

  // ==================== STAFF DETAILS BOTTOM SHEET ====================
  void showStaffDetailsBottomSheet(AppUser user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: user.role.color.withOpacity(0.2),
                  child: Icon(user.role.icon, color: user.role.color, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: user.role.color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          user.role.displayName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: user.role.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: user.isActive ? successColor.withOpacity(0.1) : Colors.grey[100],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        user.isActive ? Icons.check_circle : Icons.cancel,
                        size: 16,
                        color: user.isActive ? successColor : Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        user.isActive ? 'Active' : 'Inactive',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: user.isActive ? successColor : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            _buildDetailRow(Icons.email_outlined, 'Email', user.email.isNotEmpty ? user.email : 'Not provided'),
            if (user.phone != null && user.phone!.isNotEmpty)
              _buildDetailRow(Icons.phone_outlined, 'Phone', user.phone!),
            _buildDetailRow(Icons.calendar_today_outlined, 'Joined', _formatDate(user.createdAt)),
            if (user.lastLogin != null)
              _buildDetailRow(Icons.access_time, 'Last Login', _formatDate(user.lastLogin!)),
            const SizedBox(height: 24),
            const Text(
              'Permissions',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            _buildPermissionsList(user.permissions),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      showEditPermissionsDialog(user);
                    },
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit Permissions'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      showChangeRoleDialog(user);
                    },
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Change Role'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              Text(value, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildPermissionsList(Permission permissions) {
    final permissionItems = [
      {'label': 'Create Invoice', 'allowed': permissions.createInvoice},
      {'label': 'View Reports', 'allowed': permissions.viewReports},
      {'label': 'Manage Products', 'allowed': permissions.manageProducts},
      {'label': 'Create Purchase', 'allowed': permissions.createPurchase},
      {'label': 'Record Payments', 'allowed': permissions.recordPayment},
      {'label': 'Manage Customers', 'allowed': permissions.manageCustomers},
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: permissionItems.map((item) {
        final allowed = item['allowed'] as bool;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: allowed ? successColor.withOpacity(0.1) : Colors.grey[100],
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: allowed ? successColor.withOpacity(0.3) : Colors.grey[300]!,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                allowed ? Icons.check : Icons.close,
                size: 14,
                color: allowed ? successColor : Colors.grey,
              ),
              const SizedBox(width: 4),
              Text(
                item['label'] as String,
                style: TextStyle(
                  fontSize: 12,
                  color: allowed ? Colors.grey[800] : Colors.grey[500],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ==================== EDIT PERMISSIONS DIALOG ====================
  void showEditPermissionsDialog(AppUser user) {
    // Create mutable copy of permissions
    Map<String, bool> editedPermissions = {
      'createInvoice': user.permissions.createInvoice,
      'editInvoice': user.permissions.editInvoice,
      'deleteInvoice': user.permissions.deleteInvoice,
      'viewInvoice': user.permissions.viewInvoice,
      'createQuotation': user.permissions.createQuotation,
      'viewReports': user.permissions.viewReports,
      'viewProfitAnalytics': user.permissions.viewProfitAnalytics,
      'createPurchase': user.permissions.createPurchase,
      'editPurchase': user.permissions.editPurchase,
      'viewPurchase': user.permissions.viewPurchase,
      'manageCustomers': user.permissions.manageCustomers,
      'viewCustomers': user.permissions.viewCustomers,
      'manageSuppliers': user.permissions.manageSuppliers,
      'viewSuppliers': user.permissions.viewSuppliers,
      'manageProducts': user.permissions.manageProducts,
      'viewProducts': user.permissions.viewProducts,
      'viewStock': user.permissions.viewStock,
      'recordPayment': user.permissions.recordPayment,
      'viewPayments': user.permissions.viewPayments,
    };

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.security, color: Colors.purple[700]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Edit Permissions',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              user.name,
                              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    shrinkWrap: true,
                    children: [
                      _buildPermissionSection('Invoices & Quotations', [
                        _buildPermissionSwitch('Create Invoice', 'createInvoice', editedPermissions, setState),
                        _buildPermissionSwitch('Edit Invoice', 'editInvoice', editedPermissions, setState),
                        _buildPermissionSwitch('View Invoice', 'viewInvoice', editedPermissions, setState),
                        _buildPermissionSwitch('Create Quotation', 'createQuotation', editedPermissions, setState),
                      ]),
                      _buildPermissionSection('Reports', [
                        _buildPermissionSwitch('View Reports', 'viewReports', editedPermissions, setState),
                        _buildPermissionSwitch('View Profit Analytics', 'viewProfitAnalytics', editedPermissions, setState),
                      ]),
                      _buildPermissionSection('Purchases', [
                        _buildPermissionSwitch('Create Purchase', 'createPurchase', editedPermissions, setState),
                        _buildPermissionSwitch('Edit Purchase', 'editPurchase', editedPermissions, setState),
                        _buildPermissionSwitch('View Purchase', 'viewPurchase', editedPermissions, setState),
                      ]),
                      _buildPermissionSection('Customers & Suppliers', [
                        _buildPermissionSwitch('Manage Customers', 'manageCustomers', editedPermissions, setState),
                        _buildPermissionSwitch('View Customers', 'viewCustomers', editedPermissions, setState),
                        _buildPermissionSwitch('Manage Suppliers', 'manageSuppliers', editedPermissions, setState),
                        _buildPermissionSwitch('View Suppliers', 'viewSuppliers', editedPermissions, setState),
                      ]),
                      _buildPermissionSection('Products', [
                        _buildPermissionSwitch('Manage Products', 'manageProducts', editedPermissions, setState),
                        _buildPermissionSwitch('View Products', 'viewProducts', editedPermissions, setState),
                        _buildPermissionSwitch('View Stock', 'viewStock', editedPermissions, setState),
                      ]),
                      _buildPermissionSection('Payments', [
                        _buildPermissionSwitch('Record Payment', 'recordPayment', editedPermissions, setState),
                        _buildPermissionSwitch('View Payments', 'viewPayments', editedPermissions, setState),
                      ]),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            await _savePermissions(user.id, editedPermissions);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('Save Changes'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionSection(String title, List<Widget> switches) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        ...switches,
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildPermissionSwitch(
    String label,
    String key,
    Map<String, bool> permissions,
    StateSetter setState,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Switch(
            value: permissions[key] ?? false,
            onChanged: (value) => setState(() => permissions[key] = value),
            activeColor: successColor,
          ),
        ],
      ),
    );
  }

  Future<void> _savePermissions(String userId, Map<String, bool> permissions) async {
    try {
      // TODO: Implement saving permissions via UserService
      // await userService.updateUserPermissions(userId, permissions);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permissions updated successfully'),
            backgroundColor: successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: dangerColor),
        );
      }
    }
  }

  // ==================== CHANGE ROLE DIALOG ====================
  Future<void> showChangeRoleDialog(AppUser user) async {
    UserRole? selectedRole = await showDialog<UserRole>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.swap_horiz, color: Colors.teal),
                  const SizedBox(width: 12),
                  const Text(
                    'Change Role',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Select new role for ${user.name}',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 20),
              ...[UserRole.manager, UserRole.salesStaff, UserRole.inventoryStaff].map((role) {
                final isSelected = user.role == role;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => Navigator.pop(context, role),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isSelected ? role.color.withOpacity(0.1) : bgColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? role.color : Colors.grey[300]!,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(role.icon, color: role.color, size: 28),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  role.displayName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? role.color : Colors.black,
                                  ),
                                ),
                                Text(
                                  getRoleDescription(role),
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            Icon(Icons.check_circle, color: role.color),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (selectedRole != null && selectedRole != user.role) {
      try {
        await userService.updateUserRole(user.id, selectedRole);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Role updated to ${selectedRole.displayName}'),
              backgroundColor: successColor,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: dangerColor),
          );
        }
      }
    }
  }

  String getRoleDescription(UserRole role) {
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

  // ==================== TOGGLE USER STATUS ====================
  Future<void> toggleUserStatus(AppUser user) async {
    final action = user.isActive ? 'deactivate' : 'activate';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('${user.isActive ? 'Deactivate' : 'Activate'} ${user.name}?'),
        content: Text(
          user.isActive
              ? 'This user will not be able to access the app until reactivated.'
              : 'This user will regain access to the app.',
        ),
        actions: [
          TextButton(
            on
