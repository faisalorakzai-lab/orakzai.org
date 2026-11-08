import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import 'helpdesk_api.dart';
import 'helpdesk_common.dart';
import 'helpdesk_widgets.dart';

/// Category Selection. Returns the chosen category key via Navigator.pop.
class CategorySelectionScreen extends StatelessWidget {
  const CategorySelectionScreen({this.selected, super.key});
  final String? selected;

  @override
  Widget build(BuildContext context) {
    return HdScaffold(
      title: 'Choose a category',
      subtitle: 'Pick the closest match. Staff can re-route your request if needed.',
      children: [
        for (final entry in HelpDeskApi.categories.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: HdCard(
              accent: entry.key == selected ? AppColors.gold : null,
              onTap: () => Navigator.pop(context, entry.key),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: entry.key == 'emergency_assistance' ? AppColors.dangerWash : AppColors.goldWash,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(helpDeskCategoryIcons[entry.key],
                        color: entry.key == 'emergency_assistance' ? AppColors.danger : AppColors.navy),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.value, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(helpDeskCategoryHints[entry.key] ?? '', style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  ),
                  Icon(entry.key == selected ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                      color: entry.key == selected ? AppColors.green : AppColors.muted),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
