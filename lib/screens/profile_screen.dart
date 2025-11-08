import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  Map<String, dynamic>? _companyData;
  bool _loading = true;
  Database? _db;
  Uint8List? _logoBytes;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _initDb();
    await _fetchCompanyDetails();
    await _loadLocalLogo();
  }

  /// 🔹 Initialize SQLite for logo
  Future<void> _initDb() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = path.join(docsDir.path, 'smartbilling.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE company_logo (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT,
            logo BLOB
          )
        ''');
      },
    );
  }

  /// 🔹 Load company details from Firestore
  Future<void> _fetchCompanyDetails() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('company')
          .doc('details')
          .get();

      if (doc.exists) {
        setState(() {
          _companyData = doc.data();
        });
      }
    } catch (e) {
      debugPrint("❌ Error fetching company details: $e");
    } finally {
      setState(() => _loading = false);
    }
  }

  /// 🔹 Load local logo (from SQLite)
  Future<void> _loadLocalLogo() async {
    final user = _auth.currentUser;
    if (user == null || _db == null) return;

    final result = await _db!.query(
      'company_logo',
      where: 'user_id = ?',
      whereArgs: [user.uid],
      limit: 1,
    );

    if (result.isNotEmpty) {
      final bytes = result.first['logo'] as Uint8List;
      setState(() => _logoBytes = bytes);
    }
  }

  /// 🔹 Pick and save new logo to SQLite
  Future<void> _pickAndSaveLogo() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;

    final file = File(picked.path);
    final ext = path.extension(file.path).toLowerCase();

    if (ext != '.png') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Only PNG logos are supported.")),
      );
      return;
    }

    final user = _auth.currentUser;
    if (user == null) return;

    final bytes = await file.readAsBytes();

    await _db!.delete(
      'company_logo',
      where: 'user_id = ?',
      whereArgs: [user.uid],
    );
    await _db!.insert('company_logo', {'user_id': user.uid, 'logo': bytes});

    setState(() => _logoBytes = bytes);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("✅ Company logo updated successfully")),
    );
  }

  /// 🔹 Edit company info
  Future<void> _editCompanyDetails() async {
    final nameController = TextEditingController(
      text: _companyData?['name'] ?? '',
    );
    final gstController = TextEditingController(
      text: _companyData?['gstin'] ?? '',
    );
    final addressController = TextEditingController(
      text: _companyData?['address'] ?? '',
    );
    final phoneController = TextEditingController(
      text: _companyData?['phone'] ?? '',
    );
    final upiController = TextEditingController(
      text: _companyData?['upi_id'] ?? '',
    );

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Edit Company Details"),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: "Company Name"),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: gstController,
                  decoration: const InputDecoration(labelText: "GSTIN"),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(labelText: "Address"),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(labelText: "Phone Number"),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: upiController,
                  decoration: const InputDecoration(labelText: "UPI ID"),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  final uid = _auth.currentUser!.uid;
                  await _firestore
                      .collection('users')
                      .doc(uid)
                      .collection('company')
                      .doc('details')
                      .update({
                        'name': nameController.text.trim(),
                        'gstin': gstController.text.trim(),
                        'address': addressController.text.trim(),
                        'phone': phoneController.text.trim(),
                        'upi_id': upiController.text.trim(),
                        'updated_at': FieldValue.serverTimestamp(),
                      });
                  if (mounted) Navigator.pop(context);
                  _fetchCompanyDetails();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("✅ Company details updated")),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Error updating details: $e")),
                  );
                }
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  /// 🔹 Logout
  Future<void> _logout() async {
    await _auth.signOut();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF1F3A5F);
    const accentColor = Color(0xFF00A3A3);

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: _companyData == null
          ? const Center(child: Text("No company details found."))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // 🏢 Logo avatar
                  GestureDetector(
                    onTap: _pickAndSaveLogo,
                    child: CircleAvatar(
                      radius: 60,
                      backgroundColor: accentColor.withOpacity(0.1),
                      backgroundImage: _logoBytes != null
                          ? MemoryImage(_logoBytes!)
                          : null,
                      child: _logoBytes == null
                          ? const Icon(
                              Icons.add_a_photo,
                              color: accentColor,
                              size: 35,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _companyData?['name'] ?? 'Company Name',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _auth.currentUser?.email ?? '',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 20),

                  // 📋 Company info card
                  Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _detailRow(
                            Icons.confirmation_number,
                            "GSTIN",
                            _companyData?['gstin'] ?? '-',
                          ),
                          _detailRow(
                            Icons.phone,
                            "Phone",
                            _companyData?['phone'] ?? '-',
                          ),
                          _detailRow(
                            Icons.location_on,
                            "Address",
                            _companyData?['address'] ?? '-',
                          ),
                          _detailRow(
                            Icons.qr_code,
                            "UPI ID",
                            _companyData?['upi_id'] ?? '-',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _editCompanyDetails,
                        icon: const Icon(Icons.edit),
                        label: const Text("Edit"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          minimumSize: const Size(140, 45),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _logout,
                        icon: const Icon(Icons.logout),
                        label: const Text("Logout"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          minimumSize: const Size(140, 45),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF1F3A5F)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
