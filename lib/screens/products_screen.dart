import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart'; // For TextInputFormatter

// ======================================================================
// 1. DATA MODEL (Best Practice: Use a Model)
// ======================================================================
class ProductModel {
  final String id;
  final String name;
  final double rate;
  final String unit;
  final String hsnCode;
  final double stock;
  final double gstPercent;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  ProductModel({
    required this.id,
    required this.name,
    required this.rate,
    required this.unit,
    required this.hsnCode,
    required this.stock,
    required this.gstPercent,
    this.createdAt,
    this.updatedAt,
  });

  factory ProductModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return ProductModel(
      id: doc.id,
      name: data['name'] as String? ?? 'N/A',
      rate: (data['rate'] as num?)?.toDouble() ?? 0.0,
      unit: data['unit'] as String? ?? 'Unit',
      hsnCode: data['hsn_code'] as String? ?? '',
      stock: (data['stock'] as num?)?.toDouble() ?? 0.0,
      gstPercent: (data['gst_percent'] as num?)?.toDouble() ?? 0.0,
      createdAt: data['created_at'] as Timestamp?,
      updatedAt: data['updated_at'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'rate': rate,
      'unit': unit,
      'hsn_code': hsnCode,
      'stock': stock,
      'gst_percent': gstPercent,
      'updated_at': FieldValue.serverTimestamp(),
      if (createdAt == null) 'created_at': FieldValue.serverTimestamp(),
    };
  }
}

// ======================================================================
// 2. THEME CONSTANTS
// ======================================================================

const Color _primaryColor = Color(0xFF1F3A5F); // Deep Navy Blue
const Color _accentColor = Color(0xFF00A3A3); // Teal/Cyan Accent
const Color _deleteColor = Colors.redAccent;

