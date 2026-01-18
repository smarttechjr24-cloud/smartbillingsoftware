import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smartbilling/showticket.dart';

class ContactSupportScreen extends StatefulWidget {
  const ContactSupportScreen({Key? key}) : super(key: key);

  @override
  State<ContactSupportScreen> createState() => _ContactSupportScreenState();
}

class _ContactSupportScreenState extends State<ContactSupportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _issueCtrl = TextEditingController();

  bool _isSubmitting = false;

  // 🔢 Generate Ticket Number
  String _generateTicketNumber() {
    final random = Random();
    return "SB-${100000 + random.nextInt(900000)}";
  }

  // ✅ Save Ticket to Firebase
  Future<void> _submitTicket() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final ticketNo = _generateTicketNumber();

      await FirebaseFirestore.instance
          .collection('support_tickets')
          .doc(ticketNo) // ✅ USE TICKET NO AS ID
          .set({
            'ticketNumber': ticketNo,
            'name': _nameCtrl.text.trim(),
            'mobile': _mobileCtrl.text.trim(),
            'issue': _issueCtrl.text.trim(),
            'status': 'Open',
            'userId': user?.uid,
            'createdAt': FieldValue.serverTimestamp(),
          });

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("✅ Ticket Raised"),
          content: Text("Ticket No: $ticketNo"),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text("OK"),
            ),
          ],
        ),
      );

      _nameCtrl.clear();
      _mobileCtrl.clear();
      _issueCtrl.clear();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to submit ticket: $e")));
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Contact Support"),
        backgroundColor: primary,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Raise a Support Ticket",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              "Please fill the form below and our team will get back to you.",
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),

            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: "Your Name",
                      prefixIcon: Icon(Icons.person),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? "Name is required"
                        : null,
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _mobileCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: "Mobile Number",
                      prefixIcon: Icon(Icons.phone),
                    ),
                    validator: (v) => v == null || v.length < 10
                        ? "Enter valid mobile number"
                        : null,
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _issueCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: "Describe your issue",
                      prefixIcon: Icon(Icons.report_problem),
                      alignLabelWithHint: true,
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? "Issue is required"
                        : null,
                  ),
                  const SizedBox(height: 20),

                  ElevatedButton.icon(
                    icon: const Icon(Icons.send),
                    label: Text(
                      _isSubmitting ? "Submitting..." : "Submit Ticket",
                    ),
                    onPressed: _isSubmitting ? null : _submitTicket,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),

                  OutlinedButton.icon(
                    icon: const Icon(Icons.list_alt),
                    label: const Text("View My Tickets"),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 45),
                      side: BorderSide(color: primary),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SupportTicketsScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
