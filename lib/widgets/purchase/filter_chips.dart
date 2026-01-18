import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';

class FilterChips extends StatelessWidget {
  final String selectedFilter;
  final Function(String) onSelected;

  const FilterChips({
    super.key,
    required this.selectedFilter,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final filters = ['All', 'Paid', 'Partial', 'Outstanding', 'Overdue'];

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = selectedFilter == filter;

          return FilterChip(
            label: Text(filter),
            selected: isSelected,
            onSelected: (_) => onSelected(filter),
            backgroundColor: AppTheme.surface,
            selectedColor: AppTheme.primary.withOpacity(0.1),
            checkmarkColor: AppTheme.primary,
            labelStyle: TextStyle(
              color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: isSelected
                    ? AppTheme.primary
                    : AppTheme.border,
              ),
            ),
            showCheckmark: false,
          );
        },
      ),
    );
  }
}
