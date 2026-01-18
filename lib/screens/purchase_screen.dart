import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/purchase_model.dart';
import '../services/purchase_service.dart';
import '../utils/app_theme.dart';
import '../widgets/purchase/invoice_summary_card.dart';
import '../widgets/purchase/item_entry_row.dart';
import '../widgets/purchase/supplier_search_dialog.dart';

class PurchaseInvoiceScreen extends StatefulWidget {
  final PurchaseModel? purchase; // Optional purchase for editing

  const PurchaseInvoiceScreen({super.key, this.purchase});

  @override
  State<PurchaseInvoiceScreen> createState() => _PurchaseInvoiceScreenState();
}

class _PurchaseInvoiceScreenState extends State<PurchaseInvoiceScreen> {
  final PurchaseService _service = PurchaseService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // State
  bool _isLoadingData = true;
  bool _isSaving = false;
  List<Supplier> _fetchedSuppliers = [];
  List<Item> _fetchedItems = [];

  // Invoice Data
  Supplier? _selectedSupplier;
  final List<InvoiceItem> _invoiceItems = [];
  final TextEditingController _invoiceNumberController = TextEditingController();
  DateTime _invoiceDate = DateTime.now();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 30));

  // Payment Data
  String _paymentStatus = 'unpaid'; // 'paid', 'unpaid', 'partial'
  final TextEditingController _paidAmountController = TextEditingController(text: '0');
  DateTime _paymentDate = DateTime.now();
  String _paymentMethod = 'cash'; // 'cash', 'bank', 'upi', 'cheque'
  final TextEditingController _paymentNotesController = TextEditingController();

  // Config
  final String _yourStateCode = 'MH'; // Replace with actual user config

  @override
  void initState() {
    super.initState();
    if (widget.purchase != null) {
      _loadPurchaseData();
    } else {
      _invoiceNumberController.text = 'PI-${Random().nextInt(99999) + 1000}';
    }
    _loadInitialData();
  }

  void _loadPurchaseData() {
    final p = widget.purchase!;
    _invoiceNumberController.text = p.invoiceNumber;
    _invoiceDate = p.purchaseDate;
    _dueDate = p.dueDate;
    _paymentStatus = p.paymentStatus.toString().split('.').last;
    _paidAmountController.text = p.paidAmount.toStringAsFixed(2);
    _paymentDate = p.paymentDate ?? DateTime.now();
    _paymentMethod = p.paymentMethod;
    _paymentNotesController.text = p.paymentNotes ?? '';
    
    // Items will be loaded after fetching products to ensure we have full Item objects
  }

  @override
  void dispose() {
    _invoiceNumberController.dispose();
    _paidAmountController.dispose();
    _paymentNotesController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      final results = await Future.wait([
        _firestore.collection('users').doc(uid).collection('suppliers').get(),
        _firestore.collection('users').doc(uid).collection('products').get(),
      ]);

      setState(() {
        _fetchedSuppliers =
            results[0].docs.map(Supplier.fromFirestore).toList();
        _fetchedItems = results[1].docs.map(Item.fromFirestore).toList();
        _isLoadingData = false;
        
        // If editing, populate supplier and items now that we have the lists
        if (widget.purchase != null) {
          final p = widget.purchase!;
          
          // Find Supplier
          try {
            _selectedSupplier = _fetchedSuppliers.firstWhere((s) => s.id == p.supplierId);
          } catch (e) {
            // Supplier might have been deleted, create a temporary one
            _selectedSupplier = Supplier(
              id: p.supplierId,
              name: p.supplierName,
              stateCode: p.supplierStateCode,
              gstin: '',
              phone: '',
              outstandingBalance: 0,
            );
          }
          
          // Map Items
          for (var itemData in p.items) {
            try {
              final product = _fetchedItems.firstWhere((i) => i.id == itemData.itemId);
              _invoiceItems.add(InvoiceItem(
                item: product,
                quantity: itemData.quantity,
                unitPrice: itemData.unitPrice,
                discount: itemData.discount,
              ));
            } catch (e) {
              // Product might be deleted
              debugPrint('Product not found for editing: ${itemData.itemId}');
            }
          }
        }
      });
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  // Calculation Logic
  TaxTotals get _totals {
    final totals = TaxTotals();
    final supplierState = _selectedSupplier?.stateCode ?? 'XX';

    for (var item in _invoiceItems) {
      totals.totalTaxable += item.taxableAmount;
      totals.totalDiscount += item.quantity * item.discount;

      if (supplierState == _yourStateCode) {
        final halfTax = item.totalTaxAmount / 2;
        totals.cgstTotal += halfTax;
        totals.sgstTotal += halfTax;
      } else {
        totals.igstTotal += item.totalTaxAmount;
      }
    }
    totals.totalTax = totals.cgstTotal + totals.sgstTotal + totals.igstTotal;
    totals.grandTotal = totals.totalTaxable + totals.totalTax;
    return totals;
  }

  // Actions
  void _addItem(Item item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ItemEntryRow(
          item: item,
          onAdd: (invoiceItem) {
            setState(() => _invoiceItems.add(invoiceItem));
            Navigator.pop(context);
          },
          onCancel: () => Navigator.pop(context),
        ),
      ),
    );
  }

  Future<void> _saveInvoice() async {
    if (_selectedSupplier == null) {
      _showError('Please select a supplier');
      return;
    }
    if (_invoiceItems.isEmpty) {
      _showError('Please add at least one item');
      return;
    }
    if (_invoiceNumberController.text.isEmpty) {
      _showError('Please enter invoice number');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final totals = _totals;
      final paidAmount = double.tryParse(_paidAmountController.text) ?? 0.0;
      final outstandingAmount = totals.grandTotal - paidAmount;

      // Determine payment status
      String finalPaymentStatus;
      if (paidAmount >= totals.grandTotal) {
        finalPaymentStatus = 'paid';
      } else if (paidAmount > 0) {
        finalPaymentStatus = 'partial';
      } else {
        finalPaymentStatus = 'unpaid';
      }

      if (widget.purchase != null) {
        // UPDATE Existing Invoice
        await _service.updatePurchaseInvoice(
          invoiceId: widget.purchase!.id,
          oldSupplierId: widget.purchase!.supplierId,
          oldItems: widget.purchase!.items.map((i) {
             // We need to reconstruct InvoiceItem from PurchaseItemModel for the service
             // But the service only needs item.id and quantity for reversion.
             // We can create a dummy Item with the correct ID.
             return InvoiceItem(
               item: Item(id: i.itemId, name: '', gstRate: 0, purchasePrice: 0, salePrice: 0),
               quantity: i.quantity,
               unitPrice: 0,
               discount: 0,
             );
          }).toList(),
          oldGrandTotal: widget.purchase!.totalAmount,
          oldPaidAmount: widget.purchase!.paidAmount,
          
          invoiceNumber: _invoiceNumberController.text,
          supplier: _selectedSupplier!,
          items: _invoiceItems,
          totals: totals,
          invoiceDate: _invoiceDate,
          dueDate: _dueDate,
          yourStateCode: _yourStateCode,
          userName: _auth.currentUser?.displayName,
          paymentStatus: finalPaymentStatus,
          paidAmount: paidAmount,
          paymentDate: _paymentDate,
          paymentMethod: _paymentMethod,
          paymentNotes: _paymentNotesController.text,
          outstandingAmount: outstandingAmount,
        );
      } else {
        // CREATE New Invoice
        await _service.savePurchaseInvoice(
          invoiceNumber: _invoiceNumberController.text,
          supplier: _selectedSupplier!,
          items: _invoiceItems,
          totals: totals,
          invoiceDate: _invoiceDate,
          dueDate: _dueDate,
          yourStateCode: _yourStateCode,
          userName: _auth.currentUser?.displayName,
          paymentStatus: finalPaymentStatus,
          paidAmount: paidAmount,
          paymentDate: _paymentDate,
          paymentMethod: _paymentMethod,
          paymentNotes: _paymentNotesController.text,
          outstandingAmount: outstandingAmount,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.purchase != null ? 'Invoice Updated Successfully' : 'Invoice Saved Successfully'),
            backgroundColor: AppTheme.success,
          ),
        );
        Navigator.pop(context); // Return to list
      }
    } catch (e) {
      _showError('Failed to save invoice: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.danger),
    );
  }

  Future<void> _generatePurchasePdf() async {
    if (_selectedSupplier == null || _invoiceItems.isEmpty) {
      _showError('Please add supplier and items first');
      return;
    }

    try {
      final pdf = pw.Document();
      final dateFormat = DateFormat('dd MMM yyyy');
      final totals = _totals;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (context) => [
            // Header
            pw.Text(
              'PURCHASE INVOICE',
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 20),

            // Invoice Details
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Invoice No: ${_invoiceNumberController.text}',
                        style: const pw.TextStyle(fontSize: 12)),
                    pw.SizedBox(height: 4),
                    pw.Text('Date: ${dateFormat.format(_invoiceDate)}',
                        style: const pw.TextStyle(fontSize: 12)),
                    pw.SizedBox(height: 4),
                    pw.Text('Due Date: ${dateFormat.format(_dueDate)}',
                        style: const pw.TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 20),

            // Supplier Details
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Supplier Details',
                      style: pw.TextStyle(
                          fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 8),
                  pw.Text('Name: ${_selectedSupplier!.name}',
                      style: const pw.TextStyle(fontSize: 11)),
                  if (_selectedSupplier!.gstin.isNotEmpty)
                    pw.Text('GSTIN: ${_selectedSupplier!.gstin}',
                        style: const pw.TextStyle(fontSize: 11)),
                  if (_selectedSupplier!.phone.isNotEmpty)
                    pw.Text('Phone: ${_selectedSupplier!.phone}',
                        style: const pw.TextStyle(fontSize: 11)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // Items Table
            pw.Table.fromTextArray(
              headers: ['Item', 'Qty', 'Rate', 'Disc', 'Tax', 'Amount'],
              data: _invoiceItems.map((invoiceItem) {
                return [
                  invoiceItem.item.name,
                  invoiceItem.quantity.toStringAsFixed(2),
                  invoiceItem.unitPrice.toStringAsFixed(2),
                  invoiceItem.discount.toStringAsFixed(2),
                  '${(invoiceItem.item.gstRate * 100).toStringAsFixed(1)}%',
                  invoiceItem.lineTotal.toStringAsFixed(2),
                ];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignment: pw.Alignment.centerRight,
              cellAlignments: {0: pw.Alignment.centerLeft},
            ),
            pw.SizedBox(height: 20),

            // Totals
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Container(
                  width: 250,
                  child: pw.Column(
                    children: [
                      _buildPdfTotalRow('Taxable Amount',
                          totals.totalTaxable.toStringAsFixed(2)),
                      if (totals.cgstTotal > 0)
                        _buildPdfTotalRow(
                            'CGST', totals.cgstTotal.toStringAsFixed(2)),
                      if (totals.sgstTotal > 0)
                        _buildPdfTotalRow(
                            'SGST', totals.sgstTotal.toStringAsFixed(2)),
                      if (totals.igstTotal > 0)
                        _buildPdfTotalRow(
                            'IGST', totals.igstTotal.toStringAsFixed(2)),
                      pw.Divider(thickness: 2),
                      _buildPdfTotalRow('Grand Total',
                          totals.grandTotal.toStringAsFixed(2),
                          isBold: true),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'Purchase_${_invoiceNumberController.text}.pdf',
      );
    } catch (e) {
      _showError('Failed to generate PDF: $e');
    }
  }

  pw.Widget _buildPdfTotalRow(String label, String amount,
      {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight:
                      isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text('₹$amount',
              style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight:
                      isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      ),
    );
  }

  // UI Builders
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('New Purchase Invoice'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_invoiceItems.isNotEmpty && _selectedSupplier != null)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: 'Preview PDF',
              onPressed: _generatePurchasePdf,
            ),
        ],
      ),
      body: _isLoadingData
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderSection(),
                  const SizedBox(height: 24),
                  _buildSupplierSection(),
                  const SizedBox(height: 24),
                  _buildItemsSection(),
                  const SizedBox(height: 24),
                  InvoiceSummaryCard(totals: _totals),
                  const SizedBox(height: 24),
                  _buildPaymentSection(),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _isSaving ? null : _saveInvoice,
                      child: _isSaving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'SAVE INVOICE',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeaderSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration,
      child: Column(
        children: [
          TextField(
            controller: _invoiceNumberController,
            decoration: AppTheme.inputDecoration('Invoice Number'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildDatePicker(
                  'Date',
                  _invoiceDate,
                  (d) => setState(() => _invoiceDate = d),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildDatePicker(
                  'Due Date',
                  _dueDate,
                  (d) => setState(() => _dueDate = d),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildSupplierSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Supplier',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  onPressed: _showAddSupplierDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Supplier'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_selectedSupplier != null) ...[
              ListTile(
                title: Text(
                  _selectedSupplier!.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_selectedSupplier!.gstin.isNotEmpty)
                      Text('GSTIN: ${_selectedSupplier!.gstin}'),
                    if (_selectedSupplier!.phone.isNotEmpty)
                      Text('Phone: ${_selectedSupplier!.phone}'),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: _showAddSupplierDialog,
                ),
              ),
            ] else
              const Text('No supplier selected', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
  
  Widget _buildItemsSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Items',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  onPressed: _showAddProductDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Item'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_invoiceItems.isNotEmpty)
              ..._invoiceItems.map((item) => ListTile(
                    title: Text(item.item.name),
                    subtitle: Text(
                        '${item.quantity} x ₹${item.unitPrice.toStringAsFixed(2)} = ₹${(item.quantity * item.unitPrice).toStringAsFixed(2)}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => setState(() => _invoiceItems.remove(item)),
                    ),
                  ))
            else
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16.0),
                  child: Text('No items added yet', style: TextStyle(color: Colors.grey)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatePicker(
      String label, DateTime date, Function(DateTime) onSelect) {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (d != null) onSelect(d);
      },
      child: InputDecorator(
        decoration: AppTheme.inputDecoration(label).copyWith(labelText: label),
        child: Text(
          DateFormat('dd MMM yyyy').format(date),
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }

  Widget _buildPaymentSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.payment, color: AppTheme.primary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Payment Details',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Payment Status
            DropdownButtonFormField<String>(
              value: _paymentStatus,
              decoration: const InputDecoration(
                labelText: 'Payment Status',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: const [
                DropdownMenuItem(value: 'paid', child: Text('Paid')),
                DropdownMenuItem(value: 'unpaid', child: Text('Unpaid')),
              ],
              onChanged: (value) {
                setState(() {
                  _paymentStatus = value!;
                  if (value == 'paid') {
                    _paidAmountController.text = _totals.grandTotal.toStringAsFixed(2);
                  } else {
                    _paidAmountController.text = '0';
                  }
                });
              },
            ),
            
            if (_paymentStatus == 'paid') ...[
              const SizedBox(height: 16),
              
              // Paid Amount
              TextFormField(
                controller: _paidAmountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Paid Amount',
                  border: const OutlineInputBorder(),
                  prefixText: '₹ ',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  suffixText: 'of ₹${_totals.grandTotal.toStringAsFixed(2)}',
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Payment Date
              InkWell(
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _paymentDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (date != null) {
                    setState(() => _paymentDate = date);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Payment Date',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(DateFormat('dd MMM yyyy').format(_paymentDate)),
                      const Icon(Icons.calendar_today, size: 20),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Payment Method
              DropdownButtonFormField<String>(
                value: _paymentMethod,
                decoration: const InputDecoration(
                  labelText: 'Payment Method',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'bank', child: Text('Bank Transfer')),
                  DropdownMenuItem(value: 'upi', child: Text('UPI')),
                  DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                ],
                onChanged: (value) => setState(() => _paymentMethod = value!),
              ),
              
              const SizedBox(height: 16),
              
              // Payment Notes
              TextFormField(
                controller: _paymentNotesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Payment Notes (Optional)',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showAddSupplierDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final gstinController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Supplier'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: AppTheme.inputDecoration('Supplier Name'),
                validator: (v) => v?.isEmpty == true ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: phoneController,
                decoration: AppTheme.inputDecoration('Phone Number'),
                keyboardType: TextInputType.phone,
                validator: (v) => v?.isEmpty == true ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: gstinController,
                decoration: AppTheme.inputDecoration('GSTIN (Optional)'),
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
              if (formKey.currentState!.validate()) {
                try {
                  final newSupplier = await _service.addQuickSupplier(
                    name: nameController.text,
                    phone: phoneController.text,
                    gstin: gstinController.text,
                  );
                  
                  setState(() {
                    _fetchedSuppliers.add(newSupplier);
                    _selectedSupplier = newSupplier;
                    _invoiceItems.clear(); // Clear items as supplier changed
                  });
                  
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Supplier added successfully')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger),
                    );
                  }
                }
              }
            },
            child: const Text('Add Supplier'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddProductDialog() async {
    final nameController = TextEditingController();
    final purchasePriceController = TextEditingController();
    final salePriceController = TextEditingController();
    final gstController = TextEditingController(text: '18');
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Product'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: AppTheme.inputDecoration('Product Name'),
                  validator: (v) => v?.isEmpty == true ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: purchasePriceController,
                        decoration: AppTheme.inputDecoration('Purchase Price'),
                        keyboardType: TextInputType.number,
                        validator: (v) => v?.isEmpty == true ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: salePriceController,
                        decoration: AppTheme.inputDecoration('Sale Price'),
                        keyboardType: TextInputType.number,
                        validator: (v) => v?.isEmpty == true ? 'Required' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: gstController,
                  decoration: AppTheme.inputDecoration('GST %'),
                  keyboardType: TextInputType.number,
                  validator: (v) => v?.isEmpty == true ? 'Required' : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                try {
                  final gstRate = (double.tryParse(gstController.text) ?? 0) / 100;
                  final newProduct = await _service.addQuickProduct(
                    name: nameController.text,
                    purchasePrice: double.tryParse(purchasePriceController.text) ?? 0,
                    salePrice: double.tryParse(salePriceController.text) ?? 0,
                    gstRate: gstRate,
                  );
                  
                  setState(() {
                    _fetchedItems.add(newProduct);
                    _addItem(newProduct);
                  });
                  
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Product added successfully')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger),
                    );
                  }
                }
              }
            },
            child: const Text('Add Product'),
          ),
        ],
      ),
    );
  }
}
