import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smartbilling/notificationservice.dart';

class ReminderService {
  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static String? get _uid => _auth.currentUser?.uid;

  /// 🔹 Generate payment reminders for customers with pending >7 days
  static Future<void> generateReminders() async {
    if (_uid == null) return;

    final now = DateTime.now();

    try {
      final customersSnapshot = await _firestore
          .collection('users')
          .doc(_uid)
          .collection('customers')
          .get();

      for (var doc in customersSnapshot.docs) {
        final data = doc.data();
        final customerId = doc.id;
        final name = data['name'] ?? 'Unknown';
        final outstanding = (data['outstanding'] ?? 0).toDouble();

        // ✅ Skip if no pending amount
        if (outstanding <= 0) continue;

        final lastPayment = (data['last_payment_date'] as Timestamp?)?.toDate();
        if (lastPayment == null) continue;

        final daysDiff = now.difference(lastPayment).inDays;

        // ✅ Only create reminder if >7 days old
        if (daysDiff > 7) {
          final message =
              "Payment pending from $name (₹${outstanding.toStringAsFixed(2)}) since $daysDiff days.";

          // 🔹 Check if a reminder for this customer already exists (avoid duplicates)
          final existing = await _firestore
              .collection('users')
              .doc(_uid)
              .collection('notifications')
              .where('type', isEqualTo: 'reminder')
              .where('customer_id', isEqualTo: customerId)
              .where('read', isEqualTo: false)
              .get();

          if (existing.docs.isEmpty) {
            await NotificationService.addNotification(
              title: "⏰ Payment Reminder",
              message: message,
              type: "reminder",
              customerId: customerId,
            );
          }
        }
      }
    } catch (e) {
      print("⚠️ ReminderService error: $e");
    }
  }
}
