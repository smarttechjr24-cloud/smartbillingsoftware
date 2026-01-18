import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/purchase_model.dart';

/// Service class for all Firestore operations related to Purchases and Dashboard data.
class PurchaseService {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final FirebaseAuth auth = FirebaseAuth.instance;

  String? get _uid => auth.currentUser?.uid;

  /// Provides a stream of all Purchase records, ordered by date.
  Stream<List<PurchaseModel>> get fetchPurchases {
    final uid = _uid;
    if (uid == null) return Stream.value(const []); // Return empty if no user

    return firestore
        .collection('users')
        .doc(uid)
        .collection('purchases')
        .orderBy('invoiceDate', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map(PurchaseModel.fromFirestore).toList(),
        );
  }

  /// Calculates the total outstanding balance from all supplier documents.
  /// This fulfills the requirement to *not* calculate outstanding from individual purchases.
  Future<double> getTotalSupplierOutstanding() async {
    final uid = _uid;
    if (uid == null) return 0.0;

    try {
      final snapshot = await firestore
          .collection('users')
          .doc(uid)
          .collection('suppliers')
          .get();

      // Fold/reduce the list of supplier documents to sum the outstandingBalance field.
      return snapshot.docs.fold<double>(0.0, (sum, doc) {
        final data = doc.data();
        final outstanding =
            (data['outstandingBalance'] as num?)?.toDouble() ?? 0.0;
        return sum + outstanding;
      });
    } catch (e) {
      // In a real app, this should be logged to a crashlytics/analytics service.
      debugPrint('Error fetching total supplier outstanding: $e');
      return 0.0;
    }
  }

  /// Calculates dashboard metrics from a list of purchases.
  /// Note: 'totalSupplierOutstanding' is fetched separately and added here for the dashboard map structure.
  Future<Map<String, double>> getDashboardData(
    List<PurchaseModel> purchases,
  ) async {
    final totalPurchases = purchases.length.toDouble();
    final totalAmount = purchases.fold<double>(
      0.0,
      (sum, p) => sum + p.totalAmount,
    );

    // Calculate total amount that is currently overdue.
    final overdueAmount = purchases
        .where((p) => p.isOverdue)
        .fold<double>(0.0, (sum, p) => sum + p.outstandingAmount);

    final totalOutstanding =
        await getTotalSupplierOutstanding(); // Required separate fetch

    return {
      'totalPurchases': totalPurchases,
      'totalAmount': totalAmount, // Optional but good to have
      'totalOverdue': overdueAmount,
      'totalSupplierOutstanding': totalOutstanding, // The required metric
    };
  }

  /// Deletes a purchase record.
  Future<void> deletePurchase(String purchaseId) async {
    final uid = _uid;
    if (uid == null) return;

    try {
      await firestore
          .collection('users')
          .doc(uid)
          .collection('purchases')
          .doc(purchaseId)
          .delete();
    } catch (e) {
      debugPrint('Error deleting purchase: $e');
      rethrow;
    }
  }

  // ===========================================================================
  // TRANSACTIONAL METHODS (New for Upgrade)
  // ===========================================================================

