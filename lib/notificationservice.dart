// lib/services/notification_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationService {
  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static String? get _uid => _auth.currentUser?.uid;

  /// Create a notification under users/{uid}/notifications
  ///
  /// [type] can be: 'reminder', 'system', 'payment', etc.
  /// Optionals: [customerId], [invoiceId], [extra] for custom payload.
  static Future<void> addNotification({
    required String title,
    required String message,
    required String type,
    String? customerId,
    String? invoiceId,
    Map<String, dynamic>? extra,
  }) async {
    final uid = _uid;
    if (uid == null) return;

    final doc = <String, dynamic>{
      'title': title,
      'message': message,
      'type': type,
      'read': false,
      'timestamp': FieldValue.serverTimestamp(),
      if (customerId != null) 'customer_id': customerId,
      if (invoiceId != null) 'invoice_id': invoiceId,
      if (extra != null) 'extra': extra,
    };

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .add(doc);
  }

  /// Mark a single notification as read
  static Future<void> markAsRead(String notificationId) async {
    final uid = _uid;
    if (uid == null) return;

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .doc(notificationId)
        .update({'read': true});
  }

  /// Mark all notifications as read
  static Future<void> markAllAsRead() async {
    final uid = _uid;
    if (uid == null) return;

    final snap = await _firestore
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .get();

    final batch = _firestore.batch();
    for (final d in snap.docs) {
      batch.update(d.reference, {'read': true});
    }
    await batch.commit();
  }

  /// Optional: stream unread count (for a badge in AppBar)
  static Stream<int> unreadCountStream() {
    final uid = _uid;
    if (uid == null) {
      // empty stream that always emits 0 if not logged in
      return const Stream<int>.empty();
    }
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .snapshots()
        .map((s) => s.size);
  }
}
