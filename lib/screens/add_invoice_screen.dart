import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:smartbilling/main.dart';
import 'package:smartbilling/screens/profile_screen.dart';

class AddInvoiceScreen extends StatefulWidget {
  const AddInvoiceScreen({Key? key}) : super(key: key);

  @override
  State<AddInvoiceScreen> createState() => _AddInvoiceScreenState();
}

class _AddInvoiceScreenState extends State<AddInvoiceScreen> {
  final _formKey = GlobalKey<FormState>();

  // Customer fields
  final _customerController = TextEditingController();
  final _mobileController = TextEditingController();
  final _fromController = TextEditingController();
  final _toController = TextEditingController();
  final _noteController = TextEditingController();
  final _gstController = TextEditingController(text: "5");

  // Suggestions
  List<String> _customerSuggestions = [];
  List<Map<String, dynamic>> _productSuggestions = [];

  // Items and totals
  List<Map<String, dynamic>> items = [];
  double subtotal = 0.0;
  double gst = 0.0;
  double grandTotal = 0.0;

  var invoiceDate = DateTime.now();
  late DateTime dueDate;
  String _dueTerm = "Net 7"; // default option
  final List<String> _dueOptions = [
    "Net 7",
    "Net 30",
    "Net 60",
    "No Due",
    "Custom Date",
  ];

  @override
  void initState() {
    super.initState();
    dueDate = invoiceDate.add(const Duration(days: 7));
  }

  @override
  void dispose() {
    _customerController.dispose();
    _mobileController.dispose();
    _fromController.dispose();
    _toController.dispose();
    _noteController.dispose();
    _gstController.dispose();
    super.dispose();
  }

  void _updateDueDate(String term) {
    setState(() {
      _dueTerm = term;
      switch (term) {
        case "Net 7":
          dueDate = invoiceDate.add(const Duration(days: 7));
          break;
        case "Net 30":
          dueDate = invoiceDate.add(const Duration(days: 30));
          break;
        case "Net 60":
          dueDate = invoiceDate.add(const Duration(days: 60));
          break;
        case "No Due":
          dueDate = invoiceDate; // symbolic far future, optional
          break;
        case "Custom Date":
          _pickDueDate();
          break;
      }
    });
  }

