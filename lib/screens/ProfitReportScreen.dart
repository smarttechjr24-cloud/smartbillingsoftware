import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shimmer/shimmer.dart';

class ProfitReportScreen extends StatefulWidget {
  const ProfitReportScreen({super.key});

  @override
  State<ProfitReportScreen> createState() => _ProfitReportScreenState();
}

class _ProfitReportScreenState extends State<ProfitReportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Data State
  bool _isLoading = true;
  List<Map<String, dynamic>> _salesData = [];
  List<Map<String, dynamic>> _purchaseData = [];

  // Calculated Metrics
  double _dailySales = 0;
  double _dailyPurchase = 0;
  double _weeklySales = 0;
  double _weeklyPurchase = 0;
  double _monthlySales = 0;
  double _monthlyPurchase = 0;

  Map<DateTime, double> _dailyProfitLast7Days = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 🔥 DATA FETCHING & LOGIC
  // ---------------------------------------------------------------------------

  Future<void> _fetchData() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isLoading = true);

    try {
      // 1. Fetch Sales (Invoices)
      // FIX: Changed collection from 'sales' to 'invoices'
      final salesSnapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('invoices')
          .orderBy('created_at', descending: true)
          .get();

      _salesData = salesSnapshot.docs.map((doc) {
        final data = doc.data();
        // FIX: Handle different date fields (invoice_date or created_at)
        final date = _parseDate(data['invoice_date'] ?? data['created_at']);
        return {
          'date': date,
          'amount': (data['grand_total'] as num?)?.toDouble() ?? 0.0,
          'type': 'Sale',
          'invoice_no': data['invoice_number'] ?? 'INV-???',
        };
      }).toList();

      // 2. Fetch Purchases
      final purchaseSnapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('purchases')
          .orderBy('invoiceDate', descending: true)
          .get();

      _purchaseData = purchaseSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'date': _parseDate(data['invoiceDate']),
          'amount': (data['grand_total'] as num?)?.toDouble() ?? 0.0,
          'type': 'Purchase',
          'invoice_no': data['invoiceNumber'] ?? 'PUR-???',
        };
      }).toList();

      _calculateMetrics();
    } catch (e) {
      debugPrint('Error fetching report data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  DateTime _parseDate(dynamic date) {
    if (date == null) return DateTime.now();
    if (date is Timestamp) return date.toDate();
    if (date is String) return DateTime.tryParse(date) ?? DateTime.now();
    return DateTime.now();
  }

  void _calculateMetrics() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startOfWeek = today.subtract(const Duration(days: 7));
    final startOfMonth = DateTime(now.year, now.month, 1);

    // Reset
    _dailySales = 0;
    _dailyPurchase = 0;
    _weeklySales = 0;
    _weeklyPurchase = 0;
    _monthlySales = 0;
    _monthlyPurchase = 0;
    _dailyProfitLast7Days = {};

    // 1. Calculate Aggregates
    for (var sale in _salesData) {
      final date = sale['date'] as DateTime;
      final amount = sale['amount'] as double;
      final dateOnly = DateTime(date.year, date.month, date.day);

      if (dateOnly.isAtSameMomentAs(today)) _dailySales += amount;
      if (date.isAfter(startOfWeek)) _weeklySales += amount;
      if (date.isAfter(startOfMonth)) _monthlySales += amount;

      // For Charts: Group by Day
      if (date.isAfter(startOfWeek)) {
        _dailyProfitLast7Days[dateOnly] =
            (_dailyProfitLast7Days[dateOnly] ?? 0) + amount;
      }
    }

    for (var purchase in _purchaseData) {
      final date = purchase['date'] as DateTime;
      final amount = purchase['amount'] as double;
      final dateOnly = DateTime(date.year, date.month, date.day);

      if (dateOnly.isAtSameMomentAs(today)) _dailyPurchase += amount;
      if (date.isAfter(startOfWeek)) _weeklyPurchase += amount;
      if (date.isAfter(startOfMonth)) _monthlyPurchase += amount;

      // For Charts: Subtract Purchase from Sales
      if (date.isAfter(startOfWeek)) {
        _dailyProfitLast7Days[dateOnly] =
            (_dailyProfitLast7Days[dateOnly] ?? 0) - amount;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 🔥 PDF GENERATION
  // ---------------------------------------------------------------------------

  Future<void> _generateAndDownloadPdf() async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final period = ['Daily', 'Weekly', 'Monthly'][_tabController.index];
    
    // Get current view data
    double sales = 0, purchase = 0;
    if (period == 'Daily') {
      sales = _dailySales;
      purchase = _dailyPurchase;
    } else if (period == 'Weekly') {
      sales = _weeklySales;
      purchase = _weeklyPurchase;
    } else {
      sales = _monthlySales;
      purchase = _monthlyPurchase;
    }
    
    final profit = sales - purchase;
    final transactions = _getFilteredTransactions(period);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Profit & Loss Report',
                      style: pw.TextStyle(
                          fontSize: 24, fontWeight: pw.FontWeight.bold)),
                  pw.Text(DateFormat('dd MMM yyyy').format(now)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text('Period: $period', style: const pw.TextStyle(fontSize: 18)),
            pw.SizedBox(height: 20),
            
            // Summary Table
            pw.Table.fromTextArray(
              headers: ['Total Sales', 'Total Purchase', 'Net Profit'],
              data: [
                [
                  '${sales.toStringAsFixed(2)}',
                  '${purchase.toStringAsFixed(2)}',
                  '${profit.toStringAsFixed(2)}'
                ]
              ],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignments: {
                0: pw.Alignment.centerRight,
                1: pw.Alignment.centerRight,
                2: pw.Alignment.centerRight,
              },
            ),
            pw.SizedBox(height: 30),
            
            // Transactions List
            pw.Text('Detailed Transactions',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Table.fromTextArray(
              headers: ['Date', 'Invoice No', 'Type', 'Amount'],
              data: transactions.map((t) {
                final isSale = t['type'] == 'Sale';
                return [
                  DateFormat('dd MMM yyyy').format(t['date']),
                  t['invoice_no'],
                  t['type'],
                  '${isSale ? '+' : '-'} ${t['amount'].toStringAsFixed(2)}',
                ];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerLeft,
                3: pw.Alignment.centerRight,
              },
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Profit_Report_${DateFormat('yyyyMMdd').format(now)}.pdf',
    );
  }

  List<Map<String, dynamic>> _getFilteredTransactions(String period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startOfWeek = today.subtract(const Duration(days: 7));
    final startOfMonth = DateTime(now.year, now.month, 1);

    List<Map<String, dynamic>> allTransactions = [
      ..._salesData,
      ..._purchaseData
    ];

    allTransactions.sort((a, b) =>
        (b['date'] as DateTime).compareTo(a['date'] as DateTime));

    return allTransactions.where((t) {
      final date = t['date'] as DateTime;
      if (period == 'Daily') {
        return DateTime(date.year, date.month, date.day)
            .isAtSameMomentAs(today);
      } else if (period == 'Weekly') {
        return date.isAfter(startOfWeek);
      } else {
        return date.isAfter(startOfMonth);
      }
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // 🔥 UI BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Reports & Analytics'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Download PDF',
            onPressed: _isLoading ? null : _generateAndDownloadPdf,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Daily'),
            Tab(text: 'Weekly'),
            Tab(text: 'Monthly'),
          ],
          onTap: (index) => setState(() {}), // Rebuild to update PDF context
        ),
      ),
      body: _isLoading
          ? _buildLoadingState()
          : TabBarView(
              controller: _tabController,
              children: [
                _buildReportView('Daily', _dailySales, _dailyPurchase),
                _buildReportView('Weekly', _weeklySales, _weeklyPurchase,
                    showChart: true),
                _buildReportView('Monthly', _monthlySales, _monthlyPurchase),
              ],
            ),
    );
  }

  Widget _buildReportView(String period, double sales, double purchase,
      {bool showChart = false}) {
    final profit = sales - purchase;
    final isProfit = profit >= 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary Cards
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  'Total Sales',
                  sales,
                  Colors.blue[50]!,
                  Colors.blue[700]!,
                  Icons.arrow_upward,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  'Total Purchase',
                  purchase,
                  Colors.orange[50]!,
                  Colors.orange[700]!,
                  Icons.shopping_cart,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSummaryCard(
            'Net Profit ($period)',
            profit,
            isProfit ? Colors.green[50]! : Colors.red[50]!,
            isProfit ? Colors.green[700]! : Colors.red[700]!,
            isProfit ? Icons.trending_up : Icons.trending_down,
            isFullWidth: true,
          ),

          const SizedBox(height: 24),

          // Chart Section
          if (showChart) ...[
            const Text(
              'Profit Trend (Last 7 Days)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final date = DateTime.fromMillisecondsSinceEpoch(
                              value.toInt());
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              DateFormat('E').format(date), // Mon, Tue
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: _dailyProfitLast7Days.entries.map((entry) {
                    final isPositive = entry.value >= 0;
                    return BarChartGroupData(
                      x: entry.key.millisecondsSinceEpoch,
                      barRods: [
                        BarChartRodData(
                          toY: entry.value,
                          color: isPositive ? Colors.green : Colors.red,
                          width: 16,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Transaction List
          const Text(
            'Recent Transactions',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildTransactionList(period),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    String title,
    double amount,
    Color bgColor,
    Color textColor,
    IconData icon, {
    bool isFullWidth = false,
  }) {
    final format = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    return Container(
      width: isFullWidth ? double.infinity : null,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
              Icon(icon, color: textColor, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            format.format(amount),
            style: TextStyle(
              color: textColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionList(String period) {
    final filtered = _getFilteredTransactions(period);

    if (filtered.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('No transactions found for this period'),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final t = filtered[index];
        final isSale = t['type'] == 'Sale';
        final amount = t['amount'] as double;
        final date = t['date'] as DateTime;

        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: isSale ? Colors.green[50] : Colors.orange[50],
            child: Icon(
              isSale ? Icons.arrow_upward : Icons.shopping_cart,
              color: isSale ? Colors.green : Colors.orange,
              size: 20,
            ),
          ),
          title: Text(isSale ? 'Sale Invoice' : 'Purchase Invoice'),
          subtitle: Text(DateFormat('dd MMM yyyy, hh:mm a').format(date)),
          trailing: Text(
            '${isSale ? '+' : '-'} ₹${amount.toStringAsFixed(2)}',
            style: TextStyle(
              color: isSale ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadingState() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                    child: Container(
                        height: 100,
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12)))),
                const SizedBox(width: 12),
                Expanded(
                    child: Container(
                        height: 100,
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12)))),
              ],
            ),
            const SizedBox(height: 12),
            Container(
                height: 100,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12))),
            const SizedBox(height: 24),
            Container(
                height: 200,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12))),
          ],
        ),
      ),
    );
  }
}
