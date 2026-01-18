import 'dart:io';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/firestore_service.dart';
import '../utils/signature_repository.dart';
import '../utils/invoices/templateb.dart' as templateB;
import '../utils/invoices/templatec.dart' as templateC;
import '../utils/invoices/templateE.dart' as templateE;
import '../utils/pdfcopy.dart' as pdfNoGST;

class PdfService {
  static final _service = FirestoreService();

  // ---------- Corporate Colors ----------
  static const PdfColor primaryColor = PdfColor.fromInt(0xFF1F3A5F);
  static const PdfColor borderColor = PdfColor.fromInt(0xFFD4DAE3);
  static const PdfColor textColor = PdfColor.fromInt(0xFF333333);
  static const PdfColor mutedText = PdfColor.fromInt(0xFF808C8C);
  static const PdfColor headerBgColor = PdfColor.fromInt(0xFFF0F5F7);
  static const PdfColor totalBg = PdfColor.fromInt(0xFFEBF4F7);

  // ---------- Default Company Info (Fallback) ----------
  static const Map<String, dynamic> defaultCompany = {
    "name": "Smart Billing Pvt Ltd",
    "gstin": "33AAACQP0073R1ZU",
    "address": [
      "No.7, Kottai Street, Kottaikuppam, Ponneri",
      "Thiruvallur, Tamil Nadu, 601205",
      "Mobile +91 9080289690",
    ],
    "title": "TAX INVOICE",
    "poweredBy": "Powered by Smart Tech",
    "email": "support@smarttech.com",
    "state_name": "Tamil Nadu",
    "state_code": "33",
  };

  // Helper function to force rounding to 2 decimal places for currency consistency
  static double _roundToTwo(double value) {
    return double.parse(value.toStringAsFixed(2));
  }

