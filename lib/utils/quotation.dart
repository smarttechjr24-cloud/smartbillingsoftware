import 'dart:io';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class QuotationPdfService {
  static const PdfColor black = PdfColor(0, 0, 0);
  static const PdfColor gray = PdfColor(0.95, 0.95, 0.95);

  static Future<void> generateQuotationPDF(
    String quotationId, {
    Map<String, dynamic>? cachedData,
    bool printDirectly = false,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // 🔹 Fetch quotation data
    final quotation =
        cachedData ??
        (await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .collection('quotations')
                .doc(quotationId)
                .get())
            .data();

    if (quotation == null) return;

    // 🔹 Fetch company details
    final companyDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('company')
        .doc('details')
        .get();

    final company =
        companyDoc.data() ??
        {
          "name": "Your Company Name",
          "address": "Company Address",
          "email": "company@email.com",
          "phone": "9999999999",
        };

    final font = await PdfGoogleFonts.nunitoRegular();
    final bold = await PdfGoogleFonts.nunitoBold();

    final pdf = pw.Document();
    final dateFormat = DateFormat('dd/MM/yyyy');

    final items = List<Map<String, dynamic>>.from(quotation['items'] ?? []);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        theme: pw.ThemeData.withFont(base: font, bold: bold),
        build: (context) => [
          _buildHeader(company, quotation, dateFormat),
          pw.SizedBox(height: 16),
          _buildCustomerSection(quotation),
          pw.SizedBox(height: 14),
          _buildItemsTable(items),
          pw.SizedBox(height: 14),
          _buildTotalSection(quotation),
          pw.SizedBox(height: 20),
          _buildNotesSection(quotation),
          pw.SizedBox(height: 25),
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
      await Printing.sharePdf(
        bytes: bytes,
        filename: "quotation_$quotationId.pdf",
      );
    }
  }

  // ---------- HEADER ----------
  static pw.Widget _buildHeader(
    Map<String, dynamic> company,
    Map<String, dynamic> quotation,
    DateFormat dateFormat,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Center(
          child: pw.Text(
            "QUOTATION",
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 22,
              decoration: pw.TextDecoration.underline,
            ),
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Left - Company Info
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  company["name"] ?? "",
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                pw.Text(
                  company["address"] ?? "",
                  style: const pw.TextStyle(fontSize: 10),
                ),
                pw.Text(
                  "Phone: ${company["phone"] ?? '-'}",
                  style: const pw.TextStyle(fontSize: 10),
                ),
                pw.Text(
                  "Email: ${company["email"] ?? '-'}",
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
            // Right - Quotation Info
            pw.Container(
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: black, width: 1),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _infoRow("Quotation ID:", quotation['id'] ?? 'QO-XXXX'),

                  _infoRow("Date:", () {
                    try {
                      final dateValue = quotation['quotation_date'];
                      DateTime date;

                      if (dateValue is Timestamp) {
                        date = dateValue.toDate();
                      } else if (dateValue is String) {
                        date = DateTime.tryParse(dateValue) ?? DateTime.now();
                      } else {
                        date = DateTime.now();
                      }

                      return dateFormat.format(date);
                    } catch (e) {
                      print("⚠️ Error parsing quotation_date: $e");
                      return dateFormat.format(DateTime.now());
                    }
                  }()),

                  _infoRow("Status:", quotation['status'] ?? 'Draft'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _infoRow(String label, String value) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(width: 6),
        pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
      ],
    );
  }

  // ---------- CUSTOMER ----------
  static pw.Widget _buildCustomerSection(Map<String, dynamic> quotation) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          "To:",
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
        ),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: black, width: 1),
          ),
          child: pw.Text(
            "${quotation['customer_name'] ?? 'Customer Name'}\n"
            "${quotation['billing_address'] ?? ''}\n"
            "${quotation['shipping_address'] ?? ''}",
            style: const pw.TextStyle(fontSize: 10),
          ),
        ),
      ],
    );
  }

  // ---------- ITEMS ----------
  static pw.Widget _buildItemsTable(List<Map<String, dynamic>> items) {
    return pw.Table.fromTextArray(
      border: pw.TableBorder.all(color: black, width: 0.7),
      headerDecoration: const pw.BoxDecoration(color: gray),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
      cellStyle: const pw.TextStyle(fontSize: 9),
      headers: ["#", "Item", "Qty", "Rate (₹)", "Amount (₹)"],
      data: List.generate(
        items.length,
        (i) => [
          "${i + 1}",
          items[i]['item'] ?? '',
          "${items[i]['qty'] ?? 0}",
          "₹${(items[i]['rate'] ?? 0).toStringAsFixed(2)}",
          "₹${(items[i]['lineTotal'] ?? 0).toStringAsFixed(2)}",
        ],
      ),
    );
  }

  // ---------- TOTAL ----------
  static pw.Widget _buildTotalSection(Map<String, dynamic> quotation) {
    final subtotal = (quotation['subtotal'] ?? 0).toDouble();
    final gst = (quotation['gst_amount'] ?? 0).toDouble();
    final grandTotal = (quotation['grand_total'] ?? subtotal + gst).toDouble();
    final gstPercent = (quotation['gst_percentage'] ?? 0).toString();

    return pw.Container(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 220,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: black, width: 1),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _totalRow("Subtotal", subtotal),
            _totalRow("GST ($gstPercent%)", gst),
            pw.Divider(color: black),
            _totalRow("Grand Total", grandTotal, bold: true),
          ],
        ),
      ),
    );
  }

  static pw.Widget _totalRow(String label, double value, {bool bold = false}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
        pw.Text(
          "₹${value.toStringAsFixed(2)}",
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ],
    );
  }

  // ---------- NOTES ----------
  static pw.Widget _buildNotesSection(Map<String, dynamic> quotation) {
    if ((quotation['note'] ?? '').toString().trim().isEmpty)
      return pw.SizedBox();

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: black, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            "Notes:",
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
          ),
          pw.SizedBox(height: 4),
          pw.Text(quotation['note'], style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  // ---------- FOOTER ----------
  static pw.Widget _buildFooter(Map<String, dynamic> company) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(
          "For ${company['name'] ?? ''}",
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 25),
        pw.Container(
          width: 150,
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(width: 1)),
          ),
          alignment: pw.Alignment.center,
          child: pw.Text(
            "Authorized Signatory",
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
      ],
    );
  }
}
