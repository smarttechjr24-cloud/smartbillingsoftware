import 'dart:io';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'quotationcopy.dart' as quotationNoGST;
// Needed for logo bytes (if implemented)

class QuotationPdfService {
  // ---------- Corporate Colors (CHANGED TO BLACK & WHITE THEME) ----------
  static const PdfColor primaryColor = PdfColor.fromInt(0xFF1F3A5F);
  static const PdfColor borderColor = PdfColor.fromInt(0xFFD4DAE3);
  static const PdfColor textColor = PdfColor.fromInt(0xFF333333);
  static const PdfColor mutedText = PdfColor.fromInt(0xFF808C8C);
  static const PdfColor headerBgColor = PdfColor.fromInt(0xFFF0F5F7);
  static const PdfColor totalBg = PdfColor.fromInt(0xFFEBF4F7);
  static const PdfColor black = PdfColor(0, 0, 0);

  // 🔑 KEY CHANGES FOR B&W THEME:
  static const PdfColor bwPrimary = PdfColor(
    0.1,
    0.1,
    0.1,
  ); // Very dark grey/near black for headers
  static const PdfColor bwBorder = PdfColor(
    0.6,
    0.6,
    0.6,
  ); // Medium grey for borders
  static const PdfColor bwTextColor = PdfColor(0.2, 0.2, 0.2); // Dark text
  static const PdfColor bwMutedText = PdfColor(
    0.4,
    0.4,
    0.4,
  ); // Lighter grey text
  static const PdfColor bwHeaderBg = PdfColor(
    0.95,
    0.95,
    0.95,
  ); // Very light grey background
  static const PdfColor bwTotalBg = PdfColor(
    0.90,
    0.90,
    0.90,
  ); // Light grey total row background

  // ---------- Default Company Info (Updated with State Info) ----------
  static const Map<String, dynamic> defaultCompany = {
    "name": "Smart Tech Junior",
    "gstin": "33AAACQP0073R1ZU",
    "address": "Company Address, City, Pincode",
    "email": "company@email.com",
    "phone": "9999999999",
    "title": "QUOTATION", // Quotation-specific title
    "poweredBy": "Powered by Smart Tech",
    "state_name": "Tamil Nadu",
    "state_code": "33",
  };

  // Helper function to force rounding to 2 decimal places for currency consistency
  static double _roundToTwo(double value) {
    return double.parse(value.toStringAsFixed(2));
  }

