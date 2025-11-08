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

  // --- Theme Colors for Consistency ---
  final primaryColor = const Color(0xFF1F3A5F); // Deep Navy Blue
  final accentColor = const Color(0xFF00A3A3); // Teal/Cyan Accent
  final deleteColor = Colors.redAccent;
  final outstandingColor = Colors.orange.shade700;

  // --- Firestore Stream ---
  Stream<QuerySnapshot<Map<String, dynamic>>> _getCustomers() {
    if (_uid == null) return const Stream.empty();
    return _firestore
        .collection('users')
        .doc(_uid)
        .collection('customers')
        .orderBy('name')
        .snapshots();
  }

  // --- Snack Bar Utility ---
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

  // --- Modal Dialog for Add/Edit Customer ---
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
    final isNew = data == null;

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isNew ? "Add New Customer" : "Edit Customer",
          style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
        ),
        content: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // --- Name ---
                  TextFormField(
                    controller: nameCtrl,
                    decoration: _inputDecoration(
                      "Customer Name",
                      Icons.person_outline,
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? "Name is required"
                        : null,
                  ),
                  const SizedBox(height: 12),
                  // --- Phone ---
                  TextFormField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: _inputDecoration(
                      "Phone Number",
                      Icons.phone_outlined,
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? "Phone is required"
                        : null,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 10,
                  ),
                  const SizedBox(height: 12),
                  // --- Address ---
                  TextFormField(
                    controller: addressCtrl,
                    maxLines: 2,
                    decoration: _inputDecoration(
                      "Address",
                      Icons.location_on_outlined,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // --- GST Number ---
                  TextFormField(
                    controller: gstCtrl,
                    decoration: _inputDecoration(
                      "GST Number (Optional)",
                      Icons.confirmation_number_outlined,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // --- Outstanding (Only editable for NEW customer) ---
                  TextFormField(
                    controller: outstandingCtrl,
                    keyboardType: TextInputType.number,
                    enabled:
                        isNew, // Only allow setting initial outstanding amount
                    decoration: _inputDecoration(
                      "Initial Outstanding (₹)",
                      Icons.money_off,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}'),
                      ),
                    ],
                    validator: (v) {
                      if (!isNew && (v == null || v.trim().isEmpty))
                        return null;
                      if (double.tryParse(v!) == null)
                        return "Enter a valid amount";
                      return null;
                    },
                    style: isNew
                        ? null
                        : TextStyle(color: Colors.grey.shade600),
                  ),
                  if (!isNew)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        "Outstanding balance must be updated via payment/invoice.",
                        style: TextStyle(fontSize: 12, color: outstandingColor),
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
            child: Text("Cancel", style: TextStyle(color: primaryColor)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_formKey.currentState!.validate()) {
                final dataMap = {
                  'name': nameCtrl.text.trim(),
                  'phone': phoneCtrl.text.trim(),
                  'address': addressCtrl.text.trim(),
                  'gst_number': gstCtrl.text.trim(),
                  'outstanding': double.tryParse(outstandingCtrl.text) ?? 0.0,
                  'updated_at': FieldValue.serverTimestamp(),
                };

                final ref = _firestore
                    .collection('users')
                    .doc(_uid)
                    .collection('customers');

                try {
                  if (id == null) {
                    await ref.add({
                      ...dataMap,
                      'created_at': FieldValue.serverTimestamp(),
                    });
                    _showSnack("✅ Customer added!", success: true);
                  } else {
                    // When editing, don't update 'outstanding' if the field was disabled (not new)
                    final updateMap = Map<String, dynamic>.from(dataMap);
                    if (!isNew) updateMap.remove('outstanding');

                    await ref.doc(id).update(updateMap);
                    _showSnack("✅ Customer updated!", success: true);
                  }
                } catch (e) {
                  _showSnack("❌ Error saving customer: $e");
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
            child: Text(isNew ? "Add Customer" : "Save Changes"),
          ),
        ],
      ),
    );
  }

  // --- Deletion Confirmation ---
  Future<void> _deleteCustomer(String id, String name) async {
    final bool confirm =
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Confirm Deletion"),
            content: Text(
              "Are you sure you want to delete '$name'? This action cannot be undone.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text("Cancel", style: TextStyle(color: primaryColor)),
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
      try {
        await _firestore
            .collection('users')
            .doc(_uid)
            .collection('customers')
            .doc(id)
            .delete();
        _showSnack("🗑 Customer '$name' deleted!", success: true);
      } catch (e) {
        _showSnack("❌ Error deleting customer: $e");
      }
    }
  }

  // --- Reusable Input Decoration ---
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
      counterText: "", // Hide character counter for phone/GST
    );
  }

  // ----------------------------------------------------------------------
  // 🏗️ BUILD METHOD
  // ----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Customers List 🧑‍🤝‍🧑"),
        centerTitle: true,
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: accentColor,
        foregroundColor: Colors.white,
        onPressed: () => _addOrEditCustomer(),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text("Add Customer"),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _getCustomers(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 80,
                    color: primaryColor.withOpacity(0.5),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "No customers found. Tap '+' to add a customer.",
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(
              top: 8,
              bottom: 80,
              left: 8,
              right: 8,
            ),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final String name = data['name'] ?? 'N/A';
              final String phone = data['phone'] ?? 'No Phone';
              final double outstanding = (data['outstanding'] is num)
                  ? data['outstanding'].toDouble()
                  : 0.0;
              final String gst = data['gst_number'] ?? 'N/A';

              return Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 4.0,
                  horizontal: 8.0,
                ),
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: primaryColor.withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    // --- Leading Icon/Avatar ---
                    leading: CircleAvatar(
                      backgroundColor: accentColor.withOpacity(0.1),
                      child: Icon(Icons.person, color: accentColor),
                    ),
                    // --- Title and Subtitle ---
                    title: Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          "Phone: $phone",
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              "Outstanding: ",
                              style: TextStyle(
                                fontSize: 14,
                                color: primaryColor.withOpacity(0.8),
                              ),
                            ),
                            Text(
                              "₹${outstanding.toStringAsFixed(2)}",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: outstanding > 0
                                    ? outstandingColor
                                    : Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                        if (gst != 'N/A')
                          Text(
                            "GST: $gst",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                    // --- Trailing Actions ---
                    trailing: PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_vert,
                        color: primaryColor.withOpacity(0.7),
                      ),
                      onSelected: (v) {
                        if (v == 'edit') {
                          _addOrEditCustomer(data: data, id: doc.id);
                        } else if (v == 'delete') {
                          _deleteCustomer(doc.id, name);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text("Edit")),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            "Delete",
                            style: TextStyle(color: deleteColor),
                          ),
                        ),
                      ],
                    ),
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
