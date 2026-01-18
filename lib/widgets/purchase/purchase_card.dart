import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/purchase_model.dart';
import '../../utils/app_theme.dart';

class PurchaseCard extends StatelessWidget {
  final PurchaseModel purchase;
  final VoidCallback? onView;
  final VoidCallback? onEdit;
  final VoidCallback? onAddPayment;
  final Function(PurchaseModel) onDelete;

  const PurchaseCard({
    super.key,
    required this.purchase,
    this.onView,
    this.onEdit,
    this.onAddPayment,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final statusConfig = _getStatusConfig(purchase.paymentStatus);
    final isOverdue = purchase.isOverdue;
    final dateFormat = DateFormat('dd MMM yyyy');
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Dismissible(
        key: ValueKey(purchase.id),
        direction: DismissDirection.endToStart,
        background: _buildDeleteBackground(),
        confirmDismiss: (_) => _confirmDelete(context),
        child: Container(
          decoration: BoxDecoration(
            color: isOverdue ? const Color(0xFFFFF2F2) : AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: isOverdue
                ? Border.all(color: AppTheme.danger.withOpacity(0.5), width: 1)
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Calculate widths based on available space
                  final availableWidth = constraints.maxWidth;
                  final amountWidth = availableWidth * 0.30; // 30% for amount

                  return Row(
                    children: [
                      // Status Indicator Strip
                      Container(
                        width: 4,
                        height: 50,
                        decoration: BoxDecoration(
                          color: statusConfig.color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Main Content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              purchase.supplierName,
                              style: AppTheme.titleMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.receipt_long,
                                    size: 14, color: AppTheme.textSecondary),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    purchase.invoiceNumber,
                                    style: AppTheme.bodySmall,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.calendar_today,
                                    size: 14, color: AppTheme.textSecondary),
                                const SizedBox(width: 4),
                                Text(
                                  dateFormat.format(purchase.purchaseDate),
                                  style: AppTheme.bodySmall,
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            // Payment Status Badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: statusConfig.color.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: statusConfig.color.withOpacity(0.3)),
                              ),
                              child: Text(
                                statusConfig.label,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: statusConfig.color,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Amount Column with constrained width
                      SizedBox(
                        width: amountWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              currencyFormat.format(purchase.totalAmount),
                              style: AppTheme.titleMedium.copyWith(
                                color: AppTheme.primary,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              textAlign: TextAlign.right,
                            ),
                            if (purchase.outstandingAmount > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Due: ${currencyFormat.format(purchase.outstandingAmount)}',
                                  style: AppTheme.bodySmall.copyWith(
                                    color: AppTheme.danger,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  textAlign: TextAlign.right,
                                ),
                              ),
                          ],
                        ),
                      ),

                      // Three-dot Menu
                      SizedBox(
                        width: 32,
                        child: PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
                          onSelected: (value) {
                            switch (value) {
                              case 'view':
                                onView?.call();
                                break;
                              case 'edit':
                                onEdit?.call();
                                break;
                              case 'payment':
                                onAddPayment?.call();
                                break;
                              case 'delete':
                                _showDeleteDialog(context);
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'view',
                              child: Row(
                                children: [
                                  Icon(Icons.visibility, size: 20, color: AppTheme.primary),
                                  SizedBox(width: 12),
                                  Text('View Details'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit, size: 20, color: Colors.blue),
                                  SizedBox(width: 12),
                                  Text('Edit'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'payment',
                              child: Row(
                                children: [
                                  Icon(Icons.payment, size: 20, color: Colors.green),
                                  SizedBox(width: 12),
                                  Text('Add Payment'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete, size: 20, color: AppTheme.danger),
                                  SizedBox(width: 12),
                                  Text('Delete'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Purchase'),
        content: const Text('Are you sure you want to delete this purchase?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      onDelete(purchase);
    }
  }

  Widget _buildDeleteBackground() {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      decoration: BoxDecoration(
        color: AppTheme.danger,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.delete, color: Colors.white),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Purchase'),
        content: const Text('Are you sure you want to delete this purchase?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              onDelete(purchase);
              Navigator.pop(context, true);
            },
            child: const Text('Delete', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
  }

  _StatusConfig _getStatusConfig(PurchasePaymentStatus status) {
    switch (status) {
      case PurchasePaymentStatus.paid:
        return _StatusConfig('Paid', AppTheme.success);
      case PurchasePaymentStatus.partial:
        return _StatusConfig('Partial', AppTheme.warning);
      case PurchasePaymentStatus.outstanding:
        return _StatusConfig('Unpaid', AppTheme.danger);
    }
  }
}

class _StatusConfig {
  final String label;
  final Color color;
  _StatusConfig(this.label, this.color);
}
