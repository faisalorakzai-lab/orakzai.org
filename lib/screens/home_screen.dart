import 'package:flutter/material.dart';

import '../app/app_language.dart';
import '../app/app_theme.dart';
import '../data/program_area.dart';
import '../widgets/app_components.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.language,
    required this.onOpenHelpDesk,
    super.key,
  });

  final AppLanguage language;
  final VoidCallback onOpenHelpDesk;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final copy = AppCopy.text;
    final visibleAreas = publicProgramAreas
        .where(
          (area) =>
              area.title.toLowerCase().contains(_query.toLowerCase()) ||
              area.summary.toLowerCase().contains(_query.toLowerCase()),
        )
        .take(3)
        .toList();

    return AppPage(
      title: copy(widget.language, 'homeTitle'),
      subtitle: copy(widget.language, 'homeSubtitle'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WELCOME TO THE GLOBAL COMMUNITY',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppColors.green,
              fontSize: 10,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'A place to connect, support and grow together.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 19),
          TextField(
            onChanged: (value) => setState(() => _query = value.trim()),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: copy(widget.language, 'search'),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: QuickActionCard(
                  icon: Icons.emergency_outlined,
                  title: copy(widget.language, 'emergency'),
                  subtitle: 'Open private help options',
                  emergency: true,
                  onTap: widget.onOpenHelpDesk,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: QuickActionCard(
                  icon: Icons.edit_note_rounded,
                  title: copy(widget.language, 'shareProblem'),
                  subtitle: 'Start a private preview form',
                  onTap: widget.onOpenHelpDesk,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const InfoBanner(
            title: 'Organization update',
            message:
                'ORAKZAI.ORG describes its public mission as education, community development and humanitarian support.',
            icon: Icons.campaign_outlined,
            background: Colors.white,
            foreground: AppColors.navy,
          ),
          const SizedBox(height: 24),
          SectionHeading(
            title: 'Program areas',
            actionLabel: _query.isEmpty ? 'From public site' : 'Search results',
          ),
          if (visibleAreas.isEmpty)
            const EmptyState(
              title: 'No matching programs',
              message: 'Try a different search phrase.',
              icon: Icons.search_off_rounded,
            )
          else
            ...visibleAreas.map(
              (area) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ProgramAreaCard(
                  area: area,
                  onTap: () => _showProgramDetails(context, area),
                ),
              ),
            ),
          const SizedBox(height: 14),
          const SectionHeading(title: 'Events & opportunities'),
          const InfoBanner(
            title: 'No live event feed yet',
            message:
                'This app foundation does not claim current events or open opportunities. Verified updates can be connected in a later milestone.',
            icon: Icons.event_note_outlined,
            background: AppColors.greenWash,
            foreground: AppColors.green,
          ),
          const SizedBox(height: 20),
          const InfoBanner(
            title: 'Preview data only',
            message:
                'No membership counts, assistance outcomes or connected services are shown as verified app data.',
            icon: Icons.verified_user_outlined,
          ),
        ],
      ),
    );
  }

  Future<void> _showProgramDetails(
    BuildContext context,
    ProgramArea area,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(area.title),
        content: Text(
          '${area.summary}\n\nThis is information from the public website. '
          'Current service availability has not been confirmed in the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
