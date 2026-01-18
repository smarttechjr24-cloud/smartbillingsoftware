import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:smartbilling/main.dart';

class CompanyDetailsScreen extends StatefulWidget {
  const CompanyDetailsScreen({Key? key}) : super(key: key);

  @override
  State<CompanyDetailsScreen> createState() => _CompanyDetailsScreenState();
}

class _CompanyDetailsScreenState extends State<CompanyDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _gstController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  // ⚡ NEW: Email Controller
  final _emailController = TextEditingController();
  final _upiController = TextEditingController();

  File? _logoFile;
  bool _isSaving = false;

  Database? _db;

  // --------------------------------------------------------------------------
  // 🔹 Initialize local SQLite database
  // --------------------------------------------------------------------------
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
    // ⚡ Load existing data from Firestore on startup
    _loadDetails();
  }

  // --------------------------------------------------------------------------
  // 🔹 Load existing company details from Firestore
  // --------------------------------------------------------------------------
  Future<void> _loadDetails() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('company')
        .doc('details')
        .get();

    if (doc.exists) {
      final data = doc.data()!;
      _nameController.text = data['name'] ?? '';
      _gstController.text = data['gstin'] ?? '';
      _addressController.text = data['address'] ?? '';
      _phoneController.text = data['phone'] ?? '';
      // ⚡ Load Email
      _emailController.text = data['email'] ?? '';
      _upiController.text = data['upi_id'] ?? '';
      // No need to load logo file, as it's handled by FutureBuilder
      setState(() {});
    }
  }

  // --------------------------------------------------------------------------
  // 🔹 Check subscription status
  // --------------------------------------------------------------------------
  Future<void> _checkSubscription() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final sub = userDoc.data()?['subscription'];

    // 👇 No subscription found — redirect
    if (sub == null) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/subscription');
      }
      return;
    }

    // 👇 Check expiry
    try {
      final expiry = (sub['expiry'] as Timestamp).toDate();
      if (expiry.isBefore(DateTime.now())) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/subscription');
        }
      }
    } catch (e) {
      // If expiry field missing or invalid
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/subscription');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _initDb();
    _checkSubscription();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _gstController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose(); // ⚡ Dispose new controller
    _upiController.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // 📸 Pick PNG logo
  // --------------------------------------------------------------------------
  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (pickedFile == null) return;

    final file = File(pickedFile.path);
    final extension = path.extension(file.path).toLowerCase();

    if (extension != ".png") {
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Only PNG files are allowed."),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _logoFile = file);
  }

  // --------------------------------------------------------------------------
  // 💾 Save company details — Firestore + SQLite
  // --------------------------------------------------------------------------
  Future<void> _saveDetails() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User not logged in.");

      // 🔹 Convert logo file to bytes and save in SQLite
      if (_logoFile != null && _db != null) {
        final bytes = await _logoFile!.readAsBytes();
        await _db!.delete(
          'company_logo',
          where: 'user_id = ?',
          whereArgs: [user.uid],
        );
        await _db!.insert('company_logo', {'user_id': user.uid, 'logo': bytes});
      }

      // 🔹 Save company data (excluding logo) to Firestore
      final companyData = {
        'name': _nameController.text.trim(),
        'gstin': _gstController.text.trim(),
        'address': _addressController.text.trim(),
        'phone': _phoneController.text.trim(),
        'email': _emailController.text.trim(), // ⚡ NEW: Saving Email
        'upi_id': _upiController.text.trim(),
        'logo_url': '', // empty since stored locally
        'created_at': FieldValue.serverTimestamp(),
      };

      final firestore = FirebaseFirestore.instance;
      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('company')
          .doc('details')
          .set(
            companyData,
            SetOptions(merge: true),
          ); // Use merge: true to avoid overwriting unrelated fields

      await firestore.collection('users').doc(user.uid).update({
        'has_company_details': true,
      });

      if (mounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Company details saved successfully!"),
          ),
        );
        // ignore: use_build_context_synchronously
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainNavigation()),
        );
      }
    } catch (e) {
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("❌ Error: $e")));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // --------------------------------------------------------------------------
  // 🔹 Load local logo (if exists)
  // --------------------------------------------------------------------------
  Future<ImageProvider?> _loadLocalLogo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _db == null) return null;

    final result = await _db!.query(
      'company_logo',
      where: 'user_id = ?',
      whereArgs: [user.uid],
      limit: 1,
    );
    if (result.isNotEmpty) {
      final bytes = result.first['logo'] as Uint8List;
      return MemoryImage(bytes);
    }
    return null;
  }

  // --------------------------------------------------------------------------
  // 🔹 Build UI
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF1F3A5F);
    const accentColor = Color(0xFF00A3A3);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Company Details"),
        backgroundColor: primaryColor,
        centerTitle: true,
      ),
      body: FutureBuilder<ImageProvider?>(
        future: _loadLocalLogo(),
        builder: (context, snapshot) {
          final existingLogo = snapshot.data;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  // 🏢 Company Logo
                  GestureDetector(
                    onTap: _pickLogo,
                    child: Container(
                      height: 120,
                      width: 120,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                        border: Border.all(color: accentColor, width: 1.5),
                        image: _logoFile != null
                            ? DecorationImage(
                                image: FileImage(_logoFile!),
                                fit: BoxFit.cover,
                              )
                            : existingLogo != null
                            ? DecorationImage(
                                image: existingLogo,
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: _logoFile == null && existingLogo == null
                          ? const Icon(
                              Icons.add_a_photo,
                              color: accentColor,
                              size: 40,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 20),

                  TextFormField(
                    controller: _nameController,
                    decoration: _inputDecoration(
                      "Company Name",
                      Icons.business,
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? "Enter company name" : null,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _gstController,
                    decoration: _inputDecoration(
                      "GSTIN",
                      Icons.confirmation_number,
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? "Enter GSTIN" : null,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _addressController,
                    maxLines: 3,
                    decoration: _inputDecoration("Address", Icons.location_on),
                    validator: (v) =>
                        v == null || v.isEmpty ? "Enter address" : null,
                  ),
                  const SizedBox(height: 16),

                  // ⚡ NEW: Email Input Field
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _inputDecoration("Email", Icons.email),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return "Enter email address";
                      }
                      // Basic email validation regex
                      if (!RegExp(
                        r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                      ).hasMatch(v)) {
                        return "Enter a valid email address";
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: _inputDecoration("Phone", Icons.phone),
                    validator: (v) =>
                        v == null || v.isEmpty ? "Enter phone number" : null,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _upiController,
                    decoration: _inputDecoration(
                      "UPI ID (e.g. merchant@paytm)",
                      Icons.qr_code,
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? "Enter UPI ID" : null,
                  ),
                  const SizedBox(height: 24),

                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveDetails,
                    icon: const Icon(Icons.save_outlined),
                    label: _isSaving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("Save Details"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Colors.grey.shade100,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }
}
