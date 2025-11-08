import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // 🔹 Fetch invoice data by ID
  Future<Map<String, dynamic>?> fetchInvoice(String invoiceId) async {
    try {
      final doc = await _db.collection('invoices').doc(invoiceId).get();
      if (!doc.exists) return null;

      final data = doc.data()!;
      final itemsSnapshot = await _db
          .collection('invoices')
          .doc(invoiceId)
          .collection('items')
          .get();

      final items = itemsSnapshot.docs.map((d) => d.data()).toList();

      return {...data, 'items': items};
    } catch (e) {
      print('🔥 Firestore fetch error: $e');
      return null;
    }
  }
}
