class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.phone,
    required this.emailVerified,
    required this.accountStatus,
    required this.profile,
    required this.regionAssignments,
  });

  final String id;
  final String email;
  final String phone;
  final bool emailVerified;
  final String accountStatus;
  final Map<String, dynamic> profile;
  final List<Map<String, dynamic>> regionAssignments;

  String get fullName => profile['fullName'] as String? ?? '';
  String? get memberId => profile['memberId'] as String?;
  String? get profilePhotoUrl => profile['profilePhotoUrl'] as String?;
  String? get city => profile['city'] as String?;
  String? get country => profile['country'] as String?;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final profileValue = json['profile'];
    final assignmentsValue = json['regionAssignments'];
    return AppUser(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      emailVerified: json['emailVerified'] as bool? ?? false,
      accountStatus: json['accountStatus'] as String? ?? 'pending',
      profile: profileValue is Map
          ? Map<String, dynamic>.from(profileValue)
          : <String, dynamic>{},
      regionAssignments: assignmentsValue is List
          ? assignmentsValue
                .whereType<Map>()
                .map(Map<String, dynamic>.from)
                .toList()
          : const [],
    );
  }
}
