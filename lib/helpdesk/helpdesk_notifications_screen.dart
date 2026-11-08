import 'package:flutter/material.dart';
import 'helpdesk_common.dart';
import 'helpdesk_widgets.dart';
import 'helpdesk_paged_list.dart';
import 'request_detail_screen.dart';

class HelpDeskNotificationsScreen extends StatefulWidget {
  const HelpDeskNotificationsScreen({required this.session,super.key});
  final HelpDeskSession session;
  @override
  State<HelpDeskNotificationsScreen> createState()=>_HelpDeskNotificationsScreenState();
}
class _HelpDeskNotificationsScreenState extends State<HelpDeskNotificationsScreen> {
  final _list=GlobalKey<HdPagedListState>();
  static const _labels={
    'helpdesk_submitted':'Request submitted',
    'helpdesk_assigned':'Request assigned',
    'helpdesk_status':'Request status updated',
    'helpdesk_reply':'New support conversation response',
    'helpdesk_documents':'Additional documents requested',
    'helpdesk_resolved':'Request resolved',
    'helpdesk_closed':'Request closed',
  };
  Future<void> _open(Map<String,dynamic> n) async {
    try {
      await widget.session.api.post('/notifications/${n['id']}/read',{});
      if(!mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder:(_)=>RequestDetailScreen(session:widget.session,requestId:n['requestId'] as String)));
      if(mounted) await _list.currentState?.reload();
    } catch(e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(hdError(e))));
    }
  }
  @override
  Widget build(BuildContext context)=>HdScaffold(
    title:'Help Desk updates',
    subtitle:'Private in-app notifications for requests you can currently access.',
    children:[HdPagedList(
      key:_list,
      fetch:(offset,limit)=>widget.session.api.get('/notifications',query:{'offset':'$offset','limit':'$limit'}),
      emptyTitle:'No updates yet',
      emptyMessage:'Request and staff response notifications will appear here.',
      itemLabel:'updates',
      itemBuilder:(context,n)=>Card(child:ListTile(
        leading:Icon(n['readAt']==null?Icons.mark_email_unread_outlined:Icons.drafts_outlined),
        title:Text(_labels[n['kind']]??'Help Desk update'),
        subtitle:Text(hdDate(n['createdAt'])),
        trailing:const Icon(Icons.chevron_right),
        onTap:()=>_open(n),
      )),
    )],
  );
}
