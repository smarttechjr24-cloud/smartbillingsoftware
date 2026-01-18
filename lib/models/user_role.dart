import 'package:flutter/material.dart';

enum UserRole {
  owner,
  manager,
  salesStaff,
  inventoryStaff,
}

/// Extension to get display name and color for roles
extension UserRoleExtension on UserRole {
  String get displayName {
    switch (this) {
      case UserRole.owner:
        return 'Owner';
      case UserRole.manager:
        return 'Manager';
      case UserRole.salesStaff:
        return 'Sales Staff';
      case UserRole.inventoryStaff:
        return 'Inventory Staff';
    }
  }

  Color get color {
    switch (this) {
      case UserRole.owner:
        return const Color(0xFF6A1B9A); // Purple
      case UserRole.manager:
        return const Color(0xFF1976D2); // Blue
      case UserRole.salesStaff:
        return const Color(0xFF388E3C); // Green
      case UserRole.inventoryStaff:
        return const Color(0xFFF57C00); // Orange
    }
  }

  IconData get icon {
    switch (this) {
      case UserRole.owner:
        return Icons.admin_panel_settings;
      case UserRole.manager:
        return Icons.manage_accounts;
      case UserRole.salesStaff:
        return Icons.point_of_sale;
      case UserRole.inventoryStaff:
        return Icons.inventory;
    }
  }

  /// Convert role to string for Firestore
  String toFirestore() {
    return toString().split('.').last;
  }

  /// Parse role from Firestore string
  static UserRole fromFirestore(String value) {
    switch (value) {
      case 'owner':
        return UserRole.owner;
      case 'manager':
        return UserRole.manager;
      case 'salesStaff':
        return UserRole.salesStaff;
      case 'inventoryStaff':
        return UserRole.inventoryStaff;
      default:
        return UserRole.salesStaff; // Default to most restricted
    }
  }
}

/// Granular permissions for different actions
class Permission {
  // Dashboard & Reports
  final bool viewDashboard;
  final bool viewReports;
  final bool viewProfitAnalytics;

  // Invoices & Quotations
  final bool createInvoice;
  final bool editInvoice;
  final bool deleteInvoice;
  final bool viewInvoice;
  final bool createQuotation;
  final bool editQuotation;
  final bool deleteQuotation;
  final bool viewQuotation;

  // Purchases
  final bool createPurchase;
  final bool editPurchase;
  final bool deletePurchase;
  final bool viewPurchase;

  // Customers & Suppliers
  final bool manageCustomers;
  final bool viewCustomers;
  final bool manageSuppliers;
  final bool viewSuppliers;

  // Products & Inventory
  final bool manageProducts;
  final bool viewProducts;
  final bool viewStock;

  // Payments
  final bool recordPayment;
  final bool viewPayments;
  final bool recordPurchasePayment;

  // Settings & Users
  final bool manageUsers;
  final bool editSettings;
  final bool viewActivityLog;
  final bool editPDFTheme;

  const Permission({
    // Dashboard & Reports
    this.viewDashboard = true,
    this.viewReports = false,
    this.viewProfitAnalytics = false,

    // Invoices & Quotations
    this.createInvoice = false,
    this.editInvoice = false,
    this.deleteInvoice = false,
    this.viewInvoice = false,
    this.createQuotation = false,
    this.editQuotation = false,
    this.deleteQuotation = false,
    this.viewQuotation = false,

    // Purchases
    this.createPurchase = false,
    this.editPurchase = false,
    this.deletePurchase = false,
    this.viewPurchase = false,

    // Customers & Suppliers
    this.manageCustomers = false,
    this.viewCustomers = false,
    this.manageSuppliers = false,
    this.viewSuppliers = false,

    // Products & Inventory
    this.manageProducts = false,
    this.viewProducts = false,
    this.viewStock = false,

    // Payments
    this.recordPayment = false,
    this.viewPayments = false,
    this.recordPurchasePayment = false,

    // Settings & Users
    this.manageUsers = false,
    this.editSettings = false,
    this.viewActivityLog = false,
    this.editPDFTheme = false,
  });

