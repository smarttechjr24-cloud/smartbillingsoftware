import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({Key? key}) : super(key: key);

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  String? get _uid => _auth.currentUser?.uid;

  final primaryColor = const Color(0xFF1976D2);
  final accentColor = const Color(0xFF1976D2);
  final deleteColor = Colors.redAccent;
  final outstandingColor = Colors.orange.shade700;
  final successColor = Colors.green.shade700;

  final String _companyState = "Tamil Nadu";

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = "";

  final List<String> _indianStates = [
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

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() {
        _searchQuery = _searchCtrl.text.toLowerCase().trim();
      });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _getCustomers() {
    if (_uid == null) return const Stream.empty();
    return _firestore
        .collection('users')
        .doc(_uid)
        .collection('customers')
        .orderBy('name')
        .snapshots();
  }

  String _determineTaxType(String customerState) {
    if (customerState == _companyState) {
      return "CGST_SGST";
    } else {
      return "IGST";
    }
  }

  void _showSnack(String msg, {bool success = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: success ? accentColor : deleteColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _addOrEditCustomer({
    Map<String, dynamic>? data,
    String? id,
  }) async {
    final _formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: data?['name']);
    final phoneCtrl = TextEditingController(text: data?['phone']);
    final addressCtrl = TextEditingController(text: data?['address']);
    final gstCtrl = TextEditingController(text: data?['gst_number']);
    final outstandingCtrl = TextEditingController(
      text: (data?['outstanding'] is num)
          ? data!['outstanding'].toString()
          : '0.0',
    );
    String? selectedState = data?['customer_state'] ?? _companyState;
    final isNew = data == null;

    await showDialog(
      context: context,
      builder: (_) => LayoutBuilder(
        builder: (context, constr) {
          final width = MediaQuery.of(context).size.width;
          final isSmall = width < 600;
          final contentPad = isSmall ? 12.0 : 24.0;

          return StatefulBuilder(
            builder: (context, setStateDialog) {
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: Row(
                  children: [
                    Icon(
                      isNew ? Icons.person_add : Icons.edit,
                      color: primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isNew ? "New Customer" : "Edit Customer",
                      style: TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                content: Container(
                  width: width * (isSmall ? 0.98 : 0.65),
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(contentPad),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextFormField(
                            controller: nameCtrl,
                            decoration: _inputDecoration(
                              "Customer Name",
                              Icons.business,
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? "Name is required"
                                : null,
                          ),
                          SizedBox(height: isSmall ? 8 : 12),
                          TextFormField(
                            controller: phoneCtrl,
                            keyboardType: TextInputType.phone,
                            decoration: _inputDecoration(
                              "Phone Number",
                              Icons.phone,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(10),
                            ],
                            validator: (v) {
                              if (v == null || v.trim().isEmpty)
                                return "Phone is required";
                              if (v.length != 10)
                                return "Phone must be 10 digits";
                              return null;
                            },
                          ),
                          SizedBox(height: isSmall ? 8 : 12),
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            value: selectedState,
                            decoration: _inputDecoration("State", Icons.map),
                            items: _indianStates.map((state) {
                              return DropdownMenuItem(
                                value: state,
                                child: Text(state),
                              );
                            }).toList(),
                            onChanged: (val) =>
                                setStateDialog(() => selectedState = val),
                            validator: (v) {
                              if (gstCtrl.text.isNotEmpty && v == null) {
                                return "State required for GST calculation";
                              }
                              return null;
                            },
                          ),
                          SizedBox(height: isSmall ? 8 : 12),
                          TextFormField(
                            controller: gstCtrl,
                            textCapitalization: TextCapitalization.characters,
                            decoration: _inputDecoration(
                              "GST Number (Optional)",
                              Icons.confirmation_number,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[a-zA-Z0-9]'),
                              ),
                              LengthLimitingTextInputFormatter(15),
                            ],
                            validator: (v) {
                              if (v != null && v.isNotEmpty) {
                                if (v.length != 15)
                                  return "GST must be 15 characters";
                                final gstRegex = RegExp(
                                  r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$',
                                );
                                if (!gstRegex.hasMatch(v))
                                  return "Invalid GST Format";
                              }
                              return null;
                            },
                          ),
                          SizedBox(height: isSmall ? 8 : 12),

                          TextFormField(
                            controller: addressCtrl,
                            maxLines: 2,
                            decoration: _inputDecoration(
                              "Billing Address",
                              Icons.location_on,
                            ),
                          ),
                          SizedBox(height: isSmall ? 8 : 12),
                          if (isNew)
                            TextFormField(
                              controller: outstandingCtrl,
                              keyboardType: TextInputType.number,
                              decoration: _inputDecoration(
                                "Opening Balance (₹)",
                                Icons.account_balance_wallet,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*\.?\d{0,2}'),
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
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      "Cancel",
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      if (_formKey.currentState!.validate()) {
                        final taxType = _determineTaxType(
                          selectedState ?? _companyState,
                        );

                        final dataMap = {
                          'name': nameCtrl.text.trim(),
                          'phone': phoneCtrl.text.trim(),
                          'address': addressCtrl.text.trim(),
                          'gst_number': gstCtrl.text.trim().toUpperCase(),
                          'customer_state': selectedState,
                          'tax_type': taxType,
                          'updated_at': FieldValue.serverTimestamp(),
                        };

                        final ref = _firestore
                            .collection('users')
                            .doc(_uid)
                            .collection('customers');
                        try {
                          if (id == null) {
                            dataMap['outstanding'] =
                                double.tryParse(outstandingCtrl.text) ?? 0.0;
                            dataMap['created_at'] =
                                FieldValue.serverTimestamp();
                            await ref.add(dataMap);
                            _showSnack(
                              "✅ Customer added successfully!",
                              success: true,
                            );
                          } else {
                            await ref.doc(id).update(dataMap);
                            _showSnack("✅ Customer updated!", success: true);
                          }
                        } catch (e) {
                          _showSnack("❌ Error: $e");
                        }
                        if (context.mounted) Navigator.pop(context);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(isNew ? "Save Customer" : "Update"),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _deleteCustomer(String id, String name) async {
    final bool confirm =
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Delete Customer?"),
            content: Text("Are you sure you want to delete '$name'?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text("Delete", style: TextStyle(color: deleteColor)),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      await _firestore
          .collection('users')
          .doc(_uid)
          .collection('customers')
          .doc(id)
          .delete();
      _showSnack("Customer deleted");
    }
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: primaryColor.withOpacity(0.7)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: accentColor, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      isDense: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isSmall = width < 600;
    final outerPad = isSmall ? 7.0 : 13.0;
    final topPad = isSmall ? 4.0 : 10.0;
    final bottomPad = isSmall ? 50.0 : 80.0;
    final avatarRadius = isSmall ? 19.0 : 24.0;
    final titleFont = isSmall ? 13.9 : 16.0;
    final subtitleFont = isSmall ? 12.2 : 13.3;
    final chipFont = isSmall ? 8.4 : 10.0;
    final iconSize = isSmall ? 15.0 : 20.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Parties / Customers"),
        centerTitle: true,
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(isSmall ? 50 : 70),
          child: Padding(
            padding: EdgeInsets.fromLTRB(outerPad + 6, 0, outerPad + 6, 10),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: "Search Name or Phone...",
                filled: true,
                fillColor: Colors.white,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchCtrl.clear(),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.symmetric(vertical: isSmall ? 1 : 5),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: accentColor,
        foregroundColor: Colors.white,
        onPressed: () => _addOrEditCustomer(),
        icon: Icon(Icons.add, size: isSmall ? 19 : 24),
        label: Text("Add Party", style: TextStyle(fontSize: isSmall ? 13 : 15)),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _getCustomers(),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data!.docs;

          final filteredDocs = docs.where((doc) {
            final data = doc.data();
            final name = (data['name'] ?? '').toLowerCase();
            final phone = (data['phone'] ?? '').toString();
            return name.contains(_searchQuery) || phone.contains(_searchQuery);
          }).toList();

          if (filteredDocs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.person_search_outlined,
                    size: isSmall ? 40 : 60,
                    color: Colors.grey[400],
                  ),
                  SizedBox(height: isSmall ? 4 : 10),
                  Text(
                    _searchQuery.isEmpty
                        ? "No customers yet."
                        : "No results found.",
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.only(
              top: topPad,
              bottom: bottomPad,
              left: outerPad,
              right: outerPad,
            ),
            itemCount: filteredDocs.length,
            itemBuilder: (context, index) {
              final doc = filteredDocs[index];
              final data = doc.data();

              final name = data['name'] ?? 'N/A';
              final phone = data['phone'] ?? '';
              final state = data['customer_state'] ?? 'Unknown State';
              final gst = data['gst_number'] ?? '';
              final taxType = data['tax_type'] ?? 'IGST';
              final double outstanding = (data['outstanding'] is num)
                  ? data['outstanding'].toDouble()
                  : 0.0;

              return Card(
                elevation: 2,
                margin: EdgeInsets.only(bottom: isSmall ? 5 : 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: EdgeInsets.all(isSmall ? 7 : 12),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: avatarRadius,
                            backgroundColor: primaryColor.withOpacity(0.1),
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: primaryColor,
                                fontSize: avatarRadius,
                              ),
                            ),
                          ),
                          SizedBox(width: isSmall ? 8 : 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: titleFont,
                                  ),
                                ),
                                SizedBox(height: isSmall ? 2 : 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.phone,
                                      size: iconSize,
                                      color: Colors.grey[600],
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      phone,
                                      style: TextStyle(
                                        color: Colors.grey[800],
                                        fontSize: subtitleFont,
                                      ),
                                    ),
                                    SizedBox(width: isSmall ? 7 : 12),
                                    Icon(
                                      Icons.location_on,
                                      size: iconSize,
                                      color: Colors.grey[600],
                                    ),
                                    SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        state,
                                        style: TextStyle(
                                          color: Colors.grey[800],
                                          fontSize: subtitleFont,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: Icon(
                              Icons.more_vert,
                              size: isSmall ? 16 : 20,
                            ),
                            onSelected: (v) {
                              if (v == 'edit')
                                _addOrEditCustomer(data: data, id: doc.id);
                              if (v == 'delete') _deleteCustomer(doc.id, name);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text("Edit"),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text(
                                  "Delete",
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (gst.isNotEmpty)
                                Row(
                                  children: [
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: Colors.green.shade200,
                                        ),
                                      ),
                                      child: Text(
                                        "GST Active",
                                        style: TextStyle(
                                          fontSize: chipFont,
                                          color: Colors.green,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 6),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: Colors.blue.shade200,
                                        ),
                                      ),
                                      child: Text(
                                        taxType.replaceAll('_', '+'),
                                        style: TextStyle(
                                          fontSize: chipFont,
                                          color: Colors.blue,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Text(
                                  "Unregistered",
                                  style: TextStyle(
                                    fontSize: chipFont + 3,
                                    color: Colors.grey[500],
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                "Outstanding",
                                style: TextStyle(
                                  fontSize: chipFont + 2,
                                  color: Colors.grey[600],
                                ),
                              ),
                              Text(
                                "₹${outstanding.toStringAsFixed(2)}",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: titleFont + 1,
                                  color: outstanding > 0
                                      ? outstandingColor
                                      : successColor,
                                ),
                              ),
                            ],
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
      ),
    );
  }
}