// ======================================================================
// 3. PRODUCT SCREEN (Main Widget)
// ======================================================================

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({Key? key}) : super(key: key);

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  String? get _uid => _auth.currentUser?.uid;

  // New: Search controller and query
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() {
        _searchQuery = _searchCtrl.text;
      });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // --- Firestore Stream with Filtering ---
  Stream<QuerySnapshot<Map<String, dynamic>>> _getProducts() {
    if (_uid == null) return const Stream.empty();
    // Base query: All products ordered by name
    Query<Map<String, dynamic>> baseQuery = _firestore
        .collection('users')
        .doc(_uid)
        .collection('products')
        .orderBy('name');

    // Note: Firestore doesn't easily support 'contains' search on a single field
    // without manual filtering or more advanced indexing (like Algolia/Elasticsearch).
    // We'll stick to client-side filtering or a simpler prefix query for performance.

    // For now, we'll rely on client-side filtering in the StreamBuilder as it's common for small lists.
    return baseQuery.snapshots();
  }

  // --- Deletion Confirmation (Unchanged) ---
  Future<void> _deleteProduct(String id, String name) async {
    final bool confirm =
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Confirm Deletion"),
            content: Text("Are you sure you want to delete '$name'?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  "Cancel",
                  style: TextStyle(color: _primaryColor),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  "Delete",
                  style: TextStyle(color: _deleteColor),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      await _firestore
          .collection('users')
          .doc(_uid)
          .collection('products')
          .doc(id)
          .delete();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Product '$name' deleted.")));
      }
    }
  }

  // --- Reusable Input Decoration (Using Constants) ---
  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: _primaryColor.withOpacity(0.7)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: _primaryColor.withOpacity(0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _accentColor, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
    );
  }

  // ----------------------------------------------------------------------
  // 🏗️ BUILD METHOD
  // ----------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Product Inventory 📦"),
        centerTitle: true,
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60.0),
          // New: Search Bar
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: "Search products by name...",
                filled: true,
                fillColor: Colors.white.withOpacity(0.15),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white70),
                        onPressed: () {
                          _searchCtrl.clear();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _accentColor,
        foregroundColor: Colors.white,
        onPressed: () => showDialog(
          context: context,
          builder: (context) => ProductFormDialog(
            firestore: _firestore,
            uid: _uid,
            primaryColor: _primaryColor,
            accentColor: _accentColor,
            inputDecoration: _inputDecoration,
          ),
        ),
        icon: const Icon(Icons.add_shopping_cart_outlined),
        label: const Text("Add Product"),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _getProducts(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 80,
                    color: _primaryColor.withOpacity(0.5),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "No products found. Tap '+' to add one.",
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          // Convert documents to ProductModel list
          final allProducts = snapshot.data!.docs
              .map(ProductModel.fromFirestore)
              .toList();

          // Client-side filtering
          final filteredProducts = allProducts.where((product) {
            final query = _searchQuery.toLowerCase().trim();
            if (query.isEmpty) return true;
            return product.name.toLowerCase().contains(query);
          }).toList();

          if (filteredProducts.isEmpty && _searchQuery.isNotEmpty) {
            return Center(child: Text("No products match '$_searchQuery'"));
          }

          final docs = filteredProducts;

          return ListView.builder(
            itemCount: docs.length,
            padding: const EdgeInsets.only(
              top: 8,
              bottom: 80,
              left: 8,
              right: 8,
            ), // Add padding for FAB
            itemBuilder: (context, i) {
              final product = docs[i];

              return Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 4.0,
                  horizontal: 8.0,
                ),
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: _primaryColor.withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: _accentColor.withOpacity(0.1),
                      child: Icon(
                        Icons.inventory_2_rounded,
                        color: _accentColor,
                      ),
                    ),
                    title: Text(
                      product.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        // Use a consistent display format
                        Text(
                          "Rate: ₹${product.rate.toStringAsFixed(2)} / ${product.unit}",
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          "Stock: ${product.stock.toStringAsFixed(product.stock.truncateToDouble() == product.stock ? 0 : 2)} ${product.unit} | GST: ${product.gstPercent.toStringAsFixed(1)}%",
                          style: TextStyle(
                            fontSize: 12,
                            color: _primaryColor.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                    trailing: PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_vert,
                        color: _primaryColor.withOpacity(0.7),
                      ),
                      onSelected: (v) {
                        if (v == 'edit') {
                          showDialog(
                            context: context,
                            builder: (context) => ProductFormDialog(
                              product: product, // Pass the product model
                              firestore: _firestore,
                              uid: _uid,
                              primaryColor: _primaryColor,
                              accentColor: _accentColor,
                              inputDecoration: _inputDecoration,
                            ),
                          );
                        } else if (v == 'delete') {
                          _deleteProduct(product.id, product.name);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text("Edit")),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            "Delete",
                            style: TextStyle(color: _deleteColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ======================================================================
// 4. SEPARATE DIALOG WIDGET (Best Practice: State Management)
// ======================================================================

class ProductFormDialog extends StatefulWidget {
  final ProductModel? product;
  final FirebaseFirestore firestore;
  final String? uid;
  final Color primaryColor;
  final Color accentColor;
  final InputDecoration Function(String, IconData) inputDecoration;

  const ProductFormDialog({
    Key? key,
    this.product,
    required this.firestore,
    required this.uid,
    required this.primaryColor,
    required this.accentColor,
    required this.inputDecoration,
  }) : super(key: key);

  @override
  State<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _rateCtrl;
  late final TextEditingController _hsnCtrl;
  late final TextEditingController _stockCtrl;
  late final TextEditingController _gstCtrl;
  late String _selectedUnit;

  final List<String> _units = [
    "Unit",
    "Kg",
    "Piece",
    "Box",
    "Dozen",
    "Meter",
    "Liter",
  ];

  @override
  void initState() {
    super.initState();
    final data = widget.product;

    _nameCtrl = TextEditingController(text: data?.name);
    _rateCtrl = TextEditingController(
      text: data == null ? '' : data.rate.toString(),
    );
    _hsnCtrl = TextEditingController(text: data?.hsnCode);
    _stockCtrl = TextEditingController(
      text: data == null ? '' : data.stock.toString(),
    );
    _gstCtrl = TextEditingController(
      text: data == null ? '' : data.gstPercent.toString(),
    );
    _selectedUnit = data?.unit ?? "Unit";
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _rateCtrl.dispose();
    _hsnCtrl.dispose();
    _stockCtrl.dispose();
    _gstCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;
    if (widget.uid == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("User not logged in.")));
      }
      return;
    }

    final collectionRef = widget.firestore
        .collection('users')
        .doc(widget.uid)
        .collection('products');

    final productData = ProductModel(
      id: widget.product?.id ?? '', // Use existing ID or temporary empty string
      name: _nameCtrl.text.trim(),
      rate: double.tryParse(_rateCtrl.text) ?? 0.0,
      unit: _selectedUnit,
      hsnCode: _hsnCtrl.text.trim(),
      stock: double.tryParse(_stockCtrl.text) ?? 0.0,
      gstPercent: double.tryParse(_gstCtrl.text) ?? 0.0,
    );

    try {
      if (widget.product == null) {
        // Add new product
        await collectionRef.add(productData.toMap());
      } else {
        // Update existing product
        await collectionRef.doc(widget.product!.id).update(productData.toMap());
      }
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error saving product: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isEditing = widget.product != null;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: screenWidth * 0.8,
              maxHeight: screenHeight * 0.8, // limit to 80% of screen height
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // --- Title ---
                    Text(
                      isEditing ? "Edit Product" : "Add New Product",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: widget.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // --- Product Name ---
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: widget.inputDecoration(
                        "Product Name",
                        Icons.label_outline,
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? "Name is required"
                          : null,
                    ),
                    const SizedBox(height: 16),

                    // --- Rate & Unit Row ---
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _rateCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'^\d+\.?\d{0,2}'),
                              ),
                            ],
                            decoration: widget.inputDecoration(
                              "Rate (₹)",
                              Icons.attach_money,
                            ),
                            validator: (v) =>
                                v == null ||
                                    v.trim().isEmpty ||
                                    (double.tryParse(v) ?? 0) <= 0
                                ? "Rate is required"
                                : null,
                          ),
                        ),
                        const SizedBox(width: 10),

                        // --- Unit Dropdown with "Add UOM" option ---
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            value: _selectedUnit,
                            decoration: widget.inputDecoration(
                              "Unit",
                              Icons.unfold_more,
                            ),
                            items: [
                              ..._units.map(
                                (e) => DropdownMenuItem(
                                  value: e,
                                  child: Text(
                                    e,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              const DropdownMenuItem(
                                value: "__add_new__",
                                child: Text(
                                  "+ Add UOM",
                                  style: TextStyle(color: Colors.blue),
                                ),
                              ),
                            ],
                            onChanged: (v) async {
                              if (v == "__add_new__") {
                                await _showAddUOMDialog(context);
                              } else {
                                setState(() => _selectedUnit = v!);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // --- Stock & GST Row ---
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _stockCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'^\d+\.?\d{0,3}'),
                              ),
                            ],
                            decoration: widget.inputDecoration(
                              "Stock (Qty)",
                              Icons.inbox_outlined,
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? "Required"
                                : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _gstCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'^\d+\.?\d{0,2}'),
                              ),
                            ],
                            decoration: widget.inputDecoration(
                              "GST (%)",
                              Icons.percent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // --- HSN Code ---
                    TextFormField(
                      controller: _hsnCtrl,
                      decoration: widget.inputDecoration(
                        "HSN Code (Optional)",
                        Icons.qr_code_2,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 24),

                    // --- Buttons ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            "Cancel",
                            style: TextStyle(color: widget.primaryColor),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: _saveProduct,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.accentColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(isEditing ? "Save" : "Add"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // --- Helper: Show dialog to add new UOM ---
  Future<void> _showAddUOMDialog(BuildContext context) async {
    final TextEditingController uomCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Add New UOM"),
        content: TextField(
          controller: uomCtrl,
          decoration: const InputDecoration(
            labelText: "Enter new UOM",
            hintText: "e.g. Box, Packet, Meter",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              if (uomCtrl.text.trim().isNotEmpty) {
                setState(() {
                  _units.add(uomCtrl.text.trim());
                  _selectedUnit = uomCtrl.text.trim();
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }
}
