import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:smartbilling/utils/delivery_chellan.dart';
import '../utils/pdf.dart';
import 'add_invoice_screen.dart';

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({Key? key}) : super(key: key);

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _searchController = TextEditingController();

  String _searchQuery = "";
  String _filterStatus = "All";
  String? get _uid => _auth.currentUser?.uid;

  Stream<QuerySnapshot<Map<String, dynamic>>> _getInvoices() {
    if (_uid == null) return const Stream.empty();
    return _firestore
        .collection('users')
        .doc(_uid)
        .collection('invoices')
        .orderBy('created_at', descending: true)
        .snapshots();
  }

  String _formatTimestamp(dynamic ts) {
    if (ts is Timestamp) {
      return DateFormat('dd MMM yyyy, hh:mm a').format(ts.toDate());
    }
    return '-';
  }

  void _showSnack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: success ? Colors.green : Colors.redAccent,
      ),
    );
  }

  Future<void> _deleteInvoice(String id) async {
    try {
      if (_uid == null) return;

      final userRef = _firestore.collection('users').doc(_uid);
      final invoicesRef = userRef.collection('invoices');
      final customersRef = userRef.collection('customers');
      final quotationsRef = userRef.collection('quotations');

      // 1️⃣ Fetch the invoice document
      final invoiceDoc = await invoicesRef.doc(id).get();
      if (!invoiceDoc.exists) {
        _showSnack("❌ Invoice not found");
        return;
      }

      final invoiceData = invoiceDoc.data()!;
      final String customerName = invoiceData['customer_name'] ?? '';
      final double grandTotal = (invoiceData['grand_total'] ?? 0.0).toDouble();
      final String? quotationId = invoiceData['quotation_id'];

      // 2️⃣ If invoice was created from a quotation, reset it back to "Open"
      if (quotationId != null && quotationId.isNotEmpty) {
        final qSnap = await quotationsRef
            .where('id', isEqualTo: quotationId)
            .limit(1)
            .get();

        if (qSnap.docs.isNotEmpty) {
          await qSnap.docs.first.reference.update({'status': 'Open'});
        }
      }

      // 3️⃣ Reduce customer's outstanding balance
      if (customerName.isNotEmpty) {
        final custSnap = await customersRef
            .where('name', isEqualTo: customerName)
            .limit(1)
            .get();

        if (custSnap.docs.isNotEmpty) {
          final custDoc = custSnap.docs.first;
          final currentOutstanding = (custDoc['outstanding'] ?? 0.0).toDouble();
          final newOutstanding = (currentOutstanding - grandTotal).clamp(
            0,
            double.infinity,
          );

          await custDoc.reference.update({'outstanding': newOutstanding});
        }
      }

      // 4️⃣ Delete the invoice
      await invoiceDoc.reference.delete();

      _showSnack('✅ Invoice deleted successfully', success: true);
    } catch (e) {
      _showSnack('❌ Error deleting invoice: $e');
    }
  }

  Future<void> _generatePDF(
    String id,
    Map<String, dynamic> data, {
    bool printDirectly = false,
  }) async {
    try {
      await PdfService.generateAndOpenPDF(
        id,
        cachedData: data,
        printDirectly: printDirectly,
      );
    } catch (e) {
      _showSnack("❌ Failed to generate PDF: $e");
    }
  }

  // ✅ QR Dialog

  Future<void> _addPayment(
    String invoiceId,
    Map<String, dynamic> invoiceData,
  ) async {
    final total = (invoiceData['grand_total'] ?? 0).toDouble();
    final paid = (invoiceData['paid_amount'] ?? 0).toDouble();
    final balance = total - paid;
    final customerName = invoiceData['customer_name'] ?? '';
    final invoiceNumber = invoiceData['invoice_number'] ?? '-';
    final _uid = FirebaseAuth.instance.currentUser?.uid;

    if (_uid == null) {
      _showSnack("❌ User not logged in");
      return;
    }

    final amountCtrl = TextEditingController();
    String paymentMode = "Cash";

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              title: const Text("Add Payment"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Invoice Total: ₹${total.toStringAsFixed(2)}"),
                  Text("Already Paid: ₹${paid.toStringAsFixed(2)}"),
                  Text("Balance Due: ₹${balance.toStringAsFixed(2)}"),
                  const SizedBox(height: 10),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Enter Payment Amount",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: paymentMode,
                    decoration: const InputDecoration(
                      labelText: "Payment Mode",
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: "Cash", child: Text("Cash")),
                      DropdownMenuItem(
                        value: "UPI",
                        child: Text("UPI / QR / Paytm"),
                      ),
                      DropdownMenuItem(
                        value: "Bank Transfer",
                        child: Text("Bank Transfer"),
                      ),
                      DropdownMenuItem(
                        value: "Credit Card",
                        child: Text("Credit Card"),
                      ),
                      DropdownMenuItem(value: "Cheque", child: Text("Cheque")),
                      DropdownMenuItem(value: "Other", child: Text("Other")),
                    ],
                    onChanged: (v) =>
                        setStateDialog(() => paymentMode = v ?? "Cash"),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Cancel"),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text("Save Payment"),
                  onPressed: () async {
                    final entered =
                        double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                    if (entered <= 0) {
                      _showSnack("❌ Enter a valid amount");
                      return;
                    }
                    if (entered > balance) {
                      _showSnack("❌ Payment exceeds balance due");
                      return;
                    }

                    // Compute new values
                    final newPaid = paid + entered;
                    final newBalance = total - newPaid;

                    String status = "Pending";
                    if (newPaid == 0) {
                      status = "Pending";
                    } else if (newPaid < total) {
                      status = "Partially Paid";
                    } else if (newPaid >= total) {
                      status = "Paid";
                    }

                    final now = DateTime.now();
                    final firestore = FirebaseFirestore.instance;
                    final userRef = firestore.collection('users').doc(_uid);
                    final invoiceRef = userRef
                        .collection('invoices')
                        .doc(invoiceId);

                    try {
                      // 🧾 1. Save payment inside invoice’s subcollection
                      await invoiceRef.collection('payments').add({
                        'amount': entered,
                        'payment_mode': paymentMode,
                        'created_at': Timestamp.now(),
                      });

                      // 🧾 2. Save copy in main payments collection (for receipt screen)
                      await userRef.collection('payments').add({
                        'amount': entered,
                        'payment_mode': paymentMode,
                        'created_at': Timestamp.now(),
                        'customer_name': customerName,
                        'invoice_id': invoiceId,
                        'invoice_number': invoiceNumber,
                        'balance_due': newBalance,
                      });

                      // 💰 3. Update invoice totals
                      await invoiceRef.update({
                        'paid_amount': newPaid,
                        'balance_due': newBalance,
                        'status': status,
                        'last_payment_date': now.toIso8601String(),
                      });

                      // 👤 4. Update customer's outstanding
                      final custSnap = await userRef
                          .collection('customers')
                          .where('name', isEqualTo: customerName)
                          .limit(1)
                          .get();

                      if (custSnap.docs.isNotEmpty) {
                        final custDoc = custSnap.docs.first;
                        final currentOutstanding = (custDoc['outstanding'] ?? 0)
                            .toDouble();
                        final newOutstanding = (currentOutstanding - entered)
                            .clamp(0, double.infinity);

                        await custDoc.reference.update({
                          'outstanding': newOutstanding,
                        });
                      }

                      if (ctx.mounted) Navigator.pop(ctx);
                      _showSnack(
                        "✅ Payment added successfully!",
                        success: true,
                      );
                    } catch (e) {
                      _showSnack("❌ Failed to add payment: $e");
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ✅ Edit Invoice Info
  // ✅ Edit Invoice Main Dialog
  Future<void> _openEditInvoiceDialog(
    String id,
    Map<String, dynamic> data,
  ) async {
    final nameCtrl = TextEditingController(text: data['customer_name']);
    final billCtrl = TextEditingController(text: data['billing_address']);
    final shipCtrl = TextEditingController(text: data['shipping_address']);
    final noteCtrl = TextEditingController(text: data['note'] ?? '');
    double gst = (data['gst_percentage'] ?? 18).toDouble();

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                "Edit Invoice",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: "Customer Name",
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) =>
                            v!.trim().isEmpty ? "Enter customer name" : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: billCtrl,
                        decoration: const InputDecoration(
                          labelText: "Billing Address",
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: shipCtrl,
                        decoration: const InputDecoration(
                          labelText: "Shipping Address",
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<double>(
                        value: gst,
                        decoration: const InputDecoration(
                          labelText: "GST Percentage",
                          border: OutlineInputBorder(),
                        ),
                        items: [0, 5, 12, 18, 28]
                            .map(
                              (v) => DropdownMenuItem(
                                value: v.toDouble(),
                                child: Text("$v%"),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setStateDialog(() => gst = v ?? 18),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: noteCtrl,
                        decoration: const InputDecoration(
                          labelText: "Notes (optional)",
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => _openEditItemsDialog(id, data),
                  child: const Text("Edit Items"),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text("Save Changes"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00A3A3),
                  ),
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    try {
                      await _firestore
                          .collection('users')
                          .doc(_uid)
                          .collection('invoices')
                          .doc(id)
                          .update({
                            'customer_name': nameCtrl.text.trim(),
                            'billing_address': billCtrl.text.trim(),
                            'shipping_address': shipCtrl.text.trim(),
                            'note': noteCtrl.text.trim(),
                            'gst_percentage': gst,
                            'updated_at': FieldValue.serverTimestamp(),
                          });
                      if (ctx.mounted) Navigator.pop(ctx);
                      _showSnack(
                        "✅ Invoice updated successfully!",
                        success: true,
                      );
                    } catch (e) {
                      _showSnack("❌ Error updating invoice: $e");
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openEditItemsDialog(
    String invoiceId,
    Map<String, dynamic> invoiceData,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);
    List<Map<String, dynamic>> items = List<Map<String, dynamic>>.from(
      invoiceData['items'] ?? [],
    );
    double total = (invoiceData['grand_total'] ?? 0).toDouble();
    final double oldTotal = total;
    final customerName = invoiceData['customer_name'] ?? '';

    final productCtrl = TextEditingController();
    final rateCtrl = TextEditingController();
    List<Map<String, dynamic>> allProducts = [];

    try {
      final snap = await userRef.collection('products').get();
      allProducts = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (e) {
      debugPrint("⚠️ Error loading products: $e");
    }

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            void recalc() {
              total = items.fold(
                0.0,
                (sum, i) => sum + ((i['qty'] ?? 1) * (i['rate'] ?? 0)),
              );
              setStateDialog(() {});
            }

            Future<void> addItem(String name, double rate) async {
              if (name.isEmpty || rate <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("⚠️ Enter valid product and rate"),
                  ),
                );
                return;
              }

              items.add({'item': name, 'qty': 1.0, 'rate': rate});
              recalc();

              // Add product to database if not exists
              final exists = allProducts.any(
                (p) =>
                    (p['name'] ?? '').toString().toLowerCase() ==
                    name.toLowerCase(),
              );
              if (!exists) {
                try {
                  final doc = await userRef.collection('products').add({
                    'name': name,
                    'rate': rate,
                    'created_at': FieldValue.serverTimestamp(),
                  });
                  allProducts.add({'id': doc.id, 'name': name, 'rate': rate});
                } catch (e) {
                  debugPrint("❌ Error adding new product: $e");
                }
              }

              productCtrl.clear();
              rateCtrl.clear();
            }

            return Dialog.fullscreen(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Scaffold(
                  backgroundColor: Colors.grey.shade100,
                  appBar: AppBar(
                    backgroundColor: const Color(0xFF1F3A5F),
                    foregroundColor: Colors.white,
                    title: const Text("Edit Invoice Items"),
                    centerTitle: true,
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  body: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // --- Product Add Row ---
                          Row(
                            children: [
                              Expanded(
                                flex: 4,
                                child: Autocomplete<Map<String, dynamic>>(
                                  displayStringForOption: (p) =>
                                      p['name'] ?? '',
                                  optionsBuilder: (text) {
                                    if (text.text.isEmpty)
                                      return const Iterable.empty();
                                    return allProducts.where(
                                      (p) => (p['name'] ?? '')
                                          .toLowerCase()
                                          .contains(text.text.toLowerCase()),
                                    );
                                  },
                                  onSelected: (selected) {
                                    productCtrl.text = selected['name'] ?? '';
                                    rateCtrl.text = (selected['rate'] ?? 0)
                                        .toString();
                                  },
                                  fieldViewBuilder:
                                      (context, controller, node, onSubmit) {
                                        controller.text = productCtrl.text;
                                        return TextField(
                                          controller: controller,
                                          focusNode: node,
                                          decoration: InputDecoration(
                                            labelText: "Product",
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            prefixIcon: const Icon(
                                              Icons.shopping_bag_outlined,
                                            ),
                                          ),
                                          onChanged: (v) =>
                                              productCtrl.text = v,
                                        );
                                      },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: rateCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: "Rate (₹)",
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton(
                                onPressed: () async {
                                  final name = productCtrl.text.trim();
                                  final rate =
                                      double.tryParse(rateCtrl.text.trim()) ??
                                      0.0;
                                  await addItem(name, rate);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1F3A5F),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  minimumSize: const Size(65, 58),
                                ),
                                child: const Icon(Icons.add, size: 26),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),
                          const Divider(),

                          // --- Item List ---
                          Expanded(
                            child: ListView.builder(
                              itemCount: items.length,
                              itemBuilder: (context, index) {
                                final i = items[index];
                                final qtyCtrl = TextEditingController(
                                  text: (i['qty'] ?? 1).toString(),
                                );
                                final rateCtrlItem = TextEditingController(
                                  text: (i['rate'] ?? 0).toString(),
                                );
                                final amount =
                                    (i['qty'] ?? 1.0) * (i['rate'] ?? 0.0);

                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  elevation: 3,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                i['item'] ?? 'Unnamed',
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.delete_outline,
                                                color: Colors.redAccent,
                                                size: 22,
                                              ),
                                              onPressed: () {
                                                items.removeAt(index);
                                                recalc();
                                              },
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),

                                        // --- Qty + Rate + Amount ---
                                        // --- Qty + Rate + Amount ---
                                        Row(
                                          children: [
                                            // Qty field
                                            Flexible(
                                              flex: 3,
                                              child: Row(
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons
                                                          .remove_circle_outline,
                                                      color: Colors.redAccent,
                                                      size: 20,
                                                    ),
                                                    onPressed: () {
                                                      double qty =
                                                          double.tryParse(
                                                            qtyCtrl.text,
                                                          ) ??
                                                          1;
                                                      if (qty > 1) {
                                                        qty -= 1;
                                                        qtyCtrl.text = qty
                                                            .toString();
                                                        i['qty'] = qty;
                                                        recalc();
                                                      }
                                                    },
                                                  ),
                                                  SizedBox(
                                                    width:
                                                        MediaQuery.of(
                                                          context,
                                                        ).size.width *
                                                        0.12, // ✅ smaller width
                                                    child: TextField(
                                                      controller: qtyCtrl,
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: const TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                      keyboardType:
                                                          TextInputType.number,
                                                      decoration: const InputDecoration(
                                                        border:
                                                            OutlineInputBorder(),
                                                        contentPadding:
                                                            EdgeInsets.symmetric(
                                                              vertical: 6,
                                                              horizontal: 4,
                                                            ),
                                                      ),
                                                      onChanged: (v) {
                                                        i['qty'] =
                                                            double.tryParse(
                                                              v,
                                                            ) ??
                                                            1.0;
                                                        recalc();
                                                      },
                                                    ),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.add_circle_outline,
                                                      color: Colors.green,
                                                      size: 20,
                                                    ),
                                                    onPressed: () {
                                                      double qty =
                                                          double.tryParse(
                                                            qtyCtrl.text,
                                                          ) ??
                                                          1;
                                                      qty += 1;
                                                      qtyCtrl.text = qty
                                                          .toString();
                                                      i['qty'] = qty;
                                                      recalc();
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 6),

                                            // ✅ Rate field with dynamic size
                                            SizedBox(
                                              width:
                                                  MediaQuery.of(
                                                    context,
                                                  ).size.width *
                                                  0.22,
                                              child: TextField(
                                                controller: rateCtrlItem,
                                                textAlign: TextAlign.center,
                                                keyboardType:
                                                    TextInputType.number,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                ),
                                                decoration:
                                                    const InputDecoration(
                                                      labelText: "Rate (₹)",
                                                      labelStyle: TextStyle(
                                                        fontSize: 11,
                                                      ),
                                                      border:
                                                          OutlineInputBorder(),
                                                      contentPadding:
                                                          EdgeInsets.symmetric(
                                                            vertical: 6,
                                                            horizontal: 6,
                                                          ),
                                                    ),
                                                onChanged: (v) {
                                                  i['rate'] =
                                                      double.tryParse(v) ?? 0.0;
                                                  recalc();
                                                },
                                              ),
                                            ),

                                            const SizedBox(width: 8),

                                            // Amount
                                            Text(
                                              "₹${amount.round()}",
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.teal,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  bottomNavigationBar: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.2),
                          blurRadius: 6,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Total: ₹${total.round()}",
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueAccent,
                          ),
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.save, size: 18),
                          label: const Text(
                            "Save",
                            style: TextStyle(fontSize: 15),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1F3A5F),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () async {
                            if (items.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("⚠️ Add at least one item"),
                                ),
                              );
                              return;
                            }

                            try {
                              await userRef
                                  .collection('invoices')
                                  .doc(invoiceId)
                                  .update({
                                    'items': items,
                                    'grand_total': total,
                                    'subtotal': total,
                                  });

                              // ✅ Update outstanding correctly
                              if (customerName.isNotEmpty) {
                                final custSnap = await userRef
                                    .collection('customers')
                                    .get();
                                QueryDocumentSnapshot<Map<String, dynamic>>?
                                custDoc;

                                for (var doc in custSnap.docs) {
                                  if ((doc['name'] ?? '')
                                          .toString()
                                          .toLowerCase() ==
                                      customerName.toLowerCase()) {
                                    custDoc = doc;
                                    break;
                                  }
                                }

                                if (custDoc != null) {
                                  final currentOutstanding =
                                      (custDoc['outstanding'] ?? 0).toDouble();
                                  final diff = total - oldTotal;
                                  final newOutstanding =
                                      (currentOutstanding + diff).clamp(
                                        0,
                                        double.infinity,
                                      );
                                  await custDoc.reference.update({
                                    'outstanding': newOutstanding,
                                    'updated_at': FieldValue.serverTimestamp(),
                                  });
                                }
                              }

                              if (ctx.mounted) Navigator.pop(ctx);
                              _showSnack(
                                "✅ Items updated successfully!",
                                success: true,
                              );
                            } catch (e) {
                              _showSnack("❌ Error saving: $e");
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ✅ Filter Chips
  Widget _buildFilterChips() {
    final filters = ["All", "Pending", "Paid", "Partially Paid"];
    return Wrap(
      spacing: 8,
      children: filters.map((f) {
        final selected = f == _filterStatus;
        return ChoiceChip(
          label: Text(f),
          selected: selected,
          selectedColor: Colors.blue.shade600,
          backgroundColor: Colors.grey.shade200,
          labelStyle: TextStyle(
            color: selected ? Colors.white : Colors.black87,
          ),
          onSelected: (_) => setState(() => _filterStatus = f),
        );
      }).toList(),
    );
  }

  // ✅ View Invoice Details
  void _viewInvoice(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text("Invoice: ${data['customer_name'] ?? 'Unknown'}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("From: ${data['billing_address'] ?? '-'}"),
            Text("To: ${data['shipping_address'] ?? '-'}"),
            Text("Total: ₹${data['grand_total'] ?? 0}"),
            Text("GST: ${data['gst_percentage'] ?? 0}%"),
            Text("Date: ${_formatTimestamp(data['created_at'])}"),
            Text("Status: ${data['status'] ?? 'Pending'}"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  // ✅ Main UI
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Invoices"),
        centerTitle: true,
        backgroundColor: primary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
              decoration: InputDecoration(
                hintText: "Search by customer name...",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = "");
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primary,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddInvoiceScreen()),
          );
        },
        label: const Text("New Invoice"),
        icon: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _getInvoices(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snapshot.data!.docs.where((doc) {
              final data = doc.data();
              final name = (data['customer_name'] ?? '')
                  .toString()
                  .toLowerCase();
              final status = (data['status'] ?? 'Pending').toString();
              return name.contains(_searchQuery) &&
                  (_filterStatus == "All" || status == _filterStatus);
            }).toList();

            if (docs.isEmpty) {
              return const Center(child: Text("No invoices found."));
            }

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: _buildFilterChips(),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data();
                      final status = (data['status'] ?? 'Pending').toString();

                      Color color;
                      switch (status) {
                        case 'Paid':
                          color = Colors.green;
                          break;
                        case 'Pending':
                          color = Colors.orange;
                          break;
                        case 'Partially Paid':
                          color = Colors.blue;
                          break;
                        default:
                          color = Colors.grey;
                      }

                      return Card(
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(14),
                          leading: CircleAvatar(
                            backgroundColor: color.withOpacity(0.15),
                            child: Icon(
                              Icons.receipt_long_rounded,
                              color: color,
                            ),
                          ),
                          title: Text(
                            data['customer_name'] ?? 'Unnamed Customer',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Date: ${_formatTimestamp(data['created_at'])}",
                              ),
                              Text(
                                "Total: ₹${(data['grand_total'] ?? 0).toStringAsFixed(2)}",
                              ),
                              Text(
                                "Status: $status",
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          trailing: Wrap(
                            spacing: 6,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.print,
                                  color: Colors.blueAccent,
                                ),
                                onPressed: () => _generatePDF(
                                  doc.id,
                                  data,
                                  printDirectly: true,
                                ),
                              ),
                              PopupMenuButton<String>(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                onSelected: (v) async {
                                  switch (v) {
                                    case 'view':
                                      _viewInvoice(data);
                                      break;
                                    case 'edit':
                                      _openEditInvoiceDialog(doc.id, data);
                                      break;
                                    case 'pdf':
                                      _generatePDF(doc.id, data);
                                      break;

                                    case 'pay':
                                      _addPayment(doc.id, data);
                                      break;
                                    case 'challan':
                                      generateDeliveryChallanPDF(data);
                                      break;

                                    case 'delete':
                                      _deleteInvoice(doc.id);
                                      break;
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'view',
                                    child: Text("View"),
                                  ),
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text("Edit"),
                                  ),
                                  PopupMenuItem(
                                    value: 'pdf',
                                    child: Text("Download PDF"),
                                  ),
                                  PopupMenuItem(
                                    value: 'pay',
                                    child: Text("Add Payment"),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text("Delete"),
                                  ),
                                  PopupMenuItem(
                                    value: 'challan',
                                    child: Text("Delivery Challan"),
                                  ),
                                ],
                              ),
                            ],
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
      ),
    );
  }
}
