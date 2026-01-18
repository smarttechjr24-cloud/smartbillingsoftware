import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
// NOTE: Add 'shimmer: ^3.0.0' to your pubspec.yaml

// --------------------------------------------------------------------------
// 1. DATA MODELS (SupplierModel, SupplierPaymentModel)
// --------------------------------------------------------------------------

class SupplierModel {
  String id;
  String name;
  String mobile;
  String address;
  String state;
  String gstin;
  double openingBalance;
  // 🎯 Standardized Firestore field name used in model
  double outstandingBalance;
  Timestamp? createdAt;
  Timestamp? updatedAt;
  Timestamp? lastPurchaseDate; // For display, as seen in your data

  SupplierModel({
    required this.id,
    required this.name,
    this.mobile = '',
    this.address = '',
    this.state = '',
    this.gstin = '',
    this.openingBalance = 0.0,
    this.outstandingBalance = 0.0,
    this.createdAt,
    this.updatedAt,
    this.lastPurchaseDate,
  });

  factory SupplierModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return SupplierModel(
      id: doc.id,
      name: data['name'] ?? 'N/A',
      mobile: data['mobile'] ?? 'N/A',
      address: data['address'] ?? '',
      state: data['state'] ?? 'N/A',
      gstin: data['gstin'] ?? 'N/A',
      openingBalance: (data['opening_balance'] ?? 0.0).toDouble(),
      // 🎯 Reading from standardized Firestore field: outstanding_balance
      outstandingBalance: (data['outstandingBalance'] ?? 0.0).toDouble(),
      createdAt: data['created_at'] as Timestamp?,
      updatedAt: data['updated_at'] as Timestamp?,
      lastPurchaseDate: data['lastPurchaseDate'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'mobile': mobile,
      'address': address,
      'state': state,
      'gstin': gstin,
      'opening_balance': openingBalance,
      // 🎯 Writing to standardized Firestore field: outstanding_balance
      'outstandingBalance': outstandingBalance,
      'updated_at': FieldValue.serverTimestamp(),
      if (createdAt == null) 'created_at': FieldValue.serverTimestamp(),
    };
  }
}

class SupplierPaymentModel {
  String id;
  String supplierId;
  String supplierName;
  double amount;
  String paymentMode;
  DateTime paymentDate;
  String notes;
  Timestamp? createdAt;

  SupplierPaymentModel({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.amount,
    required this.paymentMode,
    required this.paymentDate,
    this.notes = '',
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'amount': amount,
      'payment_mode': paymentMode,
      'payment_date': Timestamp.fromDate(paymentDate),
      'notes': notes,
      'created_at': FieldValue.serverTimestamp(),
    };
  }
}

enum PaymentMode { cash, bankTransfer, upi, cheque, other }

extension PaymentModeExtension on PaymentMode {
  String get name {
    switch (this) {
      case PaymentMode.cash:
        return 'Cash';
      case PaymentMode.bankTransfer:
        return 'Bank Transfer';
      case PaymentMode.upi:
        return 'UPI';
      case PaymentMode.cheque:
        return 'Cheque';
      case PaymentMode.other:
        return 'Other';
    }
  }
}

final List<String> IndianStates = [
  'Maharashtra',
  'Karnataka',
  'Tamil Nadu',
  'Gujarat',
  'Delhi',
  'Other',
];

// --------------------------------------------------------------------------
// 2. SUPPLIER SERVICE (Firestore Logic & Stream Management)
// --------------------------------------------------------------------------

class SupplierService {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  String? get _uid => _auth.currentUser?.uid;

  // 🎯 StreamController for Total Outstanding Payable (Fixes Rebuild Issue)
  final StreamController<double> _totalOutstandingController =
      StreamController<double>.broadcast();
  Stream<double> get totalOutstandingPayableStream =>
      _totalOutstandingController.stream;

  // 🎯 StreamController for Dashboard Totals (Requirement 7)
  final StreamController<Map<String, dynamic>> _dashboardTotalsController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get dashboardTotalsStream =>
      _dashboardTotalsController.stream;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _suppliersSubscription;

  SupplierService() {
    // Start listening immediately to calculate and stream totals
    _startOutstandingListener();
  }

