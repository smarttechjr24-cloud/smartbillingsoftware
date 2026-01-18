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

Future<void> generatePDF_B(
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
    final templateB = await _buildTemplateB(
      company,
      invoice,
      logoBytes,
      signatureBytes,
      items,
      dateFormat,
    );
    pdf.addPage(templateB);

    final dir = await getApplicationDocumentsDirectory();
    final file = File("${dir.path}/invoiceB_$invoiceId.pdf");
    final pdfBytes = await pdf.save();
    await file.writeAsBytes(pdfBytes);

    if (printDirectly) {
      await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
    } else {
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: "invoiceB_$invoiceId.pdf",
      );
    }
  } catch (e) {
    print("❌ Template-B PDF generation failed: $e");
  }
}

// Template B: Minimal Professional
Future<pw.MultiPage> _buildTemplateB(
  Map<String, dynamic> company,
  Map<String, dynamic> invoice,
  Uint8List? logoBytes,
  Uint8List? signatureBytes,
  List<Map<String, dynamic>> items,
  DateFormat dateFormat,
) async {
  // --- Colors and Fonts ---
  const PdfColor kPrimary = PdfColor.fromInt(0xFF1976D2); // Professional Blue
  const PdfColor kDarkText = PdfColor.fromInt(0xFF212121);
  const PdfColor kLightText = PdfColor.fromInt(0xFF757575);
  const PdfColor kBorderColor = PdfColor.fromInt(0xFFE0E0E0);
  const PdfColor kHeaderBg = PdfColor.fromInt(0xFFF5F7FA);

  // Load fonts
  final ttf = await PdfGoogleFonts.notoSansRegular();
  final ttfBold = await PdfGoogleFonts.notoSansBold();

  final taxType = invoice['tax_type'] as String? ?? 'CGST_SGST';
  final isInterstate = taxType == 'IGST';
  final companyName = company['name'] ?? 'Company Name';

  // --- Helper Styles ---
  final primaryTextStyle = pw.TextStyle(font: ttf, fontSize: 9, color: kDarkText);
  final boldTextStyle = pw.TextStyle(font: ttfBold, fontSize: 9, color: kDarkText);
  final mutedTextStyle = pw.TextStyle(font: ttf, fontSize: 8, color: kLightText);
  final headerStyle = pw.TextStyle(font: ttfBold, fontSize: 10, color: kPrimary);

  // --- Components ---

  // 1. Header
  pw.Widget _buildHeader() {
    final sellerName = company['name'] ?? 'Company Name';
    final addressLines = (company["address"] is List ? company["address"] : [company["address"]])
        .whereType<String>()
        .join(', ');
    final sellerGstin = company['gstin'] ?? 'N/A';
    final sellerEmail = company['email'] ?? 'N/A';

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logoBytes != null)
              pw.Container(
                height: 40,
                margin: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
              )
            else
              pw.Text(sellerName, style: pw.TextStyle(font: ttfBold, fontSize: 18, color: kPrimary)),
            
            pw.SizedBox(height: 4),
            pw.Text(addressLines, style: mutedTextStyle),
            pw.Text('GSTIN: $sellerGstin', style: mutedTextStyle),
            pw.Text('Email: $sellerEmail', style: mutedTextStyle),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text("TAX INVOICE", style: pw.TextStyle(font: ttfBold, fontSize: 16, color: kPrimary)),
            pw.SizedBox(height: 4),
            pw.Text("Original for Recipient", style: mutedTextStyle),
          ],
        ),
      ],
    );
  }

  // 2. Info Grid
  pw.Widget _buildInfoGrid() {
    final invoiceNo = invoice['invoice_number'] ?? '-';
    final invoiceDateStr = invoice['invoice_date'] != null
        ? dateFormat.format(DateTime.parse(invoice['invoice_date']))
        : '-';
    final buyerName = invoice['customer_name'] ?? 'N/A';
    final billingAddress = invoice['billing_address'] ?? 'N/A';
    final customerGstin = invoice['customer_gstin'] ?? 'N/A';

    return pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 20),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: kBorderColor),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Bill To
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text("BILL TO", style: headerStyle),
                pw.SizedBox(height: 4),
                pw.Text(buyerName, style: boldTextStyle),
                pw.Text(billingAddress, style: primaryTextStyle),
                if (customerGstin.isNotEmpty)
                  pw.Text("GSTIN: $customerGstin", style: primaryTextStyle),
              ],
            ),
          ),
          // Invoice Details
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text("INVOICE DETAILS", style: headerStyle),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.Text("Invoice No: ", style: mutedTextStyle),
                    pw.Text(invoiceNo, style: boldTextStyle),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.Text("Date: ", style: mutedTextStyle),
                    pw.Text(invoiceDateStr, style: boldTextStyle),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 3. Items Table
  pw.Widget _buildItemsTable() {
    final headers = ["#", "Item", "HSN", "Qty", "Rate", "Amount"];
    final columnWidths = {
      0: const pw.FlexColumnWidth(0.5),
      1: const pw.FlexColumnWidth(3),
      2: const pw.FlexColumnWidth(1),
      3: const pw.FlexColumnWidth(1),
      4: const pw.FlexColumnWidth(1.2),
      5: const pw.FlexColumnWidth(1.2),
    };

    return pw.Table(
      columnWidths: columnWidths,
      border: pw.TableBorder.all(color: kBorderColor),
      children: [
        // Header
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: kHeaderBg),
          children: headers.map((h) => pw.Padding(
            padding: const pw.EdgeInsets.all(8),
            child: pw.Text(h, style: boldTextStyle, textAlign: h == "Item" ? pw.TextAlign.left : pw.TextAlign.center),
          )).toList(),
        ),
        // Items
        ...items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          final qty = (item['qty'] as num?)?.toDouble() ?? 0.0;
          final rate = (item['rate'] as num?)?.toDouble() ?? 0.0;
          final amount = (item['taxable_amount'] as num?)?.toDouble() ?? 0.0;

          return pw.TableRow(
            children: [
              pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text("${i + 1}", style: primaryTextStyle, textAlign: pw.TextAlign.center)),
              pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(item['item_name'] ?? "", style: primaryTextStyle)),
              pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(item['hsn_code'] ?? "", style: primaryTextStyle, textAlign: pw.TextAlign.center)),
              pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(qty.toStringAsFixed(2), style: primaryTextStyle, textAlign: pw.TextAlign.center)),
              pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(rate.toStringAsFixed(2), style: primaryTextStyle, textAlign: pw.TextAlign.right)),
              pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(amount.toStringAsFixed(2), style: primaryTextStyle, textAlign: pw.TextAlign.right)),
            ],
          );
        }).toList(),
      ],
    );
  }

  // 4. Totals & Signature
  pw.Widget _buildFooterSection() {
    final subtotal = (invoice['subtotal'] as num?)?.toDouble() ?? 0.0;
    final cgst = (invoice['cgst_total'] as num?)?.toDouble() ?? 0.0;
    final sgst = (invoice['sgst_total'] as num?)?.toDouble() ?? 0.0;
    final igst = (invoice['igst_total'] as num?)?.toDouble() ?? 0.0;
    final grandTotal = (invoice['grand_total'] as num?)?.toDouble() ?? 0.0;
    final amountInWords = _localConvertNumberToWords(grandTotal);

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Left: Words & Signature
        pw.Expanded(
          flex: 6,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(height: 10),
              pw.Text("Amount in Words:", style: mutedTextStyle),
              pw.Text("INR $amountInWords Only", style: boldTextStyle),
              pw.SizedBox(height: 30),
              // Signature
              if (signatureBytes != null)
                pw.Container(
                  height: 50,
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Image(pw.MemoryImage(signatureBytes), fit: pw.BoxFit.contain),
                ),
              pw.SizedBox(height: 5),
              pw.Text("Authorised Signatory", style: mutedTextStyle),
              pw.Text("For $companyName", style: boldTextStyle),
            ],
          ),
        ),
        pw.SizedBox(width: 20),
        // Right: Totals
        pw.Expanded(
          flex: 4,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: kBorderColor),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              children: [
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text("Subtotal", style: primaryTextStyle),
                  pw.Text(subtotal.toStringAsFixed(2), style: primaryTextStyle),
                ]),
                if (!isInterstate) ...[
                  pw.SizedBox(height: 4),
                  pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                    pw.Text("CGST", style: primaryTextStyle),
                    pw.Text(cgst.toStringAsFixed(2), style: primaryTextStyle),
                  ]),
                  pw.SizedBox(height: 4),
                  pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                    pw.Text("SGST", style: primaryTextStyle),
                    pw.Text(sgst.toStringAsFixed(2), style: primaryTextStyle),
                  ]),
                ] else ...[
                  pw.SizedBox(height: 4),
                  pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                    pw.Text("IGST", style: primaryTextStyle),
                    pw.Text(igst.toStringAsFixed(2), style: primaryTextStyle),
                  ]),
                ],
                pw.Divider(color: kBorderColor),
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text("Grand Total", style: boldTextStyle),
                  pw.Text("₹ ${grandTotal.toStringAsFixed(2)}", style: pw.TextStyle(font: ttfBold, fontSize: 12, color: kPrimary)),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  return pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(30),
    build: (context) => [
      _buildHeader(),
      _buildInfoGrid(),
      _buildItemsTable(),
      pw.SizedBox(height: 20),
      _buildFooterSection(),
    ],
    footer: (context) => pw.Center(
      child: pw.Text("Powered by Smart Billing", style: mutedTextStyle),
    ),
  );
}
