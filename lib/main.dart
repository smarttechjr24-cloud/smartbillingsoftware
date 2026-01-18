import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:smartbilling/contactsupport.dart';
import 'package:smartbilling/screens/more_options.dart';

// Screens
import 'config/theme.dart';
import 'screens/dashboard_screen.dart';
import 'screens/add_invoice_screen.dart';
import 'screens/add_quotation.dart';
import 'screens/profile_screen.dart';
import 'screens/notifications_screen.dart';
import 'login_screen.dart';
import 'screens/waiting_for_approval_screen.dart';
import 'screens/accept_invitation_screen.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/user_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  if (Platform.isAndroid) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyBsQywBagsKjKfneaVjcjdziNRCxsxNHrk",
        appId: "1:435804658565:android:00c9478e53a6085525c2ec",
        messagingSenderId: "435804658565",
        projectId: "smartbillingsoftware",
        storageBucket: "smartbillingsoftware.firebasestorage.app",
      ),
    );
  } else {
    await Firebase.initializeApp();
  }

  runApp(const SmartBillingApp());
}

class SmartBillingApp extends StatefulWidget {
  const SmartBillingApp({super.key});

  @override
  State<SmartBillingApp> createState() => _SmartBillingAppState();
}

class _SmartBillingAppState extends State<SmartBillingApp> {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  late AppLinks _appLinks;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  void _initDeepLinks() async {
    _appLinks = AppLinks();

    // Handle initial link
    try {
      final uri = await _appLinks.getInitialLink();
      if (uri != null) {
        _processDeepLink(uri);
      }
    } catch (e) {
      // Handle error
    }

    // Handle incoming links
    _appLinks.uriLinkStream.listen((uri) {
      _processDeepLink(uri);
    });
  }

  void _processDeepLink(Uri uri) {
    if (uri.scheme == 'smartbilling' && uri.host == 'join') {
      final code = uri.queryParameters['code'];
      if (code != null && code.isNotEmpty) {
        // Navigate to AcceptInvitationScreen with code
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => AcceptInvitationScreen(invitationCode: code),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: "Smart Billing",
      theme: appTheme,
      home: const AuthGate(),
    );
  }
}

// ====================== AUTH GATE =============================
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool loading = true;
  Widget? screen;

  @override
  void initState() {
    super.initState();
    checkUser();
  }

