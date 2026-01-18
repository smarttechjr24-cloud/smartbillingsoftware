import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:smartbilling/main.dart';
import 'package:smartbilling/screens/profile_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class AddQuotationScreen extends StatefulWidget {
  final String? quotationId;
  final Map<String, dynamic>? quotationData;
  
  const AddQuotationScreen({
    Key? key,
    this.quotationId,
    this.quotationData,
  }) : super(key: key);

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

  // 🔑 NEW: Helper for rounding to two decimal places
  double _round2(double v) => double.parse(v.toStringAsFixed(2));

  // 🔑 NEW: Indian States List
  final List<String> _indianStates = const [
    "Andhra Pradesh",
    "Arunachal Pradesh",
    "Assam",
    "Bihar",
    "Chhattisgarh",
    "Goa",
    "Gujarat",
    "Haryana",
    "Himachal Pradesh",
    "Jharkhand",
    "Karnataka",
    "Kerala",
    "Madhya Pradesh",
    "Maharashtra",
    "Manipur",
    "Meghalaya",
    "Mizoram",
    "Nagaland",
    "Odisha",
    "Punjab",
    "Rajasthan",
    "Sikkim",
    "Tamil Nadu",
    "Telangana",
    "Tripura",
    "Uttar Pradesh",
    "Uttarakhand",
    "West Bengal",
    "Andaman and Nicobar Islands",
    "Chandigarh",
    "Dadra and Nagar Haveli and Daman and Diu",
    "Delhi",
    "Jammu and Kashmir",
    "Ladakh",
    "Lakshadweep",
    "Puducherry",
  ];

  // Controllers
  final _customerNameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _billingAddressController = TextEditingController();
  final _shippingAddressController = TextEditingController();
  final _gstinController = TextEditingController(); // 🔑 NEW GSTIN Controller
  final _noteController = TextEditingController();

  // 🔑 NEW: State & Tax Variables
  String _companyState = "Tamil Nadu"; // Fetched from user profile
  String _customerState = "Tamil Nadu"; // Default to company state

  // Logic: If states are different, it is Interstate (IGST)
  bool get _isInterState =>
      _companyState.toLowerCase().trim() != _customerState.toLowerCase().trim();

  // Suggestions
  List<Map<String, dynamic>> customerSuggestions = [];
  List<String> customUOMs = [];

  // Data
  DateTime _quotationDate = DateTime.now();
  List<Map<String, dynamic>> _items = [];

  // 🔑 UPDATED: Computed totals (root level)
  double _subtotalBeforeDiscount = 0.0;
  double _totalDiscount = 0.0;
  double _totalTaxable = 0.0;
  double _totalCGST = 0.0;
  double _totalSGST = 0.0;
  double _totalIGST = 0.0;
  double _grandTotal = 0.0;

  @override
  void initState() {
    super.initState();
    _loadCustomUOMs();
    _fetchCompanyProfile();
    _loadQuotationData(); // Load existing quotation if editing
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _mobileController.dispose();
    _billingAddressController.dispose();
    _shippingAddressController.dispose();
    _gstinController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // 🔑 Fetch logged-in user's state to determine tax type
  Future<void> _fetchCompanyProfile() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        final doc = await _firestore.collection('users').doc(uid).get();
        if (doc.exists &&
            doc.data() != null &&
            doc.data()!.containsKey('state')) {
          if (mounted) {
            setState(() {
              _companyState = doc.data()!['state'] ?? "Tamil Nadu";
              _customerState = _companyState;
            });
          }
        }
      } catch (e) {
        debugPrint("Error fetching profile: $e");
      }
    }
  }

  // 🔑 Helper to get state name from GSTIN code
  String _getStateFromGSTIN(String gstin) {
    if (gstin.length < 2) return "";
    final stateCode = gstin.substring(0, 2);
    // Common GST state codes mapping
    const Map<String, String> codeToState = {
      '01': "Jammu and Kashmir",
      '02': "Himachal Pradesh",
      '03': "Punjab",
      '04': "Chandigarh",
      '05': "Uttarakhand",
      '06': "Haryana",
      '07': "Delhi",
      '08': "Rajasthan",
      '09': "Uttar Pradesh",
      '10': "Bihar",
      '11': "Sikkim",
      '12': "Arunachal Pradesh",
      '13': "Nagaland",
      '14': "Manipur",
      '15': "Mizoram",
      '16': "Tripura",
      '17': "Meghalaya",
      '18': "Assam",
      '19': "West Bengal",
      '20': "Jharkhand",
      '21': "Odisha",
      '22': "Chhattisgarh",
      '23': "Madhya Pradesh",
      '24': "Gujarat",
      '26': "Dadra and Nagar Haveli and Daman and Diu",
      '27': "Maharashtra",
      '29': "Karnataka",
      '30': "Goa",
      '32': "Kerala",
      '33': "Tamil Nadu",
      '34': "Puducherry",
      '35': "Andaman and Nicobar Islands",
      '36': "Telangana",
      '37': "Andhra Pradesh",
      '38': "Ladakh",
    };
    return codeToState[stateCode] ?? "";
  }

  // Load custom UOMs from Firestore (existing logic - simplified)
  Future<void> _loadCustomUOMs() async {
    // Placeholder for UOM loading
  }

  // Save custom UOM to Firestore (existing logic - simplified)
  Future<void> _saveCustomUOM(String uom) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final ref = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('uoms');

      final doc = await ref.get();

      List<String> uoms = [];

      if (doc.exists) {
        uoms = List<String>.from(doc.data()?['custom_uoms'] ?? []);
      }

      if (!uoms.contains(uom)) {
        uoms.add(uom);
      }

      await ref.set({'custom_uoms': uoms}, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error saving custom UOM: $e");
    }
  }

  Future<String?> _showAddUOMDialog() async {
    final TextEditingController controller = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text("Add New Unit"),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: "Unit Name",
            hintText: "Eg: Bag, Packet, Carton",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final uom = controller.text.trim();

              if (uom.isNotEmpty) {
                await _saveCustomUOM(uom);
                Navigator.pop(context, uom);
              }
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  // 🎯 FIX: IMPLEMENTED CUSTOMER SEARCH LOGIC
  Future<void> _fetchCustomerSuggestions(String query) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || query.trim().isEmpty) {
      setState(() => customerSuggestions = []);
      return;
    }

    try {
      final snap = await _firestore
          .collection('users')
          .doc(uid)
          .collection('customers')
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThanOrEqualTo: '$query\uf8ff')
          .limit(5)
          .get();

      final List<Map<String, dynamic>> results = snap.docs.map((d) {
        final data = d.data();
        return {
          'name': (data['name'] ?? '').toString(),
          'mobile': (data['phone'] ?? data['mobile'] ?? '').toString(),
          'billing_address': (data['address'] ?? '').toString(),
          'shipping_address': (data['address'] ?? '')
              .toString(), // Assuming same address initially
          'gstin': (data['gst_number'] ?? '').toString(),
          'customer_state':
              (data['customer_state'] ??
                      _getStateFromGSTIN(data['gst_number'] ?? ''))
                  .toString(),
        };
      }).toList();

      setState(() {
        customerSuggestions = results;
      });
    } catch (e) {
      debugPrint("Error searching customers: $e");
      setState(() => customerSuggestions = []);
    }
  }

  // Helper to select and populate fields when suggestion is tapped
  void _selectCustomer(Map<String, dynamic> cust) {
    _customerNameController.text = cust['name'];
    _mobileController.text = cust['mobile'];
    _billingAddressController.text = cust['billing_address'];
    _shippingAddressController.text = cust['shipping_address'];
    _gstinController.text = cust['gstin'];

    setState(() {
      _customerState = cust['customer_state'];
      customerSuggestions = [];
      _recalculateTotals(); // Trigger tax recalculation if state changed
    });
  }

  // 🔑 UPDATED: Product Autocomplete (fetches HSN and GST%)
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
      return snapshot.docs.map((d) {
        final data = d.data();
        return {
          'id': d.id,
          'name': data['name'],
          'rate': (data['rate'] as num?)?.toDouble() ?? 0.0,
          'unit': data['unit'] ?? 'Unit',
          'hsn_code': data['hsn_code'] ?? '',
          'gst_percent': (data['gst_percent'] as num?)?.toDouble() ?? 18.0,
        };
      }).toList();
    } catch (e) {
      debugPrint('Error: $e');
      return [];
    }
  }

  // 🔑 UPDATED: Save New Product (includes HSN and GST%)
  Future<void> _saveNewProduct(
    String name,
    double rate,
    String unit,
    String hsnCode,
    double gstPercent,
  ) async {
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
            'hsn_code': hsnCode,
            'gst_percent': gstPercent,
            'created_at': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  // 🔑 NEW: Recalculate root totals based on items (Must be called after any item change or state change)
  void _recalculateTotals() {
    double subBeforeDisc = 0.0;
    double totalDisc = 0.0;
    double totalTax = 0.0;
    double cgst = 0.0;
    double sgst = 0.0;
    double igst = 0.0;
    double grand = 0.0;

    for (var item in _items) {
      double gstPerc = (item['gst_percent'] as num).toDouble();
      double taxable = (item['taxable_amount'] as num).toDouble();

      // Re-calculate tax split based on current customer state
      double cgstP = 0.0;
      double sgstP = 0.0;
      double igstP = 0.0;

      if (_isInterState) {
        igstP = _round2(gstPerc);
      } else {
        cgstP = _round2(gstPerc / 2);
        sgstP = _round2(gstPerc / 2);
      }

      // Re-calculate amounts
      final double cgstAmt = _round2(taxable * (cgstP / 100));
      final double sgstAmt = _round2(taxable * (sgstP / 100));
      final double igstAmt = _round2(taxable * (igstP / 100));
      final double totalTaxAmount = _round2(cgstAmt + sgstAmt + igstAmt);
      final double lineTotal = _round2(taxable + totalTaxAmount);

      // Update item map in case of state change (to save correct split)
      item['cgst_percent'] = cgstP;
      item['sgst_percent'] = sgstP;
      item['igst_percent'] = igstP;
      item['cgst_amount'] = cgstAmt;
      item['sgst_amount'] = sgstAmt;
      item['igst_amount'] = igstAmt;
      item['lineTotal'] = lineTotal;

      // Summation for root totals
      subBeforeDisc += (item['base_amount'] as num).toDouble();
      totalDisc += (item['discount_amount'] as num).toDouble();
      totalTax += taxable;
      cgst += cgstAmt;
      sgst += sgstAmt;
      igst += igstAmt;
      grand += lineTotal;
    }

    setState(() {
      _subtotalBeforeDiscount = _round2(subBeforeDisc);
      _totalDiscount = _round2(totalDisc);
      _totalTaxable = _round2(totalTax);
      _totalCGST = _round2(cgst);
      _totalSGST = _round2(sgst);
      _totalIGST = _round2(igst);
      _grandTotal = _round2(grand);
    });
  }

  // 🔑 NEW: Load quotation data when editing
  void _loadQuotationData() {
    if (widget.quotationData == null) return;

    final data = widget.quotationData!;

    // Populate customer fields
    _customerNameController.text = data['customer_name'] ?? '';
    _mobileController.text = data['mobile'] ?? '';
    _billingAddressController.text = data['billing_address'] ?? '';
    _shippingAddressController.text = data['shipping_address'] ?? '';
    _gstinController.text = data['customer_gstin'] ?? '';
    _noteController.text = data['note'] ?? '';

    // Set customer state
    if (data['customer_state'] != null) {
      setState(() {
        _customerState = data['customer_state'];
      });
    }

    // Set quotation date
    if (data['quotation_date'] != null) {
      try {
        _quotationDate = DateTime.parse(data['quotation_date']);
      } catch (e) {
        debugPrint('Error parsing quotation date: $e');
      }
    }

    // Load items
    if (data['items'] != null && data['items'] is List) {
      final itemsList = List<Map<String, dynamic>>.from(data['items']);
      setState(() {
        _items = itemsList.map((item) {
          return {
            'item': item['item'] ?? '',
            'hsn_code': item['hsn_code'] ?? '',
            'qty': (item['qty'] as num?)?.toDouble() ?? 1.0,
            'rate': (item['rate'] as num?)?.toDouble() ?? 0.0,
            'unit': item['unit'] ?? 'Unit',
            'discount_percent': (item['discount_percent'] as num?)?.toDouble() ?? 0.0,
            'base_amount': (item['base_amount'] as num?)?.toDouble() ?? 0.0,
            'discount_amount': (item['discount_amount'] as num?)?.toDouble() ?? 0.0,
            'taxable_amount': (item['taxable_amount'] as num?)?.toDouble() ?? 0.0,
            'gst_percent': (item['gst_percent'] as num?)?.toDouble() ?? 18.0,
            'cgst_percent': (item['cgst_percent'] as num?)?.toDouble() ?? 0.0,
            'sgst_percent': (item['sgst_percent'] as num?)?.toDouble() ?? 0.0,
            'igst_percent': (item['igst_percent'] as num?)?.toDouble() ?? 0.0,
            'cgst_amount': (item['cgst_amount'] as num?)?.toDouble() ?? 0.0,
            'sgst_amount': (item['sgst_amount'] as num?)?.toDouble() ?? 0.0,
            'igst_amount': (item['igst_amount'] as num?)?.toDouble() ?? 0.0,
            'lineTotal': (item['lineTotal'] as num?)?.toDouble() ?? 0.0,
          };
        }).toList();
      });

      // Recalculate totals after loading items
      _recalculateTotals();
    }
  }


  // 🔑 UPDATED: Item Dialog with full tax calculation (omitted for brevity)
  void _addItemDialog({Map<String, dynamic>? existingItem, int? index}) {
    // ... Item Dialog implementation (keeping the version from the last response) ...
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
      text:
          (existingItem?['discount_percent']?.toString() ??
          '0'), // 🔑 UPDATED key
    );
    final hsnController = TextEditingController(
      text: existingItem?['hsn_code'] ?? '', // 🔑 NEW
    );
    final gstPercentController = TextEditingController(
      text: (existingItem?['gst_percent']?.toString() ?? '18'), // 🔑 NEW
    );

    String? selectedUnit = existingItem?['unit'] ?? 'Unit';
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

    showDialog(
      context: context,
      builder: (context) {
        final screenWidth = MediaQuery.of(context).size.width;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            // 1. Get live values for calculation display
            final qty = double.tryParse(qtyController.text) ?? 0.0;
            final rate = double.tryParse(rateController.text) ?? 0.0;
            final discountPerc =
                double.tryParse(discountController.text) ?? 0.0;
            final gstPerc = double.tryParse(gstPercentController.text) ?? 0.0;

            // 2. Live Calculation
            final double baseAmount = _round2(qty * rate);
            final double discountAmount = _round2(
              baseAmount * (discountPerc / 100),
            );
            final double taxableAmount = _round2(baseAmount - discountAmount);

            double cgstP = 0.0;
            double sgstP = 0.0;
            double igstP = 0.0;

            if (_isInterState) {
              igstP = _round2(gstPerc);
            } else {
              cgstP = _round2(gstPerc / 2);
              sgstP = _round2(gstPerc / 2);
            }

            final double cgstAmt = _round2(taxableAmount * (cgstP / 100));
            final double sgstAmt = _round2(taxableAmount * (sgstP / 100));
            final double igstAmt = _round2(taxableAmount * (igstP / 100));
            final double totalTaxAmount = _round2(cgstAmt + sgstAmt + igstAmt);
            final double lineTotal = _round2(taxableAmount + totalTaxAmount);

            // ✅ Save Function (Add or Edit)
            Future<void> handleSave({bool andNew = false}) async {
              if (!itemFormKey.currentState!.validate()) return;

              final name = itemNameController.text.trim();
              final hsn = hsnController.text.trim();

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
                  await _saveNewProduct(
                    name,
                    rate,
                    selectedUnit ?? 'Unit',
                    hsn,
                    gstPerc,
                  );
                }
              }

              // 🔹 Prepare item data (All Tax Fields Included)
              final itemData = {
                'item': name,
                'hsn_code': hsn, // 🔑 NEW
                'qty': qty,
                'rate': rate,
                'unit': selectedUnit ?? 'Unit',
                'discount_percent': discountPerc, // 🔑 NEW (Renamed)
                'base_amount': baseAmount, // 🔑 NEW
                'discount_amount': discountAmount, // 🔑 NEW
                'taxable_amount': taxableAmount, // 🔑 NEW
                'gst_percent': gstPerc, // 🔑 NEW
                'cgst_percent': cgstP, // 🔑 NEW
                'sgst_percent': sgstP, // 🔑 NEW
                'igst_percent': igstP, // 🔑 NEW
                'cgst_amount': cgstAmt, // 🔑 NEW
                'sgst_amount': sgstAmt, // 🔑 NEW
                'igst_amount': igstAmt, // 🔑 NEW
                'lineTotal': lineTotal,
              };

              // 🔹 Add or Update item
              setState(() {
                if (index != null && existingItem != null) {
                  _items[index] = itemData; // Update existing item
                } else {
                  _items.add(itemData); // Add new item
                }
                _recalculateTotals(); // 🔑 Recalculate root totals
              });

              // 🔹 Handle "Save & New" or "Close"
              if (andNew) {
                itemNameController.clear();
                qtyController.text = '1';
                rateController.clear();
                discountController.text = '0';
                hsnController.clear(); // 🔑 NEW
                gstPercentController.text = '18'; // 🔑 NEW
                selectedUnit = 'Unit';
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
                            // ... Product Suggestions List (kept simple for brevity) ...
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
                                      '₹${(p['rate'] ?? 0)} | HSN: ${p['hsn_code'] ?? 'N/A'} | GST: ${p['gst_percent'] ?? 0}%',
                                    ),
                                    onTap: () {
                                      itemNameController.text = p['name'] ?? '';
                                      rateController.text = (p['rate'] ?? 0)
                                          .toString();
                                      hsnController.text =
                                          p['hsn_code'] ?? ''; // 🔑 NEW
                                      gstPercentController.text =
                                          (p['gst_percent'] ?? 0)
                                              .toString(); // 🔑 NEW
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

                          // 🔹 HSN Code Field 🔑 NEW
                          TextFormField(
                            controller: hsnController,
                            decoration: const InputDecoration(
                              labelText: "HSN/SAC Code",
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.text,
                            textCapitalization: TextCapitalization.characters,
                          ),
                          const SizedBox(height: 12),

                          // 🔹 Quantity + Unit Row (Unchanged)
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
                                      value: "__add_new__",
                                      child: Text(
                                        "➕ Add New UOM",
                                        style: TextStyle(
                                          fontStyle: FontStyle.italic,
                                          color: Colors.blue,
                                        ),
                                      ),
                                    ),
                                  ],
                                  onChanged: (v) async {
                                    if (v == "__add_new__") {
                                      final newUOM = await _showAddUOMDialog();

                                      if (newUOM != null && newUOM.isNotEmpty) {
                                        setDialogState(() {
                                          if (!uomItems.contains(newUOM)) {
                                            uomItems.add(newUOM);
                                          }
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

                          // 🔹 Rate Field
                          TextFormField(
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

                          const SizedBox(height: 12),

                          // 🔹 GST % and Discount % Row 🔑 NEW
                          Row(
                            children: [
                              // GST %
                              Expanded(
                                child: TextFormField(
                                  controller: gstPercentController,
                                  decoration: const InputDecoration(
                                    labelText: "GST %",
                                    border: OutlineInputBorder(),
                                    suffixText: "%",
                                  ),
                                  keyboardType: TextInputType.number,
                                  validator: (v) =>
                                      (double.tryParse(v ?? '') ?? 0) < 0
                                      ? 'Invalid %'
                                      : null,
                                  onChanged: (_) => setDialogState(() {}),
                                ),
                              ),
                              const SizedBox(width: 10),
                              // Discount %
                              Expanded(
                                child: TextFormField(
                                  controller: discountController,
                                  decoration: const InputDecoration(
                                    labelText: "Discount %",
                                    border: OutlineInputBorder(),
                                    hintText: "0",
                                    suffixText: "%",
                                  ),
                                  keyboardType: TextInputType.number,
                                  onChanged: (_) => setDialogState(() {}),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // 🔹 Live Calculation Display 🔑 NEW
                          Text(
                            "Live Tax Calculation (${_isInterState ? 'IGST' : 'CGST+SGST'})",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8),

                          _buildCalculationRow(
                            "Base Amount (Qty x Rate)",
                            baseAmount,
                          ),
                          _buildCalculationRow(
                            "Discount Amount (${discountPerc.toStringAsFixed(1)}%)",
                            discountAmount,
                            isNegative: true,
                          ),
                          const Divider(height: 10, thickness: 1),
                          _buildCalculationRow(
                            "Taxable Value",
                            taxableAmount,
                            isBold: true,
                          ),

                          const SizedBox(height: 8),

                          if (_isInterState)
                            _buildCalculationRow(
                              "IGST (${igstP.toStringAsFixed(1)}%)",
                              igstAmt,
                            )
                          else
                            Row(
                              children: [
                                Expanded(
                                  child: _buildCalculationRow(
                                    "CGST (${cgstP.toStringAsFixed(1)}%)",
                                    cgstAmt,
                                  ),
                                ),
                                Expanded(
                                  child: _buildCalculationRow(
                                    "SGST (${sgstP.toStringAsFixed(1)}%)",
                                    sgstAmt,
                                  ),
                                ),
                              ],
                            ),

                          const Divider(thickness: 2, height: 16),

                          // 🔹 Final Line Total Display
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Text(
                                  "Line Total:",
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
                                    "₹ ${lineTotal.toStringAsFixed(2)}",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: accentColor,
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

  // Helper for displaying calculation rows in dialog
  Widget _buildCalculationRow(
    String label,
    double amount, {
    bool isBold = false,
    bool isNegative = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: isBold ? Colors.black : Colors.grey.shade700,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            "₹${isNegative ? '-' : ''}${amount.abs().toStringAsFixed(2)}",
            style: TextStyle(
              fontSize: 14,
              color: isNegative ? Colors.red.shade700 : Colors.black87,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<String> _generateQuotationNumber(String uid) async {
    final counterRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('meta')
        .doc('quotation_counter');

    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(counterRef);

      int lastNumber = 0;
      if (snapshot.exists && snapshot.data()?['last'] != null) {
        lastNumber = snapshot.get('last');
      }

      int newNumber = lastNumber + 1;

      transaction.set(counterRef, {'last': newNumber});

      return 'QUO-${newNumber.toString().padLeft(2, '0')}';
    });
  }

  // 🔑 UPDATED: Save Quotation
  Future<void> _saveQuotation() async {
    if (!_formKey.currentState!.validate()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please fill all required fields.")),
        );
      }
      return;
    }

    if (_items.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please add items to the quotation.")),
        );
      }
      return;
    }

    _recalculateTotals();

    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      String quotationNo = await _generateQuotationNumber(uid);

      final docRef = _firestore
          .collection('users')
          .doc(uid)
          .collection('quotations')
          .doc(quotationNo);

      await docRef.set({
        'id': quotationNo,
        'quotation_no': quotationNo,
        'customer_name': _customerNameController.text.trim(),
        'mobile': _mobileController.text.trim(),
        'billing_address': _billingAddressController.text.trim(),
        'shipping_address': _shippingAddressController.text.trim(),
        'note': _noteController.text.trim(),
        'customer_gstin': _gstinController.text.trim(),
        'customer_state': _customerState,
        'is_interstate': _isInterState,
        'items': _items,
        // UPDATED TOTALS
        'subtotal_before_discount': _subtotalBeforeDiscount,
        'total_discount': _totalDiscount,
        'total_taxable': _totalTaxable,
        'cgst_total': _totalCGST,
        'sgst_total': _totalSGST,
        'igst_total': _totalIGST,
        'grand_total': _grandTotal,
        'status': 'Open',
        'quotation_date': _quotationDate.toIso8601String(),
        'created_at': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Quotation $quotationNo saved successfully!"),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error saving quotation: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Decorations (existing logic)
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

  // 🔑 UPDATED: Item list display
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
                  "HSN: ${item['hsn_code'] ?? 'N/A'} | Taxable Value: ₹${((item['taxable_amount'] ?? 0) as num).toStringAsFixed(2)}",
                ),
                Text(
                  "Qty: ${item['qty'] ?? 0} ${item['unit'] ?? ''} @ ₹${((item['rate'] ?? 0) as num).toStringAsFixed(2)} (Disc: ${((item['discount_percent'] ?? 0) as num).toStringAsFixed(1)}%)",
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                Text(
                  _isInterState
                      ? "IGST: ₹${((item['igst_amount'] ?? 0) as num).toStringAsFixed(2)} (${(item['igst_percent'] as num).toStringAsFixed(1)}%)"
                      : "CGST: ₹${((item['cgst_amount'] ?? 0) as num).toStringAsFixed(2)} | SGST: ₹${((item['sgst_amount'] ?? 0) as num).toStringAsFixed(2)}",
                  style: TextStyle(fontSize: 12, color: primaryColor),
                ),
                Text(
                  "Line Total: ₹${((item['lineTotal'] ?? 0) as num).toStringAsFixed(2)}",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.teal,
                  ),
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
                  onPressed: () => setState(() {
                    _items.removeAt(index);
                    _recalculateTotals();
                  }),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // Date picker (existing logic)
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

  // 🔑 NEW: Save or Update Quotation
  Future<void> _saveQuotation() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields')),
      );
      return;
    }

    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one item')),
      );
      return;
    }

    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final quotationData = {
        'customer_name': _customerNameController.text.trim(),
        'mobile': _mobileController.text.trim(),
        'billing_address': _billingAddressController.text.trim(),
        'shipping_address': _shippingAddressController.text.trim(),
        'customer_gstin': _gstinController.text.trim(),
        'customer_state': _customerState,
        'customer_state_code': '33', // TODO: Map state to code
        'place_of_supply': _customerState,
        'tax_type': _isInterState ? 'IGST' : 'CGST_SGST',
        'quotation_date': _quotationDate.toIso8601String(),
        'valid_till_date': _quotationDate.add(const Duration(days: 30)).toIso8601String(),
        'subtotal_before_discount': _subtotalBeforeDiscount,
        'total_discount': _totalDiscount,
        'total_taxable': _totalTaxable,
        'cgst_total': _totalCGST,
        'sgst_total': _totalSGST,
        'igst_total': _totalIGST,
        'grand_total': _grandTotal,
        'items': _items,
        'note': _noteController.text.trim(),
        'status': 'Open',
      };

      if (widget.quotationId != null) {
        // UPDATE existing quotation
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('quotations')
            .doc(widget.quotationId)
            .update({
          ...quotationData,
          'updated_at': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Quotation updated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      } else {
        // CREATE new quotation
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('quotations')
            .add({
          ...quotationData,
          'created_at': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Quotation saved successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      debugPrint('Error saving quotation: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e')),
        );
      }
    }
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
              // Customer Name
              TextFormField(
                controller: _customerNameController,
                decoration: _inputDecoration(
                  "Customer Name*",
                  Icons.person_outline,
                ),
                onChanged:
                    _fetchCustomerSuggestions, // <-- This is where the magic happens
                validator: (v) =>
                    v == null || v.isEmpty ? 'Customer name required' : null,
              ),
              // Customer Suggestions List
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
                        subtitle: Text(
                          "${customer['mobile'] ?? 'No mobile'} | GSTIN: ${customer['gstin'] ?? 'N/A'}",
                        ),
                        onTap: () {
                          _selectCustomer(
                            customer,
                          ); // Use the dedicated select function
                        },
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              // Mobile Field
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
                        );
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

              // 🔑 NEW: GSTIN and State fields
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _gstinController,
                      decoration:
                          _inputDecoration(
                            "Customer GSTIN",
                            Icons.receipt_long,
                          ).copyWith(
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 12,
                            ),
                          ),
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [LengthLimitingTextInputFormatter(15)],
                      onChanged: (v) {
                        final gstin = v.trim().toUpperCase();
                        setState(() {
                          final derivedState = _getStateFromGSTIN(gstin);
                          if (derivedState.isNotEmpty &&
                              _customerState != derivedState) {
                            _customerState = derivedState;
                            _recalculateTotals();
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: _indianStates.contains(_customerState)
                          ? _customerState
                          : null,
                      decoration:
                          _inputDecoration(
                            "State (PoS)",
                            Icons.location_on_outlined,
                          ).copyWith(
                            prefixIcon: null,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 12,
                            ),
                            labelText: "State (PoS)",
                          ),
                      hint: const Text("Select State"),
                      isExpanded: true,
                      items: _indianStates
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(s, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            _customerState = v;
                            _recalculateTotals(); // Tax type might change
                          });
                        }
                      },
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Billing Address
              TextFormField(
                controller: _billingAddressController,
                decoration: _inputDecoration(
                  "Billing Address",
                  Icons.home_outlined,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              // Shipping Address
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

              // 🔑 UPDATED: Total Calculations
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
                    _buildTotalRow(
                      "Subtotal (Before Discount)",
                      _subtotalBeforeDiscount,
                      false,
                    ),
                    _buildTotalRow(
                      "Total Discount",
                      _totalDiscount,
                      false,
                      isNegative: true,
                    ),
                    const Divider(thickness: 1, height: 16),
                    _buildTotalRow(
                      "Taxable Value",
                      _totalTaxable,
                      false,
                      isTaxable: true,
                    ),

                    if (_isInterState)
                      _buildTotalRow("IGST Total", _totalIGST, false)
                    else ...[
                      _buildTotalRow("CGST Total", _totalCGST, false),
                      _buildTotalRow("SGST Total", _totalSGST, false),
                    ],

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
      // Bottom Navigation Bar (Kept as is)
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 1, // default "New" selected
        onTap: (index) {
          if (index == 0) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const MainNavigation()),
            );
          } else if (index == 1) {
            // Already on New screen
          } else if (index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ProfileScreen()),
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

  // 🔑 UPDATED: Total Row helper
  Widget _buildTotalRow(
    String label,
    double amount,
    bool isGrandTotal, {
    bool isNegative = false,
    bool isTaxable = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isGrandTotal ? 17 : 15,
              fontWeight: isGrandTotal
                  ? FontWeight.bold
                  : isTaxable
                  ? FontWeight.w600
                  : FontWeight.normal,
              color: isGrandTotal ? primaryColor : Colors.black87,
            ),
          ),
          Text(
            "₹${isNegative ? '-' : ''}${amount.abs().toStringAsFixed(2)}",
            style: TextStyle(
              fontSize: isGrandTotal ? 17 : 15,
              fontWeight: isGrandTotal ? FontWeight.bold : FontWeight.w600,
              color: isGrandTotal
                  ? accentColor
                  : isNegative
                  ? Colors.red.shade700
                  : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
