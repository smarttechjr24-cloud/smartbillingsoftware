import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:smartbilling/utils/delivery_chellan.dart';
import 'package:smartbilling/utils/invoices/templateE.dart';
import 'package:smartbilling/utils/invoices/templateb.dart';
import '../utils/pdf.dart';
import '../utils/signature_repository.dart';
import 'add_invoice_screen.dart';

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({Key? key}) : super(key: key);

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _searchController = TextEditingController();

  String _searchQuery = "";
  String _filterStatus = "All";
  String? get _uid => _auth.currentUser?.uid;

  Stream<QuerySnapshot<Map<String, dynamic>>> _getInvoices() {
    if (_uid == null) return const Stream.empty();
    
    try {
      return _firestore
          .collection('users')
          .doc(_uid)
          .collection('invoices')
          .orderBy('created_at', descending: true)
          .snapshots();
    } catch (e) {
      // Fallback if created_at index doesn't exist
      debugPrint('⚠️ Error with created_at orderBy, using invoice_date: $e');
      return _firestore
          .collection('users')
          .doc(_uid)
          .collection('invoices')
          .snapshots();
    }
  }

  String _formatTimestamp(dynamic ts) {
    if (ts is Timestamp) {
      return DateFormat('dd MMM yyyy, hh:mm a').format(ts.toDate());
    }
    return '-';
  }

  void _showSnack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: success ? Colors.green : Colors.redAccent,
      ),
    );
  }

  Future<void> _deleteInvoice(String id) async {
    try {
      if (_uid == null) return;

      final userRef = _firestore.collection('users').doc(_uid);
      final invoicesRef = userRef.collection('invoices');
      final customersRef = userRef.collection('customers');
      final quotationsRef = userRef.collection('quotations');
      final receiptsRef = userRef.collection(
        'receipts',
      ); // 👈 Added for payment check

      // 1️⃣ Fetch the invoice document
      final invoiceDoc = await invoicesRef.doc(id).get();
      if (!invoiceDoc.exists) {
        _showSnack("❌ Invoice not found");
        return;
      }

      final invoiceData = invoiceDoc.data()!;
      final String customerName = invoiceData['customer_name'] ?? '';
      final double grandTotal = (invoiceData['grand_total'] ?? 0.0).toDouble();
      final String? quotationId = invoiceData['quotation_id'];

      // 2️⃣ Check if any receipts are linked to this invoice
      final receiptsSnap = await receiptsRef
          .where('invoice_id', isEqualTo: id)
          .limit(1)
          .get();

      if (receiptsSnap.docs.isNotEmpty) {
        _showSnack('⚠️ Cannot delete invoice — payment receipt exists!');
        return;
      }

      // 3️⃣ If invoice was created from a quotation, reset it back to "Open"
      if (quotationId != null && quotationId.isNotEmpty) {
        final qSnap = await quotationsRef
            .where('id', isEqualTo: quotationId)
            .limit(1)
            .get();

        if (qSnap.docs.isNotEmpty) {
          await qSnap.docs.first.reference.update({'status': 'Open'});
        }
      }

      // 4️⃣ Reduce customer's outstanding balance
      if (customerName.isNotEmpty) {
        final custSnap = await customersRef
            .where('name', isEqualTo: customerName)
            .limit(1)
            .get();

        if (custSnap.docs.isNotEmpty) {
          final custDoc = custSnap.docs.first;
          final currentOutstanding = (custDoc['outstanding'] ?? 0.0).toDouble();
          final newOutstanding = (currentOutstanding - grandTotal).clamp(
            0,
            double.infinity,
          );

          await custDoc.reference.update({'outstanding': newOutstanding});
        }
      }

      // 5️⃣ Delete the invoice (only if no receipts)
      await invoiceDoc.reference.delete();

      _showSnack('✅ Invoice deleted successfully', success: true);
    } catch (e) {
      _showSnack('❌ Error deleting invoice: $e');
    }
  }

  Future<void> _generatePDF(
    String id,
    Map<String, dynamic> data, {
    bool printDirectly = false,
  }) async {
    try {
      // Load signature before generating PDF
      final signatureBytes = await SignatureRepository.getSignature();
      
      // Add signature to data map (temporary for PDF generation)
      // Or better, update PdfService to accept signatureBytes separately or handle it internally.
      // Since PdfService.generateAndOpenPDF takes cachedData, let's inject it there.
      final pdfData = Map<String, dynamic>.from(data);
      if (signatureBytes != null) {
        pdfData['signature_bytes'] = signatureBytes;
      }

      await PdfService.generateAndOpenPDF(
        id,
        cachedData: pdfData,
        printDirectly: printDirectly,
      );
    } catch (e) {
      _showSnack("❌ Failed to generate PDF: $e");
    }
  }

  // ✅ QR Dialog

  Future<void> _addPayment(
    String invoiceId,
    Map<String, dynamic> invoiceData,
  ) async {
    final total = (invoiceData['grand_total'] ?? 0).toDouble();
    final paid = (invoiceData['paid_amount'] ?? 0).toDouble();
    final balance = total - paid;
    final customerName = invoiceData['customer_name'] ?? '';
    final invoiceNumber = invoiceData['invoice_number'] ?? '-';
    final _uid = FirebaseAuth.instance.currentUser?.uid;

    if (_uid == null) {
      _showSnack("❌ User not logged in");
      return;
    }

    final amountCtrl = TextEditingController();
    final upiIdCtrl = TextEditingController();
    final chequeCtrl = TextEditingController();
    String paymentMode = "Cash";
    bool showQR = false;
    String qrLink = "";

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            Future<void> savePayment() async {
              final entered = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
              if (entered <= 0) {
                _showSnack("❌ Enter a valid amount");
                return;
              }
              if (entered > balance) {
                _showSnack("❌ Payment exceeds balance due");
                return;
              }

              // Compute new values
              final newPaid = paid + entered;
              final newBalance = total - newPaid;

              String status = "Pending";
              if (newPaid == 0)
                status = "Pending";
              else if (newPaid < total)
                status = "Partially Paid";
              else
                status = "Paid";

              final now = DateTime.now();
              final firestore = FirebaseFirestore.instance;
              final userRef = firestore.collection('users').doc(_uid);
              final invoiceRef = userRef.collection('invoices').doc(invoiceId);

              try {
                // 🧾 1. Add payment under invoice
                await invoiceRef.collection('payments').add({
                  'amount': entered,
                  'payment_mode': paymentMode,
                  'upi_id': upiIdCtrl.text.trim(),
                  'cheque_no': chequeCtrl.text.trim(),
                  'created_at': Timestamp.now(),
                });

                // 🧾 2. Add to main payments collection
                await userRef.collection('payments').add({
                  'amount': entered,
                  'payment_mode': paymentMode,
                  'upi_id': upiIdCtrl.text.trim(),
                  'cheque_no': chequeCtrl.text.trim(),
                  'created_at': Timestamp.now(),
                  'customer_name': customerName,
                  'invoice_id': invoiceId,
                  'invoice_number': invoiceNumber,
                  'balance_due': newBalance,
                });

                // 💰 3. Update invoice totals
                await invoiceRef.update({
                  'paid_amount': newPaid,
                  'balance_due': newBalance,
                  'status': status,
                  'last_payment_date': now.toIso8601String(),
                });

                // 👤 4. Update customer's outstanding
                final custSnap = await userRef
                    .collection('customers')
                    .where('name', isEqualTo: customerName)
                    .limit(1)
                    .get();

                if (custSnap.docs.isNotEmpty) {
                  final custDoc = custSnap.docs.first;
                  final currentOutstanding = (custDoc['outstanding'] ?? 0)
                      .toDouble();
                  final newOutstanding = (currentOutstanding - entered).clamp(
                    0,
                    double.infinity,
                  );
                  await custDoc.reference.update({
                    'outstanding': newOutstanding,
                  });
                }

                if (ctx.mounted) Navigator.pop(ctx);
                _showSnack("✅ Payment added successfully!", success: true);
              } catch (e) {
                _showSnack("❌ Failed to add payment: $e");
              }
            }

            void generateQR() async {
              final entered = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
              if (entered <= 0) {
                _showSnack("Enter valid amount before generating QR");
                return;
              }

              String upiId = upiIdCtrl.text.trim();
              if (upiId.isEmpty) {
                final companyRef = FirebaseFirestore.instance
                    .collection('users')
                    .doc(_uid)
                    .collection('company')
                    .doc('details');
                final doc = await companyRef.get();
                upiId = doc.data()?['upi_id'] ?? "";
                if (upiId.isEmpty) {
                  _showSnack("⚠️ Enter or save your UPI ID first");
                  return;
                }
              }

              final link =
                  "upi://pay?pa=$upiId&pn=${Uri.encodeComponent(customerName)}&am=$entered&cu=INR";
              setStateDialog(() {
                qrLink = link;
                showQR = true;
              });
            }

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              insetPadding: const EdgeInsets.symmetric(horizontal: 20),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Text(
                          "💳 Add Payment",
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text("Invoice: $invoiceNumber"),
                      Text("Customer: $customerName"),
                      Text("Total: ₹${total.toStringAsFixed(2)}"),
                      Text("Paid: ₹${paid.toStringAsFixed(2)}"),
                      Text(
                        "Balance: ₹${balance.toStringAsFixed(2)}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.redAccent,
                        ),
                      ),
                      const Divider(height: 20),
                      TextField(
                        controller: amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: "Enter Payment Amount",
                          prefixIcon: Icon(Icons.currency_rupee),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: paymentMode,
                        decoration: const InputDecoration(
                          labelText: "Payment Mode",
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: "Cash", child: Text("Cash")),
                          DropdownMenuItem(
                            value: "UPI",
                            child: Text("UPI / QR"),
                          ),
                          DropdownMenuItem(
                            value: "Bank Transfer",
                            child: Text("Bank Transfer"),
                          ),
                          DropdownMenuItem(
                            value: "Credit Card",
                            child: Text("Credit Card"),
                          ),
                          DropdownMenuItem(
                            value: "Cheque",
                            child: Text("Cheque"),
                          ),
                          DropdownMenuItem(
                            value: "Other",
                            child: Text("Other"),
                          ),
                        ],
                        onChanged: (v) {
                          setStateDialog(() {
                            paymentMode = v ?? "Cash";
                            showQR = false;
                          });
                        },
                      ),
                      const SizedBox(height: 10),

                      // Optional fields
                      if (paymentMode == "UPI") ...[
                        TextField(
                          controller: upiIdCtrl,
                          decoration: const InputDecoration(
                            labelText: "UPI ID (optional)",
                            prefixIcon: Icon(Icons.qr_code_2),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (paymentMode == "Cheque") ...[
                        TextField(
                          controller: chequeCtrl,
                          decoration: const InputDecoration(
                            labelText: "Cheque No (optional)",
                            prefixIcon: Icon(Icons.numbers),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      if (showQR) ...[
                        const Divider(),
                        const Center(
                          child: Text(
                            "Scan to Pay",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Center(
                          child: QrImageView(
                            data: qrLink,
                            size: 180,
                            backgroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            "₹${amountCtrl.text.trim()} for $customerName",
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: savePayment,
                              icon: const Icon(Icons.save),
                              label: const Text("Save"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                minimumSize: const Size(double.infinity, 46),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (paymentMode == "UPI")
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: generateQR,
                                icon: const Icon(Icons.qr_code_2),
                                label: const Text("Generate"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  minimumSize: const Size(double.infinity, 46),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
  // ✅ Edit Invoice Unified Dialog
  Future<void> _openEditInvoiceDialog(
    String id,
    Map<String, dynamic> data,
  ) async {
    // Indian States List
    const List<String> indianStates = [
      "Andhra Pradesh", "Arunachal Pradesh", "Assam", "Bihar", "Chhattisgarh",
      "Goa", "Gujarat", "Haryana", "Himachal Pradesh", "Jharkhand",
      "Karnataka", "Kerala", "Madhya Pradesh", "Maharashtra", "Manipur",
      "Meghalaya", "Mizoram", "Nagaland", "Odisha", "Punjab",
      "Rajasthan", "Sikkim", "Tamil Nadu", "Telangana", "Tripura",
      "Uttar Pradesh", "Uttarakhand", "West Bengal",
      "Andaman and Nicobar Islands", "Chandigarh",
      "Dadra and Nagar Haveli and Daman and Diu", "Delhi",
      "Jammu and Kashmir", "Ladakh", "Lakshadweep", "Puducherry",
    ];

    final nameCtrl = TextEditingController(text: data['customer_name']);
    final billCtrl = TextEditingController(text: data['billing_address']);
    final shipCtrl = TextEditingController(text: data['shipping_address']);
    final noteCtrl = TextEditingController(text: data['note'] ?? '');
    
    // Get customer state from data, default to Tamil Nadu if not found
    String customerState = (data['customer_state'] ?? 'Tamil Nadu').toString();
    if (!indianStates.contains(customerState)) {
      customerState = 'Tamil Nadu';
    }
    
    // Get company state (default to Tamil Nadu)
    const String companyState = 'Tamil Nadu'; // TODO: Get from company settings
    
    // Calculate tax type based on state
    String taxType = (customerState.trim().toLowerCase() != companyState.trim().toLowerCase())
        ? 'IGST'
        : 'CGST_SGST';

    DateTime invoiceDate =
        DateTime.tryParse(data['invoice_date'] ?? '') ?? DateTime.now();
    DateTime dueDate =
        DateTime.tryParse(data['due_date'] ?? '') ??
        DateTime.now().add(const Duration(days: 7));

    // Items setup
    List<Map<String, dynamic>> items = List<Map<String, dynamic>>.from(
      data['items'] ?? [],
    );
    
    // Ensure controllers for existing items
    for (final i in items) {
      i['qtyCtrl'] ??= TextEditingController(text: (i['qty'] ?? 1).toString());
      i['rateCtrl'] ??= TextEditingController(
        text: (i['rate'] ?? 0).toString(),
      );
      i['gstCtrl'] ??= TextEditingController(
        text: (i['gst_percent'] ?? i['tax_percent'] ?? 0).toString(),
      );
      i['discountCtrl'] ??= TextEditingController(
        text: (i['discount'] ?? 0).toString(),
      );
    }

    double total = (data['grand_total'] ?? 0).toDouble();
    
    // Product cache
    List<Map<String, dynamic>> products = [];
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('products')
            .get();
        products = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      } catch (e) {
        debugPrint("⚠️ Product load error: $e");
      }
    }

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final df = DateFormat("dd MMM yyyy");

            void recalc() {
              total = items.fold(0.0, (sum, i) {
                final qty = double.tryParse(i['qtyCtrl'].text) ?? 1.0;
                final rate = double.tryParse(i['rateCtrl'].text) ?? 0.0;
                final gst = double.tryParse(i['gstCtrl'].text) ?? 0.0;
                final discount = double.tryParse(i['discountCtrl']?.text ?? '0') ?? 0.0;
                
                final base = qty * rate;
                final afterDiscount = base - (base * discount / 100);
                final gstAmount = afterDiscount * (gst / 100);
                
                // Update item internal values
                i['qty'] = qty;
                i['rate'] = rate;
                i['gst_percent'] = gst;
                i['discount'] = discount;
                i['taxable_amount'] = afterDiscount;
                i['tax_amount'] = gstAmount;
                i['amount'] = afterDiscount + gstAmount;

                return sum + afterDiscount + gstAmount;
              });
              setStateDialog(() {});
            }

            Future<void> _pickInvoiceDate() async {
              final picked = await showDatePicker(
                context: context,
                initialDate: invoiceDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                setStateDialog(() {
                  invoiceDate = picked;
                  if (dueDate.isBefore(invoiceDate)) {
                    dueDate = invoiceDate.add(const Duration(days: 7));
                  }
                });
              }
            }

            Future<void> _pickDueDate() async {
              final picked = await showDatePicker(
                context: context,
                initialDate: dueDate,
                firstDate: invoiceDate,
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                setStateDialog(() => dueDate = picked);
              }
            }

            void addItem() {
              items.add({
                'item': '',
                'item_name': '',
                'qty': 1.0,
                'rate': 0.0,
                'gst_percent': 0.0,
                'discount': 0.0,
                'qtyCtrl': TextEditingController(text: '1'),
                'rateCtrl': TextEditingController(text: '0'),
                'gstCtrl': TextEditingController(text: '0'),
                'discountCtrl': TextEditingController(text: '0'),
              });
              setStateDialog(() {});
            }

            return Dialog.fullscreen(
              child: Scaffold(
                backgroundColor: Colors.grey.shade50,
                appBar: AppBar(
                  title: const Text("Edit Invoice"),
                  backgroundColor: const Color(0xFF1F3A5F),
                  foregroundColor: Colors.white,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                body: SafeArea(
                  child: Form(
                    key: formKey,
                    child: Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // --- Section 1: Invoice Details ---
                                const Text(
                                  "Invoice Details",
                                  style: TextStyle(
                                    fontSize: 18, 
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1F3A5F),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Card(
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: InkWell(
                                                onTap: _pickInvoiceDate,
                                                child: InputDecorator(
                                                  decoration: const InputDecoration(
                                                    labelText: "Invoice Date",
                                                    border: OutlineInputBorder(),
                                                    prefixIcon: Icon(Icons.calendar_today),
                                                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                  ),
                                                  child: Text(df.format(invoiceDate)),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: InkWell(
                                                onTap: _pickDueDate,
                                                child: InputDecorator(
                                                  decoration: const InputDecoration(
                                                    labelText: "Due Date",
                                                    border: OutlineInputBorder(),
                                                    prefixIcon: Icon(Icons.schedule),
                                                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                  ),
                                                  child: Text(df.format(dueDate)),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        TextFormField(
                                          controller: nameCtrl,
                                          decoration: const InputDecoration(
                                            labelText: "Customer Name",
                                            border: OutlineInputBorder(),
                                            prefixIcon: Icon(Icons.person),
                                          ),
                                          validator: (v) => v!.trim().isEmpty ? "Required" : null,
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextFormField(
                                                controller: billCtrl,
                                                decoration: const InputDecoration(
                                                  labelText: "Billing Address",
                                                  border: OutlineInputBorder(),
                                                ),
                                                maxLines: 2,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: TextFormField(
                                                controller: shipCtrl,
                                                decoration: const InputDecoration(
                                                  labelText: "Shipping Address",
                                                  border: OutlineInputBorder(),
                                                ),
                                                maxLines: 2,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        DropdownButtonFormField<String>(
                                          value: customerState,
                                          isExpanded: true, // Prevents overflow
                                          menuMaxHeight: 300, // Limits dropdown height and makes it scrollable
                                          decoration: const InputDecoration(
                                            labelText: "State of Supply",
                                            border: OutlineInputBorder(),
                                            prefixIcon: Icon(Icons.location_on),
                                          ),
                                          items: indianStates.map((state) {
                                            return DropdownMenuItem(
                                              value: state,
                                              child: Text(
                                                state,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            );
                                          }).toList(),
                                          onChanged: (v) {
                                            setStateDialog(() {
                                              customerState = v ?? 'Tamil Nadu';
                                              // Recalculate tax type based on selected state
                                              taxType = (customerState.trim().toLowerCase() != companyState.trim().toLowerCase())
                                                  ? 'IGST'
                                                  : 'CGST_SGST';
                                            });
                                          },
                                        ),
                                        const SizedBox(height: 12),
                                        TextFormField(
                                          controller: noteCtrl,
                                          decoration: const InputDecoration(
                                            labelText: "Notes (optional)",
                                            border: OutlineInputBorder(),
                                          ),
                                          maxLines: 2,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 24),

                                // --- Section 2: Items ---
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      "Items",
                                      style: TextStyle(
                                        fontSize: 18, 
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1F3A5F),
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: addItem,
                                      icon: const Icon(Icons.add, size: 18),
                                      label: const Text("Add Item"),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                
                                ...items.asMap().entries.map((entry) {
                                  final idx = entry.key;
                                  final item = entry.value;
                                  final qtyCtrl = item['qtyCtrl'] as TextEditingController;
                                  final rateCtrl = item['rateCtrl'] as TextEditingController;
                                  final gstCtrl = item['gstCtrl'] as TextEditingController;
                                  final discountCtrl = item['discountCtrl'] as TextEditingController;

                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                flex: 3,
                                                child: Autocomplete<Map<String, dynamic>>(
                                                  displayStringForOption: (p) => p['name'] ?? '',
                                                  optionsBuilder: (text) {
                                                    if (text.text.isEmpty) return const Iterable.empty();
                                                    return products.where((p) => (p['name'] ?? '').toString().toLowerCase().contains(text.text.toLowerCase()));
                                                  },
                                                  fieldViewBuilder: (context, controller, node, onSubmit) {
                                                    if (controller.text.isEmpty && (item['item_name'] ?? '').isNotEmpty) {
                                                      controller.text = item['item_name'];
                                                    }
                                                    return TextField(
                                                      controller: controller,
                                                      focusNode: node,
                                                      decoration: const InputDecoration(
                                                        labelText: "Item Name",
                                                        border: OutlineInputBorder(),
                                                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                                      ),
                                                      onChanged: (v) {
                                                        item['item_name'] = v;
                                                        item['item'] = v;
                                                      },
                                                    );
                                                  },
                                                  onSelected: (sel) {
                                                    item['item_name'] = sel['name'];
                                                    item['item'] = sel['name'];
                                                    item['rate'] = (sel['rate'] ?? 0).toDouble();
                                                    item['gst_percent'] = (sel['gst_percent'] ?? 0).toDouble();
                                                    
                                                    rateCtrl.text = item['rate'].toString();
                                                    gstCtrl.text = item['gst_percent'].toString();
                                                    recalc();
                                                  },
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.delete, color: Colors.redAccent),
                                                onPressed: () {
                                                  items.removeAt(idx);
                                                  recalc();
                                                },
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: TextField(
                                                  controller: qtyCtrl,
                                                  keyboardType: TextInputType.number,
                                                  decoration: const InputDecoration(labelText: "Qty", border: OutlineInputBorder()),
                                                  onChanged: (_) => recalc(),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: TextField(
                                                  controller: rateCtrl,
                                                  keyboardType: TextInputType.number,
                                                  decoration: const InputDecoration(labelText: "Rate", border: OutlineInputBorder()),
                                                  onChanged: (_) => recalc(),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: TextField(
                                                  controller: gstCtrl,
                                                  keyboardType: TextInputType.number,
                                                  decoration: const InputDecoration(labelText: "GST %", border: OutlineInputBorder()),
                                                  onChanged: (_) => recalc(),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: TextField(
                                                  controller: discountCtrl,
                                                  keyboardType: TextInputType.number,
                                                  decoration: const InputDecoration(labelText: "Disc %", border: OutlineInputBorder()),
                                                  onChanged: (_) => recalc(),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                                
                                const SizedBox(height: 100), // Space for bottom bar
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                bottomSheet: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -5))],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Grand Total", style: TextStyle(color: Colors.grey)),
                          Text(
                            "₹${total.toStringAsFixed(2)}",
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1F3A5F)),
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.save),
                        label: const Text("Save Invoice"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1F3A5F),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                        onPressed: () async {
                          if (!formKey.currentState!.validate()) return;
                          
                          // Final recalc to ensure consistency
                          recalc();

                          try {
                            // Clean items before saving
                            final cleanItems = items.map((i) {
                              final m = Map<String, dynamic>.from(i);
                              m.remove('qtyCtrl');
                              m.remove('rateCtrl');
                              m.remove('gstCtrl');
                              m.remove('discountCtrl');
                              return m;
                            }).toList();

                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(uid)
                                .collection('invoices')
                                .doc(id)
                                .update({
                                  'customer_name': nameCtrl.text.trim(),
                                  'billing_address': billCtrl.text.trim(),
                                  'shipping_address': shipCtrl.text.trim(),
                                  'note': noteCtrl.text.trim(),
                                  'customer_state': customerState,
                                  'tax_type': taxType,
                                  'invoice_date': invoiceDate.toIso8601String(),
                                  'due_date': dueDate.toIso8601String(),
                                  'items': cleanItems,
                                  'grand_total': total,
                                  'updated_at': FieldValue.serverTimestamp(),
                                });
                            
                            if (ctx.mounted) Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("✅ Invoice updated successfully!"), backgroundColor: Colors.green),
                            );
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("❌ Error updating invoice: $e")),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ✅ Filter Chips
  Widget _buildFilterChips() {
    final filters = ["All", "Pending", "Paid", "Partially Paid"];
    return Wrap(
      spacing: 8,
      children: filters.map((f) {
        final selected = f == _filterStatus;
        return ChoiceChip(
          label: Text(f),
          selected: selected,
          selectedColor: Colors.blue.shade600,
          backgroundColor: Colors.grey.shade200,
          labelStyle: TextStyle(
            color: selected ? Colors.white : Colors.black87,
          ),
          onSelected: (_) => setState(() => _filterStatus = f),
        );
      }).toList(),
    );
  }

  // ✅ View Invoice Details
  void _viewInvoice(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text("Invoice: ${data['customer_name'] ?? 'Unknown'}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("From: ${data['billing_address'] ?? '-'}"),
            Text("To: ${data['shipping_address'] ?? '-'}"),
            Text("Total: ₹${data['grand_total'] ?? 0}"),
            Text("GST: ${data['gst_percentage'] ?? 0}%"),
            Text("Date: ${_formatTimestamp(data['created_at'])}"),
            Text("Status: ${data['status'] ?? 'Pending'}"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  // ✅ Main UI
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Invoices"),
        centerTitle: true,
        backgroundColor: primary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
              decoration: InputDecoration(
                hintText: "Search by customer name...",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = "");
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primary,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddInvoiceScreen()),
          );
        },
        label: const Text("New Invoice"),
        icon: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _getInvoices(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snapshot.data!.docs.where((doc) {
              final data = doc.data();
              final name = (data['customer_name'] ?? '')
                  .toString()
                  .toLowerCase();
              final status = (data['status'] ?? 'Pending').toString();
              return name.contains(_searchQuery) &&
                  (_filterStatus == "All" || status == _filterStatus);
            }).toList();

            if (docs.isEmpty) {
              return const Center(child: Text("No invoices found."));
            }

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: _buildFilterChips(),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data();
                      final status = (data['status'] ?? 'Pending').toString();

                      Color color;
                      switch (status) {
                        case 'Paid':
                          color = Colors.green;
                          break;
                        case 'Pending':
                          color = Colors.orange;
                          break;
                        case 'Partially Paid':
                          color = Colors.blue;
                          break;
                        default:
                          color = Colors.grey;
                      }

                      return Card(
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(14),
                          leading: CircleAvatar(
                            backgroundColor: color.withOpacity(0.15),
                            child: Icon(
                              Icons.receipt_long_rounded,
                              color: color,
                            ),
                          ),
                          title: Text(
                            data['customer_name'] ?? 'Unnamed Customer',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Date: ${_formatTimestamp(data['created_at'])}",
                              ),
                              Text(
                                "Total: ₹${(data['grand_total'] ?? 0).toStringAsFixed(2)}",
                              ),

                              // 🟢 Added: Balance Due line
                              Builder(
                                builder: (_) {
                                  final total = (data['grand_total'] ?? 0)
                                      .toDouble();
                                  final paid = (data['paid_amount'] ?? 0)
                                      .toDouble();
                                  final balance = (total - paid).clamp(
                                    0,
                                    double.infinity,
                                  );

                                  final balanceColor = balance > 0
                                      ? Colors.redAccent
                                      : Colors.green.shade600;

                                  return Text(
                                    "Balance Due: ₹${balance.toStringAsFixed(2)}",
                                    style: TextStyle(
                                      color: balanceColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  );
                                },
                              ),

                              Text(
                                "Status: $status",
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          trailing: Wrap(
                            spacing: 6,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.print,
                                  color: Colors.blueAccent,
                                ),
                                onPressed: () async {
                                  try {
                                    await _generatePDF(
                                      doc.id,
                                      data,
                                      printDirectly: true,
                                    );
                                  } catch (e) {
                                    _showSnack("❌ Failed to print: $e");
                                  }
                                },
                              ),
                              PopupMenuButton<String>(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                onSelected: (v) async {
                                  switch (v) {
                                    case 'view':
                                      _viewInvoice(data);
                                      break;
                                    case 'edit':
                                      _openEditInvoiceDialog(doc.id, data);
                                      break;
                                    case 'pdf':
                                      await _generatePDF(
                                        doc.id,
                                        data,
                                        printDirectly: false,
                                      );
                                      break;

                                    case 'pay':
                                      _addPayment(doc.id, data);
                                      break;
                                    case 'challan':
                                      generateDeliveryChallanPDF(data);
                                      break;
                                    case 'delete':
                                      _deleteInvoice(doc.id);
                                      break;
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'view',
                                    child: Text("View"),
                                  ),
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text("Edit"),
                                  ),
                                  const PopupMenuItem(
                                    value: 'pdf',
                                    child: Text("Share PDF"),
                                  ),
                                  const PopupMenuItem(
                                    value: 'pay',
                                    child: Text("Add Payment"),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    enabled: status == 'Pending',
                                    child: Text(
                                      "Delete",
                                      style: TextStyle(
                                        color: status == 'Pending'
                                            ? Colors.red
                                            : Colors.grey,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),

                                  const PopupMenuItem(
                                    value: 'challan',
                                    child: Text("Delivery Challan"),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