  // ---------- Open SQLite Database ----------
  static Future<Database> _openDb() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(docsDir.path, 'smartbilling.db');
    return await openDatabase(dbPath, version: 1);
  }

  // ---------- Fetch Company Logo from SQLite ----------
  static Future<Uint8List?> getCompanyLogo() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final db = await _openDb();
      final result = await db.query(
        'company_logo',
        where: 'user_id = ?',
        whereArgs: [user.uid],
        limit: 1,
      );
      await db.close();

      if (result.isNotEmpty && result.first['logo'] != null) {
        return result.first['logo'] as Uint8List;
      }
      return null;
    } catch (e) {
      print("⚠️ Error fetching company logo: $e");
      return null;
    }
  }

  // 🔑 ---------- FETCH COMPANY DETAILS FROM FIRESTORE (Database) ----------
  static Future<Map<String, dynamic>> getCompanyDetails() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return defaultCompany;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('company')
          .doc('details')
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final stateName = data['state_name'] ?? defaultCompany['state_name'];
        final stateCode = data['state_code'] ?? defaultCompany['state_code'];

        return {
          "name": data['name'] ?? defaultCompany['name'],
          "gstin": data['gstin'] ?? '',
          // Combine address and phone into an address list for layout
          "address": [data['address'] ?? '', "Mobile: ${data['phone'] ?? ''}"],
          "title": "TAX INVOICE",
          "poweredBy": "Powered by Smart Tech",
          "email": data['email'] ?? defaultCompany['email'],
          "state_name": stateName,
          "state_code": stateCode,
        };
      } else {
        return defaultCompany;
      }
    } catch (e) {
      return defaultCompany;
    }
  }

  // ---------- Get Selected Template ----------
  static Future<String> getSelectedTemplate() async {
    try {
      // Try Firestore first
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('settings')
            .doc('invoice')
            .get()
            .timeout(const Duration(seconds: 2));
        
        if (doc.exists && doc.data()?['template'] != null) {
          return doc.data()!['template'] as String;
        }
      }
    } catch (e) {
      debugPrint("Error loading template from Firestore: $e");
    }

    // Fallback to SQLite
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(dir.path, "smartbilling.db");
      final db = await openDatabase(dbPath);
      final result = await db.query("invoice_theme", limit: 1);
      if (result.isNotEmpty) {
        return result.first["theme"] as String;
      }
    } catch (e) {
      debugPrint("Error loading template from SQLite: $e");
    }

    // Default to Template A
    return 'A';
  }

  // ---------- Get GST Preference from Firebase ----------
  static Future<bool> getGSTPreference() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return true; // Default to GST enabled

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('billing')
          .get();

      if (doc.exists && doc.data() != null) {
        return doc.data()!['enable_gst'] ?? true;
      }
      return true; // Default to GST enabled
    } catch (e) {
      debugPrint("Error loading GST preference: $e");
      return true; // Default to GST enabled on error
    }
  }

  // ---------- Generate & Share / Print ----------
  static Future<void> generateAndOpenPDF(
    String invoiceId, {
    Map<String, dynamic>? cachedData,
    bool printDirectly = false,
  }) async {
    // Check GST preference first
    final enableGST = await getGSTPreference();
    
    // Route to non-GST service if disabled
    if (!enableGST) {
      await pdfNoGST.PdfServiceNoGST.generateAndOpenPDF(
        invoiceId,
        cachedData: cachedData,
        printDirectly: printDirectly,
      );
      return;
    }



    final invoice = cachedData ?? await _service.fetchInvoice(invoiceId);
    if (invoice == null) {
      print("❌ Invoice not found for ID: $invoiceId");
      return;
    }

    // Get selected template
    final selectedTemplate = await getSelectedTemplate();

    // Route to appropriate template generator
    switch (selectedTemplate.toUpperCase()) {
      case 'B':
        await templateB.generatePDF_B(invoiceId, cachedData: cachedData, printDirectly: printDirectly);
        return;
      case 'C':
        await templateC.generatePDF_C(invoiceId, cachedData: cachedData, printDirectly: printDirectly);
        return;
      case 'E':
        await templateE.generatePDF_E(invoiceId, cachedData: cachedData, printDirectly: printDirectly);
        return;
      case 'A':
      default:
        // Use default template (Template A)
        await _generateTemplateA(invoice, printDirectly);
        return;
    }
  }

  // ---------- Generate Template A (Default) ----------
  static Future<void> _generateTemplateA(
    Map<String, dynamic> invoice,
    bool printDirectly,
  ) async {
    // 🔑 Fetching company details and GST preference
    final company = await getCompanyDetails();
    final logoBytes = await getCompanyLogo();
    final signatureBytes = await SignatureRepository.getSignature();
    final enableGST = await getGSTPreference();
    final font = await PdfGoogleFonts.nunitoRegular();
    final boldFont = await PdfGoogleFonts.nunitoBold();

    final pdf = pw.Document();
    final dateFormat = DateFormat('dd MMM yyyy');
    final items = List<Map<String, dynamic>>.from(invoice['items'] ?? []);

    final taxType = invoice['tax_type'] as String? ?? 'CGST_SGST';
    final isInterstate = taxType == 'IGST';

    // Update company title based on GST preference
    final Map<String, dynamic> displayCompany = Map.from(company);
    displayCompany['title'] = enableGST ? 'TAX INVOICE' : 'BILL';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        build: (context) => [
          _buildHeader(displayCompany, logoBytes),
          pw.SizedBox(height: 5),
          // 🔑 New combined table for all meta and party details
          _buildCombinedInfoTable(displayCompany, invoice, dateFormat),
          pw.SizedBox(height: 10),
          _buildItemsTable(items, isInterstate),
          pw.SizedBox(height: 14),
          // Row for totals (right) and HSN summary/Declaration (left)
          _buildTotalsAndDeclarationRow(invoice, isInterstate, items),
          pw.SizedBox(height: 25),
          _buildSignatory(displayCompany, signatureBytes),
          pw.SizedBox(height: 30),
          _buildFooter(displayCompany),
        ],
      ),
    );

    final pdfBytes = await pdf.save();
    final dir = await getApplicationDocumentsDirectory();
    final file = File("${dir.path}/invoice_${invoice['id']}.pdf");
    await file.writeAsBytes(pdfBytes);

    if (printDirectly) {
      await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
    } else {
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: "invoice_${invoice['id']}.pdf",
      );
    }
  }

  // ---------- HEADER (Simplified for Template UI) ----------
  static pw.Widget _buildHeader(
    Map<String, dynamic> company,
    Uint8List? logoBytes,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          company["title"] ?? "TAX INVOICE",
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
            color: primaryColor,
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: primaryColor, width: 2),
            ),
          ),
          padding: const pw.EdgeInsets.only(bottom: 5),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.start,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Left side: Company Info
              pw.Expanded(
                flex: 3,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (logoBytes != null)
                      pw.Container(
                        height: 30,
                        margin: const pw.EdgeInsets.only(bottom: 4),
                        child: pw.Image(pw.MemoryImage(logoBytes)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 🔑 ---------- COMBINED INFO TABLE (New function to match template layout) ----------
  static pw.Widget _buildCombinedInfoTable(
    Map<String, dynamic> company,
    Map<String, dynamic> invoice,
    DateFormat dateFormat,
  ) {
    // 🔑 SELLER INFO
    final sellerName = company['name'] ?? 'N/A';
    final addressData = company["address"];

    final sellerAddressLines = addressData is List
        ? addressData.join('\n') // ✅ each item on new line
        : addressData?.toString() ?? 'N/A';

    final sellerGstin = company['gstin'] ?? 'N/A';
    final sellerEmail = company['email'] ?? 'N/A';
    final sellerState = company['state_name'] ?? 'N/A';
    final sellerStateCode = company['state_code'] ?? 'N/A';

    // 🔑 BUYER INFO
    final buyerName = invoice['customer_name'] ?? 'N/A';
    final billingAddress = invoice['billing_address'] ?? 'N/A';
    final customerGstin = invoice['customer_gstin'] ?? 'N/A';
    final customerState = invoice['customer_state'] ?? 'N/A';
    final customerStateCode =
        invoice['customer_state_code'] ?? 'N/A';
    final placeOfSupply = invoice['place_of_supply'] ?? customerState;

    // 🔑 INVOICE META
    final invoiceNo = invoice['invoice_number'] ?? '-';

    final invoiceDateStr = invoice['invoice_date'] != null
        ? dateFormat.format(DateTime.parse(invoice['invoice_date']))
        : '-';
    final duedate = invoice['due_date'] != null
        ? dateFormat.format(DateTime.parse(invoice['due_date']))
        : 'N/A';
    return pw.Table(
      border: pw.TableBorder.all(color: borderColor, width: 0.4),
      columnWidths: const {
        0: pw.FlexColumnWidth(3.5), // Seller/Buyer Side
        1: pw.FlexColumnWidth(2.5), // Invoice Meta Side
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
      children: [
        // Row 1: Seller Info vs. Invoice No. and Date
        pw.TableRow(
          children: [
            // Left Cell: Seller Details
            _cellText(
              '**${sellerName}**\n'
              'Address: ${sellerAddressLines}\n'
              'GSTIN/UIN: ${sellerGstin}\n'
              'State Name: ${sellerState}, Code : ${sellerStateCode}\n'
              'E-Mail: ${sellerEmail}',
              padding: const pw.EdgeInsets.all(6),
            ),
            // Right Cell: Invoice Meta Details
            _cellWithMeta([
              _metaRow('Invoice No.', invoiceNo),
              _metaRow('Dated', invoiceDateStr),
              _metaRow('Due Date', duedate),
              _metaRow('Mode/Terms of Payment', ''),
              _metaRow('Reference No. & Date.', ''),
              _metaRow('Other References', ''),
            ]),
          ],
        ),

        // Row 2: Buyer Info vs. Buyer's Order Info
        pw.TableRow(
          children: [
            // Left Cell: Buyer Details
            _cellText(
              '**Bill To:**\n'
              '**${buyerName}**\n'
              'Address: ${billingAddress}\n'
              'GSTIN/UIN: ${customerGstin}\n'
              'State Name: ${customerState}, Code : ${customerStateCode}\n'
              'Place of Supply: ${placeOfSupply}',
              padding: const pw.EdgeInsets.all(6),
            ),

            // Right Cell: Dispatch/Delivery Details
            _cellWithMeta([
              _metaRow('Buyer\'s Order No.', ''),
              _metaRow('Dated', ''),
              _metaRow('Dispatch Doc No.', ''),
              _metaRow('Delivery Note Date', ''),
              _metaRow('Dispatched through', ''),
              _metaRow('Destination', ''),
              _metaRow('Terms of Delivery', ''),
            ]),
          ],
        ),
      ],
    );
  }

  // Helper for the Invoice Meta rows
  static pw.Widget _metaRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.RichText(
        text: pw.TextSpan(
          style: const pw.TextStyle(fontSize: 8, color: textColor),
          children: [
            pw.TextSpan(
              text: '$label: ',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  // Helper for the combined cell text with RichText for bolding
  static pw.Widget _cellText(
    String text, {
    pw.EdgeInsets padding = const pw.EdgeInsets.all(4),
  }) {
    return pw.Container(
      padding: padding,
      child: pw.RichText(
        text: pw.TextSpan(
          children: text.split('\n').map((line) {
            if (line.startsWith('**') && line.endsWith('**')) {
              return pw.TextSpan(
                text: '${line.replaceAll('**', '')}\n',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 9,
                ),
              );
            }
            return pw.TextSpan(
              text: '$line\n',
              style: const pw.TextStyle(fontSize: 9),
            );
          }).toList(),
        ),
      ),
    );
  }

  // Helper to wrap meta rows in a cell
  static pw.Widget _cellWithMeta(List<pw.Widget> children) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  // ---------- ITEMS TABLE (Updated for HSN and GST Breakdown) ----------
  static pw.Widget _buildItemsTable(
    List<Map<String, dynamic>> items,
    bool isInterstate,
  ) {
    final Map<int, pw.TableColumnWidth> columnWidths = {
      0: const pw.FlexColumnWidth(0.5),
      1: const pw.FlexColumnWidth(3.0),
      2: const pw.FlexColumnWidth(1.0),
      3: const pw.FlexColumnWidth(1.0),
      4: const pw.FlexColumnWidth(1.2),
      5: const pw.FlexColumnWidth(0.7),
      6: const pw.FlexColumnWidth(1.8),
    };

    double totalQty = 0.0;
    double totalTaxable = 0.0;

    final List<pw.TableRow> rows = [];

    // ---------- HEADER ----------
    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: headerBgColor),
        children: [
          _headerCell("#", pw.Alignment.center),
          _headerCell("Description of Goods", pw.Alignment.centerLeft),
          _headerCell("HSN/SAC", pw.Alignment.center),
          _headerCell("Quantity", pw.Alignment.center),
          _headerCell("Rate (₹)", pw.Alignment.center),
          _headerCell("UOM", pw.Alignment.center),
          _headerCell("Amount (₹)", pw.Alignment.centerRight),
        ],
      ),
    );

    // ---------- ITEM ROWS ----------
    for (var i = 0; i < items.length; i++) {
      final item = items[i];

      final qty = (item['qty'] as num?)?.toDouble() ?? 0.0;
      final rate = (item['rate'] as num?)?.toDouble() ?? 0.0;
      final hsnCode = item['hsn_code'] ?? 'N/A';
      final taxableAmount = (item['taxable_amount'] as num?)?.toDouble() ?? 0.0;
      final unit = item['unit'] ?? 'Nos';

      totalQty += qty;
      totalTaxable += taxableAmount;

      rows.add(
        pw.TableRow(
          children: [
            _cell("${i + 1}", pw.Alignment.center),
            _cell(
              item['item_name']?.toString() ?? 'N/A',
              pw.Alignment.centerLeft,
            ),
            _cell(hsnCode, pw.Alignment.center),
            _cell(qty.toStringAsFixed(2), pw.Alignment.center),
            _cell(rate.toStringAsFixed(2), pw.Alignment.center),
            _cell(unit, pw.Alignment.center),
            _cell(
              _roundToTwo(taxableAmount).toStringAsFixed(2),
              pw.Alignment.centerRight,
            ),
          ],
        ),
      );
    }

    // ---------- TOTAL ROW (no background, description right) ----------
    if (items.isNotEmpty) {
      rows.add(
        pw.TableRow(
          children: [
            _cell("", pw.Alignment.center),
            _cell(
              "Total",
              pw.Alignment.centerRight,
              bold: true,
            ),
            _cell("", pw.Alignment.center),
            _cell(totalQty.toStringAsFixed(2), pw.Alignment.center),
            _cell("", pw.Alignment.center),
            _cell("", pw.Alignment.center),
            _cell(
              _roundToTwo(totalTaxable).toStringAsFixed(2),
              pw.Alignment.centerRight,
              bold: true,
            ),
          ],
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: borderColor, width: 0.3),
      columnWidths: columnWidths,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: rows,
    );
  }

  // ---------- HEADER CELL ----------
  static pw.Widget _headerCell(String text, pw.Alignment align) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      alignment: align,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: primaryColor,
        ),
      ),
    );
  }

  // ---------- NORMAL CELL ----------
  static pw.Widget _cell(String text, pw.Alignment align, {bool bold = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      alignment: align,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  // 🔑 ---------- TOTALS AND DECLARATION ROW (New function for complex layout) ----------
  static pw.Widget _buildTotalsAndDeclarationRow(
    Map<String, dynamic> invoice,
    bool isInterstate,
    List<Map<String, dynamic>> items,
  ) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 1,
          child: _buildTaxSummaryAndDeclaration(invoice, isInterstate, items),
        ),
        pw.SizedBox(width: 15),
        pw.Expanded(
          flex: 1,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              _buildTotals(invoice, isInterstate),
              pw.SizedBox(height: 10),
              _buildAmountInWords(invoice),
            ],
          ),
        ),
      ],
    );
  }

  // 🔑 ---------- HSN SUMMARY AND DECLARATION (New function to match template) ----------
  static pw.Widget _buildTaxSummaryAndDeclaration(
    Map<String, dynamic> invoice,
    bool isInterstate,
    List<Map<String, dynamic>> items,
  ) {
    // Group items by HSN for the summary table
    final hsnGroups = <String, Map<String, dynamic>>{};
    double totalTaxable = 0.0;
    double totalCGST = 0.0;
    double totalSGST = 0.0;
    double totalIGST = 0.0;

    for (final item in items) {
      final hsn = item['hsn_code'] ?? 'N/A';
      final gstPerc = (item['gst_percent'] as num?)?.toDouble() ?? 0.0;
      final halfGstPerc = gstPerc / 2;
      final taxableAmt = (item['taxable_amount'] as num?)?.toDouble() ?? 0.0;
      final cgstAmt = (item['cgst'] as num?)?.toDouble() ?? 0.0;
      final sgstAmt = (item['sgst'] as num?)?.toDouble() ?? 0.0;
      final igstAmt = (item['igst'] as num?)?.toDouble() ?? 0.0;

      totalTaxable += taxableAmt;
      totalCGST += cgstAmt;
      totalSGST += sgstAmt;
      totalIGST += igstAmt;

      if (!hsnGroups.containsKey(hsn)) {
        hsnGroups[hsn] = {
          'taxable': 0.0,
          'cgst_rate': halfGstPerc,
          'sgst_rate': halfGstPerc,
          'igst_rate': gstPerc,
          'cgst_amt': 0.0,
          'sgst_amt': 0.0,
          'igst_amt': 0.0,
        };
      }
      hsnGroups[hsn]!['taxable'] += taxableAmt;
      hsnGroups[hsn]!['cgst_amt'] += cgstAmt;
      hsnGroups[hsn]!['sgst_amt'] += sgstAmt;
      hsnGroups[hsn]!['igst_amt'] += igstAmt;
    }

    // Build the HSN Summary Table
    final List<String> hsnHeaders = [
      "HSN",
      "Taxable Value",
      isInterstate ? "IGST %" : "CGST %",
      isInterstate ? "IGST  ₹" : "CGST  ₹",
      if (!isInterstate) "SGST %",
      if (!isInterstate) "SGST  ₹",
      "Total Tax Amount",
    ];

    final Map<int, pw.TableColumnWidth> hsnColumnWidths = isInterstate
        ? {
            0: const pw.FlexColumnWidth(1.8),
            1: const pw.FlexColumnWidth(1.5),
            2: const pw.FlexColumnWidth(1.0),
            3: const pw.FlexColumnWidth(1.5),
            4: const pw.FlexColumnWidth(1.8),
          }
        : {
            0: const pw.FlexColumnWidth(1.8),
            1: const pw.FlexColumnWidth(1.5),
            2: const pw.FlexColumnWidth(1.0),
            3: const pw.FlexColumnWidth(1.2),
            4: const pw.FlexColumnWidth(1.0),
            5: const pw.FlexColumnWidth(1.2),
            6: const pw.FlexColumnWidth(1.8),
          };

    final hsnTableData = hsnGroups.entries.map((entry) {
      final hsn = entry.key;
      final group = entry.value;
      final taxable = _roundToTwo(group['taxable']);
      final totalTax = _roundToTwo(
        group['igst_amt'] + group['cgst_amt'] + group['sgst_amt'],
      );

      final List<String> row = [
        hsn,
        taxable.toStringAsFixed(1),
        isInterstate
            ? "${group['igst_rate'].toStringAsFixed(1)}%"
            : "${group['cgst_rate'].toStringAsFixed(1)}%",
        isInterstate
            ? _roundToTwo(group['igst_amt']).toStringAsFixed(1)
            : _roundToTwo(group['cgst_amt']).toStringAsFixed(1),
        if (!isInterstate) "${group['sgst_rate'].toStringAsFixed(1)}%",
        if (!isInterstate) _roundToTwo(group['sgst_amt']).toStringAsFixed(1),
        totalTax.toStringAsFixed(1),
      ];
      return row;
    }).toList();

    // Add Total row for HSN summary
    final totalTaxAmount = _roundToTwo(totalCGST + totalSGST + totalIGST);

    final List<String> totalRow = [
      "Total",
      _roundToTwo(totalTaxable).toStringAsFixed(1),
      "",
      _roundToTwo(totalCGST + totalIGST).toStringAsFixed(1),
      if (!isInterstate) "",
      if (!isInterstate) _roundToTwo(totalSGST).toStringAsFixed(1),
      totalTaxAmount.toStringAsFixed(1),
    ];
    hsnTableData.add(totalRow);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // HSN Summary Table
        pw.Table.fromTextArray(
          border: pw.TableBorder.all(color: borderColor, width: 0.3),
          columnWidths: hsnColumnWidths,
          headerDecoration: const pw.BoxDecoration(color: headerBgColor),
          headerStyle: pw.TextStyle(
            color: primaryColor,
            fontWeight: pw.FontWeight.bold,
            fontSize: 5.0,
          ),
          cellStyle: const pw.TextStyle(fontSize: 7.5),
          headerAlignments: {
            0: pw.Alignment.center,
            1: pw.Alignment.center,
            2: pw.Alignment.center,
            3: pw.Alignment.center,
            4: pw.Alignment.center,
            5: pw.Alignment.center,
            6: pw.Alignment.center,
          },
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerRight,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
            5: pw.Alignment.centerRight,
            6: pw.Alignment.centerRight,
          },
          headers: hsnHeaders,
          data: hsnTableData,
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          "Tax Amount (in words) : ${_convertNumberToWords(totalTaxAmount)}",
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),

        // Declaration
        pw.SizedBox(height: 10),

        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              "Declaration:",
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: primaryColor,
              ),
            ),
            pw.SizedBox(height: 3),

            pw.Text(
              "1. Goods once sold will not be taken back or exchanged.",
              style: const pw.TextStyle(fontSize: 8, color: mutedText),
            ),
            pw.Text(
              "2. Seller is not responsible for any loss or damage of goods in transit.",
              style: const pw.TextStyle(fontSize: 8, color: mutedText),
            ),
            pw.Text(
              "3. Dispute if any will be subject to seller's court jurisdiction.",
              style: const pw.TextStyle(fontSize: 8, color: mutedText),
            ),
            pw.Text(
              "4. We declare that this invoice shows the goods described and all particulars are true and correct.",
              style: const pw.TextStyle(fontSize: 8, color: mutedText),
            ),
          ],
        ),
      ],
    );
  }

  // ---------- TOTALS (Original logic kept) ----------
  static pw.Widget _buildTotals(
    Map<String, dynamic> invoice,
    bool isInterstate,
  ) {
    // 🔑 READ PRE-CALCULATED, ROUNDED TOTALS DIRECTLY
    final subtotalTaxable = _roundToTwo(
      (invoice['subtotal'] as num?)?.toDouble() ?? 0.0,
    );
    final totalCGST = _roundToTwo(
      (invoice['cgst_total'] as num?)?.toDouble() ?? 0.0,
    );
    final totalSGST = _roundToTwo(
      (invoice['sgst_total'] as num?)?.toDouble() ?? 0.0,
    );
    final totalIGST = _roundToTwo(
      (invoice['igst_total'] as num?)?.toDouble() ?? 0.0,
    );
    final grandTotal = _roundToTwo(
      (invoice['grand_total'] as num?)?.toDouble() ?? 0.0,
    );
    final roundOff = _roundToTwo(
      (invoice['round_off'] as num?)?.toDouble() ?? 0.0,
    );

    final PdfColor borderGrey = PdfColor(0.7, 0.7, 0.7);

    return pw.Container(
      width: 260,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: borderGrey, width: 1),
      ),
      child: pw.Table(
        border: pw.TableBorder.all(color: borderGrey, width: 0.8),
        columnWidths: const {
          0: pw.FlexColumnWidth(2.5),
          1: pw.FlexColumnWidth(1.5),
        },
        children: [
          _buildTotalRow("Sub Total (Taxable Value)", subtotalTaxable),
          if (!isInterstate) _buildTotalRow("Add: Output CGST", totalCGST),
          if (!isInterstate) _buildTotalRow("Add: Output SGST", totalSGST),
          if (isInterstate) _buildTotalRow("Add: Output IGST", totalIGST),
          if (roundOff != 0.0) _buildTotalRow("Round off (+/-)", roundOff),
          // Final Grand Total Row
          _buildTotalRow(
            "Total Amount (Rounded)",
            grandTotal,
            isGrandTotal: true,
          ),
        ],
      ),
    );
  }

  // Helper for total rows
  static pw.TableRow _buildTotalRow(
    String label,
    double amount, {
    bool isGrandTotal = false,
  }) {
    return pw.TableRow(
      decoration: isGrandTotal
          ? const pw.BoxDecoration(color: totalBg)
          : const pw.BoxDecoration(),
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: isGrandTotal
                  ? pw.FontWeight.bold
                  : pw.FontWeight.normal,
              color: isGrandTotal ? primaryColor : textColor,
            ),
          ),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            "₹ ${amount.toStringAsFixed(2)}",
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: isGrandTotal
                  ? pw.FontWeight.bold
                  : pw.FontWeight.normal,
              color: isGrandTotal ? primaryColor : textColor,
            ),
          ),
        ),
      ],
    );
  }

  // ---------- AMOUNT IN WORDS ----------
  static pw.Widget _buildAmountInWords(Map<String, dynamic> invoice) {
    final grandTotal = _roundToTwo(
      (invoice['grand_total'] as num?)?.toDouble() ?? 0.0,
    );
    final words = _convertNumberToWords(grandTotal);

    return pw.Container(
      width: 260,
      alignment: pw.Alignment.centerLeft,
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: borderColor, width: 0.3),
        color: headerBgColor,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            "Amount Chargeable (in words)",
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: primaryColor,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            "INR $words ",
            style: const pw.TextStyle(fontSize: 9, color: textColor),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            "E. & O.E",
            style: const pw.TextStyle(fontSize: 8, color: mutedText),
          ),
        ],
      ),
    );
  }

  // ---------- SIGNATORY & FOOTER ----------
  static pw.Widget _buildSignatory(
    Map<String, dynamic> company,
    Uint8List? signatureBytes,
  ) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          // Company Name
          pw.Text(
            company['name'] ?? '',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: primaryColor,
            ),
          ),

          pw.SizedBox(height: 10),

          // Signature Image
          if (signatureBytes != null)
            pw.Container(
              height: 40,
              child: pw.Image(pw.MemoryImage(signatureBytes)),
            )
          else
            pw.SizedBox(height: 40),

          // Signature line
          pw.SizedBox(height: 4),

          // Label
          pw.Text(
            "Authorised Signature",
            style: const pw.TextStyle(fontSize: 8, color: mutedText),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(Map<String, dynamic> company) {
    return pw.Container(
      alignment: pw.Alignment.center,
      child: pw.Text(
        company["poweredBy"] ?? "Powered by Smart Tech",
        style: const pw.TextStyle(fontSize: 7, color: mutedText),
      ),
    );
  }

  // ---------- NUMBER TO WORDS CONVERSION (Indian System) ----------
  static String _convertNumberToWords(double n) {
    if (n == 0) return "Zero";

    int number = n.toInt();
    int decimal = ((n - number) * 100).round();

    final units = [
      "",
      "One",
      "Two",
      "Three",
      "Four",
      "Five",
      "Six",
      "Seven",
      "Eight",
      "Nine",
      "Ten",
      "Eleven",
      "Twelve",
      "Thirteen",
      "Fourteen",
      "Fifteen",
      "Sixteen",
      "Seventeen",
      "Eighteen",
      "Nineteen",
    ];

    final tens = [
      "",
      "",
      "Twenty",
      "Thirty",
      "Forty",
      "Fifty",
      "Sixty",
      "Seventy",
      "Eighty",
      "Ninety",
    ];

    String twoDigits(int n) {
      if (n < 20) return units[n];
      return "${tens[n ~/ 10]} ${units[n % 10]}".trim();
    }

    String threeDigits(int n) {
      if (n == 0) return "";
      if (n < 100) return twoDigits(n);
      return "${units[n ~/ 100]} Hundred ${twoDigits(n % 100)}".trim();
    }

    String convertIntToWords(int number) {
      if (number == 0) return "";
      String words = "";
      int crore = number ~/ 10000000;
      number %= 10000000;
      int lakh = number ~/ 100000;
      number %= 100000;
      int thousand = number ~/ 1000;
      number %= 1000;
      int hundred = number;

      if (crore > 0) {
        words += "${twoDigits(crore)} Crore ";
      }
      if (lakh > 0) {
        words += "${twoDigits(lakh)} Lakh ";
      }
      if (thousand > 0) {
        words += "${twoDigits(thousand)} Thousand ";
      }
      if (hundred > 0) {
        words += threeDigits(hundred);
      }
      return words.trim();
    }

    String finalWords = convertIntToWords(number);

    if (decimal > 0) {
      final decimalWords = twoDigits(decimal);
      if (finalWords.isNotEmpty) {
        finalWords += " and $decimalWords Paise";
      } else {
        finalWords = "$decimalWords Paise";
      }
    } else if (finalWords.isNotEmpty) {
      finalWords += " Only";
    }

    return finalWords;
  }
}