  /// Saves a new Purchase Invoice using a Firestore Transaction.
  /// Atomically updates:
  /// 1. Purchase Invoice Document
  /// 2. Supplier Outstanding Balance
  /// 3. Product Stock Quantities (Optional/Future)
  Future<void> savePurchaseInvoice({
    required String invoiceNumber,
    required Supplier supplier,
    required List<InvoiceItem> items,
    required TaxTotals totals,
    required DateTime invoiceDate,
    required DateTime dueDate,
    required String yourStateCode,
    String? userName,
    String paymentStatus = 'unpaid',
    double paidAmount = 0.0,
    DateTime? paymentDate,
    String paymentMethod = 'cash',
    String? paymentNotes,
    double? outstandingAmount,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('User not logged in');

    final purchaseRef = firestore
        .collection('users')
        .doc(uid)
        .collection('purchases')
        .doc(); // Generate ID

    final supplierRef = firestore
        .collection('users')
        .doc(uid)
        .collection('suppliers')
        .doc(supplier.id);

    return firestore.runTransaction((transaction) async {
      // 1. Prepare Invoice Data
      final invoiceData = {
        'invoiceId': purchaseRef.id,
        'invoiceNumber': invoiceNumber,
        'type': 'purchase',
        'supplierId': supplier.id,
        'supplierName': supplier.name,
        'supplierStateCode': supplier.stateCode,
        'yourStateCode': yourStateCode,
        'invoiceDate': invoiceDate.toIso8601String(),
        'dueDate': dueDate.toIso8601String(),
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
        'created_by': userName ?? 'System User',

        // Totals
        'totalTaxable': totals.totalTaxable,
        'totalDiscount': totals.totalDiscount,
        'cgst_total': totals.cgstTotal,
        'sgst_total': totals.sgstTotal,
        'igst_total': totals.igstTotal,
        'gst_amount': totals.totalTax,
        'grand_total': totals.grandTotal,

        // Payment Status
        'paymentStatus': paymentStatus,
        'paid_amount': paidAmount,
        'balance_due': outstandingAmount ?? (totals.grandTotal - paidAmount),
        'payment_date': paymentDate?.toIso8601String(),
        'payment_method': paymentMethod,
        'payment_notes': paymentNotes,

        // Items
        'items': items.map((item) => item.toMap()).toList(),
      };

      // 2. Write Invoice
      transaction.set(purchaseRef, invoiceData);

      // 3. Update Supplier Balance with outstanding amount only
      final balanceIncrement =
          outstandingAmount ?? (totals.grandTotal - paidAmount);
      transaction.update(supplierRef, {
        'outstandingBalance': FieldValue.increment(balanceIncrement),
        'lastPurchaseDate': FieldValue.serverTimestamp(),
      });

      // 4. Update Stock and Prices
      for (var item in items) {
        final productRef = firestore
            .collection('users')
            .doc(uid)
            .collection('products')
            .doc(item.item.id);

        // Update stock quantity and prices (Purchase Price & Sale Price)
        // We use the latest prices from the invoice to keep product catalog up to date
        transaction.update(productRef, {
          'stock': FieldValue.increment(item.quantity),
          'purchase_price': item.item.purchasePrice,
          'rate': item.item.salePrice,
          'updated_at': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  /// Quickly adds a new supplier.
  Future<Supplier> addQuickSupplier({
    required String name,
    required String phone,
    required String gstin,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('User not logged in');

    final supplierRef = firestore
        .collection('users')
        .doc(uid)
        .collection('suppliers')
        .doc();

    final supplierData = {
      'name': name,
      'phone': phone,
      'gstin': gstin,
      'state': 'MH', // Default state, can be enhanced
      'outstandingBalance': 0.0,
      'created_at': FieldValue.serverTimestamp(),
    };

    await supplierRef.set(supplierData);

    return Supplier(
      id: supplierRef.id,
      name: name,
      stateCode: 'MH',
      gstin: gstin,
      phone: phone,
      outstandingBalance: 0.0,
    );
  }

  /// Quickly adds a new product.
  Future<Item> addQuickProduct({
    required String name,
    required double purchasePrice,
    required double salePrice,
    required double gstRate,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('User not logged in');

    final productRef = firestore
        .collection('users')
        .doc(uid)
        .collection('products')
        .doc();

    final productData = {
      'name': name,
      'purchase_price': purchasePrice,
      'rate': salePrice,
      'gst_percent': (gstRate * 100).toInt(),
      'stock': 0.0, // Initial stock is 0, will be updated by purchase
      'created_at': FieldValue.serverTimestamp(),
    };

    await productRef.set(productData);

    return Item(
      id: productRef.id,
      name: name,
      gstRate: gstRate,
      purchasePrice: purchasePrice,
      salePrice: salePrice,
    );
  }

  /// Records a payment for a purchase invoice using a Transaction.
  Future<void> recordPayment({
    required String invoiceId,
    required String supplierId,
    required double amount,
    required String userName,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('User not logged in');

    final purchaseRef = firestore
        .collection('users')
        .doc(uid)
        .collection('purchases')
        .doc(invoiceId);

    final supplierRef = firestore
        .collection('users')
        .doc(uid)
        .collection('suppliers')
        .doc(supplierId);

    final paymentRef = firestore
        .collection('users')
        .doc(uid)
        .collection('supplier_payments')
        .doc();

    return firestore.runTransaction((transaction) async {
      final purchaseSnapshot = await transaction.get(purchaseRef);
      if (!purchaseSnapshot.exists) {
        throw Exception('Invoice not found');
      }

      final purchaseData = purchaseSnapshot.data()!;
      final currentBalance = (purchaseData['balance_due'] as num).toDouble();
      final currentPaid = (purchaseData['paid_amount'] as num).toDouble();

      if (amount > currentBalance + 0.01) {
        throw Exception('Payment exceeds balance due');
      }

      final newBalance = currentBalance - amount;
      final newPaid = currentPaid + amount;

      String status = 'Outstanding';
      if (newBalance <= 0.01)
        status = 'Paid';
      else if (newPaid > 0)
        status = 'Partial';

      // 1. Update Invoice
      transaction.update(purchaseRef, {
        'balance_due': newBalance,
        'paid_amount': newPaid,
        'paymentStatus': status,
        'updated_at': FieldValue.serverTimestamp(),
      });

      // 2. Update Supplier Balance
      transaction.update(supplierRef, {
        'outstandingBalance': FieldValue.increment(-amount),
      });

      // 3. Create Payment Record
      transaction.set(paymentRef, {
        'paymentId': paymentRef.id,
        'purchaseInvoiceId': invoiceId,
        'supplierId': supplierId,
        'supplierName': purchaseData['supplierName'] ?? 'Unknown Supplier',
        'amount': amount,
        'payment_date': DateTime.now().toIso8601String(),
        'created_at': FieldValue.serverTimestamp(),
        'recorded_by': userName,
      });
    });
  }
  // ===========================================================================
  // UPDATE METHOD
  // ===========================================================================

  /// Updates an existing Purchase Invoice.
  /// This is a complex operation that involves:
  /// 1. Reverting the effects of the OLD invoice (stock, supplier balance).
  /// 2. Applying the effects of the NEW invoice.
  /// 3. Updating the invoice document itself.
  Future<void> updatePurchaseInvoice({
    required String invoiceId,
    required String oldSupplierId,
    required List<InvoiceItem> oldItems,
    required double oldGrandTotal,
    required double oldPaidAmount,

    required String invoiceNumber,
    required Supplier supplier,
    required List<InvoiceItem> items,
    required TaxTotals totals,
    required DateTime invoiceDate,
    required DateTime dueDate,
    required String yourStateCode,
    String? userName,
    String paymentStatus = 'unpaid',
    double paidAmount = 0.0,
    DateTime? paymentDate,
    String paymentMethod = 'cash',
    String? paymentNotes,
    double? outstandingAmount,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('User not logged in');

    final purchaseRef = firestore
        .collection('users')
        .doc(uid)
        .collection('purchases')
        .doc(invoiceId);

    final oldSupplierRef = firestore
        .collection('users')
        .doc(uid)
        .collection('suppliers')
        .doc(oldSupplierId);

    final newSupplierRef = firestore
        .collection('users')
        .doc(uid)
        .collection('suppliers')
        .doc(supplier.id);

    return firestore.runTransaction((transaction) async {
      // --- 1. REVERT OLD EFFECTS ---

      // A. Revert Supplier Balance
      // If we owed money (outstanding), we remove that debt.
      final oldOutstanding = oldGrandTotal - oldPaidAmount;
      if (oldOutstanding > 0) {
        transaction.update(oldSupplierRef, {
          'outstandingBalance': FieldValue.increment(-oldOutstanding),
        });
      }

      // B. Revert Stock
      for (var item in oldItems) {
        final productRef = firestore
            .collection('users')
            .doc(uid)
            .collection('products')
            .doc(item.item.id);

        // Decrease stock by the amount that was previously added
        transaction.update(productRef, {
          'stock': FieldValue.increment(-item.quantity),
        });
      }

      // --- 2. APPLY NEW EFFECTS ---

      // A. Prepare New Invoice Data
      final invoiceData = {
        'invoiceNumber': invoiceNumber,
        'supplierId': supplier.id,
        'supplierName': supplier.name,
        'supplierStateCode': supplier.stateCode,
        'yourStateCode': yourStateCode,
        'invoiceDate': invoiceDate.toIso8601String(),
        'dueDate': dueDate.toIso8601String(),
        'updated_at': FieldValue.serverTimestamp(),
        'updated_by': userName ?? 'System User',

        // Totals
        'totalTaxable': totals.totalTaxable,
        'totalDiscount': totals.totalDiscount,
        'cgst_total': totals.cgstTotal,
        'sgst_total': totals.sgstTotal,
        'igst_total': totals.igstTotal,
        'gst_amount': totals.totalTax,
        'grand_total': totals.grandTotal,

        // Payment Status
        'paymentStatus': paymentStatus,
        'paid_amount': paidAmount,
        'balance_due': outstandingAmount ?? (totals.grandTotal - paidAmount),
        'payment_date': paymentDate?.toIso8601String(),
        'payment_method': paymentMethod,
        'payment_notes': paymentNotes,

        // Items
        'items': items.map((item) => item.toMap()).toList(),
      };

      // B. Update Invoice Document
      transaction.update(purchaseRef, invoiceData);

      // C. Update New Supplier Balance
      final newOutstanding =
          outstandingAmount ?? (totals.grandTotal - paidAmount);
      transaction.update(newSupplierRef, {
        'outstandingBalance': FieldValue.increment(newOutstanding),
        'lastPurchaseDate': FieldValue.serverTimestamp(),
      });

      // D. Update Stock (New Items)
      for (var item in items) {
        final productRef = firestore
            .collection('users')
            .doc(uid)
            .collection('products')
            .doc(item.item.id);

        transaction.update(productRef, {
          'stock': FieldValue.increment(item.quantity),
          'purchase_price': item.item.purchasePrice,
          'rate': item.item.salePrice,
          'updated_at': FieldValue.serverTimestamp(),
        });
      }
    });
  }
}
