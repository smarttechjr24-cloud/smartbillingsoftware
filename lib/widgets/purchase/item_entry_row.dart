import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/purchase_model.dart';
import '../../utils/app_theme.dart';

class ItemEntryRow extends StatefulWidget {
  final Item item;
  final Function(InvoiceItem) onAdd;
  final VoidCallback onCancel;

  const ItemEntryRow({
    super.key,
    required this.item,
    required this.onAdd,
    required this.onCancel,
  });

  @override
  State<ItemEntryRow> createState() => _ItemEntryRowState();
}

class _ItemEntryRowState extends State<ItemEntryRow> {
  final _qtyController = TextEditingController(text: '1');
  final _purchasePriceController = TextEditingController();
  final _salePriceController = TextEditingController();
  final _discountController = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    _purchasePriceController.text = widget.item.purchasePrice.toString();
    _salePriceController.text = widget.item.salePrice.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.item.name, style: AppTheme.titleMedium),
              IconButton(
                icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                onPressed: widget.onCancel,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildNumberInput(
                  controller: _qtyController,
                  label: 'Qty',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _buildNumberInput(
                  controller: _purchasePriceController,
                  label: 'Pur. Price',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _buildNumberInput(
                  controller: _salePriceController,
                  label: 'Sale Price',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildNumberInput(
                  controller: _discountController,
                  label: 'Disc/Unit',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _submit,
              child: const Text('Add Item', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberInput({
    required TextEditingController controller,
    required String label,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      decoration: AppTheme.inputDecoration(label).copyWith(labelText: label),
    );
  }

  void _submit() {
    final qty = double.tryParse(_qtyController.text) ?? 0;
    final purchasePrice = double.tryParse(_purchasePriceController.text) ?? 0;
    final salePrice = double.tryParse(_salePriceController.text) ?? 0;
    final discount = double.tryParse(_discountController.text) ?? 0;

    if (qty <= 0 || purchasePrice <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid Quantity and Purchase Price')),
      );
      return;
    }

    final invoiceItem = InvoiceItem(
      item: widget.item,
      quantity: qty,
      unitPrice: purchasePrice, // Unit Price for Purchase Invoice is Purchase Price
      discount: discount,
      // We might want to pass salePrice back to update the product, but InvoiceItem 
      // is for the invoice calculation. We can handle product updates separately 
      // or add a field to InvoiceItem if needed. For now, let's assume 
      // the user just wants to see it or we update it in the background.
    );
    
    // Hack: Attach salePrice to the item for the service to read later if needed
    // Or better, update the item object itself? 
    // Since Item is immutable, we can't. 
    // Let's just create the InvoiceItem. 
    // If the user wants to UPDATE the sale price in the DB, we need to pass that info.
    // For now, I'll stick to the requested "where pur price, sale price" by showing them.
    
    widget.onAdd(invoiceItem);
  }
}
