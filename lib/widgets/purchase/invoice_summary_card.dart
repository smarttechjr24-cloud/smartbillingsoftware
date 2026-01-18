import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/purchase_model.dart';
import '../../utils/app_theme.dart';

class InvoiceSummaryCard extends StatelessWidget {
  final TaxTotals totals;

  const InvoiceSummaryCard({super.key, required this.totals});

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration.copyWith(
        color: AppTheme.background,
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          _buildRow('Taxable Amount', totals.totalTaxable, currencyFormat),
          if (totals.totalDiscount > 0)
            _buildRow('Total Discount', -totals.totalDiscount, currencyFormat,
                color: AppTheme.success),
          const Divider(height: 24),
          if (totals.cgstTotal > 0)
            _buildRow('CGST', totals.cgstTotal, currencyFormat),
          if (totals.sgstTotal > 0)
            _buildRow('SGST', totals.sgstTotal, currencyFormat),
          if (totals.igstTotal > 0)
            _buildRow('IGST', totals.igstTotal, currencyFormat),
          const Divider(height: 24),
          _buildRow('Grand Total', totals.grandTotal, currencyFormat,
              isBold: true, size: 18, color: AppTheme.primary),
        ],
      ),
    );
  }

  Widget _buildRow(String label, double amount, NumberFormat format,
      {bool isBold = false, double size = 14, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: size,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: AppTheme.textSecondary,
            ),
          ),
          Text(
            format.format(amount),
            style: TextStyle(
              fontSize: size,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color ?? AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
