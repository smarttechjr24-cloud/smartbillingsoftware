import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class InvoiceThemeScreen extends StatefulWidget {
  final String? selectedTheme; // A, B, C, D
  const InvoiceThemeScreen({super.key, this.selectedTheme});

  @override
  State<InvoiceThemeScreen> createState() => _InvoiceThemeScreenState();
}

class _InvoiceThemeScreenState extends State<InvoiceThemeScreen> {
  String? currentTheme;

  @override
  void initState() {
    super.initState();
    currentTheme = widget.selectedTheme ?? "A";
  }

  // 🔥 Template List
  final List<Map<String, String>> templates = [
    {"key": "A", "img": "assets/templates/templatea.png"},
    {"key": "B", "img": "assets/templates/templateb.png"},
    {"key": "C", "img": "assets/templates/templatec.png"},
    {"key": "D", "img": "assets/templates/templated.png"},
  ];

  // Category Buttons (Modern, Luxury, Stylish...)
  final List<String> categories = ["Modern", "Luxury", "Stylish", "Advanced"];
  String selectedCategory = "Modern";

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
      currentTheme = template;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Template $template selected")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Theme & Color"),
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),

      body: Column(
        children: [
          const SizedBox(height: 15),

          // ---------------------- THEME PREVIEW ----------------------
          Text(
            "Preview",
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          Expanded(
            flex: 5,
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.07),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    templates.firstWhere(
                          (t) => t["key"] == currentTheme,
                        )["img"] ??
                        "",
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text(
                  "Theme Styling",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Chip(
                  backgroundColor: primary.withOpacity(0.1),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(selectedCategory, style: TextStyle(color: primary)),
                      const SizedBox(width: 5),
                      const Icon(Icons.close, size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 5),

          // ---------------------- CATEGORY BUTTONS ----------------------
          SizedBox(
            height: 45,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              itemBuilder: (context, index) {
                String category = categories[index];
                bool isActive = category == selectedCategory;

                return GestureDetector(
                  onTap: () {
                    setState(() => selectedCategory = category);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isActive ? primary : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Row(
                      children: [
                        Text(
                          category,
                          style: TextStyle(
                            color: isActive ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (category == "Luxury")
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              "NEW",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemCount: categories.length,
            ),
          ),

          const SizedBox(height: 15),

          // ---------------------- THEMES ROW ----------------------
          SizedBox(
            height: 160,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              itemCount: templates.length,
              separatorBuilder: (_, __) => const SizedBox(width: 15),
              itemBuilder: (context, index) {
                final theme = templates[index];
                final isSelected = currentTheme == theme["key"];

                return GestureDetector(
                  onTap: () {
                    setState(() => currentTheme = theme["key"]);
                  },
                  child: Container(
                    width: 130,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isSelected ? primary : Colors.grey.shade300,
                        width: isSelected ? 3 : 1,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(theme["img"]!, fit: BoxFit.cover),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 20),

          // ---------------------- APPLY BUTTON ----------------------
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () async {
                // Save to database
                await saveTemplate(currentTheme!);
                // Return the selected theme
                if (mounted) {
                  Navigator.pop(context, currentTheme);
                }
              },
              child: const Text("Apply Theme", style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}
