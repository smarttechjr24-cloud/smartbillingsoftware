import 'package:flutter_test/flutter_test.dart';
import 'package:smartbilling/utils/invoice_calculator.dart';

void main() {
  group('InvoiceCalculator Tests', () {
    test('Calculate with 18% GST (Default)', () {
      final items = [
        {'qty': 10, 'rate': 100, 'discount': 0},
      ];
      
      final result = InvoiceCalculator.calculate(
        items: items,
        gstPercentage: 18.0,
        isInterstate: false,
      );
      
      expect(result['subtotal'], 1000.0);
      expect(result['total_tax'], 180.0);
      expect(result['grand_total'], 1180.0);
      expect(result['total_cgst'], 90.0);
      expect(result['total_sgst'], 90.0);
    });

    test('Calculate with 5% GST (User Changed)', () {
      final items = [
        {'qty': 10, 'rate': 100, 'discount': 0},
      ];
      
      // Simulating user changing GST to 5%
      final result = InvoiceCalculator.calculate(
        items: items,
        gstPercentage: 5.0,
        isInterstate: false,
      );
      
      expect(result['subtotal'], 1000.0);
      expect(result['total_tax'], 50.0); // 5% of 1000
      expect(result['grand_total'], 1050.0);
      expect(result['total_cgst'], 25.0);
      expect(result['total_sgst'], 25.0);
    });

    test('Calculate Interstate (IGST)', () {
      final items = [
        {'qty': 10, 'rate': 100, 'discount': 0},
      ];
      
      final result = InvoiceCalculator.calculate(
        items: items,
        gstPercentage: 18.0,
        isInterstate: true,
      );
      
      expect(result['total_igst'], 180.0);
      expect(result['total_cgst'], 0.0);
      expect(result['total_sgst'], 0.0);
    });

    test('Quotation to Invoice Conversion (Scenario)', () {
      // Simulate data coming from a Quotation
      final quotationItems = [
        {'item': 'Service A', 'qty': 1, 'rate': 5000, 'discount': 10}, // 4500 taxable
        {'item': 'Product B', 'qty': 2, 'rate': 1000, 'discount': 0},  // 2000 taxable
      ];
      
      // Scenario: User changes GST from 18% (Quotation) to 12% (Invoice)
      final result = InvoiceCalculator.calculate(
        items: quotationItems,
        gstPercentage: 12.0, // New GST rate
        isInterstate: false,
      );
      
      // Expected:
      // Item 1: 5000 - 10% = 4500
      // Item 2: 2000
      // Subtotal: 6500
      // Tax (12%): 780
      // Total: 7280
      
      expect(result['subtotal'], 6500.0);
      expect(result['total_tax'], 780.0);
      expect(result['grand_total'], 7280.0);
    });
  });
}
