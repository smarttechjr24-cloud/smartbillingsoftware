import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:smartbilling/screens/add_quotation.dart';
import '../utils/quotation.dart'; // QuotationPdfService

class QuotationsScreen extends StatefulWidget {
  const QuotationsScreen({Key? key}) : super(key: key);

  @override
  State<QuotationsScreen> createState() => _QuotationsScreenState();
}

class _QuotationsScreenState extends State<QuotationsScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _searchController = TextEditingController();

  String _searchQuery = "";
  String _filterStatus = "All";
  String? get _uid => _auth.currentUser?.uid;

  Stream<QuerySnapshot<Map<String, dynamic>>> _getQuotations() {
    if (_uid == null) return const Stream.empty();
    return _firestore
        .collection('users')
        .doc(_uid)
        .collection('quotations')
        .orderBy('created_at', descending: true)
        .snapshots();
  }

  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return '-';
    return DateFormat('dd MMM yyyy, hh:mm a').format(ts.toDate());
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

  Future<void> _deleteQuotation(String id) async {
    try {
      await _firestore
          .collection('users')
          .doc(_uid)
          .collection('quotations')
          .doc(id)
          .delete();
      _showSnack('✅ Quotation deleted successfully', success: true);
    } catch (e) {
      _showSnack('❌ Failed to delete quotation: $e');
    }
  }

  Future<void> _printQuotation(Map<String, dynamic> data, String id) async {
    try {
      if ((data['items'] ?? []).isEmpty) {
        _showSnack("⚠ No items found to print");
        return;
      }
      await QuotationPdfService.generateQuotationPDF(
        id,
        cachedData: data,
        printDirectly: true,
      );
    } catch (e) {
      _showSnack('❌ Failed to print: $e');
    }
  }

  // 🔹 Convert to Invoice Dialog
  Future<void> _openConvertDialog(
    String quoteId,
    Map<String, dynamic> data,
  ) async {
    final formKey = GlobalKey<FormState>();
    final customerCtrl = TextEditingController(text: data['customer_name']);
    final addressCtrl = TextEditingController(text: data['billing_address']);
    List<Map<String, dynamic>> items = List<Map<String, dynamic>>.from(
      (data['items'] ?? []) as List,
    );
    double total = (data['grand_total'] ?? 0).toDouble();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        final padding = size.width * 0.04; // Responsive padding

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final firestore = FirebaseFirestore.instance;
            final uid = FirebaseAuth.instance.currentUser?.uid;

            // 🔹 Recalculate total
            void recalculateTotal() {
              total = items.fold<double>(
                0,
                (sum, i) => sum + ((i['qty'] ?? 1.0) * (i['rate'] ?? 0.0)),
              );
              setStateDialog(() {});
            }

            // 🔹 Add new item
            void addNewItem() {
              items.add({'item': '', 'qty': 1.0, 'rate': 0.0, 'unit': 'Unit'});
              recalculateTotal();
            }

            // 🔹 Product AJAX search
            Timer? debounce;
            Future<void> _ajaxSearchProducts(
              String query,
              Function(List<Map<String, dynamic>>) onResult,
            ) async {
              if (debounce?.isActive ?? false) debounce!.cancel();
              debounce = Timer(const Duration(milliseconds: 300), () async {
                if (query.isEmpty || uid == null) {
                  onResult([]);
                  return;
                }
                try {
                  final snap = await firestore
                      .collection('users')
                      .doc(uid)
                      .collection('products')
                      .where('name', isGreaterThanOrEqualTo: query)
                      .where('name', isLessThanOrEqualTo: '$query\uf8ff')
                      .limit(10)
                      .get();

                  final products = snap.docs
                      .map((d) => {'id': d.id, ...d.data()})
                      .toList();
                  onResult(products);
                } catch (e) {
                  debugPrint("❌ AJAX Search error: $e");
                }
              });
            }

            // 🔹 Ensure product exists
            Future<void> _ensureProductExists(String name, double rate) async {
              if (uid == null || name.trim().isEmpty) return;
              final ref = firestore
                  .collection('users')
                  .doc(uid)
                  .collection('products');
              final exists = await ref
                  .where('name', isEqualTo: name)
                  .limit(1)
                  .get();
              if (exists.docs.isEmpty) {
                await ref.add({
                  'name': name,
                  'rate': rate,
                  'unit': 'Unit',
                  'created_at': FieldValue.serverTimestamp(),
                });
                debugPrint("✅ New product '$name' added.");
              }
            }

            return Dialog.fullscreen(
              child: Scaffold(
                backgroundColor: Colors.grey.shade100,
                appBar: AppBar(
                  title: const Text("Convert Quotation to Invoice"),
                  backgroundColor: Colors.blue.shade800,
                  foregroundColor: Colors.white,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                body: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: padding,
                      vertical: padding / 1.5,
                    ),
                    child: Form(
                      key: formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // --- Customer Info Row ---
                          Row(
                            children: [
                              Expanded(
                                flex: 5,
                                child: TextFormField(
                                  controller: customerCtrl,
                                  decoration: InputDecoration(
                                    labelText: "Customer Name",
                                    prefixIcon: const Icon(
                                      Icons.person_outline,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  validator: (v) => v == null || v.isEmpty
                                      ? 'Customer name required'
                                      : null,
                                ),
                              ),
                              SizedBox(width: size.width * 0.03),
                              Expanded(
                                flex: 5,
                                child: TextFormField(
                                  controller: addressCtrl,
                                  maxLines: 2,
                                  decoration: InputDecoration(
                                    labelText: "Billing Address",
                                    prefixIcon: const Icon(Icons.location_on),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          SizedBox(height: size.height * 0.02),

                          // --- Items Header ---
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "Items",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: addNewItem,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: size.width * 0.03,
                                    vertical: size.height * 0.012,
                                  ),
                                ),
                                icon: const Icon(Icons.add),
                                label: const Text("Add Item"),
                              ),
                            ],
                          ),
                          SizedBox(height: size.height * 0.015),

                          // --- Dynamic Item List ---
                          Expanded(
                            child: ListView.builder(
                              itemCount: items.length,
                              itemBuilder: (context, idx) {
                                final item = items[idx];
                                final nameCtrl = TextEditingController(
                                  text: item['item'],
                                );
                                final qtyCtrl = TextEditingController(
                                  text: (item['qty'] ?? 1).toString(),
                                );
                                final rateCtrl = TextEditingController(
                                  text: (item['rate'] ?? 0).toString(),
                                );

                                List<Map<String, dynamic>> suggestions = [];

                                return StatefulBuilder(
                                  builder: (context, setLocal) {
                                    return Card(
                                      margin: EdgeInsets.symmetric(
                                        vertical: size.height * 0.01,
                                      ),
                                      elevation: 2,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Padding(
                                        padding: EdgeInsets.all(
                                          size.width * 0.03,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // --- Item Name with AJAX Suggestions ---
                                            TextFormField(
                                              controller: nameCtrl,
                                              decoration: const InputDecoration(
                                                labelText: "Item Name",
                                                border: OutlineInputBorder(),
                                              ),
                                              onChanged: (v) {
                                                item['item'] = v;
                                                if (v.trim().length > 1) {
                                                  _ajaxSearchProducts(
                                                    v,
                                                    (res) => setLocal(() {
                                                      suggestions = res;
                                                    }),
                                                  );
                                                } else {
                                                  setLocal(
                                                    () => suggestions.clear(),
                                                  );
                                                }
                                              },
                                            ),
                                            if (suggestions.isNotEmpty)
                                              Container(
                                                margin: const EdgeInsets.only(
                                                  top: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade50,
                                                  border: Border.all(
                                                    color: Colors.grey.shade300,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Column(
                                                  children: suggestions
                                                      .map(
                                                        (p) => ListTile(
                                                          dense: true,
                                                          title: Text(
                                                            p['name'],
                                                          ),
                                                          subtitle: Text(
                                                            "₹${p['rate']} • ${p['unit'] ?? 'Unit'}",
                                                          ),
                                                          onTap: () {
                                                            item['item'] =
                                                                p['name'];
                                                            item['rate'] =
                                                                (p['rate'] ??
                                                                        0.0)
                                                                    .toDouble();
                                                            nameCtrl.text =
                                                                p['name'];
                                                            rateCtrl.text =
                                                                p['rate']
                                                                    .toString();
                                                            suggestions.clear();
                                                            setLocal(() {});
                                                            recalculateTotal();
                                                          },
                                                        ),
                                                      )
                                                      .toList(),
                                                ),
                                              ),
                                            SizedBox(
                                              height: size.height * 0.012,
                                            ),

                                            // --- Editable Qty & Rate ---
                                            Row(
                                              children: [
                                                // Qty
                                                Flexible(
                                                  flex: 4,
                                                  child: Row(
                                                    children: [
                                                      IconButton(
                                                        icon: const Icon(
                                                          Icons.remove_circle,
                                                          color:
                                                              Colors.redAccent,
                                                        ),
                                                        onPressed: () {
                                                          double current =
                                                              double.tryParse(
                                                                qtyCtrl.text,
                                                              ) ??
                                                              1;
                                                          if (current > 1) {
                                                            current -= 1;
                                                            qtyCtrl.text =
                                                                current
                                                                    .toString();
                                                            item['qty'] =
                                                                current;
                                                            recalculateTotal();
                                                          }
                                                        },
                                                      ),
                                                      Expanded(
                                                        child: TextFormField(
                                                          controller: qtyCtrl,
                                                          textAlign:
                                                              TextAlign.center,
                                                          keyboardType:
                                                              TextInputType
                                                                  .number,
                                                          decoration:
                                                              const InputDecoration(
                                                                labelText:
                                                                    "Qty",
                                                                border:
                                                                    OutlineInputBorder(),
                                                              ),
                                                          onChanged: (v) {
                                                            item['qty'] =
                                                                double.tryParse(
                                                                  v,
                                                                ) ??
                                                                1;
                                                            recalculateTotal();
                                                          },
                                                        ),
                                                      ),
                                                      IconButton(
                                                        icon: const Icon(
                                                          Icons.add_circle,
                                                          color: Colors.green,
                                                        ),
                                                        onPressed: () {
                                                          double current =
                                                              double.tryParse(
                                                                qtyCtrl.text,
                                                              ) ??
                                                              1;
                                                          current += 1;
                                                          qtyCtrl.text = current
                                                              .toString();
                                                          item['qty'] = current;
                                                          recalculateTotal();
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                SizedBox(
                                                  width: size.width * 0.02,
                                                ),
                                                // Rate
                                                Flexible(
                                                  flex: 4,
                                                  child: TextFormField(
                                                    controller: rateCtrl,
                                                    textAlign: TextAlign.center,
                                                    keyboardType:
                                                        TextInputType.number,
                                                    decoration:
                                                        const InputDecoration(
                                                          labelText: "Rate (₹)",
                                                          border:
                                                              OutlineInputBorder(),
                                                        ),
                                                    onChanged: (v) {
                                                      item['rate'] =
                                                          double.tryParse(v) ??
                                                          0.0;
                                                      recalculateTotal();
                                                    },
                                                    onEditingComplete: () {
                                                      _ensureProductExists(
                                                        nameCtrl.text,
                                                        double.tryParse(
                                                              rateCtrl.text,
                                                            ) ??
                                                            0.0,
                                                      );
                                                    },
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.delete_outline,
                                                    color: Colors.redAccent,
                                                  ),
                                                  onPressed: () {
                                                    items.removeAt(idx);
                                                    recalculateTotal();
                                                  },
                                                ),
                                              ],
                                            ),
                                            SizedBox(
                                              height: size.height * 0.008,
                                            ),
                                            Align(
                                              alignment: Alignment.centerRight,
                                              child: Text(
                                                "Subtotal: ₹${((item['qty'] ?? 0) * (item['rate'] ?? 0)).toStringAsFixed(2)}",
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.teal,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),

                          // --- Total Section ---
                          SizedBox(height: size.height * 0.012),
                          Container(
                            padding: EdgeInsets.all(size.width * 0.04),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.blueAccent),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "Total Amount:",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  "₹${total.toStringAsFixed(2)}",
                                  style: const TextStyle(
                                    fontSize: 20,
                                    color: Colors.blueAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: size.height * 0.015),

                          // --- Action Buttons ---
                          Align(
                            alignment: Alignment.centerRight,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text("Cancel"),
                                ),
                                SizedBox(width: size.width * 0.02),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text("Convert to Invoice"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blueAccent,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: size.width * 0.04,
                                      vertical: size.height * 0.015,
                                    ),
                                  ),
                                  onPressed: () async {
                                    if (!formKey.currentState!.validate())
                                      return;
                                    await _convertToInvoice(quoteId, {
                                      ...data,
                                      'customer_name': customerCtrl.text.trim(),
                                      'billing_address': addressCtrl.text
                                          .trim(),
                                      'items': items,
                                      'grand_total': total,
                                    });
                                    if (ctx.mounted) Navigator.pop(ctx);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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

  // 🔹 Convert Function - FIXED
  Future<void> _convertToInvoice(
    String quoteId,
    Map<String, dynamic> data,
  ) async {
    try {
      final uid = _uid;
      if (uid == null) return;

      final invoicesRef = _firestore
          .collection('users')
          .doc(uid)
          .collection('invoices');

      final customersRef = _firestore
          .collection('users')
          .doc(uid)
          .collection('customers');

      final quotationRef = _firestore
          .collection('users')
          .doc(uid)
          .collection('quotations')
          .doc(quoteId);

      final newInvoiceRef = invoicesRef.doc();
      final invoiceId = newInvoiceRef.id;

      final double grandTotal = (data['grand_total'] ?? 0).toDouble();
      final customerName = data['customer_name'] ?? 'Unknown';

      await newInvoiceRef.set({
        ...data,
        'id': invoiceId,
        'status': 'Pending',
        'quotation_id': quoteId,
        'created_at': FieldValue.serverTimestamp(),
      });

      // ✅ Update Quotation Status
      await quotationRef.update({'status': 'Converted'});

      // ✅ Update Customer Outstanding
      final customersQuery = await customersRef
          .where('name', isEqualTo: customerName)
          .limit(1)
          .get();

      if (customersQuery.docs.isNotEmpty) {
        final customerDoc = customersQuery.docs.first;
        final currentOutstanding = (customerDoc.data()['outstanding'] ?? 0)
            .toDouble();

        await customerDoc.reference.update({
          'outstanding': currentOutstanding + grandTotal,
        });
      } else {
        await customersRef.add({
          'name': customerName,
          'outstanding': grandTotal,
          'created_at': FieldValue.serverTimestamp(),
        });
      }

      _showSnack('✅ Quotation converted to Invoice!', success: true);
    } catch (e) {
      _showSnack('❌ Conversion failed: $e');
    }
  }

  Future<void> _updateQuotation(
    String quoteId,
    Map<String, dynamic> updatedData,
  ) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      final docRef = _firestore
          .collection('users')
          .doc(uid)
          .collection('quotations')
          .doc(quoteId);

      // Safely calculate subtotal and GST
      final subtotal =
          (updatedData['items'] as List?)?.fold<double>(
            0,
            (sum, i) =>
                sum +
                ((i['qty'] ?? 0).toDouble() * (i['rate'] ?? 0).toDouble()),
          ) ??
          0.0;

      final gstPercentage = (updatedData['gst_percentage'] ?? 0).toDouble();
      final gstAmount = subtotal * (gstPercentage / 100);
      final grandTotal = subtotal + gstAmount;

      await docRef.update({
        'customer_name': updatedData['customer_name'],
        'billing_address': updatedData['billing_address'],
        'items': updatedData['items'],
        'subtotal': subtotal,
        'gst_percentage': gstPercentage,
        'gst_amount': gstAmount,
        'grand_total': grandTotal,
        'updated_at': FieldValue.serverTimestamp(),
        'status': updatedData['status'] ?? 'Draft',
      });

      _showSnack("✅ Quotation updated successfully!", success: true);
    } catch (e) {
      _showSnack("❌ Failed to update quotation: $e");
    }
  }

  Future<void> _openEditDialog(
    String quoteId,
    Map<String, dynamic> data,
  ) async {
    final formKey = GlobalKey<FormState>();
    final customerCtrl = TextEditingController(text: data['customer_name']);
    final addressCtrl = TextEditingController(text: data['billing_address']);
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final userRef = _firestore.collection('users').doc(uid);

    // Fetch product list once (cache)
    List<Map<String, dynamic>> products = [];
    try {
      final snap = await userRef.collection('products').get();
      products = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (e) {
      debugPrint("⚠️ Product load error: $e");
    }

    // Convert Firestore list safely
    List<Map<String, dynamic>> items =
        (data['items'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        [];

    double total = (data['grand_total'] ?? 0).toDouble();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            void recalcTotal() {
              total = items.fold<double>(
                0,
                (sum, i) =>
                    sum +
                    ((i['qty'] ?? 1).toDouble() * (i['rate'] ?? 0).toDouble()),
              );
              setStateDialog(() {});
            }

            Future<void> addProduct(String name, double rate) async {
              // Check if product already exists
              final exists = products.any(
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
                  products.add({'id': doc.id, 'name': name, 'rate': rate});
                  debugPrint("✅ Added new product '$name'");
                } catch (e) {
                  debugPrint("❌ Failed to save new product: $e");
                }
              }
            }

            void addItem() {
              items.add({'item': '', 'qty': 1.0, 'rate': 0.0});
              recalcTotal();
            }

            return Dialog.fullscreen(
              child: Scaffold(
                backgroundColor: Colors.grey.shade100,
                appBar: AppBar(
                  backgroundColor: Color(0xFF1F3A5F),
                  title: const Text("Edit Quotation"),
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
                    child: Form(
                      key: formKey,
                      child: Column(
                        children: [
                          // 🟠 Customer info
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: customerCtrl,
                                  decoration: const InputDecoration(
                                    labelText: "Customer Name",
                                    prefixIcon: Icon(Icons.person_outline),
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: (v) => v == null || v.isEmpty
                                      ? "Customer name required"
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 3,
                                child: TextFormField(
                                  controller: addressCtrl,
                                  maxLines: 2,
                                  decoration: const InputDecoration(
                                    labelText: "Billing Address",
                                    prefixIcon: Icon(
                                      Icons.location_on_outlined,
                                    ),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // 🟠 Items header
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "Items",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.add),
                                label: const Text("Add Item"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: addItem,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // 🟠 Item list
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                children: items.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final item = entry.value;

                                  final qtyCtrl = TextEditingController(
                                    text: ((item['qty'] ?? 1).toDouble())
                                        .toString(),
                                  );
                                  final rateCtrl = TextEditingController(
                                    text: ((item['rate'] ?? 0).toDouble())
                                        .toStringAsFixed(2),
                                  );

                                  return Card(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 6,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    elevation: 2,
                                    child: Padding(
                                      padding: const EdgeInsets.all(12.0),
                                      child: Column(
                                        children: [
                                          // 🟢 Autocomplete Product Field
                                          Row(
                                            children: [
                                              Expanded(
                                                flex: 5,
                                                child: Autocomplete<Map<String, dynamic>>(
                                                  displayStringForOption: (p) =>
                                                      p['name'] ?? '',
                                                  optionsBuilder: (text) {
                                                    if (text.text.isEmpty) {
                                                      return const Iterable.empty();
                                                    }
                                                    final query = text.text
                                                        .toLowerCase();
                                                    return products.where(
                                                      (p) => (p['name'] ?? '')
                                                          .toString()
                                                          .toLowerCase()
                                                          .contains(query),
                                                    );
                                                  },
                                                  fieldViewBuilder:
                                                      (
                                                        context,
                                                        controller,
                                                        node,
                                                        onSubmit,
                                                      ) {
                                                        controller.text =
                                                            item['item'] ?? '';
                                                        return TextField(
                                                          controller:
                                                              controller,
                                                          focusNode: node,
                                                          decoration: const InputDecoration(
                                                            labelText:
                                                                "Search or Add Item",
                                                            border:
                                                                OutlineInputBorder(),
                                                          ),
                                                          onChanged: (v) =>
                                                              item['item'] = v,
                                                        );
                                                      },
                                                  onSelected: (selected) {
                                                    item['item'] =
                                                        selected['name'] ?? '';
                                                    item['rate'] =
                                                        (selected['rate'] ?? 0)
                                                            .toDouble();
                                                    rateCtrl.text =
                                                        (selected['rate'] ?? 0)
                                                            .toStringAsFixed(2);
                                                    recalcTotal();
                                                  },
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.delete,
                                                  color: Colors.redAccent,
                                                ),
                                                onPressed: () {
                                                  items.removeAt(index);
                                                  recalcTotal();
                                                },
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: TextField(
                                                  controller: qtyCtrl,
                                                  keyboardType:
                                                      TextInputType.number,
                                                  decoration:
                                                      const InputDecoration(
                                                        labelText: "Qty",
                                                        border:
                                                            OutlineInputBorder(),
                                                      ),
                                                  onChanged: (v) {
                                                    final val =
                                                        double.tryParse(v) ??
                                                        1.0;
                                                    item['qty'] = val;
                                                    recalcTotal();
                                                  },
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: TextField(
                                                  controller: rateCtrl,
                                                  keyboardType:
                                                      TextInputType.number,
                                                  decoration:
                                                      const InputDecoration(
                                                        labelText: "Rate (₹)",
                                                        border:
                                                            OutlineInputBorder(),
                                                      ),
                                                  onChanged: (v) async {
                                                    final val =
                                                        double.tryParse(v) ??
                                                        0.0;
                                                    item['rate'] = val;
                                                    await addProduct(
                                                      item['item'] ?? '',
                                                      val,
                                                    ); // ✅ Add to DB if new
                                                    recalcTotal();
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),

                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.orangeAccent),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "Total:",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                Text(
                                  "₹${total.toStringAsFixed(2)}",
                                  style: TextStyle(
                                    color: Colors.orange.shade800,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 15),

                          // Save/Cancel
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text("Cancel"),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.save),
                                label: const Text("Save Changes"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Color(0xFF1F3A5F),
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () async {
                                  if (!formKey.currentState!.validate()) return;
                                  await _updateQuotation(quoteId, {
                                    'customer_name': customerCtrl.text.trim(),
                                    'billing_address': addressCtrl.text.trim(),
                                    'items': items,
                                    'grand_total': total,
                                  });
                                  if (ctx.mounted) Navigator.pop(ctx);
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
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

  // Other methods remain the same...
  @override
  Widget build(BuildContext context) {
    // ... Full build method
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Quotations"),
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
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddQuotationScreen()),
          );
          setState(() {}); // refresh after adding
        },
        label: const Text("New Quotation"),
        icon: const Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _getQuotations(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs.where((doc) {
            final data = doc.data();
            final name = (data['customer_name'] ?? '').toString().toLowerCase();
            final status = (data['status'] ?? 'Open').toString();
            return name.contains(_searchQuery) &&
                (_filterStatus == "All" || status == _filterStatus);
          }).toList();

          if (docs.isEmpty) {
            return const Center(child: Text("No quotations found."));
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
                    final status = (data['status'] ?? 'Open').toString();

                    Color color;
                    switch (status) {
                      case 'Converted':
                        color = Colors.purple;
                        break;
                      case 'Open':
                      default:
                        color = Colors.orange;
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
                          child: Icon(Icons.description_rounded, color: color),
                        ),
                        title: Text(
                          data['customer_name'] ?? 'Unnamed Customer',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Date: ${_formatTimestamp(data['created_at'] as Timestamp?)}",
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
                              icon: const Icon(Icons.print, color: Colors.blue),
                              onPressed: () => _printQuotation(data, doc.id),
                            ),
                            PopupMenuButton<String>(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              onSelected: (v) async {
                                switch (v) {
                                  case 'edit':
                                    // You would call _openEditDialog here
                                    _openEditDialog(doc.id, data);

                                    break;
                                  case 'convert':
                                    _openConvertDialog(doc.id, data);
                                    break;
                                  case 'delete':
                                    _deleteQuotation(doc.id);
                                    break;
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text("Edit"),
                                ),
                                PopupMenuItem(
                                  value: 'convert',
                                  child: Text("Convert"),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text("Delete"),
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
    );
  }

  Widget _buildFilterChips() {
    final filters = ["All", "Open", "Converted"];
    return Wrap(
      spacing: 8,
      children: filters.map((f) {
        final selected = f == _filterStatus;
        return ChoiceChip(
          label: Text(f),
          selected: selected,
          selectedColor: Colors.blue.shade700,
          backgroundColor: Colors.grey.shade200,
          labelStyle: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w500,
          ),
          onSelected: (_) => setState(() => _filterStatus = f),
        );
      }).toList(),
    );
  }
}
