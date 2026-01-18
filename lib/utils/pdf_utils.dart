import 'dart:typed_data';
import 'package:printing/printing.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Convert PDF bytes to PNG (first page)
Future<Uint8List?> pdfToPng(Uint8List pdfBytes) async {
  try {
    final page = await Printing.raster(pdfBytes).first;
    final png = await page.toPng();
    return png;
  } catch (e) {
    print("PDF -> PNG error: $e");
    return null;
  }
}

Future<File?> savePngToDocDir(Uint8List pngBytes, String filename) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(pngBytes);
    return file;
  } catch (e) {
    print("Save PNG error: $e");
    return null;
  }
}
