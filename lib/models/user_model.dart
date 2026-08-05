class UserModel {
  final String studentId;
  final String name;
  final String email;
  final String role;
  final String phone;

  UserModel({
    required this.studentId,
    required this.name,
    required this.email,
    required this.role,
    this.phone = '',
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      studentId: json['studentId'] ?? 'STU-2026-000',
      name: json['name'] ?? 'Student',
      email: json['email'] ?? '',
      role: json['role'] ?? 'student',
      phone: json['phone'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'studentId': studentId,
      'name': name,
      'email': email,
      'role': role,
      'phone': phone,
    };
  }

  UserModel copyWith({
    String? studentId,
    String? name,
    String? email,
    String? role,
    String? phone,
  }) {
    return UserModel(
      studentId: studentId ?? this.studentId,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      phone: phone ?? this.phone,
    );
  }
}
