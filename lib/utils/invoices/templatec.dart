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

Future<void> generatePDF_C(
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
    final templateC = await _buildTemplateC(
      company,
      invoice,
      logoBytes,
      signatureBytes,
      items,
      dateFormat,
    );
    pdf.addPage(templateC);

    final dir = await getApplicationDocumentsDirectory();
    final file = File("${dir.path}/invoiceC_$invoiceId.pdf");
    final pdfBytes = await pdf.save();
    await file.writeAsBytes(pdfBytes);

    if (printDirectly) {
      await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
    } else {
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: "invoiceC_$invoiceId.pdf",
      );
    }
  } catch (e) {
    print("❌ Template-C PDF generation failed: $e");
  }
}

Future<pw.MultiPage> _buildTemplateC(
  Map<String, dynamic> company,
  Map<String, dynamic> invoice,
  Uint8List? logoBytes,
  Uint8List? signatureBytes,
  List<Map<String, dynamic>> items,
  DateFormat dateFormat,
) async {
  // Colors
  const PdfColor kBlue = PdfColor.fromInt(0xFF0D47A1); // Deep Blue
  const PdfColor kLightBlue = PdfColor.fromInt(0xFFE3F2FD);
  const PdfColor kWhite = PdfColors.white;
  const PdfColor kText = PdfColor.fromInt(0xFF212121);
  const PdfColor kMuted = PdfColor.fromInt(0xFF757575);

  // Load fonts
  final ttf = await PdfGoogleFonts.notoSansRegular();
  final ttfBold = await PdfGoogleFonts.notoSansBold();

  final taxType = invoice['tax_type'] as String? ?? 'CGST_SGST';
  final isInterstate = taxType == 'IGST';
  final companyName = company['name'] ?? 'Company Name';

  // Helper styles
  final textStyle = pw.TextStyle(font: ttf, fontSize: 9, color: kText);
  final boldStyle = pw.TextStyle(font: ttfBold, fontSize: 9, color: kText);
  final whiteBoldStyle = pw.TextStyle(font: ttfBold, fontSize: 10, color: kWhite);
  final mutedStyle = pw.TextStyle(font: ttf, fontSize: 8, color: kMuted);

  // Components

  // 1. Header
  pw.Widget _buildHeader() {
    final sellerName = company['name'] ?? 'Company Name';
    final addressLines = (company["address"] is List ? company["address"] : [company["address"]])
        .whereType<String>()
        .join(', ');

    return pw.Container(
      color: kBlue,
      padding: const pw.EdgeInsets.all(20),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(sellerName, style: pw.TextStyle(font: ttfBold, fontSize: 20, color: kWhite)),
              pw.SizedBox(height: 5),
              pw.Text(addressLines, style: pw.TextStyle(font: ttf, fontSize: 9, color: kWhite)),
              pw.Text("GSTIN: ${company['gstin'] ?? ''}", style: pw.TextStyle(font: ttf, fontSize: 9, color: kWhite)),
            ],
          ),
          if (logoBytes != null)
            pw.Container(
              height: 50,
              width: 50,
              decoration: pw.BoxDecoration(
                color: kWhite,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              padding: const pw.EdgeInsets.all(4),
              child: pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
            ),
        ],
      ),
    );
  }

  // 2. Info Block
  pw.Widget _buildInfoBlock() {
    final buyerName = invoice['customer_name'] ?? 'N/A';
    final billingAddress = invoice['billing_address'] ?? 'N/A';
    final invoiceNo = invoice['invoice_number'] ?? '-';
    final date = invoice['invoice_date'] != null ? dateFormat.format(DateTime.parse(invoice['invoice_date'])) : '-';

    return pw.Padding(
      padding: const pw.EdgeInsets.all(20),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text("BILL TO", style: pw.TextStyle(font: ttfBold, fontSize: 10, color: kBlue)),
              pw.SizedBox(height: 5),
              pw.Text(buyerName, style: boldStyle),
              pw.Text(billingAddress, style: textStyle),
              if (invoice['customer_gstin'] != null)
                pw.Text("GSTIN: ${invoice['customer_gstin']}", style: textStyle),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text("INVOICE DETAILS", style: pw.TextStyle(font: ttfBold, fontSize: 10, color: kBlue)),
              pw.SizedBox(height: 5),
              pw.Text("Invoice #: $invoiceNo", style: textStyle),
              pw.Text("Date: $date", style: textStyle),
            ],
          ),
        ],
      ),
    );
  }

  // 3. Items Table
  pw.Widget _buildItemsTable() {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 20),
      child: pw.Table(
        border: pw.TableBorder.all(color: kLightBlue),
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
            decoration: const pw.BoxDecoration(color: kBlue),
            children: ["#", "Item", "HSN", "Qty", "Rate", "Amount"]
                .map((h) => pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(h, style: whiteBoldStyle, textAlign: h == "Item" ? pw.TextAlign.left : pw.TextAlign.center),
                    ))
                .toList(),
          ),
          ...items.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            final qty = (item['qty'] as num?)?.toDouble() ?? 0.0;
            final rate = (item['rate'] as num?)?.toDouble() ?? 0.0;
            final amount = (item['taxable_amount'] as num?)?.toDouble() ?? 0.0;

            return pw.TableRow(
              decoration: pw.BoxDecoration(color: i % 2 == 0 ? kWhite : const PdfColor.fromInt(0x4DE3F2FD)),
              children: [
                pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text("${i + 1}", style: textStyle, textAlign: pw.TextAlign.center)),
                pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(item['item_name'] ?? "", style: textStyle)),
                pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(item['hsn_code'] ?? "", style: textStyle, textAlign: pw.TextAlign.center)),
                pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(qty.toStringAsFixed(2), style: textStyle, textAlign: pw.TextAlign.center)),
                pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(rate.toStringAsFixed(2), style: textStyle, textAlign: pw.TextAlign.right)),
                pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(amount.toStringAsFixed(2), style: textStyle, textAlign: pw.TextAlign.right)),
              ],
            );
          }).toList(),
        ],
      ),
    );
  }

  // 4. Footer
  pw.Widget _buildFooterSection() {
    final grandTotal = (invoice['grand_total'] as num?)?.toDouble() ?? 0.0;
    final amountInWords = _localConvertNumberToWords(grandTotal);

    return pw.Padding(
      padding: const pw.EdgeInsets.all(20),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 6,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text("Amount in Words", style: mutedStyle),
                pw.Text("INR $amountInWords Only", style: boldStyle),
                pw.SizedBox(height: 20),
                if (signatureBytes != null)
                  pw.Container(
                    height: 50,
                    child: pw.Image(pw.MemoryImage(signatureBytes), fit: pw.BoxFit.contain),
                  ),
                pw.SizedBox(height: 5),
                pw.Text("Authorised Signatory", style: mutedStyle),
                pw.Text("For $companyName", style: boldStyle),
              ],
            ),
          ),
          pw.Expanded(
            flex: 4,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(12),
              color: const PdfColor.fromInt(0x80E3F2FD),
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
                  pw.Divider(),
                  pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                    pw.Text("Grand Total", style: pw.TextStyle(font: ttfBold, fontSize: 12, color: kBlue)),
                    pw.Text("₹ ${grandTotal.toStringAsFixed(2)}", style: pw.TextStyle(font: ttfBold, fontSize: 12, color: kBlue)),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  return pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: pw.EdgeInsets.zero, // Full bleed header
    build: (context) => [
      _buildHeader(),
      _buildInfoBlock(),
      _buildItemsTable(),
      _buildFooterSection(),
    ],
    footer: (context) => pw.Container(
      alignment: pw.Alignment.center,
      margin: const pw.EdgeInsets.only(bottom: 20),
      child: pw.Text("Powered by Smart Billing", style: mutedStyle),
    ),
  );
}