  Future<void> _pickInvoiceDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: invoiceDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        // Adjust due date relative to new invoice date if term is Net 7/30/60
        final diff = dueDate.difference(invoiceDate).inDays;
        invoiceDate = picked;
        if (_dueTerm.startsWith("Net")) {
          final days =
              int.tryParse(_dueTerm.replaceAll(RegExp(r'\D'), "")) ?? 7;
          dueDate = picked.add(Duration(days: days));
        } else if (_dueTerm == "Custom Date") {
          // keep custom as is
        }
      });
    }
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: dueDate,
      firstDate: invoiceDate,
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        dueDate = picked;
        _dueTerm = "Custom Date";
      });
    }
  }

  // -------------------------------------------------------------
  // AJAX-like search
  // -------------------------------------------------------------
  Future<void> _searchCustomers(String query) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || query.trim().isEmpty) {
      setState(() => _customerSuggestions = []);
      return;
    }
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('customers')
        .where('name', isGreaterThanOrEqualTo: query)
        .where('name', isLessThanOrEqualTo: '$query\uf8ff')
        .limit(8)
        .get();

    setState(() {
      _customerSuggestions = snap.docs
          .map((d) => (d['name'] as String?) ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    });
  }

  Widget _buildNavButton({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: selected ? Colors.blue.shade100 : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 26,
              color: selected ? Colors.blue : Colors.black54,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.blue : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _searchProducts(String query) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || query.trim().isEmpty) {
      setState(() => _productSuggestions = []);
      return;
    }
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('products')
        .where('name', isGreaterThanOrEqualTo: query)
        .where('name', isLessThanOrEqualTo: '$query\uf8ff')
        .limit(8)
        .get();

    setState(() {
      _productSuggestions = snap.docs.map((d) {
        final data = d.data();
        return {
          'id': d.id,
          'name': data['name'] ?? '',
          'rate': (data['rate'] ?? 0).toDouble(),
          'unit': data['unit'] ?? 'Unit',
        };
      }).toList();
    });
  }

  // -------------------------------------------------------------
  // Add item dialog with validation + product auto-create
  // -------------------------------------------------------------
  Future<void> _openAddItemDialog({
    Map<String, dynamic>? existingItem,
    int? index,
  }) async {
    final itemCtrl = TextEditingController(text: existingItem?['item'] ?? '');
    final qtyCtrl = TextEditingController(
      text: (existingItem?['qty']?.toString() ?? '1'),
    );
    final rateCtrl = TextEditingController(
      text: (existingItem?['rate']?.toString() ?? ''),
    );
    String? selectedUnit = existingItem?['unit'];
    String taxType = existingItem?['tax_type'] ?? "Without Tax";
    final formKey = GlobalKey<FormState>();

    List<Map<String, dynamic>> productSuggestions = [];
    Timer? _debounce;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    final firestore = FirebaseFirestore.instance;

    Future<void> _ajaxSearchProducts(String query, Function setSB) async {
      if (_debounce?.isActive ?? false) _debounce!.cancel();

      _debounce = Timer(const Duration(milliseconds: 400), () async {
        if (query.trim().isEmpty || uid == null) {
          setSB(() => productSuggestions = []);
          return;
        }

        try {
          final result = await firestore
              .collection('users')
              .doc(uid)
              .collection('products')
              .where('name', isGreaterThanOrEqualTo: query)
              .where('name', isLessThanOrEqualTo: '$query\uf8ff')
              .limit(10)
              .get();

          setSB(() {
            productSuggestions = result.docs.map((d) => d.data()).toList();
          });
        } catch (e) {
          debugPrint("❌ AJAX Search error: $e");
        }
      });
    }

    Future<void> _ensureProductExists({
      required String name,
      required double rate,
      required String unit,
    }) async {
      if (uid == null) return;

      try {
        final query = await firestore
            .collection('users')
            .doc(uid)
            .collection('products')
            .where('name', isEqualTo: name)
            .limit(1)
            .get();

        if (query.docs.isEmpty) {
          await firestore
              .collection('users')
              .doc(uid)
              .collection('products')
              .add({
                'name': name,
                'rate': rate,
                'unit': unit,
                'created_at': FieldValue.serverTimestamp(),
              });
          debugPrint("✅ Product '$name' added to Firestore");
        }
      } catch (e) {
        debugPrint("⚠️ Error saving product: $e");
      }
    }

    await showDialog(
      context: context,
      builder: (context) {
        final size = MediaQuery.of(context).size;
        final dialogWidth = size.width * 0.92;
        final dialogHeight = size.height * 0.68;

        return StatefulBuilder(
          builder: (context, setSB) {
            void applySuggestion(Map<String, dynamic> p) {
              itemCtrl.text = p['name'] ?? '';
              rateCtrl.text = (p['rate'] ?? 0).toString();
              selectedUnit = p['unit'] ?? 'Unit';
              setSB(() => productSuggestions.clear());
            }

            Future<void> handleSave({bool andNew = false}) async {
              if (!formKey.currentState!.validate()) return;

              final qty = double.tryParse(qtyCtrl.text) ?? 0;
              final rate = double.tryParse(rateCtrl.text) ?? 0;

              // 🧠 Auto-create product in Firestore
              await _ensureProductExists(
                name: itemCtrl.text.trim(),
                rate: rate,
                unit: selectedUnit ?? 'Unit',
              );

              final newItem = {
                'item': itemCtrl.text.trim(),
                'qty': qty,
                'rate': rate,
                'unit': selectedUnit ?? "Unit",
                'tax_type': taxType,
                'lineTotal': qty * rate,
              };

              // 🧩 Update main list
              setState(() {
                if (index != null && existingItem != null) {
                  items[index] = newItem;
                } else {
                  items.add(newItem);
                }
                _recalculateTotals();
              });

              if (andNew) {
                itemCtrl.clear();
                qtyCtrl.text = '1';
                rateCtrl.clear();
                selectedUnit = null;
                setSB(() => productSuggestions.clear());
              } else {
                Navigator.pop(context);
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              title: Text(
                existingItem != null ? "Edit Item" : "Add New Item",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: dialogWidth,
                height: dialogHeight,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // 🧠 Product AJAX Search
                        TextFormField(
                          controller: itemCtrl,
                          decoration: const InputDecoration(
                            labelText: "Item Name",
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => _ajaxSearchProducts(v, setSB),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Item required'
                              : null,
                        ),

                        // 🔹 Dynamic suggestion box
                        if (productSuggestions.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: productSuggestions.map((p) {
                                return ListTile(
                                  dense: true,
                                  title: Text(p['name']),
                                  subtitle: Text(
                                    "₹${(p['rate'] ?? 0).toStringAsFixed(2)} • ${p['unit'] ?? 'Unit'}",
                                  ),
                                  onTap: () => applySuggestion(p),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),

                        // Quantity + Unit
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: qtyCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: "Quantity",
                                  border: OutlineInputBorder(),
                                ),
                                validator: (v) {
                                  final n = double.tryParse(v ?? '');
                                  if (n == null || n <= 0) return 'Qty > 0';
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: selectedUnit,
                                items: const [
                                  DropdownMenuItem(
                                    value: 'Unit',
                                    child: Text('Unit'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Kg',
                                    child: Text('Kg'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Piece',
                                    child: Text('Piece'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Dozen',
                                    child: Text('Dozen'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Litre',
                                    child: Text('Litre'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Box',
                                    child: Text('Box'),
                                  ),
                                ],
                                onChanged: (v) => setSB(() => selectedUnit = v),
                                decoration: const InputDecoration(
                                  labelText: "Unit",
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Rate + Tax
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: rateCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: "Rate (₹)",
                                  border: OutlineInputBorder(),
                                ),
                                validator: (v) {
                                  final n = double.tryParse(v ?? '');
                                  if (n == null || n <= 0) return 'Rate > 0';
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: taxType,
                                items: const [
                                  DropdownMenuItem(
                                    value: "Without Tax",
                                    child: Text("Without Tax"),
                                  ),
                                  DropdownMenuItem(
                                    value: "Inclusive",
                                    child: Text("Inclusive"),
                                  ),
                                  DropdownMenuItem(
                                    value: "Exclusive",
                                    child: Text("Exclusive"),
                                  ),
                                ],
                                onChanged: (v) =>
                                    setSB(() => taxType = v ?? "Without Tax"),
                                decoration: const InputDecoration(
                                  labelText: "Tax Type",
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => handleSave(andNew: true),
                        child: const Text("Save & New"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => handleSave(andNew: false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                        ),
                        child: const Text("Save Item"),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _ensureProductExists({
    required String name,
    required double rate,
    required String unit,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || name.isEmpty) return;

    final productsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('products');

    final existing = await productsRef
        .where('name', isEqualTo: name)
        .limit(1)
        .get();
    if (existing.docs.isEmpty) {
      await productsRef.add({
        'name': name,
        'rate': rate,
        'unit': unit,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
    } else {
      // Optionally update rate/unit if changed
      final doc = existing.docs.first;
      final data = doc.data();
      final oldRate = (data['rate'] ?? 0).toDouble();
      final oldUnit = data['unit'] ?? 'Unit';
      if (oldRate != rate || oldUnit != unit) {
        await doc.reference.update({
          'rate': rate,
          'unit': unit,
          'updated_at': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  void _removeItem(int index) {
    setState(() {
      items.removeAt(index);
      _recalculateTotals();
    });
  }

  void _recalculateTotals() {
    subtotal = items.fold(
      0.0,
      (sum, i) => sum + ((i['lineTotal'] ?? 0.0) as double),
    );
    final gstPercent = double.tryParse(_gstController.text) ?? 0;
    gst = subtotal * gstPercent / 100;
    grandTotal = subtotal + gst;
    setState(() {});
  }

  // -------------------------------------------------------------
  // Save invoice with checks and outstanding
  // -------------------------------------------------------------
  Future<void> _saveInvoice() async {
    // Form-level checks
    if (!_formKey.currentState!.validate()) return;

    // Business rules
    if (_customerController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Customer name is required")),
      );
      return;
    }
    if (items.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Add at least one item")));
      return;
    }
    // Prevent any zero-price items (double safety)
    final hasZero = items.any(
      (i) => (i['rate'] ?? 0) <= 0 || (i['lineTotal'] ?? 0) <= 0,
    );
    if (hasZero) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Items with zero price are not allowed")),
      );
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("User not logged in")));
        return;
      }

      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final invoicesRef = userRef.collection('invoices');
      final customersRef = userRef.collection('customers');

      // Auto-increment invoice number
      final countSnapshot = await invoicesRef.count().get();
      final nextInvoiceNo = 'INV-${(countSnapshot.count ?? 0) + 1}';

      // Ensure customer exists + update mobile if provided
      final custName = _customerController.text.trim();
      final existingCustomer = await customersRef
          .where('name', isEqualTo: custName)
          .limit(1)
          .get();

      if (existingCustomer.docs.isEmpty) {
        await customersRef.add({
          'name': custName,
          'mobile': _mobileController.text.trim(),
          'outstanding': 0.0,
          'created_at': FieldValue.serverTimestamp(),
        });
      } else {
        final doc = existingCustomer.docs.first;
        // Optional: update mobile if new one given
        if ((_mobileController.text.trim()).isNotEmpty) {
          await doc.reference.update({'mobile': _mobileController.text.trim()});
        }
      }

      // Re-fetch customer to update outstanding
      final customerDoc =
          (await customersRef.where('name', isEqualTo: custName).limit(1).get())
              .docs
              .first;
      final currentOutstanding = (customerDoc['outstanding'] ?? 0).toDouble();
      final newOutstanding = currentOutstanding + grandTotal;

      // Prepare invoice
      final invoiceData = {
        'invoice_number': nextInvoiceNo,
        'customer_name': custName,
        'mobile': _mobileController.text.trim(),
        'billing_address': _fromController.text.trim(),
        'shipping_address': _toController.text.trim(),
        'gst_percentage': double.tryParse(_gstController.text) ?? 0.0,
        'note': _noteController.text.trim(),
        'invoice_date': invoiceDate.toIso8601String(),
        'due_date': dueDate.toIso8601String(),
        'subtotal': subtotal,
        'gst_amount': gst,
        'grand_total': grandTotal,
        'created_at': FieldValue.serverTimestamp(),
        'items': items,
        'status': 'Pending',
        'outstanding_after_invoice': newOutstanding,
      };

      await invoicesRef.add(invoiceData);

      // Update customer's outstanding
      await customerDoc.reference.update({'outstanding': newOutstanding});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green,
          content: Text("✅ Invoice saved successfully: $nextInvoiceNo"),
        ),
      );

      setState(() {
        _customerController.clear();
        _mobileController.clear();
        _fromController.clear();
        _toController.clear();
        _noteController.clear();
        items.clear();
        subtotal = gst = grandTotal = 0.0;
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("❌ Failed to save invoice: $e")));
    }
  }

  // -------------------------------------------------------------
  // UI
  // -------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final df = DateFormat("dd MMM yyyy");

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _pickInvoiceDate,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_today,
                            size: 18,
                            color: Colors.teal,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "Invoice: ${DateFormat('dd MMM yyyy').format(invoiceDate)}",
                            style: theme.textTheme.bodyMedium!.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Icon(
                          Icons.schedule,
                          size: 18,
                          color: Colors.teal,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _dueTerm,
                              items: _dueOptions.map((term) {
                                return DropdownMenuItem(
                                  value: term,
                                  child: Text(
                                    term,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) _updateDueDate(val);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  "Due Date: ${_dueTerm == "No Due" ? df.format(invoiceDate) : DateFormat('dd MMM yyyy').format(dueDate)}",
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
              ),

              const SizedBox(height: 20),

              // Customer Info Card
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 20),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Customer name with suggestions
                      TextFormField(
                        controller: _customerController,
                        decoration: const InputDecoration(
                          labelText: "Customer Name",
                          prefixIcon: Icon(Icons.person),
                        ),
                        onChanged: _searchCustomers,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Customer required'
                            : null,
                      ),
                      if (_customerSuggestions.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: _customerSuggestions.map((name) {
                              return ListTile(
                                dense: true,
                                title: Text(name),
                                onTap: () {
                                  _customerController.text = name;
                                  setState(() => _customerSuggestions = []);
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _mobileController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: "Mobile Number",
                          prefixIcon: Icon(Icons.phone),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _fromController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: "From (Address)",
                          prefixIcon: Icon(Icons.home_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _toController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: "To (Address)",
                          prefixIcon: Icon(Icons.location_on_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Items Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Invoice Items",
                    style: theme.textTheme.titleMedium!.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _openAddItemDialog,
                    icon: const Icon(Icons.add),
                    label: const Text("Add Items"),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (items.isNotEmpty)
                Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: MaterialStateProperty.all(
                        Colors.blue.shade50,
                      ),
                      columns: const [
                        DataColumn(label: Text("S.No")),
                        DataColumn(label: Text("Item")),
                        DataColumn(label: Text("Qty")),
                        DataColumn(label: Text("Rate")),
                        DataColumn(label: Text("Line Total")),
                        DataColumn(label: Text("Action")),
                      ],
                      rows: List.generate(items.length, (index) {
                        final item = items[index];
                        return DataRow(
                          cells: [
                            DataCell(Text("${index + 1}")),
                            DataCell(Text(item['item'] ?? '-')),
                            DataCell(Text(item['qty'].toString())),
                            DataCell(
                              Text(
                                '₹${(item['rate'] as double).toStringAsFixed(2)}',
                              ),
                            ),
                            DataCell(
                              Text(
                                '₹${(item['lineTotal'] as double).toStringAsFixed(2)}',
                              ),
                            ),
                            DataCell(
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit,
                                      color: Colors.teal,
                                    ),
                                    tooltip: "Edit Item",
                                    onPressed: () => _openAddItemDialog(
                                      existingItem: items[index],
                                      index: index,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                    ),
                                    tooltip: "Delete Item",
                                    onPressed: () => _removeItem(index),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
                ),

              // Totals
              Align(
                alignment: Alignment.centerRight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text("Subtotal: ₹${subtotal.toStringAsFixed(2)}"),
                    Text("GST: ₹${gst.toStringAsFixed(2)}"),
                    const SizedBox(height: 6),
                    Text(
                      "Grand Total: ₹${grandTotal.toStringAsFixed(2)}",
                      style: theme.textTheme.titleMedium!.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade900,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // GST + Note
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _gstController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "GST Percentage (%)",
                        prefixIcon: Icon(Icons.percent),
                      ),
                      onChanged: (_) => _recalculateTotals(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _noteController,
                      decoration: const InputDecoration(
                        labelText: "Notes (optional)",
                        prefixIcon: Icon(Icons.note_alt_outlined),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),

              // Save Button
              ElevatedButton.icon(
                onPressed: _saveInvoice,
                icon: const Icon(Icons.save_alt_rounded),
                label: const Text("Save Invoice"),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavButton(
                  icon: Icons.home_outlined,
                  label: "Home",
                  selected: false,
                  onTap: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MainNavigation(),
                    ),
                  ),
                ),
                _buildNavButton(
                  icon: Icons.add_circle_outline,
                  label: "New",
                  selected: true, // you're on this screen
                  onTap: () {}, // stay here
                ),
                _buildNavButton(
                  icon: Icons.person_outline,
                  label: "Profile",
                  selected: false,
                  onTap: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ProfileScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
