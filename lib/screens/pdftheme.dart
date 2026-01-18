import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/pdf_preview_service.dart';
import '../utils/template_preview_generator.dart';

class PdfThemeScreen extends StatefulWidget {
  const PdfThemeScreen({super.key});

  @override
  State<PdfThemeScreen> createState() => _PdfThemeScreenState();
}

class _PdfThemeScreenState extends State<PdfThemeScreen> {
  String selectedTemplate = "A"; // Default
  bool loading = true;
  
  // Map to store preview image paths for each template
  final Map<String, String?> _previewPaths = {};
  final Map<String, bool> _generatingPreviews = {};

  // ----------------------------
  // OPEN SQLITE
  // ----------------------------
  Future<Database> openDb() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, "smartbilling.db");
    return openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, _) async {
        await db.execute("""
          CREATE TABLE IF NOT EXISTS invoice_theme (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            theme TEXT
          );
        """);
      },
    );
  }

  // ----------------------------
  // LOAD SAVED TEMPLATE
  // ----------------------------
  Future<void> loadSelectedTemplate() async {
    // Show UI immediately with default template
    setState(() => loading = false);
    
    // Try loading from Firestore in background
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('settings')
            .doc('invoice')
            .get()
            .timeout(const Duration(seconds: 3)); // Add timeout
        
        if (doc.exists && doc.data()?['template'] != null) {
          setState(() {
            selectedTemplate = doc.data()!['template'];
          });
          return;
        }
      }
    } catch (e) {
      debugPrint("Error loading template from Firestore: $e");
    }

    // Fallback to SQLite
    try {
      final db = await openDb();
      final result = await db.query("invoice_theme", limit: 1);

      if (result.isNotEmpty) {
        setState(() {
          selectedTemplate = result.first["theme"] as String;
        });
      }
    } catch (e) {
      debugPrint("Error loading template from SQLite: $e");
    }
  }

  // ----------------------------
  // SAVE SELECTED TEMPLATE
  // ----------------------------
  Future<void> saveTemplate(String template) async {
    // Save to Firestore
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('settings')
            .doc('invoice')
            .set({'template': template}, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint("Error saving template to Firestore: $e");
    }

    // Save to SQLite (Local Cache)
    final db = await openDb();
    await db.delete("invoice_theme");
    await db.insert("invoice_theme", {"theme": template});

    setState(() {
      selectedTemplate = template;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("Template $template selected")));
  }

  @override
  void initState() {
    super.initState();
    loadSelectedTemplate();
    // Load previews after the first frame to ensure UI context is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllPreviews();
    });
  }

  /// Load preview images for all templates
  Future<void> _loadAllPreviews() async {
    final templates = PdfPreviewService.getAvailableTemplates();
    debugPrint('📋 Loading previews for templates: $templates');
    
    // Load previews in parallel for faster loading
    final futures = templates.map((template) => _loadPreviewForTemplate(template));
    await Future.wait(futures);
    
    debugPrint('✅ Finished loading all previews');
    
    // Force a rebuild to show the previews
    if (mounted) {
      setState(() {});
    }
  }

  /// Load preview image for a specific template
  Future<void> _loadPreviewForTemplate(String templateId) async {
    if (_generatingPreviews[templateId] == true) {
      debugPrint('⏳ Preview already generating for $templateId');
      return;
    }
    
    debugPrint('🔄 Loading preview for template $templateId');
    if (mounted) {
      setState(() {
        _generatingPreviews[templateId] = true;
      });
    }

    try {
      // Generate preview on UI thread to ensure picture.toImage() works
      final imagePath = await _generatePreviewOnUIThread(templateId);
      debugPrint('📸 Preview path for $templateId: $imagePath');
      
      if (mounted) {
        // Verify file exists before updating state
        bool fileExists = false;
        if (imagePath != null && imagePath.isNotEmpty) {
          final file = File(imagePath);
          fileExists = await file.exists();
          debugPrint('📁 File exists check for $templateId: $fileExists, path: $imagePath');
          
          if (fileExists) {
            final fileSize = await file.length();
            debugPrint('📏 File size for $templateId: $fileSize bytes');
          } else {
            debugPrint('⚠️ File does not exist at: $imagePath');
          }
        }
        
        setState(() {
          _previewPaths[templateId] = fileExists ? imagePath : null;
          _generatingPreviews[templateId] = false;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error loading preview for $templateId: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _previewPaths[templateId] = null;
          _generatingPreviews[templateId] = false;
        });
      }
    }
  }

  /// Generate preview on UI thread
  Future<String?> _generatePreviewOnUIThread(String templateId) async {
    // Ensure we're on the UI thread
    await Future.delayed(Duration.zero);
    
    // Try to get existing preview first
    final existingPath = await PdfPreviewService.getPreviewImagePath(templateId);
    if (existingPath != null) {
      final file = File(existingPath);
      if (await file.exists()) {
        return existingPath;
      }
    }
    
    // Generate new preview (this will call TemplatePreviewGenerator which needs UI context)
    return await TemplatePreviewGenerator.generatePreview(templateId);
  }

  /// Regenerate preview for a template
  Future<void> _regeneratePreview(String templateId) async {
    setState(() {
      _generatingPreviews[templateId] = true;
      _previewPaths[templateId] = null;
    });

    try {
      final imagePath = await PdfPreviewService.regeneratePreview(templateId);
      if (mounted) {
        setState(() {
          _previewPaths[templateId] = imagePath;
          _generatingPreviews[templateId] = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Preview regenerated for Template $templateId')),
        );
      }
    } catch (e) {
      debugPrint('Error regenerating preview for $templateId: $e');
      if (mounted) {
        setState(() {
          _generatingPreviews[templateId] = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to regenerate preview: $e')),
        );
      }
    }
  }

  // ----------------------------
  // BUILD TEMPLATE CARD
  // ----------------------------
  Widget templateCard({
    required String title,
    required String templateId,
    required String description,
  }) {
    final isSelected = (selectedTemplate == templateId);
    final previewPath = _previewPaths[templateId];
    final isGenerating = _generatingPreviews[templateId] ?? false;

    return InkWell(
      onTap: () => saveTemplate(templateId),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? const Color(0xFF1976D2) : Colors.grey.shade300,
            width: isSelected ? 3 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? const Color(0xFF1976D2).withOpacity(0.15)
              : Colors.white,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF1976D2).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // PDF Preview Image with selection overlay
            Stack(
              children: [
                Container(
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF1976D2) : Colors.grey.shade300,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: _buildPreviewImage(previewPath, isGenerating, templateId),
                  ),
                ),
                if (isSelected)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1976D2),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                // Regenerate button
                Positioned(
                  top: 8,
                  left: 8,
                  child: Material(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      onTap: () => _regeneratePreview(templateId),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          isGenerating ? Icons.refresh : Icons.refresh,
                          size: 18,
                          color: isGenerating ? Colors.grey : Colors.blue.shade700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Title + Selected badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? const Color(0xFF1976D2) : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected ? const Color(0xFF1976D2).withOpacity(0.8) : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1976D2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text(
                          "SELECTED",
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Build preview image widget
  Widget _buildPreviewImage(String? imagePath, bool isGenerating, String templateId) {
    if (isGenerating) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 8),
            Text(
              'Generating preview...',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (imagePath != null && imagePath.isNotEmpty) {
      final file = File(imagePath);
      final exists = file.existsSync();
      debugPrint('📁 Preview file check for $templateId: exists=$exists, path=$imagePath');
      
      if (exists) {
        try {
          // Verify file is readable and has content
          final fileSize = file.lengthSync();
          debugPrint('📏 Preview file size for $templateId: $fileSize bytes');
          
          if (fileSize > 0) {
            return Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                debugPrint('❌ Error loading preview image for $templateId: $error');
                debugPrint('Stack trace: $stackTrace');
                return _buildFallbackPreview(templateId);
              },
            );
          } else {
            debugPrint('⚠️ Preview file is empty for $templateId');
          }
        } catch (e) {
          debugPrint('❌ Exception loading preview for $templateId: $e');
        }
      } else {
        debugPrint('⚠️ Preview file does not exist: $imagePath');
      }
    } else {
      debugPrint('⚠️ No preview path for template $templateId');
    }

    // Fallback to mockup if preview not available
    return _buildFallbackPreview(templateId);
  }

  /// Fallback preview (mockup) when PDF preview is not available
  Widget _buildFallbackPreview(String templateId) {
    switch (templateId) {
      case 'A':
        return _buildTemplateAMockup();
      case 'B':
        return _buildTemplateBMockup();
      case 'C':
        return _buildTemplateCMockup();
      case 'E':
        return _buildTemplateDMockup();
      default:
        return _buildTemplateAMockup();
    }
  }

  Widget _buildTemplateAMockup() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.blue.shade700, width: 2)),
            ),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  color: Colors.blue.shade100,
                ),
                const SizedBox(width: 4),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(width: 60, height: 3, color: Colors.blue.shade700),
                    const SizedBox(height: 2),
                    Container(width: 40, height: 2, color: Colors.grey.shade400),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Info boxes
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 30,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    color: Colors.grey.shade50,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Container(
                  height: 30,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    color: Colors.grey.shade50,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Items table
          Container(
            height: 50,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              children: [
                Container(
                  height: 12,
                  color: Colors.grey.shade200,
                ),
                Expanded(
                  child: Row(
                    children: List.generate(
                      5,
                      (index) => Expanded(
                        child: Container(
                          margin: const EdgeInsets.all(2),
                          color: Colors.grey.shade100,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Totals
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: 60,
              height: 20,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                color: Colors.blue.shade50,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateBMockup() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          // Centered Header
          Column(
            children: [
              Container(
                width: 20,
                height: 20,
                color: Colors.green.shade100,
              ),
              const SizedBox(height: 2),
              Container(width: 60, height: 3, color: Colors.green.shade700),
              const SizedBox(height: 1),
              Container(width: 40, height: 2, color: Colors.grey.shade400),
              const SizedBox(height: 2),
              Container(
                width: double.infinity,
                height: 2,
                color: Colors.green.shade700,
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Info boxes
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 30,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    color: Colors.grey.shade50,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Container(
                  height: 30,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    color: Colors.grey.shade50,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Items table
          Container(
            height: 50,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              children: [
                Container(
                  height: 12,
                  color: Colors.green.shade100,
                ),
                Expanded(
                  child: Row(
                    children: List.generate(
                      5,
                      (index) => Expanded(
                        child: Container(
                          margin: const EdgeInsets.all(2),
                          color: Colors.grey.shade100,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Totals
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: 60,
              height: 20,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                color: Colors.green.shade50,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateCMockup() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Premium header with gradient
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple.shade700, Colors.purple.shade400],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: 60, height: 3, color: Colors.white),
                      const SizedBox(height: 2),
                      Container(width: 40, height: 2, color: Colors.white70),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Info boxes with accent
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 30,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.purple.shade200),
                    color: Colors.purple.shade50,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Container(
                  height: 30,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.purple.shade200),
                    color: Colors.purple.shade50,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Items table
          Container(
            height: 50,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.purple.shade200),
            ),
            child: Column(
              children: [
                Container(
                  height: 12,
                  color: Colors.purple.shade100,
                ),
                Expanded(
                  child: Row(
                    children: List.generate(
                      5,
                      (index) => Expanded(
                        child: Container(
                          margin: const EdgeInsets.all(2),
                          color: Colors.grey.shade100,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Totals
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: 60,
              height: 20,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.purple.shade100, Colors.purple.shade50],
                ),
                border: Border.all(color: Colors.purple.shade300),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateDMockup() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Modern minimal header
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.orange.shade600,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(width: 4),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: 50, height: 3, color: Colors.orange.shade700),
                  const SizedBox(height: 2),
                  Container(width: 35, height: 2, color: Colors.grey.shade400),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Clean info layout
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: Colors.orange.shade600, width: 3),
              ),
              color: Colors.grey.shade50,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(height: 25, color: Colors.transparent),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Minimal table
          Container(
            height: 55,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300, width: 0.5),
            ),
            child: Column(
              children: [
                Container(
                  height: 10,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.orange.shade600, width: 2),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Row(
                      children: List.generate(
                        4,
                        (index) => Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            color: Colors.grey.shade100,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Clean totals
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: 55,
              height: 18,
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                border: Border(
                  top: BorderSide(color: Colors.orange.shade600, width: 2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Choose Invoice Theme"),
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF5F7FA),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Responsive grid: 1 column on mobile, 2 columns on tablet/desktop
          final crossAxisCount = constraints.maxWidth > 600 ? 2 : 1;
          final templates = [
            {
              'title': 'Template A',
              'id': 'A',
              'description': 'Standard GST layout with left-aligned header',
            },
            {
              'title': 'Template B',
              'id': 'B',
              'description': 'Minimal design with centered header',
            },
            {
              'title': 'Template C',
              'id': 'C',
              'description': 'Premium blue with gradient header',
            },
            {
              'title': 'Template E',
              'id': 'E',
              'description': 'Modern minimal with clean lines',
            },
          ];

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: crossAxisCount == 1
                ? Column(
                    children: templates.map((t) {
                      return templateCard(
                        title: t['title']!,
                        templateId: t['id']!,
                        description: t['description']!,
                      );
                    }).toList(),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.75,
                      ),
                      itemCount: templates.length,
                      itemBuilder: (context, index) {
                        final t = templates[index];
                        return templateCard(
                          title: t['title']!,
                          templateId: t['id']!,
                          description: t['description']!,
                        );
                      },
                    ),
                  ),
          );
        },
      ),
    );
  }
}
