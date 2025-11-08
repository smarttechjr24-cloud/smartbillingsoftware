import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class PaymentScreen extends StatefulWidget {
  final bool qrOnly;
  final String? upiUrl;

  const PaymentScreen({Key? key, this.qrOnly = false, this.upiUrl})
    : super(key: key);

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _searchController = TextEditingController();
  String searchQuery = "";

  String? get _uid => _auth.currentUser?.uid;

  /// 🔹 Stream customers with outstanding
  Stream<List<Map<String, dynamic>>> _fetchCustomers() async* {
    if (_uid == null) yield [];
    final stream = _firestore
        .collection('users')
        .doc(_uid)
        .collection('customers')
        .orderBy('name')
        .snapshots();

    await for (final snap in stream) {
      yield snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    }
  }

  /// 🔹 Payment Dialog
  Future<void> _openPaymentDialog(Map<String, dynamic> customer) async {
    final name = customer['name'] ?? '';
    final outstanding = (customer['outstanding'] ?? 0).toDouble();

    final amountController = TextEditingController();
    String paymentMode = 'Cash';

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            Future<void> savePayment() async {
              final amt = double.tryParse(amountController.text.trim()) ?? 0;
              if (amt <= 0) {
                _showSnack("Enter a valid amount");
                return;
              }

              final newOutstanding = (outstanding - amt).clamp(
                0,
                double.infinity,
              );

              final paymentData = {
                'customer_name': name,
                'customer_id': customer['id'],
                'amount': amt,
                'payment_mode': paymentMode,
                'previous_outstanding': outstanding,
                'new_outstanding': newOutstanding,
                'created_at': FieldValue.serverTimestamp(),
              };

              try {
                await _firestore
                    .collection('users')
                    .doc(_uid)
                    .collection('payments')
                    .add(paymentData);

                await _firestore
                    .collection('users')
                    .doc(_uid)
                    .collection('customers')
                    .doc(customer['id'])
                    .update({'outstanding': newOutstanding});

                // Update invoice statuses based on the new outstanding amount
                await _updateInvoiceStatuses(name, newOutstanding);

                if (context.mounted) Navigator.pop(context);
                _showSnack("✅ Payment recorded successfully!", success: true);
              } catch (e) {
                if (context.mounted) Navigator.pop(context);
                _showSnack("❌ Failed to save payment. Please try again.");
              }
            }

            void generateQR() async {
              final amt = double.tryParse(amountController.text.trim()) ?? 0;
              if (amt <= 0) {
                _showSnack("Enter a valid amount before generating QR");
                return;
              }

              Navigator.pop(context);
              await _showQrDialog(name, amt.toString());
            }

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Record Payment",
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Customer: $name\nOutstanding: ₹${outstanding.toStringAsFixed(2)}",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: "Amount Paid",
                        prefixIcon: Icon(Icons.currency_rupee),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 15),
                    DropdownButtonFormField<String>(
                      value: paymentMode,
                      items: const [
                        DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                        DropdownMenuItem(value: 'Card', child: Text('Card')),
                        DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                        DropdownMenuItem(value: 'QR', child: Text('QR Code')),
                        DropdownMenuItem(
                          value: 'Cheque',
                          child: Text('Cheque'),
                        ),
                      ],
                      onChanged: (v) => setStateDialog(() => paymentMode = v!),
                      decoration: const InputDecoration(
                        labelText: "Payment Mode",
                        prefixIcon: Icon(Icons.payment_rounded),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: savePayment,
                            icon: const Icon(Icons.save),
                            label: const Text("Save"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              minimumSize: const Size(double.infinity, 46),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: generateQR,
                            icon: const Icon(Icons.qr_code_2),
                            label: const Text("QR"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              minimumSize: const Size(double.infinity, 46),
                            ),
                          ),
                        ),
                      ],
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

  /// 🔹 Update Invoice Statuses based on outstanding amount
  Future<void> _updateInvoiceStatuses(
    String customerName,
    double newOutstanding,
  ) async {
    if (_uid == null) return;

    final invoicesRef = _firestore
        .collection('users')
        .doc(_uid)
        .collection('invoices');

    try {
      // Get all invoices for this customer
      final snapshot = await invoicesRef
          .where('customer_name', isEqualTo: customerName)
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final currentStatus = data['status'] as String?;

        // Skip if already fully paid and closed
        if (currentStatus == 'Closed') {
          continue;
        }

        final grandTotal = (data['grand_total'] ?? 0).toDouble();
        String newStatus;

        if (newOutstanding == 0) {
          // Fully paid - mark as Closed
          newStatus = 'Closed';
        } else if (newOutstanding < grandTotal) {
          // Partially paid
          newStatus = 'Partially Paid';
        } else {
          // Still pending (outstanding >= grand total)
          newStatus = 'Pending';
        }

        // Update only if status changed
        if (currentStatus != newStatus) {
          await invoicesRef.doc(doc.id).update({'status': newStatus});
        }
      }
    } catch (e) {
      debugPrint("Error updating invoice statuses: $e");
    }
  }

  /// 🔹 Show QR Dialog
  Future<void> _showQrDialog(String name, String amount) async {
    final companyRef = _firestore
        .collection('users')
        .doc(_uid)
        .collection('company')
        .doc('details');

    final companyDoc = await companyRef.get();
    String? upiId = companyDoc.data()?['upi_id'];

    if (upiId == null || upiId.isEmpty) {
      // Ask user for UPI ID
      final upiController = TextEditingController();
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Add UPI ID"),
          content: TextField(
            controller: upiController,
            decoration: const InputDecoration(
              labelText: "Enter your UPI ID",
              hintText: "example@upi",
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(context, upiController.text.trim()),
              child: const Text("Save"),
            ),
          ],
        ),
      );

      if (result == null || result.isEmpty) {
        _showSnack("⚠️ UPI ID is required to generate QR");
        return;
      }

      upiId = result;
      await companyRef.set({'upi_id': upiId}, SetOptions(merge: true));
      _showSnack("✅ UPI ID saved successfully", success: true);
    }

    final upiLink =
        "upi://pay?pa=$upiId&pn=${Uri.encodeComponent(name)}&am=$amount&cu=INR";

    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Scan to Pay",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                QrImageView(
                  data: upiLink,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
                const SizedBox(height: 12),
                Text(
                  "₹$amount for $name",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Close"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 🔹 Helper Snack
  void _showSnack(String msg, {bool success = false}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: success ? Colors.green : Colors.redAccent,
      ),
    );
  }

  /// 🔹 Main UI
  @override
  Widget build(BuildContext context) {
    if (widget.qrOnly && widget.upiUrl != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: QrImageView(
            data: widget.upiUrl!,
            size: 240,
            backgroundColor: Colors.white,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Customer Payments"),
        centerTitle: true,
        backgroundColor: const Color(0xFF1F3A5F),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _fetchCustomers(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("No customers found."));
          }

          final customers = snapshot.data!;
          final filtered = customers
              .where(
                (c) => c['name'].toString().toLowerCase().contains(
                  searchQuery.toLowerCase(),
                ),
              )
              .toList();

          final totalOutstanding = filtered.fold<double>(
            0,
            (sum, c) => sum + (c['outstanding'] ?? 0),
          );

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => searchQuery = v),
                  decoration: InputDecoration(
                    hintText: "Search customer...",
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                color: Colors.blue.shade50,
                child: Text(
                  "Total Outstanding: ₹${totalOutstanding.toStringAsFixed(2)}",
                  style: const TextStyle(
                    color: Colors.deepOrange,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: filtered.length,
                  padding: const EdgeInsets.all(8),
                  itemBuilder: (_, index) {
                    final c = filtered[index];
                    return Card(
                      elevation: 3,
                      margin: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 8,
                      ),
                      child: ListTile(
                        leading: const Icon(
                          Icons.person_outline,
                          color: Colors.blueAccent,
                        ),
                        title: Text(c['name'] ?? 'Unknown'),
                        subtitle: Text(
                          "Outstanding: ₹${(c['outstanding'] ?? 0).toStringAsFixed(2)}",
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.add_circle_outline_rounded,
                            color: Colors.green,
                          ),
                          onPressed: () => _openPaymentDialog(c),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
