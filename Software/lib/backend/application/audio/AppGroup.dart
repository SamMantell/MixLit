import 'dart:ui' show Color;

class AppGroup {
  final String id;
  final String name;
  final List<String> processNames;
  final Color color;
  final DateTime createdAt;
  final String? iconData;

  AppGroup({
    required this.id,
    required this.name,
    required this.processNames,
    required this.color,
    required this.createdAt,
    this.iconData,
  });

  AppGroup copyWith({
    String? id,
    String? name,
    List<String>? processNames,
    Color? color,
    DateTime? createdAt,
    String? iconData,
  }) {
    return AppGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      processNames: processNames ?? this.processNames,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      iconData: iconData ?? this.iconData,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'processNames': processNames,
      'color': color.value,
      'createdAt': createdAt.toIso8601String(),
      if (iconData != null) 'iconData': iconData,
    };
  }

  factory AppGroup.fromJson(Map<String, dynamic> json) {
    return AppGroup(
      id: json['id'],
      name: json['name'],
      processNames: List<String>.from(json['processNames']),
      color: Color(json['color']),
      createdAt: DateTime.parse(json['createdAt']),
      iconData: json['iconData'],
    );
  }
}
