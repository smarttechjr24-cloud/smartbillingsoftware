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

  // Indian States List
  final List<String> _indianStates = const [
    "Andhra Pradesh", "Arunachal Pradesh", "Assam", "Bihar", "Chhattisgarh",
    "Goa", "Gujarat", "Haryana", "Himachal Pradesh", "Jharkhand",
    "Karnataka", "Kerala", "Madhya Pradesh", "Maharashtra", "Manipur",
    "Meghalaya", "Mizoram", "Nagaland", "Odisha", "Punjab",
    "Rajasthan", "Sikkim", "Tamil Nadu", "Telangana", "Tripura",
    "Uttar Pradesh", "Uttarakhand", "West Bengal",
    "Andaman and Nicobar Islands", "Chandigarh",
    "Dadra and Nagar Haveli and Daman and Diu", "Delhi",
    "Jammu and Kashmir", "Ladakh", "Lakshadweep", "Puducherry",
  ];

  // Customer fields
  final _customerController = TextEditingController();
  final _mobileController = TextEditingController();
  final _fromController = TextEditingController();
  final _toController = TextEditingController();
  final _gstinController = TextEditingController();
  final _noteController = TextEditingController();
  final _gstController = TextEditingController(text: "5");
  
  // State tracking
  String _customerState = "Tamil Nadu";
  bool _enableGST = true; // Default to true

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
    _loadGSTPreference();
  }

  Future<void> _loadGSTPreference() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('billing')
          .get();
      if (doc.exists) {
        setState(() {
          _enableGST = doc.data()?['enable_gst'] ?? true;
          if (!_enableGST) {
            _gstController.text = "0";
          }
        });
      }
    } catch (e) {
      debugPrint("Error loading GST preference: $e");
    }
  }

  @override
  void dispose() {
    _customerController.dispose();
    _mobileController.dispose();
    _fromController.dispose();
    _toController.dispose();
    _gstinController.dispose();
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
  
  Future<void> _fetchCustomerDetails(String name) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || name.trim().isEmpty) return;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('customers')
          .where('name', isEqualTo: name)
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        setState(() {
          _mobileController.text = (data['mobile'] ?? '').toString();
          _gstinController.text = (data['gstin'] ?? '').toString();
          
          // Try billing_address first, then fallback to address
          final billingAddr = (data['billing_address'] ?? data['address'] ?? '').toString();
          _fromController.text = billingAddr;
          
          _toController.text = (data['shipping_address'] ?? '').toString();
          
          // Update state if valid
          final state = (data['state'] ?? '').toString();
          if (_indianStates.contains(state)) {
            _customerState = state;
          }
        });
      }
    } catch (e) {
      debugPrint("Error fetching customer details: $e");
    }
  }

  Widget _buildSummaryRow(String label, double amount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 14,
          ),
        ),
        Text(
          '₹${amount.toStringAsFixed(2)}',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ],
    );
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

  Future<void> _openAddItemDialog({
    Map<String, dynamic>? existingItem,
    int? index,
  }) async {
    final itemCtrl = TextEditingController(text: existingItem?['item'] ?? '');
    final qtyCtrl = TextEditingController(
      text: (existingItem?['qty']?.toString() ?? '1'),
    );
    final rateCtrl = TextEditingController(
      text: (existingItem?['rate']?.toString() ?? '0'),
    );
    final discountCtrl = TextEditingController(
      text: (existingItem?['discount']?.toString() ?? '0'),
    );
    final gstCtrl = TextEditingController(
      text: (existingItem?['gst']?.toString() ?? _gstController.text),
    );
    String? selectedUnit = existingItem?['unit'] ?? 'Unit';
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
        return StatefulBuilder(
          builder: (context, setSB) {
            void applySuggestion(Map<String, dynamic> p) {
              itemCtrl.text = p['name'] ?? '';
              rateCtrl.text = (p['rate'] ?? 0).toString();
              selectedUnit = p['unit'] ?? 'Unit';
              setSB(() => productSuggestions.clear());
            }

            Future<void> handleSave() async {
              if (!formKey.currentState!.validate()) return;

              final qty = double.tryParse(qtyCtrl.text) ?? 0;
              final rate = double.tryParse(rateCtrl.text) ?? 0;
              final discount = double.tryParse(discountCtrl.text) ?? 0;
              final gst = double.tryParse(gstCtrl.text) ?? 0;

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
                'discount': discount,
                'gst': gst,
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

              Navigator.pop(context);
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                "Add Item",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.85,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Item Name
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

                        // Product Suggestions
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
                        const SizedBox(height: 12),

                        // Qty and Unit Row
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: qtyCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: "Qty",
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
                                decoration: const InputDecoration(
                                  labelText: "Unit",
                                  border: OutlineInputBorder(),
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'Unit', child: Text('Unit')),
                                  DropdownMenuItem(value: 'Piece', child: Text('Piece')),
                                  DropdownMenuItem(value: 'Kg', child: Text('Kg')),
                                  DropdownMenuItem(value: 'Gram', child: Text('Gram')),
                                  DropdownMenuItem(value: 'Ton', child: Text('Ton')),
                                  DropdownMenuItem(value: 'Litre', child: Text('Litre')),
                                  DropdownMenuItem(value: 'Meter', child: Text('Meter')),
                                  DropdownMenuItem(value: 'Box', child: Text('Box')),
                                  DropdownMenuItem(value: 'Carton', child: Text('Carton')),
                                  DropdownMenuItem(value: 'Bag', child: Text('Bag')),
                                  DropdownMenuItem(value: 'Packet', child: Text('Packet')),
                                  DropdownMenuItem(value: 'Dozen', child: Text('Dozen')),
                                ],
                                onChanged: (v) => setSB(() => selectedUnit = v),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Rate
                        TextFormField(
                          controller: rateCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: "Rate",
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            final n = double.tryParse(v ?? '');
                            if (n == null || n <= 0) return 'Rate > 0';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        // Discount
                        TextFormField(
                          controller: discountCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: "Discount",
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // GST %
                        if (_enableGST)
                          TextFormField(
                            controller: gstCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: "GST %",
                              border: OutlineInputBorder(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: handleSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                  ),
                  child: const Text("Save"),
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
    final gstPercent = _enableGST ? (double.tryParse(_gstController.text) ?? 0) : 0.0;
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
      // Re-fetch customer to update outstanding
      final customerDoc =
          (await customersRef.where('name', isEqualTo: custName).limit(1).get())
              .docs
              .first;
      final currentOutstanding = (customerDoc['outstanding'] ?? 0).toDouble();
      
      // 🔹 Calculate tax breakdown per item
      const String companyState = 'Tamil Nadu'; // TODO: Get from company settings
      final String customerState = _customerState; 
      final bool isInterstate = customerState.trim().toLowerCase() != companyState.trim().toLowerCase();
      final String taxType = isInterstate ? 'IGST' : 'CGST_SGST';
      
      final gstPercent = double.tryParse(_gstController.text) ?? 0.0;
      
      double calculatedSubtotal = 0.0;
      double totalCgst = 0.0;
      double totalSgst = 0.0;
      double totalIgst = 0.0;
      
      final List<Map<String, dynamic>> cleanedItems = [];
      
      for (var item in items) {
        final qty = (item['qty'] as num?)?.toDouble() ?? 0.0;
        final rate = (item['rate'] as num?)?.toDouble() ?? 0.0;
        final discount = 0.0; // No discount in current UI
        
        final baseAmount = qty * rate;
        final discountAmount = baseAmount * (discount / 100);
        final taxableAmount = baseAmount - discountAmount;
        
        double cgst = 0.0;
        double sgst = 0.0;
        double igst = 0.0;
        
        if (isInterstate) {
          igst = taxableAmount * (gstPercent / 100);
        } else {
          cgst = taxableAmount * (gstPercent / 2 / 100);
          sgst = taxableAmount * (gstPercent / 2 / 100);
        }
        
        final lineTotal = taxableAmount + cgst + sgst + igst;
        
        calculatedSubtotal += taxableAmount;
        totalCgst += cgst;
        totalSgst += sgst;
        totalIgst += igst;
        
        // Fetch HSN code from product
        String hsnCode = '';
        try {
          final productQuery = await userRef
              .collection('products')
              .where('name', isEqualTo: item['item'] ?? '')
              .limit(1)
              .get();
          
          if (productQuery.docs.isNotEmpty) {
            hsnCode = productQuery.docs.first.data()['hsn_code'] ?? '';
          }
        } catch (e) {
          debugPrint('⚠️ Error fetching HSN code: $e');
        }
        
        cleanedItems.add({
          'item_name': item['item'] ?? '',
          'qty': qty,
          'rate': rate,
          'discount': discount,
          'gst_percent': gstPercent,
          'taxable_amount': taxableAmount,
          'cgst': cgst,
          'sgst': sgst,
          'igst': igst,
          'line_total': lineTotal,
          'hsn_code': hsnCode,
          'unit': item['unit'] ?? 'Unit',
        });
      }
      
      final gstAmountTotal = totalCgst + totalSgst + totalIgst;
      final calculatedGrandTotal = calculatedSubtotal + gstAmountTotal;
      final newOutstanding = currentOutstanding + calculatedGrandTotal;

      // Prepare invoice with complete data structure
      final invoiceData = {
        'invoice_number': nextInvoiceNo,
        'customer_name': custName,
        'mobile': _mobileController.text.trim(),
        'billing_address': _fromController.text.trim(),
        'shipping_address': _toController.text.trim(),
        'customer_gstin': _gstinController.text.trim(),
        'customer_state': customerState,
        'customer_state_code': '33', // TODO: Get from state mapping
        'place_of_supply': customerState,
        'tax_type': taxType,
        'gst_percentage': gstPercent,
        'note': _noteController.text.trim(),
        'invoice_date': invoiceDate.toIso8601String(),
        'due_date': dueDate.toIso8601String(),
        'subtotal': calculatedSubtotal,
        'cgst_total': totalCgst,
        'sgst_total': totalSgst,
        'igst_total': totalIgst,
        'gst_amount': gstAmountTotal,
        'grand_total': calculatedGrandTotal,
        'items': cleanedItems,
        'status': 'Pending',
        'outstanding_after_invoice': newOutstanding,
        'created_at': FieldValue.serverTimestamp(), // Required for invoices screen query
      };

      await invoicesRef.add(invoiceData);

      // Update customer's outstanding
      await customerDoc.reference.update({'outstanding': newOutstanding});

      // 🔹 Update Stock - Deduct quantities sold
      for (var item in cleanedItems) {
        final itemName = (item['item_name'] ?? '').toString().trim();
        if (itemName.isEmpty) continue;

        try {
          // Find product by name
          final productQuery = await userRef
              .collection('products')
              .where('name', isEqualTo: itemName)
              .limit(1)
              .get();

          if (productQuery.docs.isNotEmpty) {
            final productRef = productQuery.docs.first.reference;
            final qty = (item['qty'] as num?)?.toDouble() ?? 0.0;
            
            // Deduct stock
            await productRef.update({
              'stock': FieldValue.increment(-qty),
              'updated_at': FieldValue.serverTimestamp(),
            });
          }
        } catch (e) {
          debugPrint('⚠️ Error updating stock for $itemName: $e');
          // Continue with other items even if one fails
        }
      }

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

              // Customer Section - Simplified
              TextFormField(
                controller: _customerController,
                decoration: const InputDecoration(
                  labelText: "Customer Name",
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
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
                          _fetchCustomerDetails(name);
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // Phone and State in Row
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _mobileController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: "Phone",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _indianStates.contains(_customerState) ? _customerState : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: "State (POS)",
                        border: OutlineInputBorder(),
                      ),
                      items: _indianStates.map((state) {
                        return DropdownMenuItem(
                          value: state,
                          child: Text(
                            state,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _customerState = val;
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Billing Address
              TextFormField(
                controller: _fromController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: "Billing Address",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),

              // Items Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Items List",
                    style: theme.textTheme.titleMedium!.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _openAddItemDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text("Add Item"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Items Display or Empty State
              if (items.isEmpty)
                Container(
                  padding: const EdgeInsets.all(40),
                  alignment: Alignment.center,
                  child: Text(
                    "No items added yet",
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 14,
                    ),
                  ),
                )
              else
                ...items.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(
                        item['item'] ?? '-',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Qty: ${item['qty']} × ₹${(item['rate'] as double).toStringAsFixed(2)}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '₹${(item['lineTotal'] as double).toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _openAddItemDialog(
                              existingItem: items[index],
                              index: index,
                            ),
                            tooltip: "Edit Item",
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _removeItem(index),
                            tooltip: "Delete Item",
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),

              const SizedBox(height: 20),

              // Tax Summary
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  children: [
                    _buildSummaryRow("Taxable Amount", subtotal),
                    const SizedBox(height: 8),
                    _buildSummaryRow("CGST Total", gst / 2),
                    const SizedBox(height: 8),
                    _buildSummaryRow("SGST Total", gst / 2),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // Save Button
              ElevatedButton(
                onPressed: _saveInvoice,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: const Color(0xFF1F3A5F),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  "SAVE INVOICE",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
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
