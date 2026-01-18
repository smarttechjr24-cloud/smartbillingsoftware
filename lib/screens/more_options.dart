import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Screens
import 'package:smartbilling/main.dart';
import 'package:smartbilling/screens/invoice_settings.dart';
import 'dashboard_screen.dart';
import 'profile_screen.dart';
import '../login_screen.dart';
import '../contactsupport.dart';
import 'reports_screen.dart';
import 'account_settings_screen.dart';
import 'reminder_settings_screen.dart';
import 'manage_users_screen.dart';
import 'activity_log_screen.dart';
import '../services/user_service.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  String businessName = "Business Name";
  bool _isOwner = false;

  @override
  void initState() {
    super.initState();
    loadUserData();
  }

  // ---------------- LOAD USER DATA ----------------
  Future<void> loadUserData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Initialize user as owner if not already set
    final userService = UserService();
    await userService.initializeAsOwner();

    final doc = await FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .get();
    if (!doc.exists) return;

    final data = doc.data()!;
    setState(() {
      businessName = data["businessName"] ?? "Business Name";
      _isOwner = data["role"] == "owner" || !data.containsKey("role");
    });
  }

  // ---------------- CHECK PLAN ACTIVE ----------------
  Future<bool> _checkActive(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final doc = await FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .get();

    final data = doc.data() ?? {};
    final expiry = data["expiry"] != null
        ? (data["expiry"] as Timestamp).toDate()
        : null;

    if (expiry == null || expiry.isBefore(DateTime.now())) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Plan Expired"),
          content: const Text("Please contact admin."),
          actions: [
            TextButton(
              onPressed: () {
                FirebaseAuth.instance.signOut();
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
              child: const Text("OK"),
            ),
          ],
        ),
      );
      return false;
    }
    return true;
  }

  // ---------------- TILE UI COMPONENT ----------------
  Widget _tile({
    required IconData icon,
    required String title,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF1976D2)),
      title: Text(title, style: const TextStyle(fontSize: 16)),
      trailing: trailing ?? const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  // =====================================================
  //                     MAIN UI
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      color: const Color(0xFFF5F7FA),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---------------- TOP BUSINESS BANNER ----------------
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: primary.withOpacity(0.1)),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: primary,
                      child: Text(
                        businessName.isNotEmpty ? businessName[0] : "B",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 15),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          businessName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: Colors.grey.shade400),
                          ),
                          child: const Text(
                            "BUSINESS & GST SETTINGS",
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 15),

              // ---------------- HELP & INVITE ----------------
              _tile(
                icon: Icons.bar_chart,
                title: "Reports",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ReportsScreen(),
                    ),
                  );
                },
              ),
              _tile(icon: Icons.card_giftcard, title: "Invite & Earn"),

              const SizedBox(height: 10),

              // ---------------- SETTINGS HEADER ----------------
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 15),
                child: Text(
                  "Settings",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),

              // ---------------- SETTINGS ITEMS ----------------
              _tile(
                icon: Icons.receipt_long,
                title: "Invoice Settings",
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    "NEW",
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const InvoiceSettingsScreen(),
                    ),
                  );
                },
              ),

              _tile(
                icon: Icons.settings,
                title: "Account Settings",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AccountSettingsScreen(),
                    ),
                  );
                },
              ),
              _tile(
                icon: Icons.notifications_active,
                title: "Reminder Settings",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ReminderSettingsScreen(),
                    ),
                  );
                },
              ),
              if (_isOwner)
                _tile(
                  icon: Icons.group,
                  title: "Manage Users",
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ManageUsersScreen(),
                      ),
                    );
                  },
                ),
              if (_isOwner)
                _tile(
                  icon: Icons.history,
                  title: "Activity Log",
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ActivityLogScreen(),
                      ),
                    );
                  },
                ),
              _tile(
                icon: Icons.delete_sweep,
                title: "Recover Deleted Invoices",
              ),

              const SizedBox(height: 10),

              // ---------------- OTHERS ----------------
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 15),
                child: Text(
                  "Others",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              _tile(icon: Icons.search, title: "GST Rate Finder"),
            ],
          ),
        ),
      ),
    );
  }
}
