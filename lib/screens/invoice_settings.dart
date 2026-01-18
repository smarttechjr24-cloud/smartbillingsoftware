import 'package:flutter/material.dart';
import 'package:smartbilling/screens/invoice_theme.dart';
import 'package:smartbilling/screens/signature.dart';
import 'package:smartbilling/screens/pdftheme.dart';
import 'package:smartbilling/screens/invoice_number_prefix_screen.dart';
import 'package:smartbilling/screens/invoice_contact_screen.dart';
import 'package:smartbilling/screens/terms_conditions_screen.dart';
import 'package:smartbilling/screens/bank_account_screen.dart';

class InvoiceSettingsScreen extends StatefulWidget {
  const InvoiceSettingsScreen({super.key});

  @override
  State<InvoiceSettingsScreen> createState() => _InvoiceSettingsScreenState();
}

class _InvoiceSettingsScreenState extends State<InvoiceSettingsScreen> {
  bool loadingPreview = true;

  @override
  void initState() {
    super.initState();
    loadInvoicePreview();
  }

  Future<void> loadInvoicePreview() async {
    await Future.delayed(const Duration(milliseconds: 300)); // small delay
    setState(() => loadingPreview = false);
  }

  Widget _tile({
    required IconData icon,
    required String title,
    String? subtitle,
    bool isNew = false,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF1976D2)),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isNew)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                "NEW",
                style: TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          const SizedBox(width: 5),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Invoice Settings"),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),

      body: SingleChildScrollView(
        child: Column(
          children: [
            // ------------------------------
            // 🔥 TOP PREVIEW BANNER
            // ------------------------------
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(15),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.lightGreen.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.greenAccent),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          "NEW",
                          style: TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        "Create your own Invoice Theme",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: loadingPreview
                        ? Container(
                            height: 180,
                            alignment: Alignment.center,
                            child: const CircularProgressIndicator(),
                          )
                        : Image.asset(
                            "assets/pdf.png", // <-- your static PNG
                            height: 180,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                  ),
                ],
              ),
            ),

            // ------------------------------------
            // 🔥 SETTINGS OPTIONS
            // ------------------------------------
            _tile(
              icon: Icons.article,
              title: "Generate e-Way Bills & e-Invoices",
              subtitle: "Directly generate GST invoice documents",
            ),
            _tile(
              icon: Icons.color_lens,
              title: "Theme & Color",
              isNew: true,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => InvoiceThemeScreen()),
                );
              },
            ),

            _tile(
              icon: Icons.format_list_numbered,
              title: "Invoice Number Prefix",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const InvoiceNumberPrefixScreen(),
                  ),
                );
              },
            ),
            _tile(
              icon: Icons.phone,
              title: "Phone Number on Invoice",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const InvoiceContactScreen(),
                  ),
                );
              },
            ),
            _tile(
              icon: Icons.email,
              title: "Email on Invoice",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const InvoiceContactScreen(),
                  ),
                );
              },
            ),
            _tile(
              icon: Icons.description,
              title: "Terms and Conditions",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TermsConditionsScreen(),
                  ),
                );
              },
            ),
            _tile(
              icon: Icons.edit,
              title: "Signature",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SignatureScreen(),
                  ),
                );
              },
            ),
            _tile(
              icon: Icons.picture_as_pdf,
              title: "PDF Template",
              subtitle: "Choose invoice PDF design",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PdfThemeScreen(),
                  ),
                );
              },
            ),

            _tile(
              icon: Icons.account_balance,
              title: "Bank Account on Invoice",
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BankAccountScreen(),
                  ),
                );
              },
            ),
            _tile(
              icon: Icons.discount,
              title: "Discount Type",
              subtitle: "Discount After Tax",
            ),
          ],
        ),
      ),
    );
  }
}
