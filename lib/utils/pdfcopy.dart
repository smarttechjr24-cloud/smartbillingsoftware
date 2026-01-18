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
import 'package:path/path.dart' as path;
import '../services/firestore_service.dart';

import '../utils/signature_repository.dart';

class PdfServiceNoGST {
  static final _service = FirestoreService();

  // ---------- Corporate Colors ----------
  static const PdfColor primaryColor = PdfColor.fromInt(0xFF1F3A5F);
  static const PdfColor borderColor = PdfColor.fromInt(0xFFD4DAE3);
  static const PdfColor textColor = PdfColor.fromInt(0xFF333333);
  static const PdfColor mutedText = PdfColor.fromInt(0xFF808C8C);
  static const PdfColor headerBgColor = PdfColor.fromInt(0xFFF0F5F7);
  static const PdfColor totalBg = PdfColor.fromInt(0xFFEBF4F7);

  // ---------- Default Company Info ----------
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
  };

  // ---------- Open SQLite Database ----------
  static Future<Database> _openDb() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = path.join(docsDir.path, 'smartbilling.db');
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

  // ---------- Fetch Company Info ----------
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
        return {
          "name": data['name'] ?? defaultCompany['name'],
          "gstin": data['gstin'] ?? '',
          "address": [data['address'] ?? '', "Mobile: ${data['phone'] ?? ''}"],
          "title": "BILL",
          "poweredBy": "Powered by Smart Tech",
        };
      } else {
        return defaultCompany;
      }
    } catch (e) {
      print("⚠️ Error fetching company details: $e");
      return defaultCompany;
    }
  }



  // ---------- Generate & Share / Print ----------
  static Future<void> generateAndOpenPDF(
    String invoiceId, {
    Map<String, dynamic>? cachedData,
    bool printDirectly = false,
  }) async {
    final invoice = cachedData ?? await _service.fetchInvoice(invoiceId);
    if (invoice == null) {
      print("❌ Invoice not found for ID: $invoiceId");
      return;
    }

    final company = await getCompanyDetails();
    final logoBytes = await getCompanyLogo();
    final signatureBytes = await SignatureRepository.getSignature();
    final font = await PdfGoogleFonts.nunitoRegular();
    final boldFont = await PdfGoogleFonts.nunitoBold();

    final pdf = pw.Document();
    final dateFormat = DateFormat('dd MMM yyyy');
    final items = List<Map<String, dynamic>>.from(invoice['items'] ?? []);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        build: (context) => [
          _buildHeader(company, logoBytes),
          pw.SizedBox(height: 10),
          _buildInvoiceMeta(invoice, dateFormat),
          pw.SizedBox(height: 10),
          _buildCustomerDetails(invoice),
          pw.SizedBox(height: 10),
          _buildItemsTableNoGST(items),
          pw.SizedBox(height: 14),
          // Removed redundant _buildTotalsNoGST to fix alignment and duplication
          _buildAmountInWords(invoice),
          pw.SizedBox(height: 25),
          _buildSignatory(company, signatureBytes),
          pw.SizedBox(height: 20),
          _buildFooter(company),
        ],
      ),
    );

    final pdfBytes = await pdf.save();
    final dir = await getApplicationDocumentsDirectory();
    final file = File("${dir.path}/invoice_$invoiceId.pdf");
    await file.writeAsBytes(pdfBytes);

    if (printDirectly) {
      await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
    } else {
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: "invoice_$invoiceId.pdf",
      );
    }
  }

  // ---------- HEADER WITH LOGO ----------
  static pw.Widget _buildHeader(
    Map<String, dynamic> company,
    Uint8List? logoBytes,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 15, horizontal: 20),
      decoration: pw.BoxDecoration(
        color: headerBgColor,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Left side: Company info
          pw.Expanded(
            flex: 3,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  company["name"] ?? "",
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
                pw.SizedBox(height: 4),
                if ((company["gstin"] ?? '').isNotEmpty)
                  pw.Text(
                    "GSTIN: ${company["gstin"]}",
                    style: const pw.TextStyle(fontSize: 10, color: mutedText),
                  ),
                pw.SizedBox(height: 4),
                pw.Text(
                  (company["address"] as List).join("\n"),
                  style: const pw.TextStyle(fontSize: 9, color: textColor),
                ),
              ],
            ),
          ),

          // Right side: Logo and Title
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              // Logo
              if (logoBytes != null)
                pw.Container(
                  width: 60,
                  height: 60,
                  child: pw.Image(
                    pw.MemoryImage(logoBytes),
                    fit: pw.BoxFit.contain,
                  ),
                ),
              pw.SizedBox(height: 8),
              // Invoice Title
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: pw.BoxDecoration(
                  color: primaryColor,
                  borderRadius: pw.BorderRadius.circular(2),
                ),
                child: pw.Text(
                  company["title"] ?? "INVOICE",
                  style: pw.TextStyle(
                    fontSize: 12,
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- INVOICE META ----------
  static pw.Widget _buildInvoiceMeta(
    Map<String, dynamic> invoice,
    DateFormat dateFormat,
  ) {
    final invoiceDateStr = invoice['invoice_date'] != null
        ? dateFormat.format(DateTime.parse(invoice['invoice_date']))
        : '-';
    final dueDateStr = invoice['due_date'] != null
        ? dateFormat.format(DateTime.parse(invoice['due_date']))
        : '-';

    return pw.Table(
      border: pw.TableBorder.all(color: borderColor, width: 0.4),
      children: [
        _tableRow("Invoice No", invoice['invoice_number'] ?? '-'),
        _tableRow("Invoice Date", invoiceDateStr),
        _tableRow("Due Date", dueDateStr),
      ],
    );
  }

  // ---------- CUSTOMER DETAILS ----------
  static pw.Widget _buildCustomerDetails(Map<String, dynamic> invoice) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: borderColor, width: 0.5),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            color: headerBgColor,
            child: pw.Text(
              "Billing & Shipping Details",
              style: pw.TextStyle(
                fontSize: 10,
                color: primaryColor,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("Billed To:", style: pw.TextStyle(fontSize: 8, color: mutedText, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 3),
                      if ((invoice['customer_name'] ?? '').toString().isNotEmpty)
                        pw.Text(
                          invoice['customer_name'] ?? '',
                          style: pw.TextStyle(fontSize: 9, color: textColor, fontWeight: pw.FontWeight.bold),
                        ),
                      if ((invoice['billing_address'] ?? '').toString().isNotEmpty) ...[
                        pw.SizedBox(height: 2),
                        pw.Text(invoice['billing_address'] ?? "", style: const pw.TextStyle(fontSize: 9, color: textColor)),
                      ],
                      if ((invoice['mobile'] ?? '').toString().isNotEmpty) ...[
                        pw.SizedBox(height: 2),
                        pw.Text("Mobile: ${invoice['mobile']}", style: const pw.TextStyle(fontSize: 9, color: textColor)),
                      ],
                      if ((invoice['customer_state'] ?? invoice['place_of_supply'] ?? '').toString().isNotEmpty) ...[
                        pw.SizedBox(height: 2),
                        pw.Text(
                          "State: ${invoice['customer_state'] ?? invoice['place_of_supply'] ?? ''}",
                          style: const pw.TextStyle(fontSize: 9, color: textColor),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              pw.Container(width: 0.5, height: 60, color: borderColor),
              pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("Shipped To:", style: pw.TextStyle(fontSize: 8, color: mutedText, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 3),
                      pw.Text(invoice['shipping_address'] ?? invoice['billing_address'] ?? "", style: const pw.TextStyle(fontSize: 9, color: textColor)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- ITEMS TABLE ----------
  static pw.Widget _buildItemsTable(List<Map<String, dynamic>> items) {
    return pw.Table.fromTextArray(
      border: pw.TableBorder.all(color: borderColor, width: 0.3),
      headerDecoration: const pw.BoxDecoration(color: primaryColor),
      headerStyle: pw.TextStyle(
        color: PdfColors.white,
        fontWeight: pw.FontWeight.bold,
        fontSize: 10,
      ),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignments: {
        0: pw.Alignment.center,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
      },
      data: <List<String>>[
        ['S.No', 'Description', 'Qty', 'Rate', 'Amount'],
        ...List.generate(
          items.length,
          (i) => [
            '${i + 1}',
            items[i]['item'] ?? '',
            '${items[i]['qty'] ?? 0}',
            '₹${(items[i]['rate'] ?? 0).toStringAsFixed(2)}',
            '₹${((items[i]['subtotal'] ?? items[i]['lineTotal'] ?? 0).toStringAsFixed(2))}',
          ],
        ),
      ],
    );
  }



  // ---------- AMOUNT IN WORDS ----------
  // ---------- AMOUNT IN WORDS ----------
  static pw.Widget _buildAmountInWords(Map<String, dynamic> invoice) {
    final total = (invoice['grand_total'] ?? 0).toDouble() > 0
        ? (invoice['grand_total'] ?? 0).toDouble()
        : (invoice['subtotal'] ?? 0).toDouble() +
              (invoice['gst_amount'] ?? 0).toDouble();
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(
            "Amount in Words:",
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: primaryColor,
            ),
          ),
          pw.Text(
            _convertNumberToWords(total),
            style: const pw.TextStyle(fontSize: 10, color: mutedText),
            textAlign: pw.TextAlign.right,
          ),
        ],
      ),
    );
  }

  // ---------- SIGNATORY ----------
  static pw.Widget _buildSignatory(
    Map<String, dynamic> company,
    Uint8List? signatureBytes,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            if (signatureBytes != null)
              pw.Container(
                height: 40,
                child: pw.Image(pw.MemoryImage(signatureBytes)),
              )
            else
              pw.SizedBox(height: 40),
            pw.SizedBox(height: 4),
            pw.Text(
              "Authorized Signatory",
              style: const pw.TextStyle(fontSize: 9, color: mutedText),
            ),
            pw.Text(
              "For ${company["name"]}",
              style: pw.TextStyle(
                fontSize: 9,
                color: textColor,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------- FOOTER ----------
  static pw.Widget _buildFooter(Map<String, dynamic> company) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text(
        company["poweredBy"] ?? "",
        style: const pw.TextStyle(fontSize: 8, color: mutedText),
      ),
    );
  }

  // ---------- Helpers ----------
  static double _roundToTwo(double value) {
    return (value * 100).round() / 100;
  }

  // ---------- HEADER CELL ----------
  static pw.Widget _headerCell(
    String text,
    pw.Alignment align, {
    PdfColor? color,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      alignment: align,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: color ?? primaryColor,
        ),
      ),
    );
  }

  // ---------- NORMAL CELL ----------
  static pw.Widget _cell(
    String text,
    pw.Alignment align, {
    bool bold = false,
    PdfColor? color,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      alignment: align,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? textColor,
        ),
      ),
    );
  }
  static pw.TableRow _tableRow(String label, String value) =>
      pw.TableRow(children: [_tableCell(label, bold: true), _tableCell(value)]);

  static pw.Widget _tableCell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9.5,
          color: textColor,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }



  static pw.Widget _totalRow(String label, double value) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Text(
          "$label: ",
          style: const pw.TextStyle(fontSize: 10, color: textColor),
        ),
        pw.Text(
          "₹${value.toStringAsFixed(2)}",
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: textColor,
          ),
        ),
      ],
    ),
  );

  // ---------- Number to Words ----------
  static String _convertNumberToWords(double amount) {
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
      if (number == 0) return "Zero";
      String words = "";
      int crore = number ~/ 10000000;
      number %= 10000000;
      int lakh = number ~/ 100000;
      number %= 100000;
      int thousand = number ~/ 1000;
      number %= 1000;
      int hundred = number;
      if (crore > 0) words += "${threeDigits(crore)} Crore ";
      if (lakh > 0) words += "${threeDigits(lakh)} Lakh ";
      if (thousand > 0) words += "${threeDigits(thousand)} Thousand ";
      if (hundred > 0) words += "${threeDigits(hundred)} ";
      return words.trim();
    }

    int rupees = amount.floor();
    int paise = ((amount - rupees) * 100).round();
    String result = "Rupees ${convertIntToWords(rupees)}";
    if (paise > 0) result += " and ${convertIntToWords(paise)} Paise";
    return "$result only";
  }
  // ========== NON-GST PDF GENERATION HELPERS ==========

  // ---------- ITEMS TABLE WITHOUT GST (Professional) ----------
  static pw.Widget _buildItemsTableNoGST(
    List<Map<String, dynamic>> items,
  ) {
    final Map<int, pw.TableColumnWidth> columnWidths = {
      0: const pw.FlexColumnWidth(0.6),
      1: const pw.FlexColumnWidth(4.0),
      2: const pw.FlexColumnWidth(1.2),
      3: const pw.FlexColumnWidth(1.5),
      4: const pw.FlexColumnWidth(2.0),
    };

    double totalQty = 0.0;
    double totalAmount = 0.0;

    final List<pw.TableRow> rows = [];

    // ---------- HEADER ----------
    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: primaryColor),
        children: [
          _headerCell("S.No", pw.Alignment.center, color: PdfColors.white),
          _headerCell("Description", pw.Alignment.centerLeft, color: PdfColors.white),
          _headerCell("Qty", pw.Alignment.center, color: PdfColors.white),
          _headerCell("Rate", pw.Alignment.centerRight, color: PdfColors.white),
          _headerCell("Amount", pw.Alignment.centerRight, color: PdfColors.white),
        ],
      ),
    );

    // ---------- ITEM ROWS ----------
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final isOdd = i % 2 != 0;

      final qty = (item['qty'] as num?)?.toDouble() ?? 0.0;
      final rate = (item['rate'] as num?)?.toDouble() ?? 0.0;
      final amount = qty * rate;

      totalQty += qty;
      totalAmount += amount;

      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(color: isOdd ? headerBgColor : PdfColors.white),
          children: [
            _cell("${i + 1}", pw.Alignment.center),
            _cell(
              item['item_name']?.toString() ?? 'N/A',
              pw.Alignment.centerLeft,
            ),
            _cell(qty.toStringAsFixed(2), pw.Alignment.center),
            _cell(rate.toStringAsFixed(2), pw.Alignment.centerRight),
            _cell(
              _roundToTwo(amount).toStringAsFixed(2),
              pw.Alignment.centerRight,
            ),
          ],
        ),
      );
    }

    // ---------- TOTAL ROW ----------
    if (items.isNotEmpty) {
      rows.add(
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            color: totalBg,
            border: pw.Border(top: pw.BorderSide(color: primaryColor, width: 0.5)),
          ),
          children: [
            _cell("", pw.Alignment.center),
            _cell(
              "Total",
              pw.Alignment.centerRight,
              bold: true,
              color: primaryColor,
            ),
            _cell(totalQty.toStringAsFixed(2), pw.Alignment.center, bold: true, color: primaryColor),
            _cell("", pw.Alignment.center),
            _cell(
              "₹${_roundToTwo(totalAmount).toStringAsFixed(2)}",
              pw.Alignment.centerRight,
              bold: true,
              color: primaryColor,
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


}
