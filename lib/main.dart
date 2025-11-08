import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:smartbilling/screens/add_quotation.dart';

// Screens
import 'config/theme.dart';
import 'screens/dashboard_screen.dart';
import 'screens/add_invoice_screen.dart';

import 'screens/profile_screen.dart';
import 'screens/notifications_screen.dart';
import 'login_screen.dart';
import 'company_details_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Initialize Firebase
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
  } else if (Platform.isIOS) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "YOUR_IOS_API_KEY",
        appId: "YOUR_IOS_APP_ID",
        messagingSenderId: "YOUR_SENDER_ID",
        projectId: "smartbillingsoftware",
        storageBucket: "smartbillingsoftware.firebasestorage.app",
        iosClientId: "YOUR_IOS_CLIENT_ID",
        iosBundleId: "com.example.smartbilling",
      ),
    );
  } else {
    await Firebase.initializeApp();
  }

  runApp(const SmartBillingApp());
}

class SmartBillingApp extends StatelessWidget {
  const SmartBillingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Billing System',
      debugShowCheckedModeBanner: false,
      theme: appTheme,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _loading = true;
  Widget? _startScreen;

  @override
  void initState() {
    super.initState();
    _checkUserFlow();
  }

  Future<void> _checkUserFlow() async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        _startScreen = const LoginScreen();
      } else {
        final companyDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('company')
            .doc('details')
            .get();

        if (companyDoc.exists && companyDoc.data()?['name'] != null) {
          _startScreen = const MainNavigation();
        } else {
          _startScreen = const CompanyDetailsScreen();
        }
      }
    } catch (e) {
      debugPrint("🔥 Auth flow error: $e");
      _startScreen = const LoginScreen();
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _startScreen!;
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    DashboardScreen(),
    SizedBox(), // Placeholder for the "New" button
    ProfileScreen(),
  ];

  final List<String> _titles = [
    'Smart Billing Dashboard',
    'Create Document',
    'My Profile',
  ];

  void _showCreateOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Wrap(
              runSpacing: 10,
              children: [
                Center(
                  child: Container(
                    width: 50,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.receipt_long, color: Colors.blue),
                  title: const Text("Create Invoice"),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AddInvoiceScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.request_quote_outlined,
                    color: Colors.green,
                  ),
                  title: const Text("Create Quotation"),
                  onTap: () {
                    Navigator.pop(context);
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
        centerTitle: true,
        backgroundColor: primary,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active_outlined),
            tooltip: "Notifications",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _selectedIndex == 1 ? const SizedBox() : _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        height: 65,
        backgroundColor: Colors.white,
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          if (index == 1) {
            _showCreateOptions(context);
          } else {
            setState(() => _selectedIndex = index);
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: 'New',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
