import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class PaymentReceiptScreen extends StatefulWidget {
  const PaymentReceiptScreen({Key? key}) : super(key: key);

  @override
  State<PaymentReceiptScreen> createState() => _PaymentReceiptScreenState();
}

class _PaymentReceiptScreenState extends State<PaymentReceiptScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  bool loading = true;
  List<Map<String, dynamic>> payments = [];

  @override
  void initState() {
    super.initState();
    _fetchAllPayments();
  }

  /// 🔹 Fetch all payments
  Future<void> _fetchAllPayments() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      final userRef = _firestore.collection('users').doc(uid);
      final snap = await userRef
          .collection('payments')
          .orderBy('created_at', descending: true)
          .get();

      setState(() {
        payments = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        loading = false;
      });
    } catch (e) {
      debugPrint("❌ Error fetching payments: $e");
      setState(() => loading = false);
    }
  }

  /// 🔹 Delete a payment record & update outstanding
  /// 🔹 Delete a payment record & update invoice status + outstanding
  Future<void> _deletePayment(String id) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      // 🔹 Step 1: Confirm Deletion
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text(
            "Delete Payment?",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const Text(
            "Are you sure you want to delete this payment?\n"
            "This will adjust the invoice and customer's outstanding balance.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              child: const Text("Delete"),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      // 🔹 Step 2: Load payment document
      final userRef = _firestore.collection('users').doc(uid);
      final paymentRef = userRef.collection('payments').doc(id);
      final paymentSnap = await paymentRef.get();

      if (!paymentSnap.exists) {
        _showSnack("⚠️ Payment not found");
        return;
      }

      final paymentData = paymentSnap.data()!;
      final double amount = (paymentData['amount'] ?? 0).toDouble();
      final String? invoiceId = paymentData['invoice_id'];
      final String? customerName = paymentData['customer_name'];

      // 🔹 Step 3: Handle invoice update (if linked)
      if (invoiceId != null && invoiceId.isNotEmpty) {
        final invoiceRef = userRef.collection('invoices').doc(invoiceId);
        final invoiceSnap = await invoiceRef.get();

        if (invoiceSnap.exists) {
          final data = invoiceSnap.data()!;
          final double total = (data['grand_total'] ?? 0).toDouble();

          // Fetch all payments linked to this invoice
          final paymentsSnap = await userRef
              .collection('payments')
              .where('invoice_id', isEqualTo: invoiceId)
              .get();

          // Simulate deletion by filtering out the payment being deleted
          final remainingPayments = paymentsSnap.docs
              .where((doc) => doc.id != id)
              .toList();

          // Calculate new total paid (excluding deleted one)
          final double newPaid = remainingPayments.fold(
            0.0,
            (sum, doc) => sum + ((doc['amount'] ?? 0).toDouble()),
          );

          final double newBalance = (total - newPaid).clamp(0, total);

          // Determine new status
          String newStatus;
          if (remainingPayments.isEmpty || newPaid == 0) {
            newStatus = "Pending";
          } else if (newPaid > 0 && newPaid < total) {
            newStatus = "Partially Paid";
          } else if (newPaid >= total) {
            newStatus = "Closed";
          } else {
            newStatus = "Pending";
          }

          // ✅ Update invoice document
          await invoiceRef.update({
            'paid_amount': newPaid,
            'balance_due': newBalance,
            'status': newStatus,
            'updated_at': FieldValue.serverTimestamp(),
          });
        }
      }

      // 🔹 Step 4: Update customer outstanding
      if (customerName != null && customerName.isNotEmpty) {
        final customerQuery = await userRef
            .collection('customers')
            .where('name', isEqualTo: customerName)
            .limit(1)
            .get();

        if (customerQuery.docs.isNotEmpty) {
          final customerDoc = customerQuery.docs.first;
          final double currentOutstanding = (customerDoc['outstanding'] ?? 0)
              .toDouble();

          // Revert the payment amount back to outstanding
          final double newOutstanding = (currentOutstanding + amount).clamp(
            0,
            double.infinity,
          );

          await customerDoc.reference.update({
            'outstanding': newOutstanding,
            'updated_at': FieldValue.serverTimestamp(),
          });
        }
      }

      // 🔹 Step 5: Delete payment record
      await paymentRef.delete();

      _showSnack("✅ Payment deleted & balances updated", success: true);
      _fetchAllPayments(); // Refresh UI
    } catch (e) {
      _showSnack("❌ Failed to delete payment: $e");
    }
  }

  /// 🔹 Generate & Share PDF
  Future<void> _generateAndSharePDF(Map<String, dynamic> paymentData) async {
    try {
      final pdf = pw.Document();
      final df = DateFormat("dd MMM yyyy, hh:mm a");

      // Safely extract all values
      final createdAt =
          (paymentData['created_at'] as Timestamp?)?.toDate() ?? DateTime.now();
      final customer = (paymentData['customer_name'] ?? '-').toString();
      final amount = (paymentData['amount'] ?? 0).toDouble();
      final mode = (paymentData['payment_mode'] ?? 'Cash').toString();
      final balanceRaw =
          paymentData['balance_due'] ??
          paymentData['new_outstanding'] ??
          paymentData['outstanding'] ??
          paymentData['previous_outstanding'] ??
          0;
      final balance = double.tryParse(balanceRaw.toString()) ?? 0.0;

      final fileName =
          "Payment_Receipt_${DateTime.now().millisecondsSinceEpoch}.pdf";

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // HEADER
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          "SMART BILLING SOFTWARE",
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          "Customer Payment Receipt",
                          style: pw.TextStyle(
                            fontSize: 12,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(
                          color: PdfColors.blue,
                          width: 1.2,
                        ),
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Text(
                        "RECEIPT",
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue,
                        ),
                      ),
                    ),
                  ],
                ),

                pw.SizedBox(height: 20),
                pw.Divider(thickness: 1),

                // CUSTOMER DETAILS
                pw.Text(
                  "Customer Details",
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("Customer Name: $customer"),
                      pw.Text("Date: ${df.format(createdAt)}"),
                    ],
                  ),
                ),

                pw.SizedBox(height: 20),

                // PAYMENT DETAILS
                pw.Text(
                  "Payment Details",
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey400),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(2),
                    1: pw.FlexColumnWidth(3),
                  },
                  children: [
                    _tableRow("Field", "Value", isHeader: true),
                    _tableRow("Payment Mode", mode),
                    _tableRow(
                      "Amount Received",
                      "Rs. ${amount.toStringAsFixed(2)}",
                    ),
                    _tableRow(
                      "Outstanding Balance",
                      "Rs. ${balance.toStringAsFixed(2)}",
                    ),
                  ],
                ),

                pw.Spacer(),
                pw.Divider(thickness: 1),

                // FOOTER
                pw.Center(
                  child: pw.Text(
                    "Thank you for your business!",
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontStyle: pw.FontStyle.italic,
                      color: PdfColors.grey700,
                    ),
                  ),
                ),
                pw.Center(
                  child: pw.Text(
                    "Generated by SmartBilling AI",
                    style: pw.TextStyle(fontSize: 10, color: PdfColors.grey500),
                  ),
                ),
              ],
            );
          },
        ),
      );

      final dir = await getTemporaryDirectory();
      final file = File("${dir.path}/$fileName");
      await file.writeAsBytes(await pdf.save());

      await Share.shareXFiles([XFile(file.path)], text: "Payment Receipt");
    } catch (e) {
      debugPrint("❌ PDF Generation Error: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to generate or share PDF: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  /// helper
  pw.TableRow _tableRow(String key, String value, {bool isHeader = false}) {
    return pw.TableRow(
      decoration: isHeader
          ? const pw.BoxDecoration(color: PdfColors.grey200)
          : null,
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Text(
            key,
            style: pw.TextStyle(
              fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Text(
            value,
            style: pw.TextStyle(
              fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  /// 🔹 Helper Snack
  void _showSnack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: success ? Colors.green : Colors.redAccent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (payments.isEmpty) {
      return const Scaffold(body: Center(child: Text("No payments found.")));
    }

    final df = DateFormat("dd MMM yyyy, hh:mm a");

    return Scaffold(
      appBar: AppBar(
        title: const Text("Payment Receipts"),
        backgroundColor: const Color(0xFF1F3A5F),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchAllPayments,
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: payments.length,
          itemBuilder: (context, index) {
            final p = payments[index];
            final createdAt =
                (p['created_at'] as Timestamp?)?.toDate() ?? DateTime.now();

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 3,
              child: ListTile(
                contentPadding: const EdgeInsets.all(12),
                leading: CircleAvatar(
                  backgroundColor: Colors.green.shade100,
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: Colors.green,
                  ),
                ),
                title: Text(
                  p['customer_name'] ?? 'Unknown Customer',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Amount: ₹${(p['amount'] ?? 0).toStringAsFixed(2)}"),
                    Text("Mode: ${p['payment_mode'] ?? 'Cash'}"),
                    Text("Date: ${df.format(createdAt)}"),
                  ],
                ),
                trailing: PopupMenuButton<String>(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  onSelected: (value) {
                    if (value == 'share') {
                      _generateAndSharePDF(p);
                      print("Payment Data: $p");
                    } else if (value == 'delete') {
                      _deletePayment(p['id']);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'share',
                      child: Row(
                        children: [
                          Icon(Icons.picture_as_pdf, color: Colors.blue),
                          SizedBox(width: 8),
                          Text("Share as PDF"),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: Colors.redAccent),
                          SizedBox(width: 8),
                          Text("Delete"),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
