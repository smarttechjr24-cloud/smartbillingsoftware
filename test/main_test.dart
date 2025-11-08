// test/main_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:smartbilling/main.dart';

// ✅ Create mock classes
class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {}

class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class MockDocumentSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

class MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class MockCollectionReference extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

void main() {
  late MockFirebaseAuth mockAuth;
  late MockFirebaseFirestore mockFirestore;
  late MockUser mockUser;
  late MockDocumentSnapshot mockDoc;
  late MockDocumentReference mockDocRef;
  late MockCollectionReference mockCollection;

  setUp(() {
    mockAuth = MockFirebaseAuth();
    mockFirestore = MockFirebaseFirestore();
    mockUser = MockUser();
    mockDoc = MockDocumentSnapshot();
    mockDocRef = MockDocumentReference();
    mockCollection = MockCollectionReference();
  });

  group('🧩 SmartBillingApp Widget Tests', () {
    testWidgets('Shows loading indicator initially', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: AuthGate()));

      // Loading indicator visible first
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('Navigates to LoginScreen if no user logged in', (
      WidgetTester tester,
    ) async {
      // Mock behavior: No current user
      FirebaseAuth.instance.signOut();

      await tester.pumpWidget(const MaterialApp(home: AuthGate()));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Verify login screen appears
      expect(
        find.text('Login'),
        findsOneWidget,
      ); // Adjust if LoginScreen has other identifiers
    });

    testWidgets('Navigates to Dashboard when user and company details exist', (
      WidgetTester tester,
    ) async {
      // Mock Firebase User
      when(mockAuth.currentUser).thenReturn(mockUser);
      when(mockUser.uid).thenReturn('test_uid');

      // Mock Firestore company doc
      when(mockFirestore.collection('users')).thenReturn(mockCollection);
      when(mockCollection.doc('test_uid')).thenReturn(mockDocRef);
      when(mockDocRef.collection('company')).thenReturn(mockCollection);
      when(mockCollection.doc('details')).thenReturn(mockDocRef);
      when(mockDocRef.get()).thenAnswer((_) async => mockDoc);
      when(mockDoc.exists).thenReturn(true);
      when(mockDoc.data()).thenReturn({'name': 'Test Company'});

      await tester.pumpWidget(const MaterialApp(home: AuthGate()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Dashboard'), findsWidgets);
    });

    testWidgets('Navigates to CompanyDetailsScreen if company missing', (
      WidgetTester tester,
    ) async {
      when(mockAuth.currentUser).thenReturn(mockUser);
      when(mockUser.uid).thenReturn('test_uid');

      when(mockFirestore.collection('users')).thenReturn(mockCollection);
      when(mockCollection.doc('test_uid')).thenReturn(mockDocRef);
      when(mockDocRef.collection('company')).thenReturn(mockCollection);
      when(mockCollection.doc('details')).thenReturn(mockDocRef);
      when(mockDocRef.get()).thenAnswer((_) async => mockDoc);
      when(mockDoc.exists).thenReturn(false);

      await tester.pumpWidget(const MaterialApp(home: AuthGate()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Company Details'), findsWidgets);
    });
  });

  group('🌐 MainNavigation Widget Tests', () {
    testWidgets('Has 3 bottom navigation items', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: MainNavigation()));

      expect(find.byType(NavigationDestination), findsNWidgets(3));
    });

    testWidgets('Tapping "New" opens create options bottom sheet', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: MainNavigation()));

      // Tap the middle button (New)
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();

      // Expect Create Invoice and Create Quotation options
      expect(find.text('Create Invoice'), findsOneWidget);
      expect(find.text('Create Quotation'), findsOneWidget);
    });
  });
}
