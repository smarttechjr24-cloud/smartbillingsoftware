import 'dart:io';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class QuotationPdfServiceNoGST {
  // ---------- Corporate Colors ----------
  static const PdfColor primaryColor = PdfColor.fromInt(0xFF1F3A5F);
  static const PdfColor borderColor = PdfColor.fromInt(0xFFD4DAE3);
  static const PdfColor textColor = PdfColor.fromInt(0xFF333333);
  static const PdfColor mutedText = PdfColor.fromInt(0xFF808C8C);
  static const PdfColor headerBgColor = PdfColor.fromInt(0xFFF0F5F7);
  static const PdfColor totalBg = PdfColor.fromInt(0xFFEBF4F7);

  // ---------- Default Company Info ----------
  static const Map<String, dynamic> defaultCompany = {
    "name": "Smart Tech Junior",
    "address": "Company Address, City, Pincode",
    "email": "company@email.com",
    "phone": "9999999999",
    "title": "QUOTATION",
    "poweredBy": "Powered by Smart Tech",
  };

  // Helper function to round to 2 decimal places
  static double _roundToTwo(double value) {
    return double.parse(value.toStringAsFixed(2));
  }

  // ---------- FETCH COMPANY DETAILS FROM FIRESTORE ----------
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
          ...defaultCompany,
          "name": data['name'] ?? defaultCompany['name'],
          "address": data['address'] ?? defaultCompany['address'],
          "phone": data['phone'] ?? defaultCompany['phone'],
          "email": data['email'] ?? defaultCompany['email'],
        };
      } else {
        return defaultCompany;
      }
    } catch (e) {
      print("⚠️ Error fetching company details: $e");
      return defaultCompany;
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
        'mobile': '',
        'billing_address': 'Billing Address',
        'shipping_address': 'Shipping Address',
        'items': [],
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

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
          build: (context) => [
            _buildHeader(company),
            pw.SizedBox(height: 10),
            _buildQuotationInfo(mergedQuotation, dateFormat),
            pw.SizedBox(height: 10),
            _buildCustomerDetails(mergedQuotation),
            pw.SizedBox(height: 10),
            _buildItemsTable(items),
            pw.SizedBox(height: 10),
            _buildAmountInWords(mergedQuotation),
            pw.SizedBox(height: 20),
            if ((mergedQuotation['note'] ?? '').toString().isNotEmpty)
              _buildNote(mergedQuotation['note']),
            pw.SizedBox(height: 30),
            _buildFooter(company),
          ],
        ),
      );

      final bytes = await pdf.save();
      final dir = await getApplicationDocumentsDirectory();
      final file = File("${dir.path}/quotation_nogst_$quotationId.pdf");
      await file.writeAsBytes(bytes);

      if (printDirectly) {
        await Printing.layoutPdf(onLayout: (_) async => bytes);
      } else {
        await Printing.sharePdf(
          bytes: bytes,
          filename: "quotation_$quotationId.pdf",
        );
      }

      return file;
    } catch (e) {
      print("❌ Error generating quotation PDF: $e");
      return null;
    }
  }

  // ---------- HEADER ----------
  static pw.Widget _buildHeader(Map<String, dynamic> company) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 15, horizontal: 20),
      decoration: pw.BoxDecoration(
        color: headerBgColor,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
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
                pw.Text(
                  company["address"] ?? "",
                  style: const pw.TextStyle(fontSize: 9, color: textColor),
                ),
                if ((company["phone"] ?? '').toString().isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    "Phone: ${company["phone"]}",
                    style: const pw.TextStyle(fontSize: 9, color: textColor),
                  ),
                ],
                if ((company["email"] ?? '').toString().isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    "Email: ${company["email"]}",
                    style: const pw.TextStyle(fontSize: 9, color: textColor),
                  ),
                ],
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: pw.BoxDecoration(
              color: primaryColor,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              company["title"] ?? "QUOTATION",
              style: pw.TextStyle(
                fontSize: 14,
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- QUOTATION INFO ----------
  static pw.Widget _buildQuotationInfo(
    Map<String, dynamic> quotation,
    DateFormat dateFormat,
  ) {
    final quotationDate = quotation['quotation_date'] != null
        ? dateFormat.format(DateTime.parse(quotation['quotation_date']))
        : '-';
    final validTillDate = quotation['valid_till_date'] != null
        ? dateFormat.format(DateTime.parse(quotation['valid_till_date']))
        : '-';

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: borderColor, width: 0.5),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      padding: const pw.EdgeInsets.all(10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _buildInfoItem("Quotation No.", quotation['id'] ?? '-'),
          _buildInfoItem("Date", quotationDate),
          _buildInfoItem("Valid Till", validTillDate),
        ],
      ),
    );
  }

  static pw.Widget _buildInfoItem(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 8,
            color: mutedText,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          value,
          style: const pw.TextStyle(fontSize: 10, color: textColor),
        ),
      ],
    );
  }

  // ---------- CUSTOMER DETAILS ----------
  static pw.Widget _buildCustomerDetails(Map<String, dynamic> quotation) {
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
              "Customer Details",
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
                      pw.Text(
                        "Billed To:",
                        style: pw.TextStyle(
                          fontSize: 8,
                          color: mutedText,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      if ((quotation['customer_name'] ?? '').toString().isNotEmpty)
                        pw.Text(
                          quotation['customer_name'] ?? '',
                          style: pw.TextStyle(
                            fontSize: 9,
                            color: textColor,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      if ((quotation['billing_address'] ?? '').toString().isNotEmpty) ...[
                        pw.SizedBox(height: 2),
                        pw.Text(
                          quotation['billing_address'] ?? "",
                          style: const pw.TextStyle(fontSize: 9, color: textColor),
                        ),
                      ],
                      if ((quotation['mobile'] ?? '').toString().isNotEmpty) ...[
                        pw.SizedBox(height: 2),
                        pw.Text(
                          "Mobile: ${quotation['mobile']}",
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
                      pw.Text(
                        "Shipped To:",
                        style: pw.TextStyle(
                          fontSize: 8,
                          color: mutedText,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        quotation['shipping_address'] ??
                            quotation['billing_address'] ??
                            "",
                        style: const pw.TextStyle(fontSize: 9, color: textColor),
                      ),
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

  // ---------- ITEMS TABLE (NO GST) ----------
  static pw.Widget _buildItemsTable(List<Map<String, dynamic>> items) {
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

    // HEADER
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

    // ITEM ROWS
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
          decoration: pw.BoxDecoration(
            color: isOdd ? headerBgColor : PdfColors.white,
          ),
          children: [
            _cell("${i + 1}", pw.Alignment.center),
            _cell(
              item['item']?.toString() ?? 'N/A',
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

    // TOTAL ROW
    if (items.isNotEmpty) {
      rows.add(
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            color: totalBg,
            border: pw.Border(
              top: pw.BorderSide(color: primaryColor, width: 0.5),
            ),
          ),
          children: [
            _cell("", pw.Alignment.center),
            _cell(
              "Total",
              pw.Alignment.centerRight,
              bold: true,
              color: primaryColor,
            ),
            _cell(
              totalQty.toStringAsFixed(2),
              pw.Alignment.center,
              bold: true,
              color: primaryColor,
            ),
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

  // ---------- AMOUNT IN WORDS ----------
  static pw.Widget _buildAmountInWords(Map<String, dynamic> quotation) {
    final total = (quotation['grand_total'] ?? 0).toDouble();
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

  // ---------- NOTE ----------
  static pw.Widget _buildNote(String note) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: headerBgColor,
        borderRadius: pw.BorderRadius.circular(4),
        border: pw.Border.all(color: borderColor, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            "Note:",
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: primaryColor,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            note,
            style: const pw.TextStyle(fontSize: 9, color: textColor),
          ),
        ],
      ),
    );
  }

  // ---------- FOOTER ----------
  static pw.Widget _buildFooter(Map<String, dynamic> company) {
    return pw.Container(
      alignment: pw.Alignment.center,
      child: pw.Text(
        company["poweredBy"] ?? "Powered by Smart Tech",
        style: const pw.TextStyle(
          fontSize: 7,
          color: mutedText,
        ),
      ),
    );
  }

  // ---------- NUMBER TO WORDS CONVERSION ----------
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
