import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class PurchasePaymentReceiptScreen extends StatefulWidget {
  const PurchasePaymentReceiptScreen({Key? key}) : super(key: key);

  @override
  State<PurchasePaymentReceiptScreen> createState() =>
      _PurchasePaymentReceiptScreenState();
}

class _PurchasePaymentReceiptScreenState
    extends State<PurchasePaymentReceiptScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  bool loading = true;
  List<Map<String, dynamic>> payments = [];

  @override
  void initState() {
    super.initState();
    _fetchAllPayments();
  }

  /// Fetch all purchase payments
  Future<void> _fetchAllPayments() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      final userRef = _firestore.collection('users').doc(uid);
      
      // Fetch all payments
      final snap = await userRef
          .collection('supplier_payments')
          .orderBy('created_at', descending: true)
          .get();

      // Fetch all suppliers in one query
      final suppliersSnap = await userRef.collection('suppliers').get();
      final supplierMap = <String, String>{};
      for (var doc in suppliersSnap.docs) {
        supplierMap[doc.id] = doc.data()['name'] ?? 'Unknown Supplier';
      }

      // Match supplier names to payments
      List<Map<String, dynamic>> paymentsWithSuppliers = [];
      
      for (var doc in snap.docs) {
        final data = {'id': doc.id, ...doc.data()};
        
        // If supplierName is missing or empty, get from supplier map
        if (data['supplierName'] == null || data['supplierName'].toString().isEmpty) {
          final supplierId = data['supplierId'];
          if (supplierId != null && supplierId.toString().isNotEmpty) {
            data['supplierName'] = supplierMap[supplierId.toString()] ?? 'Unknown Supplier';
          } else {
            data['supplierName'] = 'Unknown Supplier';
          }
        }
        
        paymentsWithSuppliers.add(data);
      }

      setState(() {
        payments = paymentsWithSuppliers;
        loading = false;
      });
    } catch (e) {
      debugPrint("❌ Error fetching purchase payments: $e");
      setState(() => loading = false);
    }
  }

  /// Delete a purchase payment record & update purchase + supplier
  Future<void> _deletePayment(String id) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      // Step 1: Confirm Deletion
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
            "This will adjust the purchase invoice and supplier's outstanding balance.",
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

      // Step 2: Load payment document
      final userRef = _firestore.collection('users').doc(uid);
      final paymentRef = userRef.collection('supplier_payments').doc(id);
      final paymentSnap = await paymentRef.get();

      if (!paymentSnap.exists) {
        _showSnack("⚠️ Payment not found");
        return;
      }

      final paymentData = paymentSnap.data()!;
      final double amount = (paymentData['amount'] ?? 0).toDouble();
      final String? purchaseId = paymentData['purchaseInvoiceId'];
      final String? supplierId = paymentData['supplierId'];

      // Step 3: Update purchase invoice (if linked)
      if (purchaseId != null && purchaseId.isNotEmpty) {
        final purchaseRef = userRef.collection('purchases').doc(purchaseId);
        final purchaseSnap = await purchaseRef.get();

        if (purchaseSnap.exists) {
          final data = purchaseSnap.data()!;
          final double currentPaid = (data['paid_amount'] ?? 0).toDouble();
          final double currentBalance = (data['balance_due'] ?? 0).toDouble();

          final double newPaid = (currentPaid - amount).clamp(0, double.infinity);
          final double newBalance = currentBalance + amount;

          // Determine new status
          String newStatus;
          if (newPaid == 0) {
            newStatus = "outstanding";
          } else if (newBalance > 0) {
            newStatus = "partial";
          } else {
            newStatus = "paid";
          }

          // Update purchase invoice
          await purchaseRef.update({
            'paid_amount': newPaid,
            'balance_due': newBalance,
            'paymentStatus': newStatus,
            'updated_at': FieldValue.serverTimestamp(),
          });
        }
      }

      // Step 4: Update supplier outstanding
      if (supplierId != null && supplierId.isNotEmpty) {
        final supplierRef = userRef.collection('suppliers').doc(supplierId);
        final supplierSnap = await supplierRef.get();

        if (supplierSnap.exists) {
          // Increase supplier outstanding by the payment amount
          await supplierRef.update({
            'outstandingBalance': FieldValue.increment(amount),
            'updated_at': FieldValue.serverTimestamp(),
          });
        }
      }

      // Step 5: Delete payment record
      await paymentRef.delete();

      _showSnack("✅ Payment deleted & balances updated", success: true);
      _fetchAllPayments(); // Refresh UI
    } catch (e) {
      _showSnack("❌ Failed to delete payment: $e");
    }
  }

  /// Generate & Share PDF
  Future<void> _generateAndSharePDF(Map<String, dynamic> paymentData) async {
    try {
      final pdf = pw.Document();
      final df = DateFormat("dd MMM yyyy, hh:mm a");

      // Safely extract all values
      final createdAt =
          (paymentData['created_at'] as Timestamp?)?.toDate() ?? DateTime.now();
      final supplier = (paymentData['supplierName'] ?? '-').toString();
      final amount = (paymentData['amount'] ?? 0).toDouble();
      final paymentDate = (paymentData['payment_date'] as String?) ?? '';
      final recordedBy = (paymentData['recorded_by'] ?? 'System').toString();

      final fileName =
          "Purchase_Payment_Receipt_${DateTime.now().millisecondsSinceEpoch}.pdf";

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
                          "Purchase Payment Receipt",
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
                          color: PdfColors.orange,
                          width: 1.2,
                        ),
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Text(
                        "RECEIPT",
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.orange,
                        ),
                      ),
                    ),
                  ],
                ),

                pw.SizedBox(height: 20),
                pw.Divider(thickness: 1),

                // SUPPLIER DETAILS
                pw.Text(
                  "Supplier Details",
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
                      pw.Text("Supplier Name: $supplier"),
                      pw.Text("Date: ${df.format(createdAt)}"),
                      pw.Text("Recorded By: $recordedBy"),
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
                    _tableRow("Payment Date", paymentDate),
                    _tableRow(
                      "Amount Paid",
                      "Rs. ${amount.toStringAsFixed(2)}",
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

      await Share.shareXFiles([XFile(file.path)],
          text: "Purchase Payment Receipt");
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

  /// Helper Snack
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
      return Scaffold(
        appBar: AppBar(
          title: const Text("Purchase Payment Receipts"),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Text(
            "No purchase payments found.",
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }

    final df = DateFormat("dd MMM yyyy, hh:mm a");

    return Scaffold(
      appBar: AppBar(
        title: const Text("Purchase Payment Receipts"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
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
                  backgroundColor: Colors.orange.shade100,
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: Colors.orange,
                  ),
                ),
                title: Text(
                  p['supplierName'] ?? 'Unknown Supplier',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Amount: ₹${(p['amount'] ?? 0).toStringAsFixed(2)}"),
                    Text("Date: ${df.format(createdAt)}"),
                    Text("Recorded By: ${p['recorded_by'] ?? 'System'}"),
                  ],
                ),
                trailing: PopupMenuButton<String>(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  onSelected: (value) {
                    if (value == 'share') {
                      _generateAndSharePDF(p);
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
