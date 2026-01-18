import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({Key? key}) : super(key: key);

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  String? get _uid => _auth.currentUser?.uid;

  // Date range
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  // Report data
  double _totalSales = 0.0;
  double _totalCGST = 0.0;
  double _totalSGST = 0.0;
  double _totalIGST = 0.0;
  double _totalOutstanding = 0.0;
  int _invoiceCount = 0;
  List<Map<String, dynamic>> _topCustomers = [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    if (_uid == null) return;

    setState(() => _loading = true);

    try {
      // Fetch invoices within date range
      final invoicesSnap = await _firestore
          .collection('users')
          .doc(_uid)
          .collection('invoices')
          .where('invoice_date',
              isGreaterThanOrEqualTo: _startDate.toIso8601String())
          .where('invoice_date',
              isLessThanOrEqualTo: _endDate.toIso8601String())
          .get();

      double sales = 0.0;
      double cgst = 0.0;
      double sgst = 0.0;
      double igst = 0.0;
      Map<String, double> customerSales = {};

      for (var doc in invoicesSnap.docs) {
        final data = doc.data();
        final grandTotal = (data['grand_total'] as num?)?.toDouble() ?? 0.0;
        final cgstTotal = (data['cgst_total'] as num?)?.toDouble() ?? 0.0;
        final sgstTotal = (data['sgst_total'] as num?)?.toDouble() ?? 0.0;
        final igstTotal = (data['igst_total'] as num?)?.toDouble() ?? 0.0;
        final customerName = data['customer_name'] ?? 'Unknown';

        sales += grandTotal;
        cgst += cgstTotal;
        sgst += sgstTotal;
        igst += igstTotal;

        // Track customer sales
        customerSales[customerName] =
            (customerSales[customerName] ?? 0.0) + grandTotal;
      }

      // Get outstanding from customers
      final customersSnap = await _firestore
          .collection('users')
          .doc(_uid)
          .collection('customers')
          .get();

      double outstanding = 0.0;
      for (var doc in customersSnap.docs) {
        outstanding +=
            (doc.data()['outstanding'] as num?)?.toDouble() ?? 0.0;
      }

      // Sort top customers
      final topCustomers = customerSales.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      setState(() {
        _totalSales = sales;
        _totalCGST = cgst;
        _totalSGST = sgst;
        _totalIGST = igst;
        _totalOutstanding = outstanding;
        _invoiceCount = invoicesSnap.docs.length;
        _topCustomers = topCustomers
            .take(5)
            .map((e) => {'name': e.key, 'amount': e.value})
            .toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint("Error loading reports: $e");
      setState(() => _loading = false);
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadReports();
    }
  }

  Future<void> _generateAndDownloadPdf() async {
    final pdf = pw.Document();
    final dateFormat = DateFormat('dd MMM yyyy');

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
                  pw.Text('Business Report',
                      style: pw.TextStyle(
                          fontSize: 24, fontWeight: pw.FontWeight.bold)),
                  pw.Text(dateFormat.format(DateTime.now())),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text(
                'Period: ${dateFormat.format(_startDate)} - ${dateFormat.format(_endDate)}',
                style: const pw.TextStyle(fontSize: 18)),
            pw.SizedBox(height: 20),

            // Metrics Table
            pw.Table.fromTextArray(
              headers: ['Metric', 'Value'],
              data: [
                ['Total Sales', 'INR ${_totalSales.toStringAsFixed(2)}'],
                ['Total Invoices', '$_invoiceCount'],
                ['Total Tax', 'INR ${(_totalCGST + _totalSGST + _totalIGST).toStringAsFixed(2)}'],
                ['Total Outstanding', 'INR ${_totalOutstanding.toStringAsFixed(2)}'],
              ],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerRight,
              },
            ),
            pw.SizedBox(height: 30),

            // Top Customers
            pw.Text('Top Customers',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Table.fromTextArray(
              headers: ['Customer Name', 'Sales Amount'],
              data: _topCustomers.map((c) {
                return [
                  c['name'],
                  'INR ${(c['amount'] as double).toStringAsFixed(2)}',
                ];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerRight,
              },
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Business_Report_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text("Business Reports"),
        
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: "Download PDF",
            onPressed: _loading ? null : _generateAndDownloadPdf,
          ),
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _pickDateRange,
            tooltip: "Select Date Range",
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF5F7FA),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadReports,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date Range Display
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Report Period",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "${dateFormat.format(_startDate)} - ${dateFormat.format(_endDate)}",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          const Icon(Icons.calendar_today,
                              color: Color(0xFF1976D2)),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Sales Summary
                    const Text(
                      "Sales Summary",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricCard(
                            "Total Sales",
                            "₹${_totalSales.toStringAsFixed(2)}",
                            Icons.trending_up,
                            Colors.green,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildMetricCard(
                            "Invoices",
                            _invoiceCount.toString(),
                            Icons.receipt_long,
                            Colors.blue,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Tax Summary
                    const Text(
                      "Tax Summary",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    _buildTaxCard(),

                    const SizedBox(height: 20),

                    // Outstanding
                    const Text(
                      "Outstanding Payments",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    _buildMetricCard(
                      "Total Outstanding",
                      "₹${_totalOutstanding.toStringAsFixed(2)}",
                      Icons.account_balance_wallet,
                      Colors.orange,
                    ),

                    const SizedBox(height: 20),

                    // Top Customers
                    const Text(
                      "Top Customers",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    _buildTopCustomersList(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildMetricCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.grey,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaxCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          _buildTaxRow("CGST", _totalCGST),
          const Divider(),
          _buildTaxRow("SGST", _totalSGST),
          const Divider(),
          _buildTaxRow("IGST", _totalIGST),
          const Divider(thickness: 2),
          _buildTaxRow(
            "Total Tax",
            _totalCGST + _totalSGST + _totalIGST,
            isBold: true,
          ),
        ],
      ),
    );
  }

  Widget _buildTaxRow(String label, double amount, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            "₹${amount.toStringAsFixed(2)}",
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: const Color(0xFF1976D2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopCustomersList() {
    if (_topCustomers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Center(
          child: Text(
            "No customer data available",
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _topCustomers.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final customer = _topCustomers[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF1976D2).withOpacity(0.1),
              child: Text(
                "${index + 1}",
                style: const TextStyle(
                  color: Color(0xFF1976D2),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              customer['name'],
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            trailing: Text(
              "₹${(customer['amount'] as double).toStringAsFixed(2)}",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF1976D2),
              ),
            ),
          );
        },
      ),
    );
  }
}