  // ---------- FETCH COMPANY DETAILS FROM FIRESTORE (Database) ----------
  static Future<Map<String, dynamic>> _getCompanyDetails() async {
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
          ...defaultCompany, // Start with defaults
          "name": data['name'] ?? defaultCompany['name'],
          "gstin": data['gstin'] ?? '',
          "address": data['address'] ?? defaultCompany['address'],
          "phone": data['phone'] ?? defaultCompany['phone'],
          "email": data['email'] ?? defaultCompany['email'],
          "state_name": stateName,
          "state_code": stateCode,
        };
      } else {
        return defaultCompany;
      }
    } catch (e) {
      print("⚠️ Error fetching company details: $e");
      return defaultCompany;
    }
  }

  // ---------- GET GST PREFERENCE FROM FIREBASE ----------
  static Future<bool> _getGSTPreference() async {
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
        return doc.data()?['enable_gst'] ?? true;
      }
      return true; // Default to GST enabled
    } catch (e) {
      print("⚠️ Error fetching GST preference: $e");
      return true; // Default to GST enabled on error
    }
  }


  static Future<File?> generateQuotationPDF(
    String quotationId, {
    Map<String, dynamic>? cachedData,
    bool printDirectly = false,
  }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return null;

      // Check GST preference first
      final enableGST = await _getGSTPreference();
      
      // Route to non-GST service if disabled
      if (!enableGST) {
        return await quotationNoGST.QuotationPdfServiceNoGST.generateQuotationPDF(
          quotationId,
          cachedData: cachedData,
          printDirectly: printDirectly,
        );
      }

      final quotation =
          cachedData ??
          (await FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('quotations')
                  .doc(quotationId)
                  .get())
              .data();

      if (quotation == null) return null;
      final company = await _getCompanyDetails();

      final defaultQuotation = {
        'id': quotationId,
        'quotation_date': DateTime.now().toIso8601String(),
        'valid_till_date': DateTime.now()
            .add(const Duration(days: 7))
            .toIso8601String(),
        'customer_name': 'Customer Name',
        'mobile': '8888888888',
        'billing_address': 'Billing Address',
        'shipping_address': 'Shipping Address (if different)',
        'items': [],
        'customer_gstin': '',
        'customer_state': '',
        'customer_state_code': '', // Assuming state code is available
        'place_of_supply': '',
        'tax_type': 'CGST_SGST', // Added for logic compatibility
        'subtotal_before_discount': 0.0,
        'total_discount': 0.0,
        'total_taxable': 0.0,
        'cgst_total': 0.0,
        'sgst_total': 0.0,
        'igst_total': 0.0,
        'grand_total': 0.0,
        'note': 'All payments are due within 7 days of quotation.',
      };

      final mergedQuotation = {...defaultQuotation, ...quotation};

      final baseFont = await PdfGoogleFonts.notoSansRegular();
      final boldFont = await PdfGoogleFonts.notoSansBold();

      final pdf = pw.Document();
      final dateFormat = DateFormat('dd MMM yyyy');
      final items = List<Map<String, dynamic>>.from(
        mergedQuotation['items'] ?? [],
      );

      // Determine tax type
      final taxType = mergedQuotation['tax_type'] as String? ?? 'CGST_SGST';
      final isInterstate = taxType == 'IGST';

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
          build: (context) => [
            _buildHeader(company), // Simplified Header
            pw.SizedBox(height: 5),
            // Combines Invoice Meta and Customer Details in one table
            _buildCombinedInfoTable(company, mergedQuotation, dateFormat),
            pw.SizedBox(height: 10),
            _buildItemsTable(items, isInterstate),
            pw.SizedBox(height: 14),
            // Combines HSN Summary, Totals, and Declaration
            _buildTotalsAndDeclarationRow(mergedQuotation, isInterstate, items),
            pw.SizedBox(height: 25),
            // Use new signatory function
            pw.SizedBox(height: 40),
            _buildFooter(company),
          ],
        ),
      );

      final bytes = await pdf.save();
      final dir = await getApplicationDocumentsDirectory();
      final file = File("${dir.path}/quotation_$quotationId.pdf");
      await file.writeAsBytes(bytes);

      if (printDirectly) {
        await Printing.layoutPdf(onLayout: (_) async => bytes);
      } else {
        // Share PDF by default
        await Printing.sharePdf(
          bytes: bytes,
          filename: "quotation_$quotationId.pdf",
        );
      }

      return file;
    } catch (e) {
      return null;
    }
  }

  // ---------- 1. HEADER (Simple Title) ----------
  static pw.Widget _buildHeader(Map<String, dynamic> company) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          company["title"] ?? "QUOTATION",
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
            color: bwPrimary, // 🔑 B&W Color
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: bwPrimary, width: 2), // 🔑 B&W Color
            ),
          ),
          padding: const pw.EdgeInsets.only(bottom: 5),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.start,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 3,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------- 2. COMBINED INFO TABLE (Matches Invoice Template UI) ----------
  static pw.Widget _buildCombinedInfoTable(
    Map<String, dynamic> company,
    Map<String, dynamic> quotation,
    DateFormat dateFormat,
  ) {
    // SELLER INFO
    final sellerName = company['name'] ?? 'N/A';
    // Combine address and phone into an address list for layout
    final sellerAddressLines =
        "${company["address"]}\nMobile: ${company["phone"]}";
    final sellerGstin = company['gstin'] ?? 'N/A';
    final sellerEmail = company['email'] ?? 'N/A';
    final sellerState = company['state_name'] ?? 'N/A';
    final sellerStateCode = company['state_code'] ?? 'N/A';

    // BUYER INFO
    final buyerName = quotation['customer_name'] ?? 'N/A';
    final billingAddress = quotation['billing_address'] ?? 'N/A';
    final customerGstin = quotation['customer_gstin'] ?? 'N/A';
    final customerState = quotation['customer_state'] ?? 'N/A';
    final customerStateCode = quotation['customer_state_code'] ?? 'N/A';
    final placeOfSupply = quotation['customer_state'] ?? customerState;

    // QUOTATION META
    final quotationNo = quotation['id'] ?? '-';
    final quotationDateStr = quotation['quotation_date'] != null
        ? dateFormat.format(DateTime.parse(quotation['quotation_date']))
        : '-';
    final validTillDateStr = quotation['valid_till_date'] != null
        ? dateFormat.format(DateTime.parse(quotation['valid_till_date']))
        : '-';

    return pw.Table(
      border: pw.TableBorder.all(color: bwBorder, width: 0.4), // 🔑 B&W Color
      columnWidths: const {
        0: pw.FlexColumnWidth(3.5), // Seller/Buyer Side
        1: pw.FlexColumnWidth(2.5), // Quotation Meta Side
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
      children: [
        // Row 1: Seller Info vs. Quotation No. and Date
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
            // Right Cell: Quotation Meta Details (Adapted from Invoice Meta)
            _cellWithMeta([
              _metaRow('Quotation No.', quotationNo),
              _metaRow('Dated', quotationDateStr),
              _metaRow('Valid Till', validTillDateStr),
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
              '**$buyerName**\n'
              'Address: $billingAddress\n'
              'GSTIN/UIN: $customerGstin\n'
              'State Name: $customerState, Code : $customerStateCode\n'
              'Place of Supply: $placeOfSupply',
              padding: const pw.EdgeInsets.all(6),
            ),

            // Right Cell: Dispatch/Delivery Details (Quotation - mostly placeholders)
            _cellWithMeta([
              _metaRow('Buyer\'s Order No.', ''),
              _metaRow('Dated', ''),
              _metaRow(
                'Shipping Address',
                quotation['shipping_address'] ?? 'Same as Billing',
              ),
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
          style: const pw.TextStyle(
            fontSize: 8,
            color: bwTextColor,
          ), // 🔑 B&W Color
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
                  color: bwTextColor,
                ), // 🔑 B&W Color
              );
            }
            return pw.TextSpan(
              text: '$line\n',
              style: const pw.TextStyle(
                fontSize: 9,
                color: bwTextColor,
              ), // 🔑 B&W Color
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

  // ---------- 3. ITEMS TABLE (Matches Invoice Template UI - simple rows with total inside) ----------
  static pw.Widget _buildItemsTable(
    List<Map<String, dynamic>> items,
    bool isInterstate,
  ) {
    // Alignment for each column
    const alignmentMap = {
      0: pw.Alignment.center, // Sl No
      1: pw.Alignment.centerLeft, // Description
      2: pw.Alignment.center, // HSN/SAC
      3: pw.Alignment.center, // Qty
      4: pw.Alignment.center, // Rate
      5: pw.Alignment.center, // per
      6: pw.Alignment.centerRight, // Amount
    };

    final List<String> headers = [
      "Sl\nNo.",
      "Description of Goods",
      "HSN/SAC",
      "Quantity",
      "Rate (₹)",
      "per",
      "Amount (₹)",
    ];

    final Map<int, pw.TableColumnWidth> columnWidths = {
      0: const pw.FlexColumnWidth(0.5),
      1: const pw.FlexColumnWidth(3.0),
      2: const pw.FlexColumnWidth(1.0),
      3: const pw.FlexColumnWidth(1.0),
      4: const pw.FlexColumnWidth(1.2),
      5: const pw.FlexColumnWidth(0.7),
      6: const pw.FlexColumnWidth(1.8),
    };

    // --- Build Item Data Rows ---
    final itemData = <List<String>>[];

    double totalQty = 0.0;
    double totalTaxable = 0.0;

    for (var i = 0; i < items.length; i++) {
      final item = items[i];

      final qty = (item['qty'] as num?)?.toDouble() ?? 0.0;
      final rate = (item['rate'] as num?)?.toDouble() ?? 0.0;
      final hsnCode = item['hsn_code'] ?? 'N/A';
      final taxableAmount = (item['taxable_amount'] as num?)?.toDouble() ?? 0.0;
      final unit = item['unit'] ?? 'Nos';

      totalQty += qty;
      totalTaxable += taxableAmount;

      itemData.add([
        "${i + 1}",
        item['item']?.toString() ?? 'N/A', // quotation item name
        hsnCode,
        qty.toStringAsFixed(2),
        rate.toStringAsFixed(2),
        unit,
        _roundToTwo(taxableAmount).toStringAsFixed(2),
      ]);
    }

    // --- Add Total Row (with "Total" visually to the right in description col) ---
    itemData.add([
      '', // Sl No
      '                               Total', // pad spaces so it appears on right
      '', // HSN
      totalQty.toStringAsFixed(2), // Qty total
      '', // Rate
      '', // per
      _roundToTwo(totalTaxable).toStringAsFixed(2), // Amount total
    ]);

    return pw.Table.fromTextArray(
      border: pw.TableBorder.all(color: bwBorder, width: 0.3),
      columnWidths: columnWidths,
      headerDecoration: pw.BoxDecoration(color: bwHeaderBg),
      headerStyle: pw.TextStyle(
        color: bwPrimary,
        fontWeight: pw.FontWeight.bold,
        fontSize: 8,
      ),
      cellStyle: const pw.TextStyle(fontSize: 8, color: bwTextColor),
      headerAlignments: alignmentMap,
      cellAlignments: alignmentMap, // static map only – no functions
      headers: headers,
      data: itemData,
    );
  }

  // ---------- 4. TOTALS AND DECLARATION ROW (Matches Invoice Template UI) ----------
  static pw.Widget _buildTotalsAndDeclarationRow(
    Map<String, dynamic> quotation,
    bool isInterstate,
    List<Map<String, dynamic>> items,
  ) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 1,
          child: _buildTaxSummaryAndDeclaration(quotation, isInterstate, items),
        ),
        pw.SizedBox(width: 15),
        pw.Expanded(
          flex: 1,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              _buildTotals(quotation, isInterstate),
              pw.SizedBox(height: 10),
              // Use the Invoice-style Amount in Words box
              _buildAmountInWordsBox(quotation),
            ],
          ),
        ),
      ],
    );
  }

  // ---------- HSN SUMMARY AND DECLARATION (Matches Invoice Template UI) ----------
  static pw.Widget _buildTaxSummaryAndDeclaration(
    Map<String, dynamic> quotation,
    bool isInterstate,
    List<Map<String, dynamic>> items,
  ) {
    final hsnGroups = <String, Map<String, dynamic>>{};
    double totalTaxable = 0.0;
    double totalCGST = 0.0;
    double totalSGST = 0.0;
    double totalIGST = 0.0;

    for (final item in items) {
      final hsn = item['hsn_code'] ?? 'N/A';
      final cgstPerc = (item['cgst_percent'] as num?)?.toDouble() ?? 0.0;
      final igstPerc = (item['igst_percent'] as num?)?.toDouble() ?? 0.0;

      final taxableAmt = (item['taxable_amount'] as num?)?.toDouble() ?? 0.0;
      final cgstAmt = (item['cgst_amount'] as num?)?.toDouble() ?? 0.0;
      final sgstAmt = (item['sgst_amount'] as num?)?.toDouble() ?? 0.0;
      final igstAmt = (item['igst_amount'] as num?)?.toDouble() ?? 0.0;

      totalTaxable += taxableAmt;
      totalCGST += cgstAmt;
      totalSGST += sgstAmt;
      totalIGST += igstAmt;

      if (!hsnGroups.containsKey(hsn)) {
        hsnGroups[hsn] = {
          'taxable': 0.0,
          'cgst_rate': cgstPerc,
          'sgst_rate': cgstPerc,
          'igst_rate': igstPerc,
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

    final List<String> hsnHeaders = [
      "HSN/SAC",
      "Taxable Value",
      isInterstate ? "IGST %" : "CGST %",
      isInterstate ? "IGST ₹" : "CGST ₹",
      if (!isInterstate) "SGST %",
      if (!isInterstate) "SGST ₹",
      "Total Tax",
    ];

    final Map<int, pw.TableColumnWidth> hsnColumnWidths = isInterstate
        ? {
            0: const pw.FlexColumnWidth(1.6), // ✅ wider HSN
            1: const pw.FlexColumnWidth(1.6),
            2: const pw.FlexColumnWidth(1.1),
            3: const pw.FlexColumnWidth(1.5),
            4: const pw.FlexColumnWidth(1.8),
          }
        : {
            0: const pw.FlexColumnWidth(1.6), // ✅ wider HSN
            1: const pw.FlexColumnWidth(1.6),
            2: const pw.FlexColumnWidth(1.1),
            3: const pw.FlexColumnWidth(1.4),
            4: const pw.FlexColumnWidth(1.1),
            5: const pw.FlexColumnWidth(1.4),
            6: const pw.FlexColumnWidth(1.8),
          };

    final hsnTableData = hsnGroups.entries.map((entry) {
      final group = entry.value;
      final taxable = _roundToTwo(group['taxable']);
      final totalTax = _roundToTwo(
        group['igst_amt'] + group['cgst_amt'] + group['sgst_amt'],
      );

      return [
        entry.key,
        taxable.toStringAsFixed(2),
        isInterstate
            ? "${group['igst_rate'].toStringAsFixed(1)}%"
            : "${group['cgst_rate'].toStringAsFixed(1)}%",
        isInterstate
            ? _roundToTwo(group['igst_amt']).toStringAsFixed(2)
            : _roundToTwo(group['cgst_amt']).toStringAsFixed(2),
        if (!isInterstate) "${group['sgst_rate'].toStringAsFixed(1)}%",
        if (!isInterstate) _roundToTwo(group['sgst_amt']).toStringAsFixed(2),
        totalTax.toStringAsFixed(2),
      ];
    }).toList();

    final totalTaxAmount = _roundToTwo(totalCGST + totalSGST + totalIGST);

    hsnTableData.add([
      "Total",
      _roundToTwo(totalTaxable).toStringAsFixed(2),
      "",
      _roundToTwo(totalCGST + totalIGST).toStringAsFixed(2),
      if (!isInterstate) "",
      if (!isInterstate) _roundToTwo(totalSGST).toStringAsFixed(2),
      totalTaxAmount.toStringAsFixed(2),
    ]);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Table.fromTextArray(
          border: pw.TableBorder.all(color: bwBorder, width: 0.3),
          columnWidths: hsnColumnWidths,
          headerDecoration: pw.BoxDecoration(color: bwHeaderBg),
          headerStyle: pw.TextStyle(
            color: bwPrimary,
            fontWeight: pw.FontWeight.bold,
            fontSize: 6.0, // ✅ reduced header size
          ),
          cellStyle: const pw.TextStyle(fontSize: 7.5, color: bwTextColor),
          headers: hsnHeaders,
          data: hsnTableData,
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerRight,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
            5: pw.Alignment.centerRight,
            6: pw.Alignment.centerRight,
          },
        ),

        pw.SizedBox(height: 6),
        pw.Text(
          "Tax Amount (in words) : ${_convertNumberToWords(totalTaxAmount)}",
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: bwTextColor,
          ),
        ),

        pw.SizedBox(height: 10),
      ],
    );
  }

  // ---------- TOTALS (Matches Invoice Template UI) ----------
  static pw.Widget _buildTotals(
    Map<String, dynamic> quotation,
    bool isInterstate,
  ) {
    // READ PRE-CALCULATED, ROUNDED TOTALS DIRECTLY
    final subtotalTaxable = _roundToTwo(
      (quotation['total_taxable'] as num?)?.toDouble() ?? 0.0,
    );
    final totalCGST = _roundToTwo(
      (quotation['cgst_total'] as num?)?.toDouble() ?? 0.0,
    );
    final totalSGST = _roundToTwo(
      (quotation['sgst_total'] as num?)?.toDouble() ?? 0.0,
    );
    final totalIGST = _roundToTwo(
      (quotation['igst_total'] as num?)?.toDouble() ?? 0.0,
    );
    final grandTotal = _roundToTwo(
      (quotation['grand_total'] as num?)?.toDouble() ?? 0.0,
    );

    final PdfColor borderGrey = PdfColor(0.7, 0.7, 0.7);

    return pw.Container(
      width: 260,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: borderGrey, width: 1), // 🔑 B&W Color
      ),
      child: pw.Table(
        border: pw.TableBorder.all(
          color: borderGrey,
          width: 0.8,
        ), // 🔑 B&W Color
        columnWidths: const {
          0: pw.FlexColumnWidth(2.5),
          1: pw.FlexColumnWidth(1.5),
        },
        children: [
          _buildTotalRow("Taxable Value (Sub Total)", subtotalTaxable),
          if (!isInterstate) _buildTotalRow("Add: Output CGST", totalCGST),
          if (!isInterstate) _buildTotalRow("Add: Output SGST", totalSGST),
          if (isInterstate) _buildTotalRow("Add: Output IGST", totalIGST),
          // Round off is not explicitly in the quotation model, but can be derived if needed
          // For now, only show the Grand Total
          _buildTotalRow(
            "Total Amount (Grand Total)",
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
          ? const pw.BoxDecoration(color: bwTotalBg) // 🔑 B&W Color
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
              color: bwTextColor, // 🔑 B&W Color
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
              color: bwTextColor, // 🔑 B&W Color
            ),
          ),
        ),
      ],
    );
  }

  // ---------- AMOUNT IN WORDS BOX (Matches Invoice Template UI) ----------
  static pw.Widget _buildAmountInWordsBox(Map<String, dynamic> quotation) {
    final grandTotal = _roundToTwo(
      (quotation['grand_total'] as num?)?.toDouble() ?? 0.0,
    );
    final words = _convertNumberToWords(grandTotal);

    return pw.Container(
      width: 260,
      alignment: pw.Alignment.centerLeft,
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: bwBorder, width: 0.8), // 🔑 B&W Color
        color: bwHeaderBg, // 🔑 B&W Color
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            "Amount Chargeable (in words)",
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: bwPrimary,
            ), // 🔑 B&W Color
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            words,
            style: const pw.TextStyle(
              fontSize: 9,
              color: bwTextColor,
            ), // 🔑 B&W Color
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            "E. & O.E",
            style: const pw.TextStyle(
              fontSize: 8,
              color: bwMutedText,
            ), // 🔑 B&W Color
          ),
        ],
      ),
    );
  }

  // ---------- SIGNATORY (Matches Invoice Template UI) ----------

  // ---------- FOOTER (Matches Invoice Template UI) ----------
  static pw.Widget _buildFooter(Map<String, dynamic> company) {
    return pw.Container(
      alignment: pw.Alignment.center,
      child: pw.Text(
        company["poweredBy"] ?? "Powered by Smart Tech",
        style: const pw.TextStyle(
          fontSize: 7,
          color: bwMutedText,
        ), // 🔑 B&W Color
      ),
    );
  }

  // ---------- NUMBER TO WORDS CONVERSION (Indian System - Copied) ----------
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

    return "INR $finalWords";
  }
}
