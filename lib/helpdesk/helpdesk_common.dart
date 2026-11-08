import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../auth/auth_api.dart';
import 'helpdesk_api.dart';

/// Shared session context passed between help desk routes.
class HelpDeskSession {
  const HelpDeskSession({
    required this.api,
    required this.userId,
    this.canManage = false,
    this.isAgent = false,
  });

  final HelpDeskApi api;
  final String userId;
  final bool canManage;
  final bool isAgent;
  bool get isStaff => canManage || isAgent;
}

const helpDeskPageSize = 20;
const helpDeskMaxFileBytes = 25 * 1024 * 1024;
const helpDeskFinalStatuses = {'resolved', 'closed', 'rejected'};

const helpDeskTransitions = <String, List<String>>{
  'submitted': ['under_review', 'assigned', 'rejected'],
  'under_review': ['assigned', 'in_progress', 'waiting_for_member', 'resolved', 'rejected'],
  'assigned': ['under_review', 'in_progress', 'waiting_for_member', 'resolved', 'rejected'],
  'in_progress': ['waiting_for_member', 'resolved', 'rejected'],
  'waiting_for_member': ['in_progress', 'resolved', 'rejected'],
  'resolved': ['in_progress', 'closed'],
  'rejected': ['closed'],
  'closed': [],
};

const helpDeskCategoryIcons = <String, IconData>{
  'general_inquiry': Icons.help_outline_rounded,
  'technical_support': Icons.build_circle_outlined,
  'education_assistance': Icons.school_outlined,
  'healthcare_assistance': Icons.local_hospital_outlined,
  'employment_assistance': Icons.work_outline_rounded,
  'business_support': Icons.storefront_outlined,
  'social_welfare': Icons.volunteer_activism_outlined,
  'membership_support': Icons.badge_outlined,
  'complaints': Icons.report_outlined,
  'emergency_assistance': Icons.warning_amber_rounded,
  'other': Icons.more_horiz_rounded,
};

const helpDeskCategoryHints = <String, String>{
  'general_inquiry': 'Questions about ORAKZAI.ORG and its programmes',
  'technical_support': 'App, account or sign-in difficulties',
  'education_assistance': 'Scholarships, schooling and learning support',
  'healthcare_assistance': 'Guidance towards medical help and referrals',
  'employment_assistance': 'Jobs, skills and work referrals',
  'business_support': 'Small business and livelihood guidance',
  'social_welfare': 'Community assistance for families in need',
  'membership_support': 'Member records, verification and profile',
  'complaints': 'Raise a concern privately with the team',
  'emergency_assistance': 'Urgent welfare follow-up, not emergency response',
  'other': 'Anything that does not fit elsewhere',
};

String hdCategory(String? key) => HelpDeskApi.categories[key] ?? (key ?? 'Unknown');
String hdStatus(String? key) => HelpDeskApi.statuses[key] ?? (key ?? 'Unknown');
String hdPriority(String? key) => HelpDeskApi.priorities[key] ?? (key ?? 'Normal');

String hdError(Object error) {
  if (error is AuthApiException) return error.message;
  return 'The request did not complete. Check your connection and try again.';
}

String hdStr(Object? value) => value?.toString() ?? '';

Map<String, dynamic> hdMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<Map<String, dynamic>> hdItems(Object? value) => value is List
    ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : <Map<String, dynamic>>[];

int hdInt(Object? value) =>
    value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;

DateTime? hdParseDate(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String hdDate(Object? value, {bool time = true}) {
  final d = hdParseDate(value);
  if (d == null) return '';
  final base = '${d.day} ${_months[d.month - 1]} ${d.year}';
  if (!time) return base;
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '$base, $hh:$mm';
}

String hdBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Unwraps `{request: {...}}` responses, falling back to the body itself.
Map<String, dynamic> hdRequest(Map<String, dynamic> response) {
  final inner = response['request'];
  return inner is Map ? Map<String, dynamic>.from(inner) : response;
}

Color hdStatusColor(String? status) {
  switch (status) {
    case 'resolved':
      return AppColors.green;
    case 'rejected':
      return AppColors.danger;
    case 'closed':
      return AppColors.muted;
    case 'waiting_for_member':
      return const Color(0xFF8A6A1C);
    case 'under_review':
    case 'submitted':
      return AppColors.navySoft;
    default:
      return AppColors.navy;
  }
}

Color hdStatusWash(String? status) {
  switch (status) {
    case 'resolved':
      return AppColors.greenWash;
    case 'rejected':
      return AppColors.dangerWash;
    case 'closed':
      return AppColors.line;
    case 'waiting_for_member':
      return AppColors.goldWash;
    default:
      return const Color(0xFFE8EDF4);
  }
}

Color hdPriorityColor(String? priority) {
  switch (priority) {
    case 'urgent':
      return AppColors.danger;
    case 'high':
      return const Color(0xFF8A6A1C);
    case 'low':
      return AppColors.muted;
    default:
      return AppColors.navySoft;
  }
}
