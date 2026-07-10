class Material {
  final String id;
  final String name;
  final String category;
  final String unit;
  final double quantity;
  final double unitPrice;
  final String supplier;
  final String status;
  final String? siteId;
  final DateTime deliveryDate;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Material({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.supplier,
    required this.status,
    this.siteId,
    required this.deliveryDate,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  double get totalCost => quantity * unitPrice;

  factory Material.fromJson(Map<String, dynamic> json) {
    return Material(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      unit: json['unit'] as String,
      quantity: (json['quantity'] as num).toDouble(),
      unitPrice: (json['unit_price'] as num).toDouble(),
      supplier: json['supplier'] as String,
      status: json['status'] as String,
      siteId: json['site_id'] as String?,
      deliveryDate: DateTime.parse(json['delivery_date'] as String),
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'category': category,
        'unit': unit,
        'quantity': quantity,
        'unit_price': unitPrice,
        'supplier': supplier,
        'status': status,
        'site_id': siteId,
        'delivery_date': deliveryDate.toIso8601String(),
        'notes': notes,
      };
}
