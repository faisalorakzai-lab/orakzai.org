import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orakzai_app/app/app_theme.dart';
import 'package:orakzai_app/auth/app_user.dart';
import 'package:orakzai_app/auth/auth_api.dart';
import 'package:orakzai_app/auth/auth_controller.dart';
import 'package:orakzai_app/auth/token_store.dart';
import 'package:orakzai_app/helpdesk/helpdesk_api.dart';
import 'package:orakzai_app/helpdesk/helpdesk_common.dart';
import 'package:orakzai_app/helpdesk/helpdesk_files.dart';
import 'package:orakzai_app/helpdesk/helpdesk_content_screen.dart';
import 'package:orakzai_app/helpdesk/request_management_screen.dart';
import 'package:orakzai_app/helpdesk/request_detail_screen.dart';
import 'package:orakzai_app/helpdesk/submit_request_screen.dart';
import 'package:orakzai_app/screens/help_desk_screen.dart';

/// Test-only fake that records calls. Never used in production code.
class FakeHelpDeskApi extends HelpDeskApi {
  FakeHelpDeskApi() : super(auth: AuthApi(tokenStore: MemoryTokenStore()));

  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  Map<String, Map<String, dynamic>> getResponses = {};
  bool failUploads = false;

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) async {
    calls.add('GET $path');
    return getResponses[path] ?? {'items': [], 'total': 0, 'limit': 20, 'offset': 0};
  }

  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    calls.add('POST $path');
    bodies[path] = body;
    if (path == '/requests') {
      return {
        'request': {'id': 'r1', 'reference': 'HD-TEST-1', 'title': body['title'], 'status': 'submitted'},
      };
    }
    return {};
  }

  @override
  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) async {
    calls.add('PATCH $path');
    bodies[path] = body;
    return {};
  }

  @override
  Future<Map<String, dynamic>> upload(String requestId, Uint8List bytes, String name) async {
    calls.add('UPLOAD $requestId $name');
    if (failUploads) throw const AuthApiException('X', 'upload failed');
    return {'id': 'a1', 'name': name};
  }
}

AppUser _user(String id) => AppUser(
      id: id,
      email: 'member@orakzai.org',
      phone: '',
      emailVerified: true,
      accountStatus: 'active',
      profile: const {},
      regionAssignments: const [],
    );

AuthController _auth({bool signedIn = false}) {
  final auth = AuthController(api: AuthApi(tokenStore: MemoryTokenStore()));
  auth.status = signedIn ? AuthStatus.signedIn : AuthStatus.signedOut;
  auth.user = signedIn ? _user('u1') : null;
  addTearDown(auth.dispose);
  return auth;
}

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: Scaffold(body: child));

void main() {
  testWidgets('request details display the API geography fields without losing location', (tester) async {
    final api = FakeHelpDeskApi()..getResponses['/requests/r1'] = {
      'request': {'id': 'r1', 'title': 'Location contract verification', 'status': 'submitted',
        'ownerId': 'u1', 'region': 'Region', 'district': 'District', 'qoum': 'Qoum',
        'village': 'Village', 'canManage': false, 'canStaffReply': false},
    };
    await tester.pumpWidget(_wrap(RequestDetailScreen(
      session: HelpDeskSession(api: api, userId: 'u1'), requestId: 'r1')));
    await tester.pumpAndSettle();
    expect(find.text('Region, District, Qoum, Village'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('long FAQ questions expand without intrinsic-height clipping on phones', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const question = 'How do I provide additional documents for an emergency assistance request?';
    final api = FakeHelpDeskApi()..getResponses['/faqs'] = {
      'items': [{'id': 'faq-test', 'question': question,
        'answer': 'Open your private request and use the authorized Attachments screen.'}],
      'total': 1,
    };
    await tester.pumpWidget(_wrap(HelpDeskContentScreen(
      session: HelpDeskSession(api: api, userId: 'u1'), mode: HelpDeskContentMode.faqs)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text(question));
    await tester.pumpAndSettle();
    expect(find.textContaining('authorized Attachments'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('signed-out members see a gate and no data is fetched', (tester) async {
    final api = FakeHelpDeskApi();
    var opened = false;
    await tester.pumpWidget(_wrap(HelpDeskScreen(
      authController: _auth(),
      onOpenProfile: () => opened = true,
      api: api,
    )));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to use the Help Desk'), findsOneWidget);
    await tester.tap(find.text('Open account'));
    expect(opened, isTrue);
    expect(api.calls, isEmpty);
  });

  testWidgets('signed-in home shows real stats from /home', (tester) async {
    final api = FakeHelpDeskApi()
      ..getResponses['/home'] = {
        'stats': {'total': 3, 'pending': 1, 'inProgress': 1, 'resolved': 1},
        'capabilities': {'manage': false, 'agent': false},
        'notificationsEnabled': true,
      };
    await tester.pumpWidget(_wrap(HelpDeskScreen(authController: _auth(signedIn: true), onOpenProfile: () {}, api: api)));
    await tester.pumpAndSettle();
    expect(api.calls, ['GET /home']);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Submit new request'), findsOneWidget);
    expect(find.text('Staff dashboard'), findsNothing);
  });

  testWidgets('submit creates the request once and reports failed uploads honestly', (tester) async {
    final api = FakeHelpDeskApi()..failUploads = true;
    final session = HelpDeskSession(api: api, userId: 'u1');
    await tester.pumpWidget(_wrap(SubmitRequestScreen(
      session: session,
      initialCategory: 'emergency_assistance',
      pickFiles: () async => HdPickResult([HdPickedFile('id.pdf', Uint8List.fromList([1, 2, 3]))], const []),
    )));
    expect(find.text('This is not an emergency response service'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('hd-title')), 'Need welfare help');
    await tester.enterText(find.byKey(const Key('hd-description')), 'Our family needs urgent welfare follow-up please.');
    await tester.enterText(find.byKey(const Key('hd-region')), 'Kalaya');
    await tester.ensureVisible(find.text('Add files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add files'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('hd-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('hd-submit')));
    await tester.pumpAndSettle();

    expect(api.calls.where((c) => c == 'POST /requests').length, 1);
    final body = api.bodies['/requests']!;
    expect(body['category'], 'emergency_assistance');
    expect(body['region'], 'Kalaya');
    expect(body['contactPreference'], 'in_app');
    expect(api.calls, contains('UPLOAD r1 id.pdf'));
    expect(find.textContaining('failed to upload'), findsOneWidget);
    expect(find.text('HD-TEST-1'), findsOneWidget);
  });

  testWidgets('member without staff rights never loads internal notes', (tester) async {
    final api = FakeHelpDeskApi()
      ..getResponses['/requests/r1'] = {
        'request': {'id': 'r1', 'status': 'submitted', 'ownerId': 'u1', 'canManage': false, 'canStaffReply': false},
      };
    await tester.pumpWidget(_wrap(RequestManagementScreen(session: HelpDeskSession(api: api, userId: 'u1'), requestId: 'r1')));
    await tester.pumpAndSettle();
    expect(find.text('Staff access required'), findsOneWidget);
    expect(api.calls.any((c) => c.contains('/notes')), isFalse);
  });
}
