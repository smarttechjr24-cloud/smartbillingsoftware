import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smartbilling/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('SmartBilling A-Z Integration Test', () {
    testWidgets('Full App Flow Test', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 1. Check Login State
      // Assumes user is already logged in or we are in a test environment.
      // If at Login Screen, fail or try to login (hard without credentials).
      if (find.text('Login').evaluate().isNotEmpty) {
        debugPrint('⚠️ Test requires user to be logged in. Please login manually on the device first.');
        // For now, we can't proceed if not logged in.
        // In a real CI/CD, we would mock auth or use a test account.
        return;
      }

      // 2. Verify Dashboard
      expect(find.text('Smart Billing Dashboard'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 3. Navigate to More -> Products
      await tester.tap(find.byIcon(Icons.menu)); // More Tab
      await tester.pumpAndSettle();
      
      await tester.tap(find.text('Products'));
      await tester.pumpAndSettle();
      
      // 4. Add Product
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      
      await tester.enterText(find.byType(TextField).at(0), 'Test Product A'); // Name
      await tester.enterText(find.byType(TextField).at(1), '100'); // Purchase Price
      await tester.enterText(find.byType(TextField).at(2), '150'); // Sale Price
      
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      
      // Verify Product Added
      expect(find.text('Test Product A'), findsOneWidget);
      
      await tester.pageBack(); // Back to More
      await tester.pumpAndSettle();

      // 5. Navigate to More -> Suppliers
      await tester.tap(find.text('Suppliers'));
      await tester.pumpAndSettle();
      
      // 6. Add Supplier
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      
      await tester.enterText(find.byType(TextField).at(0), 'Test Supplier X'); // Name
      await tester.enterText(find.byType(TextField).at(1), '9876543210'); // Phone
      
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      
      // Verify Supplier Added
      expect(find.text('Test Supplier X'), findsOneWidget);
      
      await tester.pageBack(); // Back to More
      await tester.pumpAndSettle();

      // 7. Create Purchase
      // Go to Home -> Create -> Purchase (if available) or via More -> Purchases
      await tester.tap(find.text('Purchases')); // Assuming it's in More
      await tester.pumpAndSettle();
      
      await tester.tap(find.byIcon(Icons.add)); // Add Purchase
      await tester.pumpAndSettle();
      
      // Select Supplier
      await tester.tap(find.text('Select Supplier'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test Supplier X'));
      await tester.pumpAndSettle();
      
      // Add Item
      await tester.tap(find.text('Add Item'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test Product A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add')); // Add in item dialog
      await tester.pumpAndSettle();
      
      // Save Purchase
      await tester.tap(find.text('SAVE INVOICE'));
      await tester.pumpAndSettle(const Duration(seconds: 2)); // Wait for save
      
      // Verify Purchase in List
      expect(find.text('Test Supplier X'), findsOneWidget);
      
      await tester.pageBack(); // Back to More
      await tester.pumpAndSettle();

      // 8. Create Quotation
      await tester.tap(find.byIcon(Icons.add_circle_outline)); // Create Tab
      await tester.pumpAndSettle();
      
      await tester.tap(find.text('Create Quotation'));
      await tester.pumpAndSettle();
      
      // Fill Quotation Details
      await tester.enterText(find.byType(TextField).at(0), 'Test Customer Y'); // Customer Name
      
      // Add Item
      await tester.tap(find.text('Add Item'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test Product A')); // Select product
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      
      // Save Quotation
      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      
      // 9. Convert to Invoice
      // Navigate to Quotations List (via More -> Quotations)
      await tester.pageBack(); // Back to Home
      await tester.tap(find.byIcon(Icons.menu)); // More Tab
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quotations'));
      await tester.pumpAndSettle();
      
      await tester.tap(find.text('Convert to Invoice').first);
      await tester.pumpAndSettle();
      
      await tester.tap(find.text('Convert')); // Confirm conversion
      await tester.pumpAndSettle(const Duration(seconds: 2));
      
      // Verify Invoice Created
      expect(find.text('Invoice Saved Successfully'), findsOneWidget);
      
      debugPrint('✅ A-Z Test Completed Successfully');
    });
  });
}
