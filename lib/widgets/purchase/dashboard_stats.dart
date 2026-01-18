import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import '../../utils/app_theme.dart';

class DashboardStats extends StatelessWidget {
  final double totalPurchases;
  final double totalOutstanding;
  final double overdueAmount;
  final bool isLoading;

  const DashboardStats({
    super.key,
    required this.totalPurchases,
    required this.totalOutstanding,
    required this.overdueAmount,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return _buildShimmer();
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: AppTheme.cardDecoration,
      child: Row(
        children: [
          _buildMetricItem(
            'Total Purchases',
            totalPurchases,
            AppTheme.primary,
            isCurrency: false,
          ),
          _buildDivider(),
          _buildMetricItem(
            'Outstanding',
            totalOutstanding,
            AppTheme.danger,
            isCurrency: true,
          ),
          _buildDivider(),
          _buildMetricItem(
            'Overdue',
            overdueAmount,
            AppTheme.warning,
            isCurrency: true,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem(
    String label,
    double value,
    Color color, {
    bool isCurrency = true,
  }) {
    final currencyFormat = NumberFormat.compactCurrency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );

    return Expanded(
      child: Column(
        children: [
          Text(label, style: AppTheme.bodySmall),
          const SizedBox(height: 4),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value),
            duration: const Duration(milliseconds: 800),
            builder: (context, val, child) {
              return Text(
                isCurrency
                    ? currencyFormat.format(val)
                    : val.toInt().toString(),
                style: AppTheme.headlineMedium.copyWith(color: color),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 40,
      width: 1,
      color: AppTheme.border,
    );
  }

  Widget _buildShimmer() {
    return Container(
      margin: const EdgeInsets.all(16),
      height: 80,
      decoration: AppTheme.cardDecoration,
      child: Shimmer.fromColors(
        baseColor: Colors.grey[200]!,
        highlightColor: Colors.grey[100]!,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(3, (index) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(width: 60, height: 10, color: Colors.white),
                const SizedBox(height: 8),
                Container(width: 40, height: 20, color: Colors.white),
              ],
            );
          }),
        ),
      ),
    );
  }
}
