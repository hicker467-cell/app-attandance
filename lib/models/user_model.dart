class UserModel {
  final String studentId;
  final String name;
  final String email;
  final String role;

  UserModel({
    required this.studentId,
    required this.name,
    required this.email,
    required this.role,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      studentId: json['studentId'] ?? 'STU-2026-000',
      name: json['name'] ?? 'Student',
      email: json['email'] ?? '',
      role: json['role'] ?? 'student',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'studentId': studentId,
      'name': name,
      'email': email,
      'role': role,
    };
  }
}
