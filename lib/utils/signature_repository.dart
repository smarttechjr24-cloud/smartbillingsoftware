import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

class SignatureRepository {
  static const String _fileName = 'signature.png';

  /// Get the local file path for the signature
  static Future<File> _getFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  /// Save signature bytes to file
  static Future<void> saveSignature(Uint8List bytes) async {
    final file = await _getFile();
    await file.writeAsBytes(bytes);
  }

  /// Load signature bytes from file
  static Future<Uint8List?> getSignature() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (e) {
      // Ignore errors if file doesn't exist or can't be read
    }
    return null;
  }

  /// Delete signature file
  static Future<void> deleteSignature() async {
    final file = await _getFile();
    if (await file.exists()) {
      await file.delete();
    }
  }
}