  /// Get permissions for a specific role
  static Permission forRole(UserRole role) {
    switch (role) {
      case UserRole.owner:
        return const Permission(
          // Full access to everything
          viewDashboard: true,
          viewReports: true,
          viewProfitAnalytics: true,
          createInvoice: true,
          editInvoice: true,
          deleteInvoice: true,
          viewInvoice: true,
          createQuotation: true,
          editQuotation: true,
          deleteQuotation: true,
          viewQuotation: true,
          createPurchase: true,
          editPurchase: true,
          deletePurchase: true,
          viewPurchase: true,
          manageCustomers: true,
          viewCustomers: true,
          manageSuppliers: true,
          viewSuppliers: true,
          manageProducts: true,
          viewProducts: true,
          viewStock: true,
          recordPayment: true,
          viewPayments: true,
          recordPurchasePayment: true,
          manageUsers: true,
          editSettings: true,
          viewActivityLog: true,
          editPDFTheme: true,
        );

      case UserRole.manager:
        return const Permission(
          // Can view and manage most things except users
          viewDashboard: true,
          viewReports: true,
          viewProfitAnalytics: true,
          createInvoice: true,
          editInvoice: true,
          deleteInvoice: false, // Cannot delete
          viewInvoice: true,
          createQuotation: true,
          editQuotation: true,
          deleteQuotation: false,
          viewQuotation: true,
          createPurchase: true,
          editPurchase: true,
          deletePurchase: false,
          viewPurchase: true,
          manageCustomers: true,
          viewCustomers: true,
          manageSuppliers: true,
          viewSuppliers: true,
          manageProducts: true,
          viewProducts: true,
          viewStock: true,
          recordPayment: true,
          viewPayments: true,
          recordPurchasePayment: true,
          manageUsers: false, // Cannot manage users
          editSettings: false,
          viewActivityLog: true,
          editPDFTheme: false,
        );

      case UserRole.salesStaff:
        return const Permission(
          // Only sales-related permissions
          viewDashboard: true,
          viewReports: false, // Cannot view financial reports
          viewProfitAnalytics: false,
          createInvoice: true,
          editInvoice: true,
          deleteInvoice: false,
          viewInvoice: true,
          createQuotation: true,
          editQuotation: true,
          deleteQuotation: false,
          viewQuotation: true,
          createPurchase: false, // No purchase access
          editPurchase: false,
          deletePurchase: false,
          viewPurchase: false,
          manageCustomers: true,
          viewCustomers: true,
          manageSuppliers: false, // No supplier access
          viewSuppliers: false,
          manageProducts: false, // Can view but not manage
          viewProducts: true,
          viewStock: true,
          recordPayment: true,
          viewPayments: true,
          recordPurchasePayment: false,
          manageUsers: false,
          editSettings: false,
          viewActivityLog: false,
          editPDFTheme: false,
        );

      case UserRole.inventoryStaff:
        return const Permission(
          // Only inventory-related permissions
          viewDashboard: true,
          viewReports: false,
          viewProfitAnalytics: false,
          createInvoice: false, // No invoice access
          editInvoice: false,
          deleteInvoice: false,
          viewInvoice: false,
          createQuotation: false,
          editQuotation: false,
          deleteQuotation: false,
          viewQuotation: false,
          createPurchase: true, // Can manage purchases
          editPurchase: true,
          deletePurchase: false,
          viewPurchase: true,
          manageCustomers: false,
          viewCustomers: false,
          manageSuppliers: true, // Can manage suppliers
          viewSuppliers: true,
          manageProducts: true, // Full product access
          viewProducts: true,
          viewStock: true,
          recordPayment: false,
          viewPayments: false,
          recordPurchasePayment: true, // Can record purchase payments
          manageUsers: false,
          editSettings: false,
          viewActivityLog: false,
          editPDFTheme: false,
        );
    }
  }

  /// Convert to map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'viewDashboard': viewDashboard,
      'viewReports': viewReports,
      'viewProfitAnalytics': viewProfitAnalytics,
      'createInvoice': createInvoice,
      'editInvoice': editInvoice,
      'deleteInvoice': deleteInvoice,
      'viewInvoice': viewInvoice,
      'createQuotation': createQuotation,
      'editQuotation': editQuotation,
      'deleteQuotation': deleteQuotation,
      'viewQuotation': viewQuotation,
      'createPurchase': createPurchase,
      'editPurchase': editPurchase,
      'deletePurchase': deletePurchase,
      'viewPurchase': viewPurchase,
      'manageCustomers': manageCustomers,
      'viewCustomers': viewCustomers,
      'manageSuppliers': manageSuppliers,
      'viewSuppliers': viewSuppliers,
      'manageProducts': manageProducts,
      'viewProducts': viewProducts,
      'viewStock': viewStock,
      'recordPayment': recordPayment,
      'viewPayments': viewPayments,
      'recordPurchasePayment': recordPurchasePayment,
      'manageUsers': manageUsers,
      'editSettings': editSettings,
      'viewActivityLog': viewActivityLog,
      'editPDFTheme': editPDFTheme,
    };
  }

  /// Create from Firestore map
  factory Permission.fromMap(Map<String, dynamic> map) {
    return Permission(
      viewDashboard: map['viewDashboard'] ?? true,
      viewReports: map['viewReports'] ?? false,
      viewProfitAnalytics: map['viewProfitAnalytics'] ?? false,
      createInvoice: map['createInvoice'] ?? false,
      editInvoice: map['editInvoice'] ?? false,
      deleteInvoice: map['deleteInvoice'] ?? false,
      viewInvoice: map['viewInvoice'] ?? false,
      createQuotation: map['createQuotation'] ?? false,
      editQuotation: map['editQuotation'] ?? false,
      deleteQuotation: map['deleteQuotation'] ?? false,
      viewQuotation: map['viewQuotation'] ?? false,
      createPurchase: map['createPurchase'] ?? false,
      editPurchase: map['editPurchase'] ?? false,
      deletePurchase: map['deletePurchase'] ?? false,
      viewPurchase: map['viewPurchase'] ?? false,
      manageCustomers: map['manageCustomers'] ?? false,
      viewCustomers: map['viewCustomers'] ?? false,
      manageSuppliers: map['manageSuppliers'] ?? false,
      viewSuppliers: map['viewSuppliers'] ?? false,
      manageProducts: map['manageProducts'] ?? false,
      viewProducts: map['viewProducts'] ?? false,
      viewStock: map['viewStock'] ?? false,
      recordPayment: map['recordPayment'] ?? false,
      viewPayments: map['viewPayments'] ?? false,
      recordPurchasePayment: map['recordPurchasePayment'] ?? false,
      manageUsers: map['manageUsers'] ?? false,
      editSettings: map['editSettings'] ?? false,
      viewActivityLog: map['viewActivityLog'] ?? false,
      editPDFTheme: map['editPDFTheme'] ?? false,
    );
  }
}
