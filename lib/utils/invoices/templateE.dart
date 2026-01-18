import 'dart:io';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:smartbilling/services/firestore_service.dart';
import 'package:smartbilling/utils/pdf.dart';
import 'package:smartbilling/utils/signature_repository.dart';

// Helper function definitions
double _localRoundToTwo(double value) {
  return double.parse(value.toStringAsFixed(2));
}

String _localConvertNumberToWords(double n) {
  if (n == 0) return "Zero";
  int number = n.toInt();
  int decimal = ((n - number) * 100).round();

  final units = [
    "", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten",
    "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen",
  ];

  final tens = [
    "", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety",
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

    if (crore > 0) words += "${twoDigits(crore)} Crore ";
    if (lakh > 0) words += "${twoDigits(lakh)} Lakh ";
    if (thousand > 0) words += "${twoDigits(thousand)} Thousand ";
    if (hundred > 0) words += threeDigits(hundred);
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

Future<void> generatePDF_E(
  String invoiceId, {
  bool printDirectly = false,
  Map<String, dynamic>? cachedData,
}) async {
  try {
    final service = FirestoreService();
    final company = await PdfService.getCompanyDetails();
    final logoBytes = await PdfService.getCompanyLogo();
    final invoice = cachedData ?? await service.fetchInvoice(invoiceId);
    
    // Fetch Signature
    final signatureBytes = await SignatureRepository.getSignature();

    if (invoice == null) {
      print("❌ Invoice not found");
      return;
    }

    final pdf = pw.Document();
    final items = List<Map<String, dynamic>>.from(invoice['items'] ?? []);
    final dateFormat = DateFormat("dd/MM/yyyy");

    // Await the async template builder
    final templateE = await _buildTemplateE(
      company,
      invoice,
      logoBytes,
      signatureBytes,
      items,
      dateFormat,
    );
    pdf.addPage(templateE);

    final dir = await getApplicationDocumentsDirectory();
    final file = File("${dir.path}/invoiceE_$invoiceId.pdf");
    final pdfBytes = await pdf.save();
    await file.writeAsBytes(pdfBytes);

    if (printDirectly) {
      await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
    } else {
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: "invoiceE_$invoiceId.pdf",
      );
    }
  } catch (e) {
    print("❌ Template-E PDF generation failed: $e");
  }
}

Future<pw.Page> _buildTemplateE(
  Map<String, dynamic> company,
  Map<String, dynamic> invoice,
  Uint8List? logoBytes,
  Uint8List? signatureBytes,
  List<Map<String, dynamic>> items,
  DateFormat dateFormat,
) async {
  // Colors
  const PdfColor kPrimary = PdfColor.fromInt(0xFF000000); // Black for professional look
  const PdfColor kAccent = PdfColor.fromInt(0xFF424242);
  const PdfColor kBorder = PdfColor.fromInt(0xFFE0E0E0);
  const PdfColor kBg = PdfColor.fromInt(0xFFFAFAFA);

  // Load fonts
  final ttf = await PdfGoogleFonts.notoSansRegular();
  final ttfBold = await PdfGoogleFonts.notoSansBold();

  final companyName = company['name'] ?? 'Company Name';
  final taxType = invoice['tax_type'] as String? ?? 'CGST_SGST';
  final isInterstate = taxType == 'IGST';

  // Styles
  final textStyle = pw.TextStyle(font: ttf, fontSize: 9, color: kAccent);
  final boldStyle = pw.TextStyle(font: ttfBold, fontSize: 9, color: kPrimary);
  final headerStyle = pw.TextStyle(font: ttfBold, fontSize: 24, color: kPrimary);
  final mutedStyle = pw.TextStyle(font: ttf, fontSize: 8, color: kAccent);

  // Components
  pw.Widget _buildHeader() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logoBytes != null)
              pw.Container(
                height: 50,
                margin: const pw.EdgeInsets.only(bottom: 10),
                child: pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
              )
            else
              pw.Text(companyName, style: pw.TextStyle(font: ttfBold, fontSize: 18)),
            pw.SizedBox(height: 5),
            pw.Text((company['address'] is List ? company['address'].join(', ') : company['address'] ?? ''), style: textStyle),
            pw.Text("GSTIN: ${company['gstin'] ?? ''}", style: textStyle),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text("INVOICE", style: headerStyle),
            pw.Text("#${invoice['invoice_number'] ?? ''}", style: pw.TextStyle(font: ttf, fontSize: 12, color: kAccent)),
            pw.SizedBox(height: 5),
            pw.Text("Date: ${invoice['invoice_date'] != null ? dateFormat.format(DateTime.parse(invoice['invoice_date'])) : ''}", style: textStyle),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildItemsTable() {
    return pw.Table(
      border: pw.TableBorder.all(color: kBorder),
      columnWidths: {
        0: const pw.FlexColumnWidth(0.5),
        1: const pw.FlexColumnWidth(3),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FlexColumnWidth(1),
        4: const pw.FlexColumnWidth(1.2),
        5: const pw.FlexColumnWidth(1.2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: kBg),
          children: ["#", "Item", "HSN", "Qty", "Rate", "Amount"]
              .map((h) => pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(h, style: boldStyle, textAlign: h == "Item" ? pw.TextAlign.left : pw.TextAlign.center),
                  ))
              .toList(),
        ),
        ...items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          return pw.TableRow(
            children: [
              pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text("${i + 1}", style: textStyle, textAlign: pw.TextAlign.center)),
              pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(item['item_name'] ?? "", style: textStyle)),
              pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(item['hsn_code'] ?? "", style: textStyle, textAlign: pw.TextAlign.center)),
              pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text((item['qty'] ?? 0).toString(), style: textStyle, textAlign: pw.TextAlign.center)),
              pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text((item['rate'] ?? 0).toStringAsFixed(2), style: textStyle, textAlign: pw.TextAlign.right)),
              pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text((item['taxable_amount'] ?? 0).toStringAsFixed(2), style: textStyle, textAlign: pw.TextAlign.right)),
            ],
          );
        }).toList(),
      ],
    );
  }

  pw.Widget _buildFooterSection(bool isInterstate) {
    final grandTotal = (invoice['grand_total'] as num?)?.toDouble() ?? 0.0;
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 6,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text("Amount in Words", style: boldStyle),
              pw.Text("INR ${_localConvertNumberToWords(grandTotal)} Only", style: textStyle),
              pw.SizedBox(height: 30),
              if (signatureBytes != null)
                pw.Container(
                  height: 50,
                  child: pw.Image(pw.MemoryImage(signatureBytes), fit: pw.BoxFit.contain),
                ),
              pw.Text("Authorised Signatory", style: textStyle),
              pw.Text("For $companyName", style: boldStyle),
            ],
          ),
        ),
        pw.Expanded(
          flex: 4,
          child: pw.Column(
            children: [
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text("Subtotal", style: textStyle),
                pw.Text((invoice['subtotal'] ?? 0).toStringAsFixed(2), style: textStyle),
              ]),
              if (!isInterstate) ...[
                pw.SizedBox(height: 4),
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text("CGST", style: textStyle),
                  pw.Text((invoice['cgst_total'] ?? 0).toStringAsFixed(2), style: textStyle),
                ]),
                pw.SizedBox(height: 4),
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text("SGST", style: textStyle),
                  pw.Text((invoice['sgst_total'] ?? 0).toStringAsFixed(2), style: textStyle),
                ]),
              ] else ...[
                pw.SizedBox(height: 4),
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text("IGST", style: textStyle),
                  pw.Text((invoice['igst_total'] ?? 0).toStringAsFixed(2), style: textStyle),
                ]),
              ],
              pw.Divider(color: kBorder),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text("Grand Total", style: boldStyle),
                pw.Text("₹ ${grandTotal.toStringAsFixed(2)}", style: pw.TextStyle(font: ttfBold, fontSize: 14, color: kPrimary)),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  return pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(40),
    build: (context) => [
      _buildHeader(),
      pw.SizedBox(height: 30),
      _buildItemsTable(),
      pw.SizedBox(height: 30),
      _buildFooterSection(isInterstate),
    ],
    footer: (context) => pw.Center(
      child: pw.Text(
        "Powered by Smart Billing",
        style: pw.TextStyle(font: ttf, fontSize: 8, color: kAccent),
      ),
    ),
  );
}
