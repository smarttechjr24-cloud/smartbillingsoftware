import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    _generateAutoNotifications();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _getUserNotifications() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return '';
    final date = ts.toDate();
    return DateFormat('dd MMM yyyy, hh:mm a').format(date);
  }

  // ================= ✅ AUTO NOTIFICATION CREATOR =================
  Future<void> _generateAutoNotifications() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    final today = DateTime.now();
    final tomorrow = DateTime(today.year, today.month, today.day + 1);

    // -------- INVOICE DUE REMINDER --------
    final invoiceSnap = await userRef.collection('invoices').get();

    for (var doc in invoiceSnap.docs) {
      final data = doc.data();
      if (!data.containsKey('due_date')) continue;

      final dueDate = DateTime.tryParse(data['due_date']);
      if (dueDate == null) continue;

      if (DateUtils.isSameDay(dueDate, tomorrow)) {
        final message =
            'Invoice ${data['invoice_number'] ?? ''} for ${data['customer_name']} is due tomorrow.';

        final existing = await userRef
            .collection('notifications')
            .where('message', isEqualTo: message)
            .get();

        if (existing.docs.isEmpty) {
          await userRef.collection('notifications').add({
            'title': 'Invoice Due Tomorrow',
            'message': message,
            'type': 'invoice',
            'read': false,
            'timestamp': FieldValue.serverTimestamp(),
          });
        }
      }
    }

    // -------- PLAN EXPIRY REMINDER --------
    final userDoc = await userRef.get();
    final planEndRaw = userDoc.data()?['plan_end_date'];

    if (planEndRaw != null) {
      final planEnd = DateTime.tryParse(planEndRaw);

      if (planEnd != null) {
        final diff = planEnd.difference(today).inDays;

        if (diff <= 3 && diff >= 0) {
          final message = 'Your plan will expire in $diff day(s). Renew soon.';

          final existing = await userRef
              .collection('notifications')
              .where('message', isEqualTo: message)
              .get();

          if (existing.docs.isEmpty) {
            await userRef.collection('notifications').add({
              'title': 'Plan Expiring Soon',
              'message': message,
              'type': 'reminder',
              'read': false,
              'timestamp': FieldValue.serverTimestamp(),
            });
          }
        }
      }
    }
  }

  Future<void> _markAsRead(String docId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .doc(docId)
        .update({'read': true});
  }

  Future<void> _deleteNotification(String docId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .doc(docId)
        .delete();
  }

  Future<void> _clearAllNotifications(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final batch = FirebaseFirestore.instance.batch();
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .get();

    for (var doc in snapshot.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("All notifications cleared")));
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Notifications"),
        backgroundColor: primary,
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: "Clear all",
            icon: const Icon(Icons.delete_sweep_rounded),
            onPressed: () async {
              await _clearAllNotifications(context);
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _getUserNotifications(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("🎉 No notifications"));
          }

          final notifications = snapshot.data!.docs;

          return ListView.builder(
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final doc = notifications[index];
              final data = doc.data();
              final title = data['title'] ?? 'Notification';
              final message = data['message'] ?? '';
              final timestamp = data['timestamp'] as Timestamp?;
              final isRead = data['read'] ?? false;

              return Dismissible(
                key: Key(doc.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: Colors.red,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (direction) {
                  _deleteNotification(doc.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Notification deleted')),
                  );
                },
                child: Card(
                  child: ListTile(
                    title: Text(
                      title,
                      style: TextStyle(
                        fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(message),
                        Text(
                          _formatTimestamp(timestamp),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isRead)
                          TextButton(
                            onPressed: () => _markAsRead(doc.id),
                            child: const Text("Mark Read"),
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _deleteNotification(doc.id),
                          tooltip: 'Delete',
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
