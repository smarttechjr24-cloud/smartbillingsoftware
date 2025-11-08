import 'dart:io';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> generateDeliveryChallanPDF(
  Map<String, dynamic> challanData,
) async {
  final pdf = pw.Document();
  final df = DateFormat("dd MMM yyyy");
  final date = df.format(DateTime.now());
  final challanNo =
      challanData['challan_no'] ??
      "DC-${DateTime.now().millisecondsSinceEpoch}";
  final customer = challanData['customer_name'] ?? '-';
  final address = challanData['address'] ?? '-';
  final contact = challanData['contact'] ?? '-';
  final items = List<Map<String, dynamic>>.from(challanData['items'] ?? []);
  final remarks = challanData['remarks'] ?? '';

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // 🔹 HEADER
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      "SMART BILLING SOFTWARE",
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue800,
                      ),
                    ),
                    pw.Text(
                      "Delivery Challan",
                      style: pw.TextStyle(
                        fontSize: 13,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      "Challan No: $challanNo",
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text("Date: $date"),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Divider(thickness: 1),

            // 🔹 CUSTOMER DETAILS
            pw.Text(
              "Customer Details",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text("Name: $customer"),
                  pw.Text("Address: $address"),
                  pw.Text("Contact: $contact"),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // 🔹 ITEMS TABLE
            pw.Text(
              "Delivered Items",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
            ),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              columnWidths: const {
                0: pw.FlexColumnWidth(0.7),
                1: pw.FlexColumnWidth(3),
                2: pw.FlexColumnWidth(1),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(
                        "S.No",
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(
                        "Item Description",
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(
                        "Qty",
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                ...List.generate(items.length, (i) {
                  final item = items[i];
                  return pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text("${i + 1}"),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(item['item'] ?? '-'),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                          (item['qty'] ?? 0).toString().replaceAll('.0', ''),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),

            pw.SizedBox(height: 20),

            // 🔹 REMARKS
            if (remarks.isNotEmpty) ...[
              pw.Text(
                "Remarks:",
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              pw.Text(remarks),
              pw.SizedBox(height: 20),
            ],

            pw.Divider(thickness: 1),

            // 🔹 SIGNATURES
            pw.SizedBox(height: 20),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  children: [
                    pw.Container(height: 40),
                    pw.Text(
                      "Receiver’s Signature",
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Container(height: 40),
                    pw.Text(
                      "Authorized Signature",
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Center(
              child: pw.Text(
                "Generated by SmartBilling Software",
                style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
              ),
            ),
          ],
        );
      },
    ),
  );

  // ✅ Save & Share
  final dir = await getTemporaryDirectory();
  final file = File("${dir.path}/DeliveryChallan_$challanNo.pdf");
  await file.writeAsBytes(await pdf.save());
  await Share.shareXFiles([XFile(file.path)], text: "Delivery Challan");
}
