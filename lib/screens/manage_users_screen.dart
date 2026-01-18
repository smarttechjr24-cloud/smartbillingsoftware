import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../models/app_user.dart';
import '../models/user_role.dart';
import '../services/user_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({Key? key}) : super(key: key);

  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen>
    with SingleTickerProviderStateMixin {
  final UserService _userService = UserService();
  final _searchController = TextEditingController();
  String _searchQuery = '';
  late TabController _tabController;

  static const Color primaryColor = Color(0xFF1976D2);
  static const Color successColor = Color(0xFF4CAF50);
  static const Color warningColor = Color(0xFFFF9800);
  static const Color dangerColor = Color(0xFFF44336);
  static const Color bgColor = Color(0xFFF5F7FA);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('Manage Staff'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showHelpDialog,
            tooltip: 'Help',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Active', icon: Icon(Icons.people, size: 20)),
            Tab(text: 'Pending', icon: Icon(Icons.hourglass_empty, size: 20)),
            Tab(text: 'Invited', icon: Icon(Icons.mail_outline, size: 20)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddStaffDialog,
        backgroundColor: primaryColor,
        icon: const Icon(Icons.person_add),
        label: const Text('Add Staff'),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildStaffList('active'),
                _buildStaffList('pending_approval'),
                _buildStaffList('invited'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
        decoration: InputDecoration(
          hintText: 'Search by name...',
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: bgColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
      ),
    );
  }

  Widget _buildStaffList(String status) {
    return StreamBuilder<List<AppUser>>(
      stream: _userService.getStaffMembers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final allStaff = snapshot.data ?? [];
        final filteredStaff = allStaff.where((user) {
          final matchesStatus = user.status == status;
          final matchesSearch = _searchQuery.isEmpty ||
              user.name.toLowerCase().contains(_searchQuery) ||
              user.email.toLowerCase().contains(_searchQuery);
          return matchesStatus && matchesSearch;
        }).toList();

        if (filteredStaff.isEmpty) {
          return _buildEmptyState(status);
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: filteredStaff.length,
          itemBuilder: (context, index) {
            final user = filteredStaff[index];
            if (status == 'pending_approval') return _buildPendingCard(user);
            if (status == 'invited') return _buildInvitedCard(user);
            return _buildActiveStaffCard(user);
          },
        );
      },
    );
  }

  Widget _buildEmptyState(String status) {
    IconData icon;
    String title;
    String subtitle;

    switch (status) {
      case 'active':
        icon = Icons.people_outline;
        title = 'No active staff';
        subtitle = 'Invite team members to get started';
        break;
      case 'pending_approval':
        icon = Icons.hourglass_empty;
        title = 'No pending requests';
        subtitle = 'Staff join requests will appear here';
        break;
      case 'invited':
        icon = Icons.mail_outline;
        title = 'No pending invitations';
        subtitle = 'Send invitations to add staff';
        break;
      default:
        icon = Icons.inbox;
        title = 'No data';
        subtitle = '';
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[700])),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildActiveStaffCard(AppUser user) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: user.role.color.withOpacity(0.2),
          child: Icon(user.role.icon, color: user.role.color),
        ),
        title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user.role.displayName, style: TextStyle(color: user.role.color, fontSize: 12)),
            if (user.email.isNotEmpty) Text(user.email, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _handleStaffAction(value, user),
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'change_role', child: Text('Change Role')),
            PopupMenuItem(
              value: user.isActive ? 'deactivate' : 'activate',
              child: Text(user.isActive ? 'Deactivate' : 'Activate'),
            ),
            const PopupMenuItem(value: 'remove', child: Text('Remove', style: TextStyle(color: Colors.red))),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingCard(AppUser user) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: warningColor.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: warningColor.withOpacity(0.2),
                  child: const Icon(Icons.person_add, color: warningColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('Waiting for approval', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: user.role.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(user.role.displayName, style: TextStyle(fontSize: 11, color: user.role.color, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _rejectRequest(user),
                    style: OutlinedButton.styleFrom(foregroundColor: dangerColor),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _approveRequest(user),
                    style: ElevatedButton.styleFrom(backgroundColor: successColor, foregroundColor: Colors.white),
                    child: const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvitedCard(AppUser user) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: primaryColor.withOpacity(0.2),
                  child: const Icon(Icons.mail_outline, color: primaryColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      if (user.email.isNotEmpty) Text(user.email, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: user.role.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(user.role.displayName, style: TextStyle(fontSize: 11, color: user.role.color, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            if (user.invitationCode != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.vpn_key, color: primaryColor, size: 20),
                    const SizedBox(width: 8),
                    Text('Code: ${user.invitationCode}', style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 20),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: user.invitationCode!));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied!')));
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.share, size: 20),
                      onPressed: () {
                        if (user.invitationCode != null && user.invitationCode!.isNotEmpty) {
                          _shareInvitationCode(user.invitationCode!, user.name);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _cancelInvitation(user),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showQRCodeDialog(user.invitationCode ?? '', user.name),
                    icon: const Icon(Icons.qr_code, size: 18),
                    label: const Text('QR Code'),
                    style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==================== ACTIONS ====================

  void _handleStaffAction(String action, AppUser user) {
    switch (action) {
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

  Future<void> _showAddStaffDialog() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    UserRole selectedRole = UserRole.salesStaff;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Staff Member'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name *',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email (Optional)',
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<UserRole>(
                  value: selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    prefixIcon: Icon(Icons.work),
                    border: OutlineInputBorder(),
                  ),
                  items: [UserRole.manager, UserRole.salesStaff, UserRole.inventoryStaff]
                      .map((role) => DropdownMenuItem(
                            value: role,
                            child: Text(role.displayName),
                          ))
                      .toList(),
                  onChanged: (value) => setState(() => selectedRole = value!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a name')),
                  );
                  return;
                }
                Navigator.pop(context, {
                  'name': nameController.text.trim(),
                  'email': emailController.text.trim(),
                  'role': selectedRole,
                });
              },
              child: const Text('Create Invitation'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      await _createInvitation(
        name: result['name'],
        email: result['email'],
        role: result['role'],
      );
    }
  }

  Future<void> _createInvitation({
    required String name,
    required String email,
    required UserRole role,
  }) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final code = await _userService.inviteUser(
        email: email,
        name: name,
        role: role,
      );

      Navigator.pop(context);

      if (mounted) {
        _showInvitationSuccessDialog(code, name);
      }
    } catch (e) {
      Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: dangerColor),
        );
      }
    }
  }

  void _showInvitationSuccessDialog(String code, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: successColor),
            SizedBox(width: 8),
            Text('Invitation Created!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Share this code with $name:'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(code, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 4)),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied!')));
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _showQRCodeDialog(code, name);
            },
            icon: const Icon(Icons.qr_code),
            label: const Text('QR Code'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final message = 'Join our team on Smart Billing!\n\nCode: $code\n\nLink: smartbilling://join?code=$code';
              Share.share(message);
            },
            icon: const Icon(Icons.share),
            label: const Text('Share'),
          ),
        ],
      ),
    );
  }

  void _showQRCodeDialog(String code, String name) {
    debugPrint('🔲 QR Dialog called with code: "$code", name: "$name"');

    if (code.isEmpty) {
      debugPrint('❌ QR Code is empty!');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No invitation code available')),
      );
      return;
    }

    final qrData = 'smartbilling://join?code=$code';
    debugPrint('🔲 QR Data: $qrData');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.qr_code_2, color: primaryColor),
            const SizedBox(width: 8),
            const Text('Scan to Join'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // QR Code Container
              Container(
                width: 220,
                height: 220,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 200,
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    errorStateBuilder: (context, error) {
                      debugPrint('❌ QR Error: $error');
                      return Container(
                        width: 200,
                        height: 200,
                        color: Colors.grey[100],
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.broken_image, color: Colors.grey, size: 48),
                              const SizedBox(height: 8),
                              Text('QR unavailable', style: TextStyle(color: Colors.grey[600])),
                              const SizedBox(height: 4),
                              Text('Use code below', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Invitation Code Display
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: primaryColor.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.vpn_key, size: 20, color: primaryColor),
                    const SizedBox(width: 10),
                    Text(
                      code,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                        fontSize: 22,
                        color: primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              Text(
                'Share this code with $name',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('✓ Code copied to clipboard!')),
              );
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _shareInvitationCode(code, name);
            },
            icon: const Icon(Icons.share, size: 18),
            label: const Text('Share'),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _shareInvitationCode(String code, String name) {
    final message = '''🎉 Join our team on Smart Billing!

Hi $name,

You've been invited to join our business team.

📱 Your Invitation Code: $code

Steps to join:
1. Download Smart Billing app
2. Tap "Join Team with Code"
3. Enter code: $code
4. Create your username
5. Wait for approval

Link: smartbilling://join?code=$code

See you on the team! 👋''';

    Share.share(message, subject: 'Join Smart Billing Team');
  }

  Future<void> _showChangeRoleDialog(AppUser user) async {
    final selectedRole = await showDialog<UserRole>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Change Role for ${user.name}'),
        children: [UserRole.manager, UserRole.salesStaff, UserRole.inventoryStaff].map((role) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(context, role),
            child: Row(
              children: [
                Icon(role.icon, color: role.color),
                const SizedBox(width: 12),
                Text(role.displayName),
                if (user.role == role) ...[
                  const Spacer(),
                  const Icon(Icons.check, color: successColor),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );

    if (selectedRole != null && selectedRole != user.role) {
      try {
        await _userService.updateUserRole(user.id, selectedRole);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Role updated to ${selectedRole.displayName}'), backgroundColor: successColor),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<void> _approveRequest(AppUser user) async {
    try {
      await _userService.approveJoinRequest(user.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user.name} approved!'), backgroundColor: successColor),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _rejectRequest(AppUser user) async {
    try {
      await _userService.rejectJoinRequest(user.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request rejected')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _cancelInvitation(AppUser user) async {
    try {
      await _userService.removeStaff(user.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invitation cancelled')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _shareInvitation(AppUser user) {
    if (user.invitationCode != null && user.invitationCode!.isNotEmpty) {
      _shareInvitationCode(user.invitationCode!, user.name);
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
              Text('Staff can login with just their username!'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Got it!')),
        ],
      ),
    );
  }
}
