import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:smartbilling/screens/customers_screen.dart';
import 'package:smartbilling/screens/invoices_screen.dart';
import 'package:smartbilling/screens/notifications_screen.dart';
import 'package:smartbilling/screens/payment_receipt_screen.dart';
import 'package:smartbilling/screens/products_screen.dart';
import 'package:smartbilling/screens/quotations_screen.dart';
import 'package:smartbilling/paytm.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  double totalSales = 0;
  double totalGST = 0;
  double totalOutstanding = 0;
  double totalQuotations = 0;
  double totalPayments = 0;
  int totalInvoices = 0;
  int totalCustomers = 0;
  int totalProducts = 0;

  double maxRevenue = 1000;
  List<BarChartGroupData> revenueData = [];

  bool isLoading = true;
  late final String uid;

  StreamSubscription? _invoiceSub;
  StreamSubscription? _quotationSub;
  StreamSubscription? _customerSub;
  StreamSubscription? _productSub;
  StreamSubscription? _paymentSub;

  @override
  void initState() {
    super.initState();
    uid = _auth.currentUser?.uid ?? '';
    if (uid.isNotEmpty) _attachRealtimeListeners();
  }

  /// 🔹 Attach real-time Firestore listeners
  void _attachRealtimeListeners() {
    _invoiceSub?.cancel();
    _quotationSub?.cancel();
    _customerSub?.cancel();
    _productSub?.cancel();
    _paymentSub?.cancel();

    // 🧾 Invoices
    _invoiceSub = _firestore
        .collection('users')
        .doc(uid)
        .collection('invoices')
        .snapshots()
        .listen(_updateDashboard);

    // 📄 Quotations
    _quotationSub = _firestore
        .collection('users')
        .doc(uid)
        .collection('quotations')
        .snapshots()
        .listen((snap) {
          setState(() => totalQuotations = snap.docs.length.toDouble());
        });

    // 👥 Customers
    _customerSub = _firestore
        .collection('users')
        .doc(uid)
        .collection('customers')
        .snapshots()
        .listen((snap) {
          double outstanding = 0;
          for (var doc in snap.docs) {
            outstanding += (doc['outstanding'] ?? 0).toDouble();
          }
          setState(() {
            totalOutstanding = outstanding;
            totalCustomers = snap.docs.length;
          });
        });

    // 📦 Products
    _productSub = _firestore
        .collection('users')
        .doc(uid)
        .collection('products')
        .snapshots()
        .listen((snap) {
          setState(() => totalProducts = snap.docs.length);
        });

    // 💳 Payments
    _paymentSub = _firestore
        .collection('users')
        .doc(uid)
        .collection('payments')
        .snapshots()
        .listen((snap) {
          double total = 0;
          for (var doc in snap.docs) {
            total += (doc['amount'] ?? 0).toDouble();
          }
          setState(() => totalPayments = total);
        });
  }

  /// 🔹 Compute weekly revenue & other stats
  void _updateDashboard(QuerySnapshot<Map<String, dynamic>> snapshot) {
    double sales = 0, gst = 0;
    int invoicesCount = 0;
    Map<int, double> revenueMap = {for (var i = 1; i <= 7; i++) i: 0.0};

    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 7));

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final total = (data['grand_total'] ?? 0).toDouble();
      final gstAmt = (data['gst_amount'] ?? 0).toDouble();
      final createdAt = (data['created_at'] as Timestamp?)?.toDate();

      sales += total;
      gst += gstAmt;
      invoicesCount++;

      if (createdAt != null &&
          createdAt.isAfter(startOfWeek) &&
          createdAt.isBefore(endOfWeek)) {
        final weekday = createdAt.weekday; // 1=Mon ... 7=Sun
        revenueMap[weekday] = (revenueMap[weekday] ?? 0) + total;
      }
    }

    setState(() {
      totalSales = sales;
      totalGST = gst;
      totalInvoices = invoicesCount;
      maxRevenue =
          (revenueMap.values.isEmpty
              ? 1000
              : revenueMap.values.reduce((a, b) => a > b ? a : b)) *
          1.3;
      revenueData = revenueMap.entries
          .map(
            (e) => BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  toY: e.value,
                  color: Colors.blueAccent,
                  width: 14,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          )
          .toList();
      isLoading = false;
    });
  }

  @override
  void dispose() {
    _invoiceSub?.cancel();
    _quotationSub?.cancel();
    _customerSub?.cancel();
    _productSub?.cancel();
    _paymentSub?.cancel();
    super.dispose();
  }

  /// 🔹 Stat Card Builder
  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: color.withOpacity(0.15),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 🔹 UI Build
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final format = NumberFormat.compactCurrency(symbol: "₹");

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Row(
          children: [
            Icon(Icons.store_rounded, color: primary, size: 28),
            const SizedBox(width: 8),
            Text(
              "Smart Billing Dashboard",
              style: TextStyle(
                color: primary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.notifications_active_outlined,
              color: Colors.black87,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
            },
          ),
        ],
      ),

      // 🔹 Main Body
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async => _attachRealtimeListeners(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Welcome Back 👋",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Your business performance this week",
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 🔹 Overview Cards
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            title: "Total Sales",
                            value: format.format(totalSales),
                            icon: Icons.trending_up_rounded,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildStatCard(
                            title: "Invoices",
                            value: totalInvoices.toString(),
                            icon: Icons.receipt_long_rounded,
                            color: Colors.blueAccent,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const InvoicesScreen(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            title: "Outstanding",
                            value: format.format(totalOutstanding),
                            icon: Icons.payments_rounded,
                            color: Colors.orangeAccent,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PaymentScreen(),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildStatCard(
                            title: "Quotations",
                            value: totalQuotations.toStringAsFixed(0),
                            icon: Icons.request_quote_outlined,
                            color: Colors.indigo,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const QuotationsScreen(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            title: "Customers",
                            value: totalCustomers.toString(),
                            icon: Icons.people_alt_outlined,
                            color: Colors.teal,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const CustomersScreen(),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildStatCard(
                            title: "Products",
                            value: totalProducts.toString(),
                            icon: Icons.inventory_2_rounded,
                            color: Colors.purple,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ProductsScreen(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    _buildStatCard(
                      title: "Payment Receipts",
                      value: format.format(totalPayments),
                      icon: Icons.account_balance_wallet_rounded,
                      color: Colors.cyan,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PaymentReceiptScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    _buildStatCard(
                      title: "Total GST",
                      value: format.format(totalGST),
                      icon: Icons.account_balance_rounded,
                      color: Colors.pinkAccent,
                    ),

                    const SizedBox(height: 24),

                    // 📊 Weekly Chart
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Weekly Revenue Trend",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Week of ${DateFormat('MMM d').format(DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1)))}",
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 220,
                            child: BarChart(
                              BarChartData(
                                maxY: maxRevenue,
                                barGroups: revenueData,
                                borderData: FlBorderData(show: false),

                                gridData: FlGridData(
                                  show: true,
                                  drawVerticalLine: false,
                                  horizontalInterval: (maxRevenue / 5).clamp(
                                    100,
                                    double.infinity,
                                  ),
                                ),

                                titlesData: FlTitlesData(
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      getTitlesWidget: (value, _) {
                                        const days = [
                                          'Mon',
                                          'Tue',
                                          'Wed',
                                          'Thu',
                                          'Fri',
                                          'Sat',
                                          'Sun',
                                        ];
                                        if (value < 1 || value > 7) {
                                          return const SizedBox.shrink();
                                        }
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8,
                                          ),
                                          child: Text(
                                            days[value.toInt() - 1],
                                            style: const TextStyle(
                                              fontSize: 10,
                                            ),
                                          ),
                                        );
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
                    Center(
                      child: Text(
                        "Powered by SmartBilling AI",
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
