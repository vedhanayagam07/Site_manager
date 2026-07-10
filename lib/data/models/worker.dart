class Worker {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String role;
  final String status;
  final DateTime joinDate;
  final String? siteId;
  final String? skillSet;
  final String? profileImageUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  Worker({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.status,
    required this.joinDate,
    this.siteId,
    this.skillSet,
    this.profileImageUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Worker.fromJson(Map<String, dynamic> json) {
    return Worker(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      phone: json['phone'] as String,
      role: json['role'] as String,
      status: json['status'] as String,
      joinDate: DateTime.parse(json['join_date'] as String),
      siteId: json['site_id'] as String?,
      skillSet: json['skill_set'] as String?,
      profileImageUrl: json['profile_image_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'phone': phone,
        'role': role,
        'status': status,
        'join_date': joinDate.toIso8601String(),
        'site_id': siteId,
        'skill_set': skillSet,
        'profile_image_url': profileImageUrl,
      };
}
