import 'package:flutter/foundation.dart';

class InvoiceCalculator {
  /// Calculates the tax breakdown and totals for a list of items
  static Map<String, dynamic> calculate({
    required List<Map<String, dynamic>> items,
    required double gstPercentage,
    required bool isInterstate,
  }) {
    double subtotal = 0.0;
    double totalCgst = 0.0;
    double totalSgst = 0.0;
    double totalIgst = 0.0;
    
    List<Map<String, dynamic>> processedItems = [];

    for (var item in items) {
      // Handle different input formats (controllers vs raw values)
      double qty = 0.0;
      double rate = 0.0;
      
      if (item['qtyCtrl'] != null) {
        qty = double.tryParse(item['qtyCtrl'].text) ?? 1.0;
      } else {
        qty = (item['qty'] ?? 1).toDouble();
      }
      
      if (item['rateCtrl'] != null) {
        rate = double.tryParse(item['rateCtrl'].text) ?? 0.0;
      } else {
        rate = (item['rate'] ?? 0).toDouble();
      }

      final discount = (item['discount'] ?? 0).toDouble();
      
      // Core Calculation Logic
      final baseAmount = qty * rate;
      final discountAmount = baseAmount * (discount / 100);
      final taxableAmount = baseAmount - discountAmount;
      
      double cgst = 0.0;
      double sgst = 0.0;
      double igst = 0.0;
      
      if (isInterstate) {
        igst = taxableAmount * (gstPercentage / 100);
      } else {
        cgst = taxableAmount * (gstPercentage / 2 / 100);
        sgst = taxableAmount * (gstPercentage / 2 / 100);
      }
      
      final lineTotal = taxableAmount + cgst + sgst + igst;
      
      subtotal += taxableAmount;
      totalCgst += cgst;
      totalSgst += sgst;
      totalIgst += igst;
      
      processedItems.add({
        ...item,
        'taxable_amount': taxableAmount,
        'cgst': cgst,
        'sgst': sgst,
        'igst': igst,
        'line_total': lineTotal,
        'gst_percent': gstPercentage, // Ensure this is stamped on the item
      });
    }
    
    final totalTax = totalCgst + totalSgst + totalIgst;
    final grandTotal = subtotal + totalTax;

    return {
      'subtotal': subtotal,
      'total_cgst': totalCgst,
      'total_sgst': totalSgst,
      'total_igst': totalIgst,
      'total_tax': totalTax,
      'grand_total': grandTotal,
      'items': processedItems,
    };
  }
}