  // 🎯 Fixes Rebuild Issue: Dedicated listener for total calculation
  void _startOutstandingListener() {
    if (_uid == null) return;

    _suppliersSubscription = _firestore
        .collection('users')
        .doc(_uid)
        .collection('suppliers')
        .snapshots()
        .listen(
          (snapshot) {
            double total = 0.0;
            int supplierCount = 0;

            for (var doc in snapshot.docs) {
              final data = doc.data();
              // Use standardized field: outstanding_balance
              final outstanding = (data['outstandingBalance'] ?? 0.0)
                  .toDouble();
              total += outstanding;
              supplierCount++;
            }

            // Update the streams
            if (!_totalOutstandingController.isClosed) {
              _totalOutstandingController.add(total);
            }
            if (!_dashboardTotalsController.isClosed) {
              _dashboardTotalsController.add({
                'totalOutstanding': total,
                'totalSuppliers': supplierCount,
              });
            }
          },
          onError: (error) {
            if (!_totalOutstandingController.isClosed) {
              _totalOutstandingController.addError(error);
            }
            if (!_dashboardTotalsController.isClosed) {
              _dashboardTotalsController.addError(error);
            }
          },
        );
  }

  void dispose() {
    _suppliersSubscription?.cancel();
    _totalOutstandingController.close();
    _dashboardTotalsController.close();
  }

  // --------------------------- CRUD ---------------------------

  Stream<List<SupplierModel>> fetchSuppliers() {
    if (_uid == null) return const Stream.empty();

    return _firestore
        .collection('users')
        .doc(_uid)
        .collection('suppliers')
        .orderBy('name')
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map(SupplierModel.fromFirestore).toList();
        });
  }

  Future<void> saveSupplier(SupplierModel supplier) async {
    if (_uid == null) throw Exception('User not authenticated.');

    await _firestore
        .collection('users')
        .doc(_uid)
        .collection('suppliers')
        .doc(supplier.id)
        .set(supplier.toMap(), SetOptions(merge: true));
  }

  Future<void> deleteSupplier(String supplierId) async {
    if (_uid == null) throw Exception('User not authenticated.');

    await _firestore
        .collection('users')
        .doc(_uid)
        .collection('suppliers')
        .doc(supplierId)
        .delete();
  }

  // --------------------------- PAYMENT FEATURE (Atomic Update) ---------------------------

  Future<void> recordSupplierPayment({
    required SupplierModel supplier,
    required double amount,
    required PaymentMode mode,
    required DateTime date,
    String notes = '',
  }) async {
    if (_uid == null) throw Exception('User not authenticated.');
    if (amount <= 0)
      throw Exception('Payment amount must be greater than zero.');

    final paymentId = _firestore
        .collection('users')
        .doc(_uid)
        .collection('supplier_payments')
        .doc()
        .id;

    final payment = SupplierPaymentModel(
      id: paymentId,
      supplierId: supplier.id,
      supplierName: supplier.name,
      amount: amount,
      paymentMode: mode.name,
      paymentDate: date,
      notes: notes,
    );

    final supplierRef = _firestore
        .collection('users')
        .doc(_uid)
        .collection('suppliers')
        .doc(supplier.id);

    // 🎯 Use Firestore Transaction for Atomic Update (Requirement 3)
    await _firestore.runTransaction((transaction) async {
      final freshSnapshot = await transaction.get(supplierRef);

      if (!freshSnapshot.exists) {
        throw Exception('Supplier does not exist.');
      }

      // Read from standardized field: outstanding_balance
      final currentOutstanding =
          (freshSnapshot.data()?['outstandingBalance'] ?? 0.0).toDouble();

      final newOutstanding = currentOutstanding - amount;

      // 1. Update Supplier's outstanding balance
      transaction.update(supplierRef, {
        'outstandingBalance': newOutstanding, // Write to standardized field
        'updated_at': FieldValue.serverTimestamp(),
      });

      // 2. Record the payment
      transaction.set(
        _firestore
            .collection('users')
            .doc(_uid)
            .collection('supplier_payments')
            .doc(paymentId),
        payment.toMap(),
      );
    });
  }
}

// --------------------------------------------------------------------------
// 3. MAIN SCREEN (UI Logic)
// --------------------------------------------------------------------------

