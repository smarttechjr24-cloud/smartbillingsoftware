import 'package:cloud_firestore/cloud_firestore.dart';

/// Defines the possible payment states for a purchase.
enum PurchasePaymentStatus { paid, partial, outstanding }

/// Model for a Purchase record, incorporating business logic for due dates.
class PurchaseModel {
  final String id;
  final String supplierId;
  final String supplierName;
  final String supplierStateCode;
  final String invoiceNumber;
  final double totalAmount;
  final double outstandingAmount;
  final double paidAmount;
  final PurchasePaymentStatus paymentStatus;
  final DateTime purchaseDate;
  final DateTime dueDate;
  final DateTime? paymentDate;
  final String paymentMethod;
  final String? paymentNotes;
  final List<PurchaseItemModel> items;

  const PurchaseModel({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.supplierStateCode,
    required this.invoiceNumber,
    required this.totalAmount,
    required this.outstandingAmount,
    required this.paidAmount,
    required this.paymentStatus,
    required this.purchaseDate,
    required this.dueDate,
    this.paymentDate,
    this.paymentMethod = 'cash',
    this.paymentNotes,
    this.items = const [],
  });

  /// Business logic to check if a purchase is overdue (passed due date AND outstanding balance > 0).
  bool get isOverdue =>
      _dateOnly(dueDate).isBefore(_dateOnly(DateTime.now())) &&
      outstandingAmount > 0;

  /// Business logic to check if a purchase is due today.
  bool get isDueToday =>
      _dateOnly(dueDate).isAtSameMomentAs(_dateOnly(DateTime.now()));

  /// Utility to compare only the year, month, and day.
  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  /// Factory constructor to create a PurchaseModel from a Firestore document.
  factory PurchaseModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    final statusString =
        (data['paymentStatus'] as String?)?.toLowerCase() ?? 'outstanding';

    // Safely parse payment status string to enum
    final status = PurchasePaymentStatus.values.firstWhere(
      (e) => e.toString().split('.').last == statusString,
      orElse: () => PurchasePaymentStatus.outstanding,
    );

    // Safely parse numerical values - Try both field name formats for compatibility
    // Try with underscore first (new format), then without (old format)
    final total = (data['grand_total'] as num?)?.toDouble() ?? 
                  (data['grandtotal'] as num?)?.toDouble() ?? 
                  (data['grand_Total'] as num?)?.toDouble() ?? 0.0;
    
    final outstanding = (data['balance_due'] as num?)?.toDouble() ?? 
                        (data['balancedue'] as num?)?.toDouble() ?? 
                        (data['balance_Due'] as num?)?.toDouble() ?? 0.0;

    final paid = (data['paid_amount'] as num?)?.toDouble() ?? 0.0;
    
    // Parse Items
    List<PurchaseItemModel> parsedItems = [];
    if (data['items'] != null && data['items'] is List) {
      parsedItems = (data['items'] as List)
          .map((item) => PurchaseItemModel.fromMap(item as Map<String, dynamic>))
          .toList();
    }
    
    return PurchaseModel(
      id: doc.id,
      supplierId: data['supplierId'] ?? '',
      supplierName: data['supplierName'] ?? 'N/A',
      supplierStateCode: data['supplierStateCode'] ?? 'MH',
      invoiceNumber: data['invoiceNumber'] ?? 'N/A',
      totalAmount: total,
      outstandingAmount: outstanding,
      paidAmount: paid,
      paymentStatus: status,
      // Safely convert Firestore Timestamp/String/null to DateTime
      purchaseDate: _safeToDateTime(data['invoiceDate']),
      dueDate: _safeToDateTime(data['dueDate']),
      paymentDate: data['payment_date'] != null ? _safeToDateTime(data['payment_date']) : null,
      paymentMethod: data['payment_method'] ?? 'cash',
      paymentNotes: data['payment_notes'],
      items: parsedItems,
    );
  }

  /// Helper to safely convert various Firestore date formats to DateTime.
  static DateTime _safeToDateTime(dynamic data) {
    if (data == null) return DateTime(1970);
    if (data is Timestamp) return data.toDate();
    if (data is String) return DateTime.tryParse(data) ?? DateTime(1970);
    return DateTime(1970); // Default fallback date
  }
}

class PurchaseItemModel {
  final String itemId;
  final String itemName;
  final double quantity;
  final double unitPrice;
  final double discount;
  final double taxAmount;
  final double totalAmount;

  PurchaseItemModel({
    required this.itemId,
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.taxAmount,
    required this.totalAmount,
  });

