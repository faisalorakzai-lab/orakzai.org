import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../data/program_area.dart';
import '../widgets/app_components.dart';

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final filtered = serviceDirectory
        .where(
          (area) =>
              area.title.toLowerCase().contains(query) ||
              area.summary.toLowerCase().contains(query),
        )
        .toList();

    return AppPage(
      title: 'Services',
      subtitle:
          'Browse the organization’s published program areas and planned service categories.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            onChanged: (value) => setState(() => _query = value.trim()),
            decoration: InputDecoration(
              hintText: 'Search services',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () => setState(() => _query = ''),
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          const InfoBanner(
            title: 'Information directory',
            message:
                'Program names and descriptions use the public website and app brief. This directory does not confirm that a service is currently available.',
            icon: Icons.info_outline_rounded,
          ),
          const SizedBox(height: 20),
          SectionHeading(
            title: 'All service areas',
            actionLabel: '${filtered.length}',
          ),
          if (filtered.isEmpty)
            const EmptyState(
              title: 'No matching services',
              message: 'Try another search term.',
              icon: Icons.search_off_rounded,
            )
          else
            ...filtered.map(
              (area) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ProgramAreaCard(
                  area: area,
                  onTap: () => _showDetails(area),
                ),
              ),
            ),
          const SizedBox(height: 10),
          const InfoBanner(
            title: 'No account or payment flows',
            message:
                'This milestone does not include sign-in, donations, checkout or private member records.',
            icon: Icons.privacy_tip_outlined,
            background: AppColors.greenWash,
            foreground: AppColors.green,
          ),
        ],
      ),
    );
  }

  Future<void> _showDetails(ProgramArea area) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 6, 22, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(area.icon, color: AppColors.navy, size: 25),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      area.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(area.summary),
              const SizedBox(height: 14),
              Text(
                '${area.source}. Availability must be confirmed directly with the organization.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