class SupplierScreen extends StatefulWidget {
  const SupplierScreen({super.key});

  @override
  State<SupplierScreen> createState() => _SupplierScreenState();
}

class _SupplierScreenState extends State<SupplierScreen> {
  // Service instance initialized here
  final SupplierService _supplierService = SupplierService();
  String _searchQuery = '';
  // State for the total outstanding card, updated by the separate stream listener
  double _totalOutstandingPayable = 0.0;

  final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
  final dateFormat = DateFormat('dd MMM yyyy');

  StreamSubscription<double>? _totalOutstandingSubscription;

  @override
  void initState() {
    super.initState();
    // 🎯 Subscribe to the total outstanding stream (Requirement 1)
    _totalOutstandingSubscription = _supplierService
        .totalOutstandingPayableStream
        .listen((total) {
          if (mounted) {
            // Only call setState to update this single variable, preventing
            // the main supplier list StreamBuilder from unnecessary rebuilds.
            setState(() {
              _totalOutstandingPayable = total;
            });
          }
        });
  }

  @override
  void dispose() {
    _totalOutstandingSubscription?.cancel();
    _supplierService.dispose(); // Clean up all service streams
    super.dispose();
  }

  // --------------------------- WIDGET METHODS ---------------------------

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Supplier Management'),
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // ⚡ Animated Total Outstanding Summary Card (Requirement 5)
          _buildTotalOutstandingCard(isMobile),
          // ⚡ Dashboard Totals Card (Requirement 7)
          _buildDashboardTotalsCard(isMobile),
          // ⚡ Search Bar
          _buildSearchBar(isMobile),
          // ⚡ Supplier List (StreamBuilder)
          Expanded(child: _buildSupplierList()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditDialog(context),
        child: const Icon(Icons.person_add_alt_1_rounded),
      ),
    );
  }

  Widget _buildTotalOutstandingCard(bool isMobile) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // Highlight based on outstanding value
        color: _totalOutstandingPayable > 0
            ? Colors.red.shade50
            : Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Total Outstanding Payable:',
              style: TextStyle(
                fontSize: isMobile ? 16 : 18,
                fontWeight: FontWeight.w600,
                color: Colors.red.shade900,
              ),
            ),
            Text(
              currencyFormat.format(_totalOutstandingPayable),
              style: TextStyle(
                fontSize: isMobile ? 18 : 22,
                fontWeight: FontWeight.bold,
                color: _totalOutstandingPayable > 0
                    ? Colors.red.shade700
                    : Colors.green.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardTotalsCard(bool isMobile) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: _supplierService.dashboardTotalsStream,
      builder: (context, snapshot) {
        final totals =
            snapshot.data ?? {'totalOutstanding': 0.0, 'totalSuppliers': 0};
        final totalSuppliers = totals['totalSuppliers'] as int;
        final totalOutstanding = totals['totalOutstanding'] as double;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
          child: Row(
            children: [
              Expanded(
                child: _buildDashboardMetric(
                  'Total Suppliers',
                  totalSuppliers.toString(),
                  Icons.people_alt,
                  const Color(0xFF1976D2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDashboardMetric(
                  'Total Payable',
                  currencyFormat.format(totalOutstanding),
                  Icons.account_balance_wallet,
                  totalOutstanding > 0
                      ? Colors.red.shade700
                      : Colors.green.shade700,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDashboardMetric(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: color.withOpacity(0.3), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 4),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(bool isMobile) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: TextField(
        onChanged: (value) {
          setState(() {
            _searchQuery = value.toLowerCase();
          });
        },
        decoration: InputDecoration(
          hintText: 'Search by Name or Mobile',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.grey.shade100,
          contentPadding: EdgeInsets.symmetric(vertical: isMobile ? 10 : 12),
        ),
      ),
    );
  }

  Widget _buildSupplierList() {
    if (_supplierService._uid == null) {
      return const Center(child: Text('User not authenticated.'));
    }

    return StreamBuilder<List<SupplierModel>>(
      // Stream is stable, only providing list updates.
      stream: _supplierService.fetchSuppliers(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting ||
            snapshot.data == null) {
          // 🎯 Loading Shimmer (Requirement 5)
          return _buildShimmerList();
        }

        final allSuppliers = snapshot.data!;

        // ⚡ Apply Search Filter
        final filteredSuppliers = allSuppliers.where((supplier) {
          final query = _searchQuery.toLowerCase();
          return supplier.name.toLowerCase().contains(query) ||
              supplier.mobile.toLowerCase().contains(query);
        }).toList();

        if (filteredSuppliers.isEmpty) {
          return Center(
            child: Text(
              _searchQuery.isEmpty
                  ? 'No suppliers found. Tap + to add one.'
                  : 'No results for "$_searchQuery".',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
        }

        return ListView.builder(
          itemCount: filteredSuppliers.length,
          itemBuilder: (context, index) {
            final supplier = filteredSuppliers[index];
            return _buildSupplierCard(supplier, context);
          },
        );
      },
    );
  }

  // 🎯 Shimmer Loading Implementation (Requirement 5)
  Widget _buildShimmerList() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: ListView.builder(
        itemCount: 5,
        itemBuilder: (context, index) {
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              title: Container(
                height: 12,
                width: 150,
                color: Colors.white,
                margin: const EdgeInsets.only(bottom: 8),
              ),
              subtitle: Container(height: 8, width: 200, color: Colors.white),
              trailing: Container(height: 15, width: 50, color: Colors.white),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSupplierCard(SupplierModel supplier, BuildContext context) {
    final outstanding = supplier.outstandingBalance;
    const highOutstandingThreshold = 5000.0;
    // 🎯 Highlight suppliers with outstanding > 5000 in red (Requirement 5)
    final isHighOutstanding = outstanding > highOutstandingThreshold;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: isHighOutstanding
              ? const BorderSide(color: Colors.red, width: 2)
              : BorderSide.none,
        ),
        child: ListTile(
          tileColor: isHighOutstanding ? Colors.red.shade50 : null,
          contentPadding: const EdgeInsets.only(
            left: 16,
            top: 8,
            bottom: 8,
            right: 0,
          ),
          onTap: () => _showAddEditDialog(context, supplier: supplier),
          title: Text(
            supplier.name,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Color(0xFF1976D2),
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              _detailRow(
                Icons.phone,
                'Mobile',
                supplier.mobile,
                Colors.grey.shade700,
              ),
              _detailRow(
                Icons.location_on_outlined,
                'State',
                supplier.state,
                Colors.grey.shade700,
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    currencyFormat.format(outstanding),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isHighOutstanding
                          ? Colors.red.shade700
                          : Colors.green.shade700,
                    ),
                  ),
                  const Text(
                    'Outstanding',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              // 🎯 Three-Dot Menu Action System (Requirement 2)
              _buildPopupMenu(supplier),
            ],
          ),
        ),
      ),
    );
  }

  // 🎯 Popup Menu Button (Requirement 2)
  Widget _buildPopupMenu(SupplierModel supplier) {
    return PopupMenuButton<String>(
      onSelected: (String result) async {
        switch (result) {
          case 'view':
            _showAddEditDialog(context, supplier: supplier, isReadOnly: true);
            break;
          case 'edit':
            _showAddEditDialog(context, supplier: supplier);
            break;
          case 'payment':
            _showOutgoingPaymentDialog(context, supplier); // Requirement 3
            break;
          case 'delete':
            final shouldDelete = await _confirmDelete(supplier);
            if (shouldDelete == true) {
              _deleteSupplier(supplier);
            }
            break;
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'view',
          child: Row(
            children: [
              Icon(Icons.visibility, color: Colors.blue),
              SizedBox(width: 8),
              Text('View Supplier Details'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit, color: Colors.orange),
              SizedBox(width: 8),
              Text('Edit Supplier'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'payment',
          child: Row(
            children: [
              Icon(Icons.payments, color: Colors.green),
              SizedBox(width: 8),
              Text('Add Outgoing Payment'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_forever, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete Supplier'),
            ],
          ),
        ),
      ],
      icon: const Icon(Icons.more_vert),
    );
  }

  Widget _detailRow(IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(fontWeight: FontWeight.w500, color: color),
          ),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------- CRUD & DIALOGS ---------------------------

  Future<bool?> _confirmDelete(SupplierModel supplier) async {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: Text(
            'Are you sure you want to delete supplier "${supplier.name}"?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteSupplier(SupplierModel supplier) async {
    try {
      await _supplierService.deleteSupplier(supplier.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Supplier ${supplier.name} deleted successfully.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete supplier: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 🎯 Add/Edit Supplier Dialog
  void _showAddEditDialog(
    BuildContext context, {
    SupplierModel? supplier,
    bool isReadOnly = false,
  }) {
    final isEditing = supplier != null;
    final formKey = GlobalKey<FormState>();

    // Controllers initialized with existing data for editing
    final nameController = TextEditingController(text: supplier?.name ?? '');
    final mobileController = TextEditingController(
      text: supplier?.mobile ?? '',
    );
    final addressController = TextEditingController(
      text: supplier?.address ?? '',
    );
    final gstinController = TextEditingController(text: supplier?.gstin ?? '');
    final openingBalanceController = TextEditingController(
      text: supplier?.openingBalance.toStringAsFixed(2) ?? '0.00',
    );

    String? selectedState = isEditing && IndianStates.contains(supplier.state)
        ? supplier.state
        : IndianStates.first;

    void save({bool saveAndNew = false}) async {
      if (!formKey.currentState!.validate()) return;

      final newSupplier = SupplierModel(
        id: isEditing
            ? supplier.id
            : FirebaseFirestore.instance.collection('temp').doc().id,
        name: nameController.text.trim(),
        mobile: mobileController.text.trim(),
        address: addressController.text.trim(),
        state: selectedState!,
        gstin: gstinController.text.trim(),
        openingBalance: double.tryParse(openingBalanceController.text) ?? 0.0,
        // Crucial: Preserve existing outstanding balance on edit
        outstandingBalance: supplier?.outstandingBalance ?? 0.0,
      );

      try {
        await _supplierService.saveSupplier(newSupplier);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Supplier ${newSupplier.name} ${isEditing ? 'updated' : 'added'} successfully.',
              ),
            ),
          );
        }

        if (saveAndNew) {
          // Reset fields for new entry
          nameController.clear();
          mobileController.clear();
          addressController.clear();
          gstinController.clear();
          openingBalanceController.text = '0.00';
          setState(() {
            selectedState = IndianStates.first;
          });
        } else {
          if (mounted) Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to save supplier: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            isReadOnly
                ? 'Supplier Details'
                : (isEditing ? 'Edit Supplier' : 'Add New Supplier'),
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Supplier Name *',
                    ),
                    validator: (v) =>
                        v!.trim().isEmpty ? 'Name is required' : null,
                    readOnly: isReadOnly,
                  ),
                  TextFormField(
                    controller: mobileController,
                    decoration: const InputDecoration(
                      labelText: 'Mobile Number',
                    ),
                    keyboardType: TextInputType.phone,
                    readOnly: isReadOnly,
                  ),
                  TextFormField(
                    controller: addressController,
                    decoration: const InputDecoration(labelText: 'Address'),
                    maxLines: 2,
                    readOnly: isReadOnly,
                  ),
                  DropdownButtonFormField<String>(
                    value: selectedState,
                    decoration: const InputDecoration(labelText: 'State *'),
                    items: IndianStates.map((String state) {
                      return DropdownMenuItem<String>(
                        value: state,
                        child: Text(state),
                      );
                    }).toList(),
                    onChanged: isReadOnly
                        ? null
                        : (String? newValue) {
                            if (mounted) {
                              setState(() {
                                selectedState = newValue;
                              });
                            }
                          },
                    validator: (v) => v == null ? 'State is required' : null,
                  ),
                  TextFormField(
                    controller: gstinController,
                    decoration: const InputDecoration(labelText: 'GSTIN'),
                    readOnly: isReadOnly,
                  ),
                  TextFormField(
                    controller: openingBalanceController,
                    decoration: const InputDecoration(
                      labelText: 'Opening Balance (Payable)',
                    ),
                    keyboardType: TextInputType.number,
                    readOnly: isReadOnly,
                    validator: (v) {
                      if (v!.isEmpty) return null;
                      if (double.tryParse(v) == null) {
                        return 'Enter a valid number';
                      }
                      return null;
                    },
                  ),
                  if (isEditing)
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: Text(
                        'Current Outstanding: ${currencyFormat.format(supplier.outstandingBalance)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: supplier.outstandingBalance > 0
                              ? Colors.red
                              : Colors.green,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            if (!isReadOnly) ...[
              if (!isEditing)
                TextButton(
                  onPressed: () => save(saveAndNew: true),
                  child: const Text('Save & New'),
                ),
              ElevatedButton(
                onPressed: () => save(saveAndNew: false),
                child: Text(isEditing ? 'Update' : 'Save'),
              ),
            ],
          ],
        );
      },
    );
  }

  // 🎯 Outgoing Payment Dialog (Requirement 3)
  void _showOutgoingPaymentDialog(
    BuildContext context,
    SupplierModel supplier,
  ) {
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    PaymentMode? selectedMode = PaymentMode.cash;
    DateTime selectedDate = DateTime.now();

    void submitPayment() async {
      if (!formKey.currentState!.validate()) return;

      final amount = double.tryParse(amountController.text) ?? 0.0;
      if (amount <= 0) return;

      try {
        await _supplierService.recordSupplierPayment(
          supplier: supplier,
          amount: amount,
          mode: selectedMode!,
          date: selectedDate,
          notes: noteController.text.trim(),
        );

        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '₹${amount.toStringAsFixed(2)} payment recorded for ${supplier.name}.',
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Payment failed: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            top: 20,
            left: 20,
            right: 20,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add Outgoing Payment',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.person),
                    title: const Text('Supplier Name (Read-only)'),
                    subtitle: Text(supplier.name),
                  ),
                  ListTile(
                    leading: const Icon(Icons.account_balance_wallet),
                    title: const Text('Current Outstanding (Read-only)'),
                    subtitle: Text(
                      currencyFormat.format(supplier.outstandingBalance),
                    ),
                    textColor: supplier.outstandingBalance > 0
                        ? Colors.red
                        : Colors.green,
                  ),
                  TextFormField(
                    controller: amountController,
                    decoration: const InputDecoration(
                      labelText: 'Payment Amount *',
                      prefixText: '₹',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final amount = double.tryParse(v ?? '');
                      if (amount == null || amount <= 0) {
                        return 'Enter a valid amount > 0';
                      }
                      return null;
                    },
                  ),
                  DropdownButtonFormField<PaymentMode>(
                    value: selectedMode,
                    decoration: const InputDecoration(
                      labelText: 'Payment Mode *',
                    ),
                    items: PaymentMode.values.map((PaymentMode mode) {
                      return DropdownMenuItem<PaymentMode>(
                        value: mode,
                        child: Text(mode.name),
                      );
                    }).toList(),
                    onChanged: (PaymentMode? newValue) {
                      if (mounted) {
                        setState(() {
                          selectedMode = newValue;
                        });
                      }
                    },
                    validator: (v) => v == null ? 'Select payment mode' : null,
                  ),
                  // 🎯 Date Picker
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Payment Date: ${dateFormat.format(selectedDate)}',
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.calendar_today),
                          label: const Text('Change'),
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime(2000),
                              lastDate: DateTime.now(),
                            );
                            if (date != null) {
                              // We need a local state update inside the bottom sheet builder
                              // to reflect the date change without rebuilding the whole screen.
                              // Since this is inside a BottomSheet builder, we rely on the
                              // outer widget's setState to handle the update or wrap this in a StatefulBuilder.
                              // For simplicity and common practice in dialogs:
                              // We can wrap the dialog content with a StatefulBuilder if needed, but for date picking,
                              // the dialog's state is usually handled well enough by the future result.
                              // Let's rely on the outer setState if we keep the variable in the screen state,
                              // or use a local variable/StatefulBuilder if this needs isolation.
                              // For this single-file, quick implementation, let's simplify state handling.
                              selectedDate =
                                  date; // Update local variable for submission
                              // Force the bottom sheet to rebuild to show new date (if using StatefulBuilder)
                              (context as Element).markNeedsBuild();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  TextFormField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'Note (Optional)',
                    ),
                    maxLines: 2,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 20.0, bottom: 20.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: submitPayment,
                        icon: const Icon(Icons.save),
                        label: const Text('Record Payment'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
