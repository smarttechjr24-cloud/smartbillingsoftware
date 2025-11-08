import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:cloud_firestore_mocks/cloud_firestore_mocks.dart';
import 'package:smartbilling/screens/login_screen.dart';

void main() {
  // Initialize Firebase before any test
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp();
  });

  group('LoginScreen UI & Logic Tests', () {
    late MockFirebaseAuth mockAuth;
    late MockFirestoreInstance mockFirestore;

    setUp(() {
      mockAuth = MockFirebaseAuth();
      mockFirestore = MockFirestoreInstance();
    });

    testWidgets('renders email, password, and login button', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Login'), findsOneWidget);
    });

    testWidgets('shows loading indicator when login pressed', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

      // Enter valid input
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'test@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'password123');

      // Tap login button
      await tester.tap(find.text('Login'));
      await tester.pump();

      // Expect loading indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('navigates after successful login', (
      WidgetTester tester,
    ) async {
      final user = MockUser(
        uid: 'test_uid',
        email: 'test@example.com',
        displayName: 'Test User',
      );

      mockAuth = MockFirebaseAuth(mockUser: user, signedIn: true);

      // Add mock Firestore user document
      await mockFirestore.collection('users').doc('test_uid').set({
        'has_company_details': true,
        'name': 'Test Company',
      });

      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

      // Enter credentials
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'test@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'password123');

      await tester.tap(find.text('Login'));
      await tester.pump(const Duration(seconds: 2));

      // Confirm that the UI changed or SnackBar shown
      expect(find.textContaining('Login successful'), findsOneWidget);
    });
  });
}
