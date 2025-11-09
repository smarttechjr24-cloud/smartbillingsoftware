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

class PdfService {
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
  static Future<Uint8List?> _getCompanyLogo() async {
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
        return {
          "name": data['name'] ?? defaultCompany['name'],
          "gstin": data['gstin'] ?? '',
          "address": [data['address'] ?? '', "Mobile: ${data['phone'] ?? ''}"],
          "title": "TAX INVOICE",
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

    final company = await _getCompanyDetails();
    final logoBytes = await _getCompanyLogo();
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
          _buildItemsTable(items),
          pw.SizedBox(height: 14),
          _buildTotals(invoice),
          pw.SizedBox(height: 16),
          _buildAmountInWords(invoice),
          pw.SizedBox(height: 25),
          _buildSignatory(company),
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
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
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
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                  if ((company["gstin"] ?? '').isNotEmpty)
                    pw.Text(
                      "GSTIN: ${company["gstin"]}",
                      style: const pw.TextStyle(fontSize: 10, color: mutedText),
                    ),
                  pw.Text(
                    (company["address"] as List).join(" | "),
                    style: const pw.TextStyle(fontSize: 9, color: mutedText),
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
                    width: 80,
                    height: 80,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: borderColor, width: 1),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Image(
                      pw.MemoryImage(logoBytes),
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                pw.SizedBox(height: 8),
                // Invoice Title
                pw.Text(
                  company["title"] ?? "INVOICE",
                  style: pw.TextStyle(
                    fontSize: 18,
                    color: primaryColor,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Divider(color: borderColor, thickness: 1),
      ],
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
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          "Billing & Shipping Details",
          style: pw.TextStyle(
            fontSize: 11,
            color: primaryColor,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Table(
          border: pw.TableBorder.all(color: borderColor, width: 0.3),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: headerBgColor),
              children: [_cellHeader("From"), _cellHeader("To")],
            ),
            pw.TableRow(
              children: [
                _cellBody(invoice['billing_address'] ?? ""),
                _cellBody(invoice['shipping_address'] ?? ""),
              ],
            ),
          ],
        ),
      ],
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

  // ---------- TOTALS ----------
  static pw.Widget _buildTotals(Map<String, dynamic> invoice) {
    final List<Map<String, dynamic>> items = List<Map<String, dynamic>>.from(
      invoice['items'] ?? [],
    );

    // 🔹 Recalculate subtotal from items if not available
    final double subtotal = items.fold(
      0.0,
      (sum, item) =>
          sum + (item['subtotal'] ?? item['lineTotal'] ?? 0).toDouble(),
    );

    // 🔹 GST (if applicable)
    double gst = (invoice['gst_amount'] ?? 0).toDouble();
    if (gst == 0 && invoice['gst_percentage'] != null) {
      gst = subtotal * ((invoice['gst_percentage'] as num).toDouble() / 100);
    }

    // 🔹 Prefer stored grand_total if exists
    final double grandTotal = (invoice['grand_total'] ?? subtotal + gst)
        .toDouble();

    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          _totalRow("Subtotal", subtotal),
          _totalRow("GST", gst),
          pw.Container(
            color: totalBg,
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            margin: const pw.EdgeInsets.only(top: 4),
            child: pw.Text(
              "Grand Total: ₹${grandTotal.toStringAsFixed(2)}",
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- AMOUNT IN WORDS ----------
  static pw.Widget _buildAmountInWords(Map<String, dynamic> invoice) {
    final total = (invoice['grand_total'] ?? 0).toDouble() > 0
        ? (invoice['grand_total'] ?? 0).toDouble()
        : (invoice['subtotal'] ?? 0).toDouble() +
              (invoice['gst_amount'] ?? 0).toDouble();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
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
        ),
      ],
    );
  }

  // ---------- SIGNATORY ----------
  static pw.Widget _buildSignatory(Map<String, dynamic> company) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          "Receiver's Signature",
          style: const pw.TextStyle(fontSize: 9, color: mutedText),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.SizedBox(height: 25),
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

  static pw.Widget _cellHeader(String text) => pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: primaryColor,
        fontSize: 10,
      ),
    ),
  );

  static pw.Widget _cellBody(String text) => pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: pw.Text(
      text,
      style: const pw.TextStyle(fontSize: 9.5, color: textColor),
    ),
  );

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
}
