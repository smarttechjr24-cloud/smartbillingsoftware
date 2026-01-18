import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/purchase_model.dart';
import '../services/purchase_service.dart';
import '../utils/app_theme.dart';
import '../widgets/purchase/dashboard_stats.dart';
import '../widgets/purchase/filter_chips.dart';
import '../widgets/purchase/purchase_card.dart';
import 'purchase_screen.dart'; // Keep for navigation to Add Screen

class PurchaseScreenList extends StatefulWidget {
  const PurchaseScreenList({super.key});

  @override
  State<PurchaseScreenList> createState() => _PurchaseScreenListState();
}

class _PurchaseScreenListState extends State<PurchaseScreenList>
    with TickerProviderStateMixin {
  final PurchaseService _service = PurchaseService();
  final TextEditingController _searchController = TextEditingController();
  
  // State
  String _searchQuery = '';
  String _selectedFilter = 'All';
  Map<String, double> _dashboardData = {};

  // Animations
  late AnimationController _searchControllerAnim;
  late AnimationController _listController;

  @override
  void initState() {
    super.initState();
    _searchControllerAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _listController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchControllerAnim.dispose();
    _listController.dispose();
    super.dispose();
  }

  Future<void> _refreshData() async {
    // Force rebuild to re-fetch stream
    setState(() {});
    // Simulate network delay for UX
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: _buildAppBar(),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const PurchaseInvoiceScreen(),
            ),
          );
        },
        backgroundColor: AppTheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: StreamBuilder<List<PurchaseModel>>(
        stream: _service.fetchPurchases,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
             return const Center(child: CircularProgressIndicator());
          }

          final purchases = snapshot.data ?? [];

          return RefreshIndicator(
            onRefresh: _refreshData,
            color: AppTheme.primary,
            child: Column(
              children: [
                _buildDashboard(purchases),
                FilterChips(
                  selectedFilter: _selectedFilter,
                  onSelected: (filter) => setState(() => _selectedFilter = filter),
                ),
                Expanded(child: _buildPurchaseList(purchases)),
              ],
            ),
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Purchases', style: AppTheme.headlineMedium.copyWith(color: Colors.white)),
          Text('Track all supplier purchases', 
               style: AppTheme.bodySmall.copyWith(color: Colors.white70)),
        ],
      ),
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.primary, AppTheme.accent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: AnimatedIcon(
            icon: AnimatedIcons.search_ellipsis,
            progress: _searchControllerAnim,
            color: Colors.white,
          ),
          onPressed: () {
            setState(() {
              if (_searchQuery.isEmpty) {
                _searchControllerAnim.forward();
              } else {
                _searchController.clear();
                _searchQuery = '';
                _searchControllerAnim.reverse();
              }
            });
          },
        ),
      ],
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(
          _searchQuery.isEmpty && !_searchControllerAnim.isAnimating ? 0.0 : 60.0,
        ),
        child: SizeTransition(
          sizeFactor: _searchControllerAnim,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
              decoration: AppTheme.inputDecoration('Search by Supplier or Invoice')
                  .copyWith(
                    prefixIcon: const Icon(Icons.search, color: AppTheme.primary),
                    fillColor: Colors.white,
                  ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard(List<PurchaseModel> purchases) {
    return FutureBuilder<Map<String, double>>(
      future: _service.getDashboardData(purchases),
      builder: (context, snapshot) {
        final data = snapshot.data ?? _dashboardData;
        
        if (snapshot.hasData) {
          _dashboardData = snapshot.data!;
        }
        
        return DashboardStats(
          totalPurchases: data['totalPurchases'] ?? 0,
          totalOutstanding: data['totalSupplierOutstanding'] ?? 0,
          overdueAmount: data['totalOverdue'] ?? 0,
          isLoading: snapshot.connectionState == ConnectionState.waiting && _dashboardData.isEmpty,
        );
      },
    );
  }

  Widget _buildPurchaseList(List<PurchaseModel> purchases) {
    final filtered = _filterPurchases(purchases);

    if (filtered.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.2),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: _listController,
            curve: Interval(
              index / filtered.length * 0.5,
              1.0,
              curve: Curves.easeOut,
            ),
          )),
          child: PurchaseCard(
            purchase: filtered[index],
            onView: () => _viewPurchaseDetails(filtered[index]),
            onEdit: () => _navigateToEdit(filtered[index]),
            onAddPayment: () => _showAddPaymentDialog(filtered[index]),
            onDelete: (p) => _service.deletePurchase(p.id),
          ),
        );
      },
    );
  }

  List<PurchaseModel> _filterPurchases(List<PurchaseModel> purchases) {
    var filtered = purchases;

    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((p) =>
          p.supplierName.toLowerCase().contains(_searchQuery) ||
          p.invoiceNumber.toLowerCase().contains(_searchQuery)).toList();
    }

    if (_selectedFilter != 'All') {
      filtered = filtered.where((p) {
        switch (_selectedFilter) {
          case 'Paid': return p.paymentStatus == PurchasePaymentStatus.paid;
          case 'Partial': return p.paymentStatus == PurchasePaymentStatus.partial;
          case 'Outstanding': return p.paymentStatus == PurchasePaymentStatus.outstanding;
          case 'Overdue': return p.isOverdue;
          default: return true;
        }
      }).toList();
    }

    return filtered;
  }

  Widget _buildShimmerList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: Container(
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_bag_outlined, size: 64, color: AppTheme.textHint),
          const SizedBox(height: 16),
          Text('No purchases found', style: AppTheme.titleMedium.copyWith(color: AppTheme.textHint)),
        ],
      ),
    );
  }

  void _viewPurchaseDetails(PurchaseModel purchase) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Purchase #${purchase.invoiceNumber}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Supplier', purchase.supplierName),
              _buildDetailRow('Date', DateFormat('dd MMM yyyy').format(purchase.purchaseDate)),
              _buildDetailRow('Due Date', DateFormat('dd MMM yyyy').format(purchase.dueDate)),
              const Divider(),
              _buildDetailRow('Total Amount', '₹${purchase.totalAmount.toStringAsFixed(2)}'),
              _buildDetailRow('Outstanding', '₹${purchase.outstandingAmount.toStringAsFixed(2)}'),
              _buildDetailRow('Status', purchase.paymentStatus.toString().split('.').last.toUpperCase()),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  void _navigateToEdit(PurchaseModel purchase) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PurchaseInvoiceScreen(purchase: purchase),
      ),
    );
  }

  void _showAddPaymentDialog(PurchaseModel purchase) {
    final amountController = TextEditingController();
    String paymentMethod = 'cash';
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Payment'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Invoice: ${purchase.invoiceNumber}'),
                Text('Outstanding: ₹${purchase.outstandingAmount.toStringAsFixed(2)}'),
                const SizedBox(height: 16),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Payment Amount',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: paymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'Payment Method',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'bank', child: Text('Bank Transfer')),
                    DropdownMenuItem(value: 'upi', child: Text('UPI')),
                    DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                  ],
                  onChanged: (value) => setState(() => paymentMethod = value!),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes (Optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text) ?? 0;
                if (amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid amount')),
                  );
                  return;
                }
                if (amount > purchase.outstandingAmount) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Amount cannot exceed outstanding balance')),
                  );
                  return;
                }

                try {
                  await _service.recordPayment(
                    invoiceId: purchase.id,
                    supplierId: purchase.supplierId,
                    amount: amount,
                    userName: FirebaseAuth.instance.currentUser?.displayName ?? 'User',
                  );
                  
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Payment recorded successfully'),
                        backgroundColor: AppTheme.success,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger),
                    );
                  }
                }
              },
              child: const Text('Record Payment'),
            ),
          ],
        ),
      ),
    );
  }
}
