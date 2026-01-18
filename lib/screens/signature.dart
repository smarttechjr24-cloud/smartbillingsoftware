import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';
import 'package:smartbilling/utils/signature_repository.dart';

class SignatureScreen extends StatefulWidget {
  const SignatureScreen({super.key});

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  Uint8List? signatureBytes;
  bool isLoading = true;
  bool showEmptyBox = false;
  bool showReceiverSignature = false;

  final SignatureController _controller = SignatureController(
    penColor: Colors.black,
    penStrokeWidth: 3,
  );

  // Theme Colors
  final Color _backgroundColor = const Color(0xFFF5F7FA);
  final Color _primaryColor = const Color(0xFF1976D2);
  final Color _cardColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _loadSignature();
  }

  Future<void> _loadSignature() async {
    final bytes = await SignatureRepository.getSignature();
    if (mounted) {
      setState(() {
        signatureBytes = bytes;
        isLoading = false;
      });
    }
  }

  Future<void> pickFromGallery() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: ImageSource.gallery);
      if (file != null) {
        final bytes = await file.readAsBytes();
        await SignatureRepository.saveSignature(bytes);
        setState(() => signatureBytes = bytes);
        _showSnack("✅ Signature imported from Gallery");
      }
    } catch (e) {
      _showSnack("❌ Failed to pick image: $e");
    }
  }

  Future<void> pickFromCamera() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: ImageSource.camera);
      if (file != null) {
        final bytes = await file.readAsBytes();
        await SignatureRepository.saveSignature(bytes);
        setState(() => signatureBytes = bytes);
        _showSnack("✅ Signature captured from Camera");
      }
    } catch (e) {
      _showSnack("❌ Failed to capture image: $e");
    }
  }

  Future<void> createSignature() async {
    if (_controller.isEmpty) {
      _showSnack("⚠️ Please draw a signature first");
      return;
    }
    final bytes = await _controller.toPngBytes();
    if (bytes != null) {
      await SignatureRepository.saveSignature(bytes);
      setState(() => signatureBytes = bytes);
      _showSnack("✅ Signature saved successfully");
    }
  }

  Future<void> deleteSignature() async {
    await SignatureRepository.deleteSignature();
    setState(() => signatureBytes = null);
    _showSnack("🗑️ Signature deleted");
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black87,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: const Text("Signature Settings", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          if (signatureBytes != null)
            IconButton(
              onPressed: deleteSignature,
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: "Delete Signature",
            ),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: _primaryColor))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Current Signature Preview
                  const Text(
                    "Current Signature",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    height: 180,
                    decoration: BoxDecoration(
                      color: _cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: signatureBytes != null
                        ? Image.memory(signatureBytes!, fit: BoxFit.contain)
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.draw_outlined, size: 48, color: Colors.grey.shade300),
                              const SizedBox(height: 8),
                              Text(
                                "No signature saved",
                                style: TextStyle(color: Colors.grey.shade400),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 24),

                  // Actions
                  const Text(
                    "Actions",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const SizedBox(height: 12),
                  
                  _actionTile(
                    icon: Icons.edit,
                    color: Colors.blue,
                    title: "Draw Signature",
                    subtitle: "Create new signature by hand",
                    onTap: () {
                      _controller.clear();
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => _buildDrawSheet(),
                      );
                    },
                  ),
                  
                  _actionTile(
                    icon: Icons.camera_alt,
                    color: Colors.green,
                    title: "Capture from Camera",
                    subtitle: "Take a photo of your signature",
                    onTap: pickFromCamera,
                  ),
                  
                  _actionTile(
                    icon: Icons.photo_library,
                    color: Colors.purple,
                    title: "Import from Gallery",
                    subtitle: "Select image from gallery",
                    onTap: pickFromGallery,
                  ),

                  const SizedBox(height: 24),
                  
                  // Settings
                  const Text(
                    "Invoice Settings",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: _cardColor,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text("Show Empty Signature Box"),
                          subtitle: const Text("If no signature is set", style: TextStyle(fontSize: 12, color: Colors.grey)),
                          value: showEmptyBox,
                          activeColor: _primaryColor,
                          onChanged: (v) => setState(() => showEmptyBox = v),
                        ),
                        Divider(height: 1, color: Colors.grey.shade100),
                        SwitchListTile(
                          title: const Text("Receiver's Signature"),
                          subtitle: const Text("Add field for customer to sign", style: TextStyle(fontSize: 12, color: Colors.grey)),
                          value: showReceiverSignature,
                          activeColor: _primaryColor,
                          onChanged: (v) => setState(() => showReceiverSignature = v),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      ),
    );
  }

  Widget _buildDrawSheet() {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
                ),
                const Text(
                  "Draw Signature",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                TextButton(
                  onPressed: () async {
                    await createSignature();
                    Navigator.pop(context);
                  },
                  child: Text("Save", style: TextStyle(color: _primaryColor, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          
          // Drawing Area
          Expanded(
            child: Container(
              color: Colors.grey.shade50,
              child: Signature(
                controller: _controller,
                backgroundColor: Colors.transparent,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),
          
          // Tools
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: () => _controller.clear(),
                  icon: const Icon(Icons.refresh),
                  tooltip: "Clear",
                ),
                IconButton(
                  onPressed: () => _controller.undo(),
                  icon: const Icon(Icons.undo),
                  tooltip: "Undo",
                ),
                IconButton(
                  onPressed: () => _controller.redo(),
                  icon: const Icon(Icons.redo),
                  tooltip: "Redo",
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
