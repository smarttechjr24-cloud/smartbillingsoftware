import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class InvoiceNumberPrefixScreen extends StatefulWidget {
  const InvoiceNumberPrefixScreen({Key? key}) : super(key: key);

  @override
  State<InvoiceNumberPrefixScreen> createState() =>
      _InvoiceNumberPrefixScreenState();
}

class _InvoiceNumberPrefixScreenState
    extends State<InvoiceNumberPrefixScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _prefixController = TextEditingController();
  final _startingNumberController = TextEditingController();

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('invoice_numbering')
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        _prefixController.text = data['prefix'] ?? 'INV';
        _startingNumberController.text =
            (data['starting_number'] ?? 1).toString();
      } else {
        _prefixController.text = 'INV';
        _startingNumberController.text = '1';
      }

      setState(() => _loading = false);
    } catch (e) {
      debugPrint("Error loading settings: $e");
      setState(() => _loading = false);
    }
  }

  Future<void> _saveSettings() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('invoice_numbering')
          .set({
        'prefix': _prefixController.text.trim(),
        'starting_number': int.tryParse(_startingNumberController.text) ?? 1,
        'updated_at': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Invoice numbering settings saved"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Invoice Number Prefix"),
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveSettings,
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF5F7FA),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Invoice Number Format",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _prefixController,
                      decoration: const InputDecoration(
                        labelText: "Prefix",
                        hintText: "e.g., INV, BILL",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.format_list_numbered),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _startingNumberController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Starting Number",
                        hintText: "e.g., 1, 100, 1000",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.numbers),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.blue),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "Preview: ${_prefixController.text}-${_startingNumberController.text}",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _prefixController.dispose();
    _startingNumberController.dispose();
    super.dispose();
  }
}
