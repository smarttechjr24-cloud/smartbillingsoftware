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
    final upiIdController = TextEditingController();
    final chequeController = TextEditingController();
    String paymentMode = 'Cash';
    bool showQR = false;
    String qrLink = '';

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
                'upi_id': upiIdController.text.trim(),
                'cheque_no': chequeController.text.trim(),
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

                await _updateInvoiceStatuses(name, newOutstanding);

                if (context.mounted) Navigator.pop(context);
                _showSnack("✅ Payment recorded successfully!", success: true);
              } catch (e) {
                _showSnack("❌ Failed to save payment. Please try again.");
              }
            }

            void generateQR() async {
              final amt = double.tryParse(amountController.text.trim()) ?? 0;
              if (amt <= 0) {
                _showSnack("Enter amount before generating QR");
                return;
              }

              String? upiId = upiIdController.text.trim();
              if (upiId.isEmpty) {
                final companyRef = _firestore
                    .collection('users')
                    .doc(_uid)
                    .collection('company')
                    .doc('details');
                final companyDoc = await companyRef.get();
                upiId = companyDoc.data()?['upi_id'] ?? '';

                if (upiId!.isEmpty) {
                  _showSnack("⚠️ Please enter your UPI ID first");
                  return;
                }
              }

              final link =
                  "upi://pay?pa=$upiId&pn=${Uri.encodeComponent(name)}&am=$amt&cu=INR";

              setStateDialog(() {
                qrLink = link;
                showQR = true;
              });
            }

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              insetPadding: const EdgeInsets.symmetric(horizontal: 20),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "💰 Record Payment",
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Customer: $name\nOutstanding: ₹${outstanding.toStringAsFixed(2)}",
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 16),
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
                      const SizedBox(height: 12),

                      // Payment Mode Dropdown
                      DropdownButtonFormField<String>(
                        value: paymentMode,
                        items: const [
                          DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                          DropdownMenuItem(value: 'Card', child: Text('Card')),
                          DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                          DropdownMenuItem(value: 'DD', child: Text('DD')),
                          DropdownMenuItem(
                            value: 'Cheque',
                            child: Text('Cheque'),
                          ),
                        ],
                        onChanged: (v) => setStateDialog(() {
                          paymentMode = v!;
                          showQR = false; // reset QR
                        }),
                        decoration: const InputDecoration(
                          labelText: "Payment Mode",
                          prefixIcon: Icon(Icons.payment_rounded),
                          border: OutlineInputBorder(),
                        ),
                      ),

                      // Optional fields based on mode
                      if (paymentMode == 'UPI') ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: upiIdController,
                          decoration: const InputDecoration(
                            labelText: "UPI ID (optional)",
                            prefixIcon: Icon(Icons.qr_code_2),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      if (paymentMode == 'Cheque') ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: chequeController,
                          decoration: const InputDecoration(
                            labelText: "Cheque No (optional)",
                            prefixIcon: Icon(Icons.numbers),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],

                      const SizedBox(height: 18),

                      // QR Section (only show if generated)
                      if (showQR) ...[
                        const Divider(),
                        const SizedBox(height: 8),
                        const Text(
                          "Scan to Pay",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        QrImageView(
                          data: qrLink,
                          size: 200,
                          backgroundColor: Colors.white,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "₹${amountController.text.trim()} for $name",
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

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
                          if (paymentMode == 'UPI')
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: generateQR,
                                icon: const Icon(Icons.qr_code_2),
                                label: const Text("Generate"),
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
              ),
            );
          },
        );
      },
    );
  }

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
      final snapshot = await invoicesRef
          .where('customer_name', isEqualTo: customerName)
          .get();
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final currentStatus = data['status'] as String?;
        if (currentStatus == 'Closed') continue;

        final grandTotal = (data['grand_total'] ?? 0).toDouble();
        String newStatus;
        if (newOutstanding == 0) {
          newStatus = 'Closed';
        } else if (newOutstanding < grandTotal) {
          newStatus = 'Partially Paid';
        } else {
          newStatus = 'Pending';
        }

        if (currentStatus != newStatus) {
          await invoicesRef.doc(doc.id).update({'status': newStatus});
        }
      }
    } catch (e) {
      debugPrint("Error updating invoice statuses: $e");
    }
  }

  void _showSnack(String msg, {bool success = false}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: success ? Colors.green : Colors.redAccent,
      ),
    );
  }

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
