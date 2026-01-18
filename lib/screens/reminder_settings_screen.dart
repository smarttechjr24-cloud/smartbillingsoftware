import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReminderSettingsScreen extends StatefulWidget {
  const ReminderSettingsScreen({Key? key}) : super(key: key);

  @override
  State<ReminderSettingsScreen> createState() => _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState extends State<ReminderSettingsScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _remindersEnabled = false;
  int _daysBefore = 3;
  String _messageTemplate =
      "Dear [Customer], your payment of ₹[Amount] is due on [DueDate]. Please pay at your earliest convenience. Thank you!";

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
          .doc('reminders')
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _remindersEnabled = data['enabled'] ?? false;
          _daysBefore = data['days_before'] ?? 3;
          _messageTemplate = data['message_template'] ?? _messageTemplate;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint("Error loading reminder settings: $e");
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
          .doc('reminders')
          .set({
        'enabled': _remindersEnabled,
        'days_before': _daysBefore,
        'message_template': _messageTemplate,
        'updated_at': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Reminder settings saved"),
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
        title: const Text("Reminder Settings"),
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveSettings,
            tooltip: "Save Settings",
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF5F7FA),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Enable/Disable Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: SwitchListTile(
                title: const Text(
                  "Enable Payment Reminders",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  "Automatically remind customers about due payments",
                ),
                value: _remindersEnabled,
                activeColor: const Color(0xFF1976D2),
                onChanged: (value) {
                  setState(() => _remindersEnabled = value);
                },
              ),
            ),

            const SizedBox(height: 20),

            // Reminder Schedule
            const Text(
              "Reminder Schedule",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

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
                      "Send reminder before due date",
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Slider(
                            value: _daysBefore.toDouble(),
                            min: 1,
                            max: 14,
                            divisions: 13,
                            label: "$_daysBefore days",
                            activeColor: const Color(0xFF1976D2),
                            onChanged: _remindersEnabled
                                ? (value) {
                                    setState(() => _daysBefore = value.toInt());
                                  }
                                : null,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1976D2).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "$_daysBefore days",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1976D2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Message Template
            const Text(
              "Message Template",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

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
                    TextField(
                      maxLines: 4,
                      enabled: _remindersEnabled,
                      controller:
                          TextEditingController(text: _messageTemplate),
                      decoration: const InputDecoration(
                        labelText: "Reminder Message",
                        hintText: "Enter your reminder message...",
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => _messageTemplate = value,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "Available placeholders:",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _buildPlaceholderChip("[Customer]"),
                        _buildPlaceholderChip("[Amount]"),
                        _buildPlaceholderChip("[DueDate]"),
                        _buildPlaceholderChip("[InvoiceNo]"),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "Reminders will be sent automatically based on invoice due dates. Make sure to save your settings.",
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderChip(String text) {
    return Chip(
      label: Text(
        text,
        style: const TextStyle(fontSize: 11),
      ),
      backgroundColor: const Color(0xFF1976D2).withOpacity(0.1),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
