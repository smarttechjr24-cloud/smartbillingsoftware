import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:smartbilling/main.dart';
import 'package:smartbilling/screens/profile_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class AddQuotationScreen extends StatefulWidget {
  const AddQuotationScreen({Key? key}) : super(key: key);

  @override
  State<AddQuotationScreen> createState() => _AddQuotationScreenState();
}

class _AddQuotationScreenState extends State<AddQuotationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // Theme Colors
  final primaryColor = const Color(0xFF1F3A5F);
  final accentColor = const Color(0xFF00A3A3);
  final infoColor = Colors.blue.shade50;

  // Controllers
  final _customerNameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _billingAddressController = TextEditingController();
  final _shippingAddressController = TextEditingController();
  final _noteController = TextEditingController();

  // Suggestions
  List<Map<String, dynamic>> customerSuggestions = [];
  List<String> customUOMs = [];

  // Data
  double _gstPercentage = 18;
  DateTime _quotationDate = DateTime.now();
  List<Map<String, dynamic>> _items = [];

  // Computed totals
  double get _subtotal => _items.fold(
    0.0,
    (sum, item) => sum + ((item['lineTotal'] ?? 0.0) as num).toDouble(),
  );
  double get _gstAmount => _subtotal * (_gstPercentage / 100);
  double get _grandTotal => _subtotal + _gstAmount;

  @override
  void initState() {
    super.initState();
    _loadCustomUOMs();
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _mobileController.dispose();
    _billingAddressController.dispose();
    _shippingAddressController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // Load custom UOMs from Firestore
  Future<void> _loadCustomUOMs() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      final doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('uoms')
          .get();
      if (doc.exists) {
        final data = doc.data();
        setState(() {
          customUOMs = List<String>.from(data?['custom_uoms'] ?? []);
        });
      }
    } catch (e) {
      debugPrint('Error loading UOMs: $e');
    }
  }

  // Save custom UOM to Firestore
  Future<void> _saveCustomUOM(String uom) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      customUOMs.add(uom);
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('uoms')
          .set({'custom_uoms': customUOMs}, SetOptions(merge: true));
      setState(() {});
    } catch (e) {
      debugPrint('Error saving UOM: $e');
    }
  }

  // Show Add UOM Dialog
  Future<String?> _showAddUOMDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Add New Unit"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: "Unit Name",
            hintText: "e.g. Bags, Cartons",
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              final uom = controller.text.trim();
              if (uom.isNotEmpty) {
                _saveCustomUOM(uom);
                Navigator.pop(context, uom);
              }
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  // Customer Autocomplete
  Future<void> _fetchCustomerSuggestions(String query) async {
    if (query.isEmpty) {
      setState(() => customerSuggestions = []);
      return;
    }
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('customers')
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThan: '$query\uf8ff')
          .limit(5)
          .get();
      setState(() {
        customerSuggestions = snapshot.docs
            .map((d) => {'id': d.id, ...d.data()})
            .toList();
      });
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  // Product Autocomplete
  Future<List<Map<String, dynamic>>> _fetchProductSuggestions(
    String query,
  ) async {
    if (query.isEmpty) return [];
    try {
      final user = _auth.currentUser;
      if (user == null) return [];
      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('products')
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThan: '$query\uf8ff')
          .limit(5)
          .get();
      return snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (e) {
      debugPrint('Error: $e');
      return [];
    }
  }

  // Save New Product
  Future<void> _saveNewProduct(String name, double rate, String unit) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('products')
          .add({
            'name': name,
            'rate': rate,
            'unit': unit,
            'created_at': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  // Item Dialog with Validation + Custom UOM
  void _addItemDialog({Map<String, dynamic>? existingItem, int? index}) {
    final itemFormKey = GlobalKey<FormState>();

    // 🧩 Pre-fill fields if editing, or use defaults if adding
    final itemNameController = TextEditingController(
      text: existingItem?['item'] ?? '',
    );
    final qtyController = TextEditingController(
      text: (existingItem?['qty']?.toString() ?? '1'),
    );
    final rateController = TextEditingController(
      text: (existingItem?['rate']?.toString() ?? ''),
    );
    final discountController = TextEditingController(
      text: (existingItem?['discount']?.toString() ?? '0'),
    );

    String? selectedUnit = existingItem?['unit'] ?? 'Unit';
    String taxType = existingItem?['tax_type'] ?? 'Without Tax';
    double? selectedTaxPercent = existingItem?['tax_percent']?.toDouble();

    List<Map<String, dynamic>> localProductSuggestions = [];

    List<String> uomItems = [
      "Unit",
      "Kg",
      "Piece",
      "Dozen",
      "Litre",
      "Box",
      "Each",
      ...customUOMs,
    ];

    final taxTypeItems = const ['With Tax', 'Without Tax'];

    showDialog(
      context: context,
      builder: (context) {
        final screenWidth = MediaQuery.of(context).size.width;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final qty = double.tryParse(qtyController.text) ?? 0.0;
            final rate = double.tryParse(rateController.text) ?? 0.0;
            final discount = double.tryParse(discountController.text) ?? 0.0;
            final subtotal = qty * rate;
            final discountAmount = (discount / 100) * subtotal;
            final afterDiscount = subtotal - discountAmount;
            final taxAmount = taxType == 'With Tax'
                ? (afterDiscount * (selectedTaxPercent ?? 0) / 100)
                : 0.0;
            final totalAmount = afterDiscount + taxAmount;

            // ✅ Save Function (Add or Edit)
            Future<void> handleSave({bool andNew = false}) async {
              if (!itemFormKey.currentState!.validate()) return;

              final name = itemNameController.text.trim();

              // 🔹 Check if product exists in Firestore, add if new
              final user = _auth.currentUser;
              if (user != null) {
                final existing = await _firestore
                    .collection('users')
                    .doc(user.uid)
                    .collection('products')
                    .where('name', isEqualTo: name)
                    .limit(1)
                    .get();
                if (existing.docs.isEmpty) {
                  await _saveNewProduct(name, rate, selectedUnit ?? 'Unit');
                }
              }

              // 🔹 Prepare item data
              final itemData = {
                'item': name,
                'qty': qty,
                'rate': rate,
                'unit': selectedUnit ?? 'Unit',
                'discount': discount,
                'tax_type': taxType,
                'tax_percent': selectedTaxPercent ?? 0,
                'lineTotal': totalAmount,
              };

              // 🔹 Add or Update item
              setState(() {
                if (index != null && existingItem != null) {
                  _items[index] = itemData; // Update existing item
                } else {
                  _items.add(itemData); // Add new item
                }
              });

              // 🔹 Handle "Save & New" or "Close"
              if (andNew) {
                itemNameController.clear();
                qtyController.text = '1';
                rateController.clear();
                discountController.text = '0';
                selectedUnit = 'Unit';
                taxType = 'Without Tax';
                selectedTaxPercent = null;
                setDialogState(() => localProductSuggestions = []);
              } else {
                Navigator.pop(context);
              }
            }

            // 🔹 Handle Product Autocomplete
            Future<void> handleItemNameChange(String v) async {
              if (v.isEmpty) {
                setDialogState(() => localProductSuggestions = []);
                return;
              }
              final suggestions = await _fetchProductSuggestions(v);
              setDialogState(() => localProductSuggestions = suggestions);
            }

            // 🧱 Dialog UI
            return SingleChildScrollView(
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      existingItem != null ? "Edit Item" : "Add Items to Sale",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                content: SizedBox(
                  width: screenWidth * 0.92,
                  height: MediaQuery.of(context).size.height * 0.68,
                  child: SingleChildScrollView(
                    child: Form(
                      key: itemFormKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Item Name",
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 4),
                          TextFormField(
                            controller: itemNameController,
                            decoration: const InputDecoration(
                              hintText: "Enter item",
                              border: OutlineInputBorder(),
                            ),
                            onChanged: handleItemNameChange,
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Required'
                                : null,
                          ),
                          if (localProductSuggestions.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 6),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: localProductSuggestions.length,
                                itemBuilder: (context, i) {
                                  final p = localProductSuggestions[i];
                                  return ListTile(
                                    dense: true,
                                    title: Text(p['name'] ?? ''),
                                    subtitle: Text(
                                      '₹${(p['rate'] ?? 0)} • ${p['unit'] ?? 'Unit'}',
                                    ),
                                    onTap: () {
                                      itemNameController.text = p['name'] ?? '';
                                      rateController.text = (p['rate'] ?? 0)
                                          .toString();
                                      setDialogState(() {
                                        selectedUnit = p['unit'] ?? 'Unit';
                                        localProductSuggestions = [];
                                      });
                                    },
                                  );
                                },
                              ),
                            ),
                          const SizedBox(height: 12),

                          // 🔹 Quantity + Unit Row
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: qtyController,
                                  decoration: const InputDecoration(
                                    labelText: "Quantity",
                                    border: OutlineInputBorder(),
                                  ),
                                  keyboardType: TextInputType.number,
                                  validator: (v) =>
                                      (double.tryParse(v ?? '') ?? 0) <= 0
                                      ? 'Qty > 0'
                                      : null,
                                  onChanged: (_) => setDialogState(() {}),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 3,
                                child: DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  value: uomItems.contains(selectedUnit)
                                      ? selectedUnit
                                      : null,
                                  items: [
                                    ...uomItems.map(
                                      (e) => DropdownMenuItem(
                                        value: e,
                                        child: Text(
                                          e,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    const DropdownMenuItem(
                                      value: "➕ Add New UOM",
                                      child: Text(
                                        "➕ Add New UOM",
                                        style: TextStyle(
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                  ],
                                  onChanged: (v) async {
                                    if (v == "➕ Add New UOM") {
                                      final newUOM = await _showAddUOMDialog();

                                      if (newUOM != null && newUOM.isNotEmpty) {
                                        setDialogState(() {
                                          // Avoid duplicates
                                          if (!uomItems.contains(newUOM)) {
                                            uomItems.add(newUOM);
                                          }

                                          // Set the new item as selected
                                          selectedUnit = newUOM;
                                        });
                                      }
                                    } else {
                                      setDialogState(() => selectedUnit = v);
                                    }
                                  },
                                  decoration: const InputDecoration(
                                    labelText: "Unit",
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          // 🔹 Rate + Tax Type Row
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextFormField(
                                  controller: rateController,
                                  decoration: const InputDecoration(
                                    labelText: "Rate (Price/Unit)",
                                    border: OutlineInputBorder(),
                                  ),
                                  keyboardType: TextInputType.number,
                                  validator: (v) =>
                                      (double.tryParse(v ?? '') ?? 0) <= 0
                                      ? 'Price > 0'
                                      : null,
                                  onChanged: (_) => setDialogState(() {}),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  value: taxType,
                                  items: taxTypeItems
                                      .map(
                                        (e) => DropdownMenuItem(
                                          value: e,
                                          child: Text(e),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) {
                                    setDialogState(() {
                                      taxType = v!;
                                      if (taxType == 'Without Tax') {
                                        selectedTaxPercent = null;
                                      }
                                    });
                                  },
                                  decoration: const InputDecoration(
                                    labelText: "Tax Type",
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // 🔹 Tax % Row
                          Row(
                            children: [
                              const Text("Tax %"),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 3,
                                child: DropdownButtonFormField<double>(
                                  isExpanded: true,
                                  value: selectedTaxPercent,
                                  hint: const Text("None"),
                                  onChanged: taxType == 'With Tax'
                                      ? (v) => setDialogState(
                                          () => selectedTaxPercent = v,
                                        )
                                      : null,
                                  items: [null, 0.0, 5.0, 12.0, 18.0, 28.0]
                                      .map(
                                        (e) => DropdownMenuItem(
                                          value: e,
                                          child: Text(
                                            e == null
                                                ? "None"
                                                : "${e.toInt()}%",
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  decoration: InputDecoration(
                                    border: const OutlineInputBorder(),
                                    filled: taxType == 'Without Tax',
                                    fillColor: taxType == 'Without Tax'
                                        ? Colors.grey.shade200
                                        : Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    "₹ ${taxAmount.toStringAsFixed(2)}",
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),

                          // 🔹 Discount Row
                          Row(
                            children: [
                              const Text("Discount %"),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextFormField(
                                  controller: discountController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    hintText: "0",
                                  ),
                                  onChanged: (_) => setDialogState(() {}),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    "₹ ${discountAmount.toStringAsFixed(2)}",
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const Divider(height: 24, thickness: 1),

                          // 🔹 Total Amount
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Text(
                                  "Total Amount:",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    "₹ ${totalAmount.toStringAsFixed(2)}",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.teal,
                                      fontSize: 18,
                                    ),
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
                  TextButton(
                    onPressed: () => handleSave(andNew: true),
                    child: const Text("Save & New"),
                  ),
                  ElevatedButton(
                    onPressed: () => handleSave(andNew: false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                    ),
                    child: const Text(
                      "Save",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Save Quotation
  Future<void> _saveQuotation() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Fill all required fields'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Add at least one item'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      final docRef = _firestore
          .collection('users')
          .doc(uid)
          .collection('quotations')
          .doc();
      await docRef.set({
        'id': docRef.id,
        'customer_name': _customerNameController.text.trim(),
        'mobile': _mobileController.text.trim(),
        'billing_address': _billingAddressController.text.trim(),
        'shipping_address': _shippingAddressController.text.trim(),
        'note': _noteController.text.trim(),
        'items': _items,
        'subtotal': _subtotal,
        'gst_percentage': _gstPercentage,
        'gst_amount': _gstAmount,
        'grand_total': _grandTotal,
        'status': 'Open',
        'quotation_date': _quotationDate.toIso8601String(),
        'created_at': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Quotation saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // Decorations
  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: primaryColor.withOpacity(0.7)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: primaryColor.withOpacity(0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: accentColor, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
    );
  }

  // Item list
  Widget _buildItemList() {
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            "Tap 'Add Item' to list products for the quotation.",
            style: TextStyle(
              color: Colors.grey.shade600,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    return Column(
      children: _items.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        return Card(
          elevation: 1,
          margin: const EdgeInsets.symmetric(vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: primaryColor.withOpacity(0.1),
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              item['item'] ?? '',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Qty: ${item['qty'] ?? 0} ${item['unit'] ?? ''} x ₹${((item['rate'] ?? 0) as num).toStringAsFixed(2)}",
                ),
                Text(
                  "Line Total: ₹${((item['lineTotal'] ?? 0) as num).toStringAsFixed(2)}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            trailing: Wrap(
              spacing: 8,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.teal, size: 22),
                  tooltip: "Edit Item",
                  onPressed: () =>
                      _addItemDialog(existingItem: item, index: index),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red, size: 22),
                  tooltip: "Delete Item",
                  onPressed: () => setState(() => _items.removeAt(index)),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // Date picker
  Widget _buildDatePicker() {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _quotationDate,
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (picked != null) setState(() => _quotationDate = picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Quotation Date",
              style: TextStyle(color: Colors.black54),
            ),
            Row(
              children: [
                Text(
                  DateFormat('dd MMM yyyy').format(_quotationDate),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.calendar_today,
                  color: primaryColor.withOpacity(0.7),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Build
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Create Quotation 📝"),
        centerTitle: true,
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "Customer Details",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _customerNameController,
                decoration: _inputDecoration(
                  "Customer Name*",
                  Icons.person_outline,
                ),
                onChanged: _fetchCustomerSuggestions,
                validator: (v) =>
                    v == null || v.isEmpty ? 'Customer name required' : null,
              ),
              if (customerSuggestions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: customerSuggestions.length,
                    itemBuilder: (context, index) {
                      final customer = customerSuggestions[index];
                      return ListTile(
                        dense: true,
                        title: Text(customer['name'] ?? ''),
                        subtitle: Text(customer['mobile'] ?? 'No mobile'),
                        onTap: () {
                          setState(() {
                            _customerNameController.text =
                                customer['name'] ?? '';
                            _mobileController.text = customer['mobile'] ?? '';
                            _billingAddressController.text =
                                customer['billing_address'] ?? '';
                            _shippingAddressController.text =
                                customer['shipping_address'] ?? '';
                            customerSuggestions = [];
                          });
                        },
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _mobileController,
                decoration: InputDecoration(
                  labelText: "Mobile Number",
                  prefixIcon: Icon(
                    Icons.phone_outlined,
                    color: primaryColor.withOpacity(0.7),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.call, color: Colors.teal),
                    tooltip: "Call this number",
                    onPressed: () async {
                      final number = _mobileController.text.trim();
                      if (number.isEmpty || number.length < 8) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Please enter a valid mobile number first',
                            ),
                          ),
                        );
                        return;
                      }
                      final Uri uri = Uri(scheme: 'tel', path: number);
                      try {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        ); // Ensures opening in dialer
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Could not open dialer'),
                          ),
                        );
                      }
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: primaryColor.withOpacity(0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: accentColor, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 12,
                  ),
                ),
                keyboardType: TextInputType.phone,
              ),

              const SizedBox(height: 12),
              TextFormField(
                controller: _billingAddressController,
                decoration: _inputDecoration(
                  "Billing Address",
                  Icons.home_outlined,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _shippingAddressController,
                decoration: _inputDecoration(
                  "Shipping Address",
                  Icons.local_shipping_outlined,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              _buildDatePicker(),
              const Divider(height: 30, thickness: 1.5),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Quotation Items",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _addItemDialog,
                    icon: const Icon(Icons.add_shopping_cart, size: 20),
                    label: const Text("Add Item"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildItemList(),
              const Divider(height: 30, thickness: 1.5),
              Text(
                "Summary & Totals",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<double>(
                value: _gstPercentage,
                decoration: _inputDecoration(
                  "Select GST (%)",
                  Icons.local_offer_outlined,
                ),
                items: [0, 5, 12, 18, 28]
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.toDouble(),
                        child: Text("$e%"),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _gstPercentage = v ?? 18),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: infoColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accentColor.withOpacity(0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildTotalRow("Subtotal", _subtotal, false),
                    _buildTotalRow(
                      "GST (${_gstPercentage.toStringAsFixed(0)}%)",
                      _gstAmount,
                      false,
                    ),
                    const Divider(thickness: 2, height: 16),
                    _buildTotalRow("GRAND TOTAL", _grandTotal, true),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _noteController,
                decoration: _inputDecoration(
                  "Notes / Terms (optional)",
                  Icons.note_alt_outlined,
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                icon: const Icon(Icons.file_download_done, color: Colors.white),
                label: const Text(
                  "SAVE QUOTATION",
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
                onPressed: _saveQuotation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 1, // default "New" selected
        onTap: (index) {
          if (index == 0) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => MainNavigation()),
            );
          } else if (index == 1) {
            // Already on New screen
          } else if (index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => ProfileScreen()),
            );
          }
        },
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: "Home",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            activeIcon: Icon(Icons.add_circle),
            label: "New",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: "Profile",
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, double amount, bool isGrandTotal) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isGrandTotal ? 17 : 15,
              fontWeight: isGrandTotal ? FontWeight.bold : FontWeight.normal,
              color: isGrandTotal ? primaryColor : Colors.black87,
            ),
          ),
          Text(
            "₹${amount.toStringAsFixed(2)}",
            style: TextStyle(
              fontSize: isGrandTotal ? 17 : 15,
              fontWeight: isGrandTotal ? FontWeight.bold : FontWeight.w600,
              color: isGrandTotal ? accentColor : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