  factory PurchaseItemModel.fromMap(Map<String, dynamic> map) {
    return PurchaseItemModel(
      itemId: map['itemId'] ?? '',
      itemName: map['itemName'] ?? '',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0.0,
      unitPrice: (map['unitPrice'] as num?)?.toDouble() ?? 0.0,
      discount: (map['discount'] as num?)?.toDouble() ?? 0.0,
      taxAmount: (map['totalTaxAmount'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (map['lineTotal'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

// =============================================================================
// NEW MODELS FOR PURCHASE INVOICE (Moved from purchase_screen.dart)
// =============================================================================

/// Represents a product or raw material being purchased.
class Item {
  final String id;
  final String name;
  final double gstRate; // e.g., 0.18 for 18% GST (Decimal format)
  final double purchasePrice;
  final double salePrice;

  Item({
    required this.id,
    required this.name,
    required this.gstRate,
    this.purchasePrice = 0.0,
    this.salePrice = 0.0,
  });

  factory Item.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    // Fix: Read 'gst_percent' (whole number), convert to double, and divide by 100
    final int gstPercent = (data?['gst_percent'] ?? 0).toInt();
    final double calculatedGstRate = gstPercent / 100.0;

    return Item(
      id: doc.id,
      name: data?['name'] ?? 'Unknown Item',
      gstRate: calculatedGstRate,
      purchasePrice: (data?['purchase_price'] as num?)?.toDouble() ?? 0.0,
      salePrice: (data?['rate'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Represents a supplier from whom goods are purchased.
class Supplier {
  final String id;
  final String name;
  final String stateCode; // e.g., 'MH', 'KA'
  final String gstin;
  final String phone;
  final double outstandingBalance;

  Supplier({
    required this.id,
    required this.name,
    required this.stateCode,
    required this.gstin,
    this.phone = '',
    this.outstandingBalance = 0.0,
  });

  factory Supplier.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    return Supplier(
      id: doc.id,
      name: data?['name'] ?? 'Unknown Supplier',
      stateCode: data?['state'] ?? 'XX',
      gstin: data?['gstin'] ?? 'N/A',
      phone: data?['phone'] ?? '',
      outstandingBalance: (data?['outstandingBalance'] as num?)?.toDouble() ?? 0.0,
    );
  }

  DocumentReference ref(String uid) => FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('suppliers')
      .doc(id);
}

/// Represents a single line item in the purchase invoice.
class InvoiceItem {
  final Item item;
  double quantity;
  double unitPrice;
  double discount; // Discount in absolute amount per unit

  InvoiceItem({
    required this.item,
    required this.quantity,
    required this.unitPrice,
    this.discount = 0.0,
  });

  // CORE CALCULATION LOGIC
  double get effectivePrice => unitPrice - discount;
  double get subtotalBeforeTax => quantity * effectivePrice;
  double get taxableAmount => subtotalBeforeTax;
  double get totalTaxAmount => taxableAmount * item.gstRate;
  double get lineTotal => taxableAmount + totalTaxAmount;

  /// Helper to determine CGST/SGST or IGST amount based on state comparison
  double getTaxAmount(String supplierStateCode, String companyStateCode) {
    if (supplierStateCode == companyStateCode) {
      // Intra-State: CGST + SGST (Tax rate is split equally)
      return totalTaxAmount / 2.0;
    } else {
      // Inter-State: IGST (Full tax rate applies)
      return totalTaxAmount;
    }
  }

  Map<String, dynamic> toMap() => {
    'itemId': item.id,
    'itemName': item.name,
    'quantity': quantity,
    'unitPrice': unitPrice,
    'discount': discount,
    'effectivePrice': effectivePrice,
    'gstRate': item.gstRate,
    'taxableAmount': taxableAmount,
    'totalTaxAmount': totalTaxAmount,
    'lineTotal': lineTotal,
  };
}

/// Represents a single payment transaction for a purchase invoice.
class Payment {
  final String id;
  final double amount;
  final DateTime date;
  final String method; // 'cash', 'bank', 'upi', 'cheque'
  final String? notes;
  final String? transactionId;

  Payment({
    required this.id,
    required this.amount,
    required this.date,
    required this.method,
    this.notes,
    this.transactionId,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'amount': amount,
    'date': date.toIso8601String(),
    'method': method,
    'notes': notes,
    'transactionId': transactionId,
  };

  factory Payment.fromMap(Map<String, dynamic> map) {
    return Payment(
      id: map['id'] ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      date: map['date'] is Timestamp
          ? (map['date'] as Timestamp).toDate()
          : DateTime.tryParse(map['date'] ?? '') ?? DateTime.now(),
      method: map['method'] ?? 'cash',
      notes: map['notes'],
      transactionId: map['transactionId'],
    );
  }
}

/// Helper class to hold calculated tax totals for the entire invoice.
class TaxTotals {
  double cgstTotal = 0.0;
  double sgstTotal = 0.0;
  double igstTotal = 0.0;
  double totalTaxable = 0.0;
  double totalDiscount = 0.0;
  double totalTax = 0.0;
  double grandTotal = 0.0;
}
