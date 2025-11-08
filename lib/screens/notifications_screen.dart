import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

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
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("Clear all notifications?"),
                  content: const Text(
                    "This will permanently delete all notifications.",
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text("Cancel"),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                      ),
                      child: const Text("Clear All"),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await _clearAllNotifications(context);
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _getUserNotifications(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                "🎉 No notifications yet.\nEverything looks good!",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            );
          }

          final notifications = snapshot.data!.docs;

          return ListView.separated(
            padding: const EdgeInsets.all(16.0),
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final doc = notifications[index];
              final data = doc.data();
              final title = data['title'] ?? 'Notification';
              final message = data['message'] ?? '';
              final timestamp = data['timestamp'] as Timestamp?;
              final isRead = data['read'] ?? false;
              final type = data['type'] ?? "general";

              final icon = switch (type) {
                "reminder" => Icons.alarm_rounded,
                "payment" => Icons.currency_rupee_rounded,
                "invoice" => Icons.receipt_long_rounded,
                _ => Icons.notifications_active_rounded,
              };

              final color = switch (type) {
                "reminder" => Colors.orangeAccent,
                "payment" => Colors.green,
                "invoice" => Colors.blueAccent,
                _ => Colors.indigo,
              };

              return Dismissible(
                key: ValueKey(doc.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  color: Colors.redAccent,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                confirmDismiss: (_) async {
                  await _deleteNotification(doc.id);
                  return true;
                },
                child: Card(
                  elevation: isRead ? 1 : 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: color.withOpacity(0.15),
                      child: Icon(icon, color: color),
                    ),
                    title: Text(
                      title,
                      style: TextStyle(
                        fontWeight: isRead
                            ? FontWeight.normal
                            : FontWeight.bold,
                        color: isRead ? Colors.black54 : Colors.black87,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (message.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              message,
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          _formatTimestamp(timestamp),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    trailing: isRead
                        ? null
                        : TextButton(
                            onPressed: () => _markAsRead(doc.id),
                            child: const Text(
                              "Mark Read",
                              style: TextStyle(fontSize: 13),
                            ),
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
