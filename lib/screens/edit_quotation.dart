import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:async';

// 🔑 Type Definitions for Callbacks (Implemented by the calling screen)
typedef UpdateCallback = Future<void> Function(Map<String, dynamic>);
typedef ConvertCallback = Future<void> Function(Map<String, dynamic>);

// 🔑 UPDATED CLASS: Includes isConversion flag and callbacks
class EditQuotationScreen extends StatefulWidget {
  final String quotationId;
  final Map<String, dynamic>? initialData;
  final bool isConversion; // NEW: To switch between edit/convert
  final UpdateCallback onUpdate; // Callback for update/status change
  final ConvertCallback onConvert; // Callback for conversion

  const EditQuotationScreen({
    Key? key,
    required this.quotationId,
    this.initialData,
    required this.isConversion,
    required this.onUpdate,
    required this.onConvert,
  }) : super(key: key);

  @override
  State<EditQuotationScreen> createState() => _EditQuotationScreenState();
}

class _EditQuotationScreenState extends State<EditQuotationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ---------- Navy Blue & White Theme Colors ----------
  final Color primaryColor = const Color(0xFF0B3D91); // Navy Blue
  final Color accentColor = const Color(0xFF3B72FF); // Lighter Blue for accents
  final Color infoColor =
      Colors.blue.shade50; // Light Blue/Grey for backgrounds

  // Autocomplete Debounce Timer
  Timer? _debounce;

  // Helper to round to 2 decimal places
  double _round2(double v) => double.parse(v.toStringAsFixed(2));

  // 🔑 Indian States List
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
  final _gstinController = TextEditingController();
  final _noteController = TextEditingController();

  // State & Tax Variables
  String _companyState = "Tamil Nadu"; // Assume default/fetched state
  String _customerState = "Tamil Nadu";

  // Getter to check for Interstate Transaction
  bool get _isInterState =>
      _companyState.toLowerCase().trim() != _customerState.toLowerCase().trim();

  // Suggestions/Data
  List<Map<String, dynamic>> customerSuggestions = [];
  List<String> customUOMs = [];
  DateTime _quotationDate = DateTime.now();
  List<Map<String, dynamic>> _items = [];

  // Computed totals (Updated in _recalculateTotals)
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
    _fetchCompanyProfile().then((_) => _loadQuotationData());
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _mobileController.dispose();
    _billingAddressController.dispose();
    _shippingAddressController.dispose();
    _gstinController.dispose();
    _noteController.dispose();
    _debounce?.cancel(); // 🔑 Important: Cancel the debounce timer
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // --- UTILITY AND HELPER METHODS -------------------------------------------
  // --------------------------------------------------------------------------

  // Custom Input Decoration
  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: primaryColor),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade400),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: accentColor, width: 2),
      ),
      filled: true,
      fillColor: Colors.white,
    );
  }

  // Load custom UOMs (Simplified)
  Future<void> _loadCustomUOMs() async {
    if (mounted) {
      setState(() {
        customUOMs = [
          "Nos",
          "Kgs",
          "Mtrs",
          "Hrs",
          "Ltrs",
          "Bags",
          "Unit",
          "Pcs",
        ];
      });
    }
  }

  // Load Existing Quotation Data
  Future<void> _loadQuotationData() async {
    Map<String, dynamic>? data = widget.initialData;
    // ... (omitted Firestore fallback for brevity, assuming initialData is provided)

    if (data == null) return;

    if (mounted) {
      setState(() {
        _customerNameController.text = data['customer_name'] ?? '';
        _mobileController.text = data['mobile'] ?? '';
        _billingAddressController.text = data['billing_address'] ?? '';
        _shippingAddressController.text =
            data['shipping_address'] ?? _billingAddressController.text;
        _gstinController.text = data['customer_gstin'] ?? '';
        _noteController.text = data['note'] ?? '';

        _quotationDate = (data['quotation_date'] != null)
            ? DateTime.tryParse(data['quotation_date']) ?? DateTime.now()
            : DateTime.now();

        // Ensure state is loaded
        _customerState = data['customer_state'] ?? _companyState;
        _items = List<Map<String, dynamic>>.from(data['items'] ?? []);

        _recalculateTotals();
      });
    }
  }

  // 🔑 CORRECTED IMPLEMENTATION: Recalculate root totals based on items
  void _recalculateTotals() {
    double subtotalBeforeDiscount = 0.0;
    double totalDiscount = 0.0;
    double totalTaxable = 0.0;
    double totalCGST = 0.0;
    double totalSGST = 0.0;
    double totalIGST = 0.0;

    // Use a local copy of _isInterState
    final isInterState =
        _isInterState; // Checks _companyState vs _customerState

    for (var item in _items) {
      final qty = (item['qty'] as num?)?.toDouble() ?? 0.0;
      final rate = (item['rate'] as num?)?.toDouble() ?? 0.0;
      final discountPerc = (item['discount'] as num?)?.toDouble() ?? 0.0;
      final gstPerc = (item['gst_percent'] as num?)?.toDouble() ?? 0.0;

      final double baseAmount = _round2(qty * rate);
      final double discountAmount = _round2(baseAmount * (discountPerc / 100));
      final double taxable = _round2(baseAmount - discountAmount);

      // --- CORE TAX CALCULATION LOGIC ---
      double cgstP = 0.0, sgstP = 0.0, igstP = 0.0;
      if (isInterState) {
        // Interstate: Only IGST
        igstP = gstPerc;
      } else {
        // Intrastate: CGST + SGST (Half of GST)
        cgstP = gstPerc / 2;
        sgstP = gstPerc / 2;
      }

      // Calculate Amounts
      final double cgstAmt = _round2(taxable * (cgstP / 100));
      final double sgstAmt = _round2(taxable * (sgstP / 100));
      final double igstAmt = _round2(taxable * (igstP / 100));
      final double totalTaxAmount = _round2(cgstAmt + sgstAmt + igstAmt);
      final double lineTotal = _round2(taxable + totalTaxAmount);
      // ------------------------------------

      // Update item map (Critically important for display and conversion)
      item['base_amount'] = baseAmount;
      item['discount_amount'] = discountAmount;
      item['taxable_amount'] = taxable;
      item['cgst_amount'] = cgstAmt;
      item['sgst_amount'] = sgstAmt;
      item['igst_amount'] = igstAmt;
      item['line_total'] = lineTotal;

      subtotalBeforeDiscount += baseAmount;
      totalDiscount += discountAmount;
      totalTaxable += taxable;
      totalCGST += cgstAmt;
      totalSGST += sgstAmt;
      totalIGST += igstAmt;
    }

    if (mounted) {
      setState(() {
        _subtotalBeforeDiscount = _round2(subtotalBeforeDiscount);
        _totalDiscount = _round2(totalDiscount);
        _totalTaxable = _round2(totalTaxable);
        _totalCGST = _round2(totalCGST);
        _totalSGST = _round2(totalSGST);
        _totalIGST = _round2(totalIGST);
        _grandTotal = _round2(
          _totalTaxable + _totalCGST + _totalSGST + _totalIGST,
        );
      });
    }
  }

  // Helper to get state name from GSTIN code (omitted for brevity)
  String _getStateFromGSTIN(String gstin) {
    if (gstin.length < 2) return "";
    const Map<String, String> codeToState = {
      '33': "Tamil Nadu",
      '27': "Maharashtra",
      '07': "Delhi",
      // Add more codes here
    };
    return codeToState[gstin.substring(0, 2)] ?? "";
  }

  Future<void> _fetchCompanyProfile() async {
    // Placeholder logic to fetch company state.
    // In a real app, this would fetch the user's registered state from Firestore.
    // For now, we rely on the initial default state.
    // Example:
    /*
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        setState(() {
          _companyState = doc.data()?['company_state'] ?? 'Tamil Nadu';
        });
      }
    } catch (e) {
      debugPrint("Error fetching company profile: $e");
    }
    */
  }

  // IMPLEMENTATION: Fetch product suggestions
  Future<List<Map<String, dynamic>>> _fetchProductSuggestions(
    String query,
  ) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || query.trim().isEmpty) return [];

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('products')
          .orderBy('name') // ✅ correct field
          .startAt([query])
          .endAt([query + '\uf8ff'])
          .limit(10)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'item': data['name'], // ✅ map name to item
          'hsn_code': data['hsn_code'],
          'rate': (data['rate'] as num).toDouble(),
          'gst_percent': (data['gst_percent'] as num).toDouble(),
          'unit': data['unit'],
          'stock': data['stock'],
        };
      }).toList();
    } catch (e) {
      debugPrint("🔥 Product search error: $e");
      return [];
    }
  }

  // 🔑 UPDATED IMPLEMENTATION: Item Add/Edit Dialog with Compact UI and Autocomplete Fix
  Future<void> _showAddItemDialog({
    Map<String, dynamic>? existingItem,
    int? itemIndex,
  }) async {
    final isEditing = existingItem != null;
    final formKey = GlobalKey<FormState>();

    // Controllers
    final itemCtrl = TextEditingController(text: existingItem?['item'] ?? '');
    final hsnCtrl = TextEditingController(
      text: existingItem?['hsn_code'] ?? '',
    );
    final qtyCtrl = TextEditingController(
      text: (existingItem?['qty']?.toString().replaceAll('.0', '') ?? '1'),
    );
    final rateCtrl = TextEditingController(
      text: (existingItem?['rate']?.toString() ?? ''),
    );
    final discountCtrl = TextEditingController(
      text: (existingItem?['discount']?.toString() ?? '0'),
    );
    final gstPercCtrl = TextEditingController(
      text: (existingItem?['gst_percent']?.toString() ?? '0'),
    );

    String? selectedUnit = existingItem?['unit'];

    // Navy theme colors
    const navy = Color(0xFF0B3D91);
    const lightGrey = Color(0xFFF4F6FA);

    // Local product suggestion list for this dialog
    List<Map<String, dynamic>> dialogProducts = [];

    double baseAmount = 0.0;
    double discountAmount = 0.0;
    double taxableValue = 0.0;
    double totalTaxAmount = 0.0;
    double lineTotal = 0.0;

    void recalc() {
      final qty = double.tryParse(qtyCtrl.text) ?? 0.0;
      final rate = double.tryParse(rateCtrl.text) ?? 0.0;
      final discountPerc = double.tryParse(discountCtrl.text) ?? 0.0;
      final gstPerc = double.tryParse(gstPercCtrl.text) ?? 0.0;

      baseAmount = _round2(qty * rate);
      discountAmount = _round2(baseAmount * (discountPerc / 100));
      taxableValue = _round2(baseAmount - discountAmount);
      totalTaxAmount = _round2(taxableValue * (gstPerc / 100));
      lineTotal = _round2(taxableValue + totalTaxAmount);
    }

    recalc();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Firestore search -> update local list
            Future<void> _searchProducts(String query) async {
              // Debouncing logic for better performance
              if (_debounce?.isActive ?? false) _debounce!.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () async {
                final results = await _fetchProductSuggestions(query);
                setDialogState(() {
                  dialogProducts = results;
                });
              });
            }

            InputDecoration _dialogDecoration(String label, IconData icon) {
              return InputDecoration(
                labelText: label,
                prefixIcon: Icon(icon, color: navy),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFCBD3E1)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                  borderSide: BorderSide(color: navy, width: 1.4),
                ),
              );
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: const Text(
                "Add Item",
                style: TextStyle(fontWeight: FontWeight.bold, color: navy),
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ITEM NAME + AJAX
                      Autocomplete<Map<String, dynamic>>(
                        optionsBuilder: (TextEditingValue value) {
                          if (value.text.isEmpty) {
                            return const Iterable<Map<String, dynamic>>.empty();
                          }
                          return dialogProducts.where(
                            (p) => (p['item'] as String).toLowerCase().contains(
                              value.text.toLowerCase(),
                            ),
                          );
                        },
                        displayStringForOption: (opt) => opt['item'] ?? '',
                        fieldViewBuilder:
                            (
                              context,
                              textController,
                              focusNode,
                              onFieldSubmitted,
                            ) {
                              // initialise controller once
                              if (textController.text.isEmpty &&
                                  itemCtrl.text.isNotEmpty) {
                                textController.text = itemCtrl.text;
                              }
                              return TextFormField(
                                controller: textController,
                                focusNode: focusNode,
                                decoration: _dialogDecoration(
                                  "Item Name*",
                                  Icons.inventory_2,
                                ),
                                validator: (v) =>
                                    v == null || v.isEmpty ? 'Required' : null,
                                onChanged: (value) {
                                  itemCtrl.text = value;
                                  _searchProducts(
                                    value,
                                  ); // AJAX call (Debounced)
                                },
                              );
                            },
                        optionsViewBuilder: (context, onSelected, options) {
                          if (options.isEmpty) return const SizedBox.shrink();
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 6,
                              borderRadius: BorderRadius.circular(10),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxHeight: 220,
                                  maxWidth: 400,
                                ),
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  itemCount: options.length,
                                  itemBuilder: (context, index) {
                                    final opt = options.elementAt(index);
                                    return ListTile(
                                      title: Text(opt['item'] ?? ''),
                                      subtitle: Text(
                                        "HSN: ${opt['hsn_code'] ?? '-'}  •  ₹${opt['rate']}  •  GST ${opt['gst_percent']}%",
                                      ),
                                      onTap: () => onSelected(opt),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                        onSelected: (selection) {
                          // AUTO-FILL ALL FIELDS
                          setDialogState(() {
                            itemCtrl.text = selection['item'] ?? '';
                            hsnCtrl.text = selection['hsn_code'] ?? '';
                            qtyCtrl.text = '1';
                            rateCtrl.text = (selection['rate'] ?? 0.0)
                                .toString();
                            gstPercCtrl.text = (selection['gst_percent'] ?? 0.0)
                                .toString();
                            selectedUnit = selection['unit'] ?? 'Unit';
                            dialogProducts = [];
                            recalc();
                          });
                        },
                      ),

                      const SizedBox(height: 10),

                      // HSN
                      TextFormField(
                        controller: hsnCtrl,
                        decoration: _dialogDecoration(
                          "HSN",
                          Icons.qr_code_2_outlined,
                        ),
                      ),

                      const SizedBox(height: 10),

                      // Qty + Unit
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: qtyCtrl,
                              decoration: _dialogDecoration(
                                "Qty",
                                Icons.tag_outlined,
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              validator: (v) =>
                                  (double.tryParse(v ?? '') ?? 0) <= 0
                                  ? 'Invalid'
                                  : null,
                              onChanged: (_) => setDialogState(recalc),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,

                              value:
                                  selectedUnit != null &&
                                      customUOMs.contains(selectedUnit)
                                  ? selectedUnit
                                  : null,

                              decoration: _inputDecoration(
                                "Unit*",
                                Icons.scale_outlined,
                              ).copyWith(prefixIcon: null),

                              hint: const Text("Select Unit"),

                              items: customUOMs.toSet().map((unit) {
                                return DropdownMenuItem<String>(
                                  value: unit,
                                  child: Text(unit),
                                );
                              }).toList(),

                              onChanged: (v) {
                                setDialogState(() {
                                  selectedUnit = v;
                                });
                              },

                              validator: (v) => v == null ? "Required" : null,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // Rate + Discount
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: rateCtrl,
                              decoration: _dialogDecoration(
                                "Rate",
                                Icons.currency_rupee,
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              validator: (v) =>
                                  (double.tryParse(v ?? '') ?? 0) < 0
                                  ? 'Invalid'
                                  : null,
                              onChanged: (_) => setDialogState(recalc),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: discountCtrl,
                              decoration: _dialogDecoration(
                                "Discount %",
                                Icons.discount_outlined,
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              onChanged: (_) => setDialogState(recalc),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // GST %
                      TextFormField(
                        controller: gstPercCtrl,
                        decoration: _dialogDecoration(
                          "GST %",
                          Icons.percent_outlined,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setDialogState(recalc),
                      ),

                      const SizedBox(height: 16),

                      // Summary
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: lightGrey,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildTotalRow("Taxable", taxableValue, false),
                            _buildTotalRow("Tax", totalTaxAmount, false),
                            const Divider(),
                            _buildTotalRow("Line Total", lineTotal, true),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: navy)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: navy,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 10,
                    ),
                  ),
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;

                    final newItem = {
                      'item': itemCtrl.text.trim(),
                      'hsn_code': hsnCtrl.text.trim(),
                      'qty': double.tryParse(qtyCtrl.text) ?? 0.0,
                      'rate': double.tryParse(rateCtrl.text) ?? 0.0,
                      'discount': double.tryParse(discountCtrl.text) ?? 0.0,
                      'gst_percent': double.tryParse(gstPercCtrl.text) ?? 0.0,
                      'unit': selectedUnit ?? 'Unit',

                      // calculated (will be re-calculated in _recalculateTotals for tax split)
                      'base_amount': baseAmount,
                      'discount_amount': discountAmount,
                      'taxable_amount': taxableValue,
                      'cgst_amount': 0.0,
                      'sgst_amount': 0.0,
                      'igst_amount': 0.0,
                      'line_total': lineTotal,
                    };

                    setState(() {
                      if (isEditing && itemIndex != null) {
                        _items[itemIndex] = newItem;
                      } else {
                        _items.add(newItem);
                      }
                      _recalculateTotals(); // Update totals after item is added/edited
                    });

                    Navigator.pop(context);
                  },
                  child: Text(isEditing ? "Update" : "Add"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --------------------------------------------------------------------------
  // --- CORE CONVERSION LOGIC ------------------------------------------------
  // --------------------------------------------------------------------------

  // 🔑 1. Generate Invoice Number using a Firestore Transaction
  Future<String> _generateNextInvoiceNumber() async {
    final uid = _auth.currentUser!.uid;
    // Counter document location
    final counterRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('counters');

    return _firestore.runTransaction((transaction) async {
      final counterSnapshot = await transaction.get(counterRef);
      int currentCount = 0;

      if (counterSnapshot.exists) {
        // Use a safe cast or null check
        currentCount =
            (counterSnapshot.data()?['invoice_count'] as num?)?.toInt() ?? 0;
      }

      final nextCount = currentCount + 1;
      // Increment the counter
      transaction.set(counterRef, {
        'invoice_count': nextCount,
      }, SetOptions(merge: true));

      // Format: INV-1, INV-2, etc.
      return 'INV-$nextCount';
    });
  }

  // 🔑 2. Corrected Prepare Data for Invoice Firestore Structure
  Future<Map<String, dynamic>> _prepareInvoiceData(
    Map<String, dynamic> quotationData,
  ) async {
    // A. Map Items to Invoice format
    final itemsList = (quotationData['items'] as List).map((item) {
      return {
        "item_name": item['item'] ?? '',
        "hsn_code": item['hsn_code'] ?? '',
        "qty": item['qty'] ?? 0,
        "rate": item['rate'] ?? 0,
        "unit": item['unit'] ?? 'Nos',
        "discount": item['discount'] ?? 0,
        "gst_percent": item['gst_percent'] ?? 0,
        // Map line calculation fields (using calculated values from _recalculateTotals)
        "taxable_amount": item['taxable_amount'] ?? 0.0,
        "cgst":
            item['cgst_amount'] ?? 0.0, // Correctly mapped to Invoice format
        "sgst":
            item['sgst_amount'] ?? 0.0, // Correctly mapped to Invoice format
        "igst":
            item['igst_amount'] ?? 0.0, // Correctly mapped to Invoice format
        "line_total": item['line_total'] ?? 0.0,
      };
    }).toList();

    // B. Map Summary and Header fields to Invoice format
    final invoiceNumber = await _generateNextInvoiceNumber();
    final now = DateTime.now();
    final dueDate = now.add(const Duration(days: 7)); // Default 7-day due date

    return {
      "billing_address": quotationData['billing_address'],
      "shipping_address": quotationData['shipping_address'],
      "customer_name": quotationData['customer_name'],
      "customer_mobile": quotationData['mobile'],
      "customer_state": quotationData['customer_state'],
      "customer_gstin": quotationData['customer_gstin'],
      // Core Invoice Fields
      "invoice_number": invoiceNumber,
      "invoice_date": now.toIso8601String(),
      "due_date": dueDate.toIso8601String(),
      "status": "Pending", // Initial status for a new invoice
      "tax_type": quotationData['tax_type'],

      // Summary Totals (Using the totals calculated and saved in quotationData)
      "subtotal":
          quotationData['total_taxable'], // Taxable Value is the subtotal before tax
      "cgst_total": quotationData['cgst_total'],
      "sgst_total": quotationData['sgst_total'],
      "igst_total": quotationData['igst_total'],
      "grand_total": quotationData['grand_total'],

      "note": quotationData['note'],
      "items": itemsList,

      // Metadata for traceability and indexing
      "quotation_id": quotationData['quotation_id'],
      "created_at": FieldValue.serverTimestamp(),
      "updated_at": FieldValue.serverTimestamp(),
    };
  }

  // 🔑 3. Corrected Handles the final action (Update or Convert)
  Future<void> _handleQuotationAction() async {
    if (!_formKey.currentState!.validate()) return;

    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one item.')),
      );
      return;
    }

    // CRITICAL FIX: Run the full recalculation logic one last time.
    _recalculateTotals();

    // The state variables now hold the correct, fully calculated totals.
    final quotationData = {
      'quotation_id': widget.quotationId,
      'customer_name': _customerNameController.text.trim(),
      'mobile': _mobileController.text.trim(),
      'billing_address': _billingAddressController.text.trim(),
      'shipping_address': _shippingAddressController.text.trim(),
      'customer_gstin': _gstinController.text.trim(),
      'customer_state': _customerState,
      'tax_type': _isInterState ? 'IGST' : 'CGST_SGST',
      'note': _noteController.text.trim(),
      'quotation_date': _quotationDate.toIso8601String(),
      'items': _items,
      'subtotal_before_discount': _subtotalBeforeDiscount,
      'total_discount': _totalDiscount,
      'total_taxable': _totalTaxable,
      'cgst_total': _totalCGST, // Use corrected state variable
      'sgst_total': _totalSGST, // Use corrected state variable
      'igst_total': _totalIGST, // Use corrected state variable
      'grand_total': _grandTotal, // Use corrected state variable
      'is_interstate': _isInterState,
    };

    try {
      if (widget.isConversion) {
        // 1. Prepare Invoice Data
        final invoiceData = await _prepareInvoiceData(quotationData);

        // 2. Perform conversion
        await widget.onConvert(invoiceData);

        // 3. Update Quotation status to 'Converted'
        await widget.onUpdate({
          ...quotationData,
          'status': 'Converted',
          'updated_at': FieldValue.serverTimestamp(),
        });
      } else {
        // Update Quotation (Edit/Save)
        await widget.onUpdate({
          ...quotationData,
          'updated_at': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
  // --------------------------------------------------------------------------
  // --- UI IMPLEMENTATION ----------------------------------------------------
  // --------------------------------------------------------------------------

  // Widget to display a single total row
  Widget _buildTotalRow(
    String label,
    double amount,
    bool isGrandTotal, {
    bool isNegative = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isGrandTotal ? 16 : 14,
              fontWeight: isGrandTotal ? FontWeight.bold : FontWeight.w500,
              color: isGrandTotal ? primaryColor : Colors.black87,
            ),
          ),
          Text(
            "₹${isNegative ? '-' : ''}${amount.abs().toStringAsFixed(2)}",
            style: TextStyle(
              fontSize: isGrandTotal ? 16 : 14,
              fontWeight: isGrandTotal ? FontWeight.bold : FontWeight.w600,
              color: isGrandTotal
                  ? primaryColor
                  : (isNegative ? Colors.red.shade700 : Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  // Item List Display
  Widget _buildItemList() {
    if (_items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            "No items added to this quotation yet. Tap 'Add Item' above.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontStyle: FontStyle.italic,
              color: Colors.grey.shade600,
            ),
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListView(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        children: _items.asMap().entries.map((entry) {
          int index = entry.key;
          Map<String, dynamic> item = entry.value;

          return Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                leading: CircleAvatar(
                  backgroundColor: accentColor.withOpacity(0.1),
                  child: Text(
                    "${index + 1}",
                    style: TextStyle(
                      color: accentColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  "${item['item'] ?? 'Unknown Item'}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  "Qty: ${item['qty']?.toStringAsFixed(0) ?? 0} ${item['unit'] ?? ''} @ ₹${item['rate']?.toStringAsFixed(2) ?? '0.00'}"
                  "\nTaxable: ₹${item['taxable_amount']?.toStringAsFixed(2) ?? '0.00'} | Total: ₹${item['line_total']?.toStringAsFixed(2) ?? '0.00'}",
                  style: const TextStyle(fontSize: 13),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.edit,
                        size: 20,
                        color: primaryColor.withOpacity(0.8),
                      ),
                      onPressed: () => _showAddItemDialog(
                        existingItem: item,
                        itemIndex: index,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        setState(() {
                          _items.removeAt(index);
                          _recalculateTotals();
                        });
                      },
                    ),
                  ],
                ),
              ),
              if (index < _items.length - 1)
                const Divider(height: 1, indent: 16, endIndent: 16),
            ],
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String appBarTitle = widget.isConversion
        ? "Convert to Invoice 🔄"
        : "Edit Quotation ✍️";
    final String actionButtonText = widget.isConversion
        ? "CONVERT TO INVOICE"
        : "SAVE QUOTATION CHANGES";

    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
        centerTitle: true,
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Customer Details ---
              Text(
                "Customer Information",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
              const SizedBox(height: 12),

              // Customer Name with Suggestions (TextFormField only for brevity)
              TextFormField(
                controller: _customerNameController,
                decoration: _inputDecoration(
                  "Customer Name*",
                  Icons.person_outline,
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Customer name required' : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _mobileController,
                decoration: _inputDecoration(
                  "Mobile Number*",
                  Icons.phone_outlined,
                ),
                keyboardType: TextInputType.phone,
                validator: (v) =>
                    v == null || v.isEmpty ? 'Mobile required' : null,
              ),
              const SizedBox(height: 12),

              // GSTIN & State Row
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _gstinController,
                      decoration: _inputDecoration(
                        "GSTIN/UIN",
                        Icons.credit_card_outlined,
                      ),
                      onChanged: (v) {
                        if (v.length == 15) {
                          final state = _getStateFromGSTIN(v);
                          if (_indianStates.contains(state)) {
                            setState(() {
                              _customerState = state;
                              _recalculateTotals();
                            });
                          }
                        }
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
                            _recalculateTotals(); // CRITICAL: Recalc on state change
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
                maxLines: 2,
                decoration: _inputDecoration(
                  "Billing Address",
                  Icons.location_city_outlined,
                ),
              ),
              const SizedBox(height: 12),

              // Shipping Address
              TextFormField(
                controller: _shippingAddressController,
                maxLines: 2,
                decoration: _inputDecoration(
                  "Shipping Address (if different)",
                  Icons.local_shipping_outlined,
                ),
              ),
              const SizedBox(height: 24),

              // --- Items Section ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Items Table (${_items.length})",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _showAddItemDialog(),
                    icon: const Icon(Icons.add_shopping_cart, size: 18),
                    label: const Text("Add Item"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Item List
              _buildItemList(),
              const SizedBox(height: 24),

              // --- Totals Summary ---
              Text(
                "Invoice Summary",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: infoColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  children: [
                    _buildTotalRow(
                      "Taxable Value (Subtotal)",
                      _totalTaxable,
                      false,
                    ),
                    _buildTotalRow(
                      "Total Discount",
                      _totalDiscount,
                      false,
                      isNegative: true,
                    ),
                    const Divider(height: 16),
                    if (!_isInterState)
                      _buildTotalRow("CGST Total", _totalCGST, false),
                    if (!_isInterState)
                      _buildTotalRow("SGST Total", _totalSGST, false),
                    if (_isInterState)
                      _buildTotalRow("IGST Total", _totalIGST, false),
                    const Divider(height: 16),
                    _buildTotalRow("GRAND TOTAL", _grandTotal, true),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // --- Notes ---
              Text(
                "Notes & Status",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _noteController,
                maxLines: 4,
                decoration: _inputDecoration(
                  "Notes / Terms & Conditions",
                  Icons.notes_outlined,
                ),
              ),
              const SizedBox(height: 30),

              // --- Action Button ---
              ElevatedButton.icon(
                onPressed: _handleQuotationAction,
                icon: Icon(
                  widget.isConversion ? Icons.receipt_long : Icons.edit_note,
                ),
                label: Text(
                  actionButtonText,
                  style: const TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
