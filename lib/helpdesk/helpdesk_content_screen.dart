import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import 'helpdesk_common.dart';
import 'helpdesk_paged_list.dart';
import 'helpdesk_widgets.dart';

enum HelpDeskContentMode { faqs, announcements }

/// FAQs and Announcements. Managers can publish new entries.
class HelpDeskContentScreen extends StatefulWidget {
  const HelpDeskContentScreen({required this.session, required this.mode, super.key});
  final HelpDeskSession session;
  final HelpDeskContentMode mode;

  @override
  State<HelpDeskContentScreen> createState() => _HelpDeskContentScreenState();
}

class _HelpDeskContentScreenState extends State<HelpDeskContentScreen> {
  final _listKey = GlobalKey<HdPagedListState>();
  bool get _faq => widget.mode == HelpDeskContentMode.faqs;

  Future<void> _create() async {
    final ok = await hdTextDialog(
      context,
      title: _faq ? 'New FAQ' : 'New announcement',
      submitLabel: 'Publish',
      fields: [
        HdDialogField(_faq ? 'Question' : 'Title', min: 3, max: 200),
        HdDialogField(_faq ? 'Answer' : 'Message', min: 10, max: 5000, maxLines: 6),
      ],
      onSubmit: (v) => widget.session.api.post(_faq ? '/admin/faqs' : '/admin/announcements', {'title': v[0], 'body': v[1]}),
    );
    if (ok) {
      _listKey.currentState?.reload();
      if (mounted) hdSnack(context, 'Published.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return HdScaffold(
      title: _faq ? 'Frequently asked' : 'Announcements',
      subtitle: _faq
          ? 'Answers from the ORAKZAI.ORG help desk team.'
          : 'Important notices from the help desk team.',
      onRefresh: () async => _listKey.currentState?.reload(),
      floatingActionButton: widget.session.canManage
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.navy,
              foregroundColor: Colors.white,
              onPressed: _create,
              icon: const Icon(Icons.add_rounded),
              label: Text(_faq ? 'Add FAQ' : 'Post notice'),
            )
          : null,
      children: [
        HdPagedList(
          key: _listKey,
          itemLabel: _faq ? 'questions' : 'announcements',
          fetch: (offset, limit) =>
              widget.session.api.get(_faq ? '/faqs' : '/announcements', query: {'limit': '$limit', 'offset': '$offset'}),
          emptyTitle: _faq ? 'No FAQs published yet' : 'No announcements right now',
          emptyMessage: _faq
              ? 'If your question is not answered here, submit a request.'
              : 'When the team posts an important notice it will appear here.',
          emptyIcon: _faq ? Icons.quiz_outlined : Icons.campaign_outlined,
          itemBuilder: (context, item) => _faq ? _faqTile(item) : _announcement(item),
        ),
        const SizedBox(height: 70),
      ],
    );
  }

  Widget _faqTile(Map<String, dynamic> f) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.line),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            iconColor: AppColors.navy,
            title: Text(hdStr(f['question']).isEmpty ? hdStr(f['title']) : hdStr(f['question']),
                style: Theme.of(context).textTheme.titleMedium),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(hdStr(f['answer']).isEmpty ? hdStr(f['body']) : hdStr(f['answer']),
                  style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }

  Widget _announcement(Map<String, dynamic> a) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: HdCard(
        accent: AppColors.gold,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(hdDate(a['createdAt'], time: false).toUpperCase(),
              style: const TextStyle(color: AppColors.green, fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(hdStr(a['title']), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(hdStr(a['body']), style: Theme.of(context).textTheme.bodyLarge),
        ]),
      ),
    );
  }
}
