import 'package:flutter/material.dart';
import '../../models/purchase_model.dart';
import '../../utils/app_theme.dart';

class SupplierSearchDialog extends StatefulWidget {
  final List<Supplier> suppliers;
  final String title;

  const SupplierSearchDialog({
    super.key,
    required this.suppliers,
    this.title = 'Select Supplier',
  });

  @override
  State<SupplierSearchDialog> createState() => _SupplierSearchDialogState();
}

class _SupplierSearchDialogState extends State<SupplierSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Supplier> _filteredSuppliers = [];

  @override
  void initState() {
    super.initState();
    _filteredSuppliers = widget.suppliers;
  }

  void _filterSuppliers(String query) {
    setState(() {
      _filteredSuppliers = widget.suppliers
          .where((s) =>
              s.name.toLowerCase().contains(query.toLowerCase()) ||
              s.gstin.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title, style: AppTheme.titleMedium),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              decoration: AppTheme.inputDecoration('Search by Name or GSTIN')
                  .copyWith(prefixIcon: const Icon(Icons.search)),
              onChanged: _filterSuppliers,
            ),
            const SizedBox(height: 10),
            Flexible(
              child: _filteredSuppliers.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text('No suppliers found', style: AppTheme.bodySmall),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _filteredSuppliers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final supplier = _filteredSuppliers[index];
                        return ListTile(
                          title: Text(supplier.name, style: AppTheme.bodyMedium),
                          subtitle: Text(
                            'GSTIN: ${supplier.gstin} • State: ${supplier.stateCode}',
                            style: AppTheme.bodySmall,
                          ),
                          onTap: () => Navigator.of(context).pop(supplier),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
