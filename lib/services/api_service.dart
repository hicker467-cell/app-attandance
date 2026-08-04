import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';
import '../models/attendance_model.dart';

class ApiService {
  static const String baseUrl = 'https://attendance-sssam.vercel.app';

  // 1. Student Login (Email & Password)
  static Future<UserModel> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'login',
        'email': email,
        'password': password,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['success'] == true && data['user'] != null) {
      return UserModel.fromJson(data['user']);
    } else {
      throw Exception(data['error'] ?? 'Login failed. Check email or password.');
    }
  }

  // 2. Send Email OTP via Brevo API for Registration
  static Future<void> sendRegistrationOtp(String email) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'send-otp',
        'email': email,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['error'] ?? 'Failed to send OTP to email.');
    }
  }

  // 3. Student Register (Requires valid Email OTP verification)
  static Future<UserModel> register({
    required String name,
    required String email,
    required String password,
    required String otp,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'register',
        'name': name,
        'email': email,
        'password': password,
        'otp': otp,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['success'] == true && data['user'] != null) {
      return UserModel.fromJson(data['user']);
    } else {
      throw Exception(data['error'] ?? 'Registration failed. Check OTP code.');
    }
  }

  // 4. Send Email OTP for Forgot Password
  static Future<void> sendForgotPasswordOtp(String email) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'forgot-password',
        'email': email,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['error'] ?? 'Failed to send password reset OTP.');
    }
  }

  // 5. Reset Password with Email OTP
  static Future<void> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'reset-password',
        'email': email,
        'otp': otp,
        'newPassword': newPassword,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['error'] ?? 'Failed to reset password. Invalid OTP.');
    }
  }

  // 6. 1-Click Google Sign In
  static Future<UserModel> googleLogin(String email, String name) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'google',
        'name': name,
        'email': email,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['success'] == true && data['user'] != null) {
      return UserModel.fromJson(data['user']);
    } else {
      throw Exception(data['error'] ?? 'Google authentication failed.');
    }
  }

  // 7. Fetch Campus Settings
  static Future<Map<String, dynamic>> fetchCampusSettings() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/admin?month=${DateTime.now().toIso8601String().substring(0, 7)}'),
      );
      final data = jsonDecode(response.body);
      if (data['settings'] != null) {
        return {
          'campusLat': (data['settings']['campusLat'] as num?)?.toDouble() ?? 28.470430,
          'campusLng': (data['settings']['campusLng'] as num?)?.toDouble() ?? 77.044326,
          'campusRadiusMeters': (data['settings']['campusRadiusMeters'] as num?)?.toInt() ?? 200,
        };
      }
    } catch (_) {}
    return {
      'campusLat': 28.470430,
      'campusLng': 77.044326,
      'campusRadiusMeters': 200,
    };
  }

  // 8. Fetch Attendance History
  static Future<List<AttendanceModel>> fetchAttendance(String studentId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/attendance?studentId=$studentId'),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['records'] != null) {
      final List list = data['records'];
      return list.map((item) => AttendanceModel.fromJson(item)).toList();
    }
    return [];
  }

  // 9. Punch In
  static Future<AttendanceModel> punchIn({
    required String studentId,
    required String studentName,
    required String mode,
    String? classMode,
    double? latitude,
    double? longitude,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/attendance'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'punch-in',
        'studentId': studentId,
        'studentName': studentName,
        'mode': mode,
        'classMode': classMode ?? (mode == 'online' ? 'online' : 'offline'),
        'location': (latitude != null && longitude != null)
            ? {'latitude': latitude, 'longitude': longitude}
            : null,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['success'] == true && data['record'] != null) {
      return AttendanceModel.fromJson(data['record']);
    } else {
      throw Exception(data['error'] ?? 'Punch in failed.');
    }
  }

  // 10. Punch Out
  static Future<AttendanceModel> punchOut({
    required String attendanceId,
    required String notes,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/attendance'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'punch-out',
        'attendanceId': attendanceId,
        'notes': notes,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['success'] == true && data['record'] != null) {
      return AttendanceModel.fromJson(data['record']);
    } else {
      throw Exception(data['error'] ?? 'Punch out failed.');
    }
  }

  // 11. Update Live Location
  static Future<void> updateLiveLocation({
    required String attendanceId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/api/attendance'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'update-location',
          'attendanceId': attendanceId,
          'location': {'latitude': latitude, 'longitude': longitude},
        }),
      );
    } catch (_) {}
  }
}
