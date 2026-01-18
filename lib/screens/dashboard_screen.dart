import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:smartbilling/screens/add_invoice_screen.dart';
import 'package:smartbilling/screens/add_quotation.dart';
import 'package:smartbilling/screens/purchase.dart';
import 'package:smartbilling/screens/purchase_screen.dart';
import 'package:smartbilling/screens/supplier_screen.dart';
import 'package:smartbilling/screens/purchase_payment_receipt_screen.dart';
import 'ProfitReportScreen.dart';

import 'customers_screen.dart';
import 'invoices_screen.dart';
import 'notifications_screen.dart';
import 'payment_receipt_screen.dart';
import 'products_screen.dart';
import 'quotations_screen.dart';
import '../paytm.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // Dashboard stats
  double totalSales = 0;
  double totalGST = 0;
  double totalOutstanding = 0;
  double totalQuotations = 0;
  double totalPayments = 0;
  int totalInvoices = 0;
  int totalCustomers = 0;
  int totalProducts = 0;
  double totalPurchase = 0;
  int totalPurchaseCount = 0;
  StreamSubscription? _purchaseSub;
  int totalSuppliers = 0;
  double totalSupplierOutstanding = 0;
  StreamSubscription? _supplierSub;

  double maxRevenue = 1000;
  List<BarChartGroupData> revenueData = [];
  bool isLoading = true;
  String uid = ""; // Will be set to businessId for staff

  StreamSubscription? _invoiceSub;
  StreamSubscription? _quotationSub;
  StreamSubscription? _customerSub;
  StreamSubscription? _productSub;
  StreamSubscription? _paymentSub;

  // Theme Colors
  final Color _backgroundColor = const Color(0xFFF5F7FA);
  final Color _primaryColor = const Color(0xFF1976D2);
  final Color _cardColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _initializeUid();
  }

  Future<void> _initializeUid() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() => isLoading = false);
      return;
    }

    try {
      // Get user document to check if staff
      final userDoc = await _firestore.collection("users").doc(user.uid).get();

      if (userDoc.exists) {
        final data = userDoc.data()!;
        final businessId = data['businessId'];

        // If staff, use businessId (owner's uid), otherwise use own uid
        if (businessId != null && businessId != user.uid) {
          uid = businessId;
        } else {
          uid = user.uid;
        }
      } else {
        uid = user.uid;
      }

      if (uid.isNotEmpty) {
        _attachRealtimeListeners();
      }
    } catch (e) {
      debugPrint("Error initializing UID: $e");
      uid = user.uid;
      if (uid.isNotEmpty) {
        _attachRealtimeListeners();
      }
    }
  }

  // --------------------------- PLAN CHECK ---------------------------
  Future<bool> checkPlanActive() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return true; // Allow if not logged in (shouldn't happen)

    try {
      final doc = await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .get();

      if (!doc.exists) return true; // Allow if doc doesn't exist

      final data = doc.data()!;

      // Check if user is staff (has businessId different from uid)
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
        } else {
          return true; // Owner not found, allow access
        }
      }

      final expiry = planData["expiry"] != null
          ? (planData["expiry"] as Timestamp).toDate()
          : null;

      // If no expiry, allow access (for backward compatibility)
      if (expiry == null) return true;

      return expiry.isAfter(DateTime.now());
    } catch (e) {
      debugPrint("Error checking plan: $e");
      return true; // Allow access on error
    }
  }

  void blockedMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Your plan has expired. Please contact admin."),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // --------------------------- REAL TIME LISTENERS ---------------------------
  void _attachRealtimeListeners() {
    _invoiceSub?.cancel();
    _quotationSub?.cancel();
    _customerSub?.cancel();
    _productSub?.cancel();
    _paymentSub?.cancel();
    _purchaseSub?.cancel();

    _supplierSub = _firestore
        .collection("users")
        .doc(uid)
        .collection("suppliers")
        .snapshots()
        .listen((snap) {
          totalSuppliers = snap.docs.length;

          double total = 0;
          for (var doc in snap.docs) {
            total += (doc['outstandingBalance'] ?? 0).toDouble();
          }

          totalSupplierOutstanding = total;
          setState(() {});
        });

    _purchaseSub = _firestore
        .collection("users")
        .doc(uid)
        .collection("purchases")
        .snapshots()
        .listen((snap) {
          double total = 0;

          for (var doc in snap.docs) {
            final data = doc.data();
            // Robust check for total amount field
            final amount = (data['grand_total'] as num?)?.toDouble() ??
                (data['grandtotal'] as num?)?.toDouble() ??
                (data['grand_Total'] as num?)?.toDouble() ??
                (data['totalAmount'] as num?)?.toDouble() ??
                0.0;
            total += amount;
          }

          totalPurchase = total;
          totalPurchaseCount = snap.docs.length;
          if (mounted) setState(() {});
        });

    _invoiceSub = _firestore
        .collection("users")
        .doc(uid)
        .collection("invoices")
        .snapshots()
        .listen(_updateDashboard);

    _quotationSub = _firestore
        .collection("users")
        .doc(uid)
        .collection("quotations")
        .snapshots()
        .listen((snap) {
          totalQuotations = snap.docs.length.toDouble();
          setState(() {});
        });

    _customerSub = _firestore
        .collection("users")
        .doc(uid)
        .collection("customers")
        .snapshots()
        .listen((snap) {
          double outstanding = 0;
          for (var doc in snap.docs) {
            outstanding += (doc['outstanding'] ?? 0).toDouble();
          }
          totalOutstanding = outstanding;
          totalCustomers = snap.docs.length;
          setState(() {});
        });

    _productSub = _firestore
        .collection("users")
        .doc(uid)
        .collection("products")
        .snapshots()
        .listen((snap) {
          totalProducts = snap.docs.length;
          setState(() {});
        });

    _paymentSub = _firestore
        .collection("users")
        .doc(uid)
        .collection("payments")
        .snapshots()
        .listen((snap) {
          double total = 0;
          for (var doc in snap.docs) {
            total += (doc['amount'] ?? 0).toDouble();
          }
          totalPayments = total;
          setState(() {});
        });
  }

  // --------------------------- UPDATE STATS ---------------------------
  void _updateDashboard(QuerySnapshot<Map<String, dynamic>> snapshot) {
    double sales = 0, gst = 0;
    int invoicesCount = 0;

    Map<int, double> revenueMap = {for (var i = 1; i <= 7; i++) i: 0};

    DateTime now = DateTime.now();
    DateTime start = now.subtract(Duration(days: now.weekday - 1));
    DateTime end = start.add(const Duration(days: 7));

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final total = (data['grand_total'] ?? 0).toDouble();
      final gstAmt = (data['gst_amount'] ?? 0).toDouble();

      // Check created_at first, then invoice_date
      DateTime? createdAt = (data['created_at'] as Timestamp?)?.toDate();
      if (createdAt == null && data['invoice_date'] != null) {
         // Try parsing invoice_date if it's a string or timestamp
         if (data['invoice_date'] is Timestamp) {
           createdAt = (data['invoice_date'] as Timestamp).toDate();
         } else if (data['invoice_date'] is String) {
           try {
             createdAt = DateFormat('dd-MM-yyyy').parse(data['invoice_date']);
           } catch (e) {
             // Ignore parse error
           }
         }
      }

      sales += total;
      gst += gstAmt;
      invoicesCount++;

      if (createdAt != null &&
          createdAt.isAfter(start) &&
          createdAt.isBefore(end)) {
        int w = createdAt.weekday;
        revenueMap[w] = (revenueMap[w] ?? 0) + total;
      }
    }

    maxRevenue =
        (revenueMap.values.isEmpty
            ? 0
            : revenueMap.values.reduce((a, b) => a > b ? a : b)) *
        1.3;

    revenueData = revenueMap.entries.map((e) {
      return BarChartGroupData(
        x: e.key,
        barRods: [
          BarChartRodData(
            toY: e.value,
            color: _primaryColor,
            width: 16,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: maxRevenue,
              color: Colors.grey.withOpacity(0.1),
            ),
          ),
        ],
      );
    }).toList();

    totalSales = sales;
    totalGST = gst;
    totalInvoices = invoicesCount;

    setState(() => isLoading = false);
  }

  @override
  void dispose() {
    _invoiceSub?.cancel();
    _quotationSub?.cancel();
    _customerSub?.cancel();
    _productSub?.cancel();
    _paymentSub?.cancel();
    _supplierSub?.cancel();

    super.dispose();
  }

  Widget _buildFAB(BuildContext context) {
    return FloatingActionButton.extended(
      backgroundColor: _primaryColor,
      elevation: 4,
      icon: const Icon(Icons.add, color: Colors.white),
      label: const Text(
        "Create New",
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      onPressed: () async {
        bool ok = await checkPlanActive();
        if (!ok) return blockedMessage();

        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Quick Actions",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _actionTile(
                      icon: Icons.receipt_long,
                      color: Colors.blue,
                      title: "Create Invoice",
                      subtitle: "Generate a new tax invoice",
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
                    _actionTile(
                      icon: Icons.request_quote,
                      color: Colors.green,
                      title: "Create Quotation",
                      subtitle: "Send an estimate to customer",
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
                    _actionTile(
                      icon: Icons.shopping_cart,
                      color: Colors.orange,
                      title: "Record Purchase",
                      subtitle: "Add a purchase entry",
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PurchaseInvoiceScreen(),
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
      },
    );
  }

  Widget _actionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }

  // --------------------------- UI ---------------------------
  @override
  Widget build(BuildContext context) {
    final format = NumberFormat.compactCurrency(symbol: "₹");

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.store_rounded, color: _primaryColor, size: 24),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Smart Billing",
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  "Dashboard",
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black87),
            onPressed: () {
              _attachRealtimeListeners();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Refreshing data...")),
              );
            },
          ),
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.notifications_outlined, color: Colors.black87, size: 28),
                Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
            onPressed: () async {
              bool ok = await checkPlanActive();
              if (!ok) return blockedMessage();

              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
            },
          ),
          const SizedBox(width: 12),
        ],
      ),
      floatingActionButton: _buildFAB(context),
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: _primaryColor))
          : RefreshIndicator(
              onRefresh: () async => _attachRealtimeListeners(),
              color: _primaryColor,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Summary Section
                    const Text(
                      "Overview",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Main Stats Cards
                    Row(
                      children: [
                        Expanded(
                          child: _summaryCard(
                            "Total Sales",
                            format.format(totalSales),
                            Icons.trending_up,
                            Colors.green,
                            isPrimary: true,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _summaryCard(
                            "Outstanding",
                            format.format(totalOutstanding),
                            Icons.warning_amber_rounded,
                            Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Quick Stats Grid
                    const Text(
                      "Quick Stats",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),

                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.5,
                      children: [
                        _statCard(
                          "Invoices",
                          totalInvoices.toString(),
                          Icons.receipt_long,
                          Colors.blue,
                          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InvoicesScreen())),
                        ),
                        _statCard(
                          "Quotations",
                          totalQuotations.toStringAsFixed(0),
                          Icons.description_outlined,
                          Colors.indigo,
                          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QuotationsScreen())),
                        ),
                        _statCard(
                          "Customers",
                          totalCustomers.toString(),
                          Icons.people_outline,
                          Colors.teal,
                          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomersScreen())),
                        ),
                        _statCard(
                          "Products",
                          totalProducts.toString(),
                          Icons.inventory_2_outlined,
                          Colors.purple,
                          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductsScreen())),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Weekly Revenue Chart
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _cardColor,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Revenue Analytics",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  Text(
                                    "Last 7 Days",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _primaryColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.bar_chart, color: _primaryColor),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 200,
                            child: BarChart(
                              BarChartData(
                                maxY: maxRevenue,
                                barGroups: revenueData,
                                borderData: FlBorderData(show: false),
                                gridData: const FlGridData(show: false),
                                titlesData: FlTitlesData(
                                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      getTitlesWidget: (value, meta) {
                                        const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                                        if (value.toInt() > 0 && value.toInt() <= 7) {
                                          return Padding(
                                            padding: const EdgeInsets.only(top: 8),
                                            child: Text(
                                              days[value.toInt() - 1],
                                              style: TextStyle(
                                                color: Colors.grey.shade600,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          );
                                        }
                                        return const SizedBox();
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // More Stats
                    const Text(
                      "Other Activities",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),

                    _listStatTile(
                      "Purchases",
                      format.format(totalPurchase),
                      Icons.shopping_bag_outlined,
                      Colors.deepOrange,
                      () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseScreenList())),
                    ),
                    _listStatTile(
                      "Suppliers",
                      "$totalSuppliers (Due: ${format.format(totalSupplierOutstanding)})",
                      Icons.local_shipping_outlined,
                      Colors.brown,
                      () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupplierScreen())),
                    ),
                    _listStatTile(
                      "Payment Receipts",
                      format.format(totalPayments),
                      Icons.receipt,
                      Colors.cyan,
                      () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentReceiptScreen())),
                    ),
                    _listStatTile(
                      "Purchase Payments",
                      "View Receipts",
                      Icons.receipt_long,
                      Colors.deepPurple,
                      () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchasePaymentReceiptScreen())),
                    ),
                    _listStatTile(
                      "Profit & Analytics",
                      "View Reports",
                      Icons.analytics_outlined,
                      Colors.purple,
                      () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfitReportScreen())),
                    ),

                    const SizedBox(height: 80), // Space for FAB
                  ],
                ),
              ),
            ),
    );
  }

  Widget _summaryCard(String title, String value, IconData icon, Color color, {bool isPrimary = false}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isPrimary ? _primaryColor : _cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (isPrimary ? _primaryColor : Colors.black).withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isPrimary ? Colors.white.withOpacity(0.2) : color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: isPrimary ? Colors.white : color, size: 20),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isPrimary ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: isPrimary ? Colors.white.withOpacity(0.8) : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: () async {
        bool allowed = await checkPlanActive();
        if (!allowed) {
          blockedMessage();
          return;
        }
        onTap();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 24),
                Icon(Icons.arrow_forward, color: Colors.grey.shade300, size: 16),
              ],
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listStatTile(String title, String value, IconData icon, Color color, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: ListTile(
        onTap: () async {
          bool allowed = await checkPlanActive();
          if (!allowed) {
            blockedMessage();
            return;
          }
          onTap();
        },
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