  Future<void> checkUser() async {
    try {
      // 1. Check for Staff Session (Username Login)
      final prefs = await SharedPreferences.getInstance();
      final staffId = prefs.getString('current_staff_id');

      if (staffId != null) {
        // Staff is logged in
        screen = MainNavigation();
        setState(() => loading = false);
        return;
      }

      // 2. Check for Owner Session (Firebase Auth)
      final user = FirebaseAuth.instance.currentUser;

      // Not logged in
      if (user == null) {
        screen = const LoginScreen();
        setState(() => loading = false);
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .get();

      if (!doc.exists) {
        await FirebaseAuth.instance.signOut();
        screen = const LoginScreen();
        setState(() => loading = false);
        return;
      }

      final data = doc.data()!;

      // Check for pending approval status
      final status = data['status'];
      if (status == 'pending_approval') {
        screen = const WaitingForApprovalScreen();
        setState(() => loading = false);
        return;
      }

      // Check if user is staff (has businessId different from uid)
      String? businessId = data['businessId'];
      bool isStaff = businessId != null && businessId != user.uid;
      Map<String, dynamic> planData = data;

      // If staff, fetch owner's data for plan check
      if (isStaff) {
        final ownerDoc = await FirebaseFirestore.instance
            .collection("users")
            .doc(businessId)
            .get();

        if (ownerDoc.exists) {
          planData = ownerDoc.data()!;
        } else {
          // Owner not found, allow access anyway
          screen = const MainNavigation();
          setState(() => loading = false);
          return;
        }
      }

      final plan = planData["plan"];
      final expiry = planData["expiry"] != null
          ? (planData["expiry"] as Timestamp).toDate()
          : null;

      // For staff: if owner has no plan/expiry, allow access
      // For owner: if no plan/expiry, redirect to login
      if (plan == null || expiry == null) {
        if (isStaff) {
          // Staff can access if owner hasn't set up plan yet
          screen = const MainNavigation();
          setState(() => loading = false);
          return;
        } else {
          // Owner needs to have plan - but allow access for now
          screen = const MainNavigation();
          setState(() => loading = false);
          return;
        }
      }

      // Expired
      if (expiry.isBefore(DateTime.now())) {
        await FirebaseAuth.instance.signOut();
        screen = const ExpiredScreen();
        setState(() => loading = false);
        return;
      }

      // Valid user → allow in
      screen = const MainNavigation();
      setState(() => loading = false);
    } catch (e) {
      screen = const LoginScreen();
      setState(() => loading = false);
      debugPrint("AUTH ERROR: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return screen!;
  }
}

// ==================== EXPIRED SCREEN ==========================
class ExpiredScreen extends StatelessWidget {
  const ExpiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(25),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_clock, size: 80, color: Colors.red),
              const SizedBox(height: 20),
              const Text(
                "Your plan has expired.\nPlease contact admin.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 15),
              ElevatedButton(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
                child: const Text("OK"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== MAIN NAVIGATION =========================
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    DashboardScreen(),
    SizedBox(), // Placeholder for Create (Index 1)
    ProfileScreen(), // Profile (Index 2)
    MoreScreen(), // More (Index 3)
  ];

  final List<String> _titles = [
    "Smart Billing Dashboard",
    "Create Document",
    "My Profile",
    "More Options",
  ];

  // 🔥 BLOCK navigation if expired - checks owner's plan for staff
  Future<bool> _checkActive(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final doc = await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .get();

      final data = doc.data() ?? {};

      // Check if user is staff (has businessId different from their uid)
      String? businessId = data['businessId'];
      Map<String, dynamic> planData = data;

      // If staff, fetch owner's data for plan check
      if (businessId != null && businessId != user.uid) {
        final ownerDoc = await FirebaseFirestore.instance
            .collection("users")
            .doc(businessId)
            .get();

        if (ownerDoc.exists) {
          planData = ownerDoc.data()!;
        }
      }

      final expiry = planData["expiry"] != null
          ? (planData["expiry"] as Timestamp).toDate()
          : null;

      // If no expiry found, allow access (for backward compatibility)
      if (expiry == null) {
        return true;
      }

      if (expiry.isBefore(DateTime.now())) {
        // SHOW popup
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
    } catch (e) {
      debugPrint("Error checking plan: $e");
      return true; // Allow access on error to not block users
    }
  }

  void _showCreateOptions(BuildContext context) async {
    if (!await _checkActive(context)) return; // BLOCK HERE

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.receipt_long, color: Colors.blue),
                  title: const Text("Create Invoice"),
                  onTap: () async {
                    if (!await _checkActive(context)) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AddInvoiceScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.request_quote, color: Colors.green),
                  title: const Text("Create Quotation"),
                  onTap: () async {
                    if (!await _checkActive(context)) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AddQuotationScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        automaticallyImplyLeading: false,
        backgroundColor: primary,
        centerTitle: true,
        actions: [
          // 🔔 Notifications
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () async {
              if (!await _checkActive(context)) return;
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
            },
          ),

          // 🎧 Contact Support
          IconButton(
            icon: const Icon(Icons.support_agent),
            tooltip: "Contact Support",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ContactSupportScreen()),
              );
            },
          ),
        ],
      ),

      body: _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) async {

          if (index == 1) {
            _showCreateOptions(context);
            return;
          }
          // Index 0 (Home), 2 (Profile), 3 (More) -> Switch Tab
          if (!await _checkActive(context)) return;
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: "Home"),
          NavigationDestination(icon: Icon(Icons.add_circle_outline), label: "Create"),
          NavigationDestination(icon: Icon(Icons.person), label: "Profile"),
          NavigationDestination(icon: Icon(Icons.menu), label: "More"),
        ],
      ),
    );
  }
}
