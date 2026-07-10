class Site {
  final String id;
  final String name;
  final String location;
  final String description;
  final DateTime startDate;
  final DateTime? endDate;
  final String status;
  final String projectManager;
  final String? imageUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  Site({
    required this.id,
    required this.name,
    required this.location,
    required this.description,
    required this.startDate,
    this.endDate,
    required this.status,
    required this.projectManager,
    this.imageUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Site.fromJson(Map<String, dynamic> json) {
    return Site(
      id: json['id'] as String,
      name: json['name'] as String,
      location: json['location'] as String,
      description: json['description'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: json['end_date'] != null ? DateTime.parse(json['end_date'] as String) : null,
      status: json['status'] as String,
      projectManager: json['project_manager'] as String,
      imageUrl: json['image_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'location': location,
        'description': description,
        'start_date': startDate.toIso8601String(),
        'end_date': endDate?.toIso8601String(),
        'status': status,
        'project_manager': projectManager,
        'image_url': imageUrl,
      };
}
