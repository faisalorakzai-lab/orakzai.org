import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../data/program_area.dart';
import '../widgets/app_components.dart';

class HelpDeskScreen extends StatefulWidget {
  const HelpDeskScreen({super.key});

  @override
  State<HelpDeskScreen> createState() => _HelpDeskScreenState();
}

class _HelpDeskScreenState extends State<HelpDeskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _detailsController = TextEditingController();
  String _selectedCategory = helpCategories.first;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Help Desk',
      subtitle:
          'Choose a topic and prepare a private assistance request preview.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const InfoBanner(
            title: 'Private by design',
            message:
                'This preview does not send, publish or save what you type. A real help desk requires a secure backend and an approved review process.',
            icon: Icons.lock_outline_rounded,
            background: AppColors.greenWash,
            foreground: AppColors.green,
          ),
          const SizedBox(height: 22),
          const SectionHeading(title: 'What do you need help with?'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: helpCategories
                .map(
                  (category) => ChoiceChip(
                    label: Text(category),
                    selected: _selectedCategory == category,
                    onSelected: (_) =>
                        setState(() => _selectedCategory = category),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 20),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Brief description',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 9),
                TextFormField(
                  controller: _detailsController,
                  maxLines: 4,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Describe the type of support you are seeking.',
                    alignLabelWithHint: true,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().length < 8) {
                      return 'Enter at least 8 characters for this preview.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _preparePreviewRequest,
                    icon: const Icon(Icons.lock_outline_rounded),
                    label: const Text('Preview request'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionHeading(title: 'Request history'),
          const EmptyState(
            title: 'No request history',
            message:
                'No requests are stored in this app milestone. A secure account and server connection are not set up yet.',
            icon: Icons.receipt_long_outlined,
          ),
          const SizedBox(height: 18),
          const InfoBanner(
            title: 'Emergency note',
            message:
                'This app preview is not an emergency response service. Contact local emergency services for urgent danger.',
            icon: Icons.warning_amber_rounded,
            background: AppColors.dangerWash,
            foreground: AppColors.danger,
          ),
        ],
      ),
    );
  }

  void _preparePreviewRequest() {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.visibility_outlined),
        title: const Text('Preview only'),
        content: Text(
          'Category: $_selectedCategory\n\n'
          'Nothing was sent to ORAKZAI.ORG and your description was not saved. '
          'The real request flow will be connected in a later milestone.',
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
