class LocationData {
  final double? latitude;
  final double? longitude;
  final int? distanceMeters;
  final bool withinRange;
  final bool isLeftCampus;
  final int? accuracy;

  LocationData({
    this.latitude,
    this.longitude,
    this.distanceMeters,
    this.withinRange = true,
    this.isLeftCampus = false,
    this.accuracy,
  });

  factory LocationData.fromJson(Map<String, dynamic>? json) {
    if (json == null) return LocationData();
    return LocationData(
      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
      distanceMeters: json['distanceMeters'] != null ? (json['distanceMeters'] as num).toInt() : null,
      withinRange: json['withinRange'] ?? true,
      isLeftCampus: json['isLeftCampus'] ?? false,
      accuracy: json['accuracy'] != null ? (json['accuracy'] as num).toInt() : null,
    );
  }
}

class AttendanceModel {
  final String id;
  final String studentId;
  final String studentName;
  final String date;
  final String month;
  final DateTime punchInTime;
  final DateTime? punchOutTime;
  final int durationMinutes;
  final String mode; // 'location' | 'online'
  final String? classMode; // 'offline' | 'online'
  final LocationData? locationData;
  final String? notes;
  final String? audioNote;
  final String status; // 'active' | 'completed'

  AttendanceModel({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.date,
    required this.month,
    required this.punchInTime,
    this.punchOutTime,
    this.durationMinutes = 0,
    required this.mode,
    this.classMode,
    this.locationData,
    this.notes,
    this.audioNote,
    required this.status,
  });

  factory AttendanceModel.fromJson(Map<String, dynamic> json) {
    return AttendanceModel(
      id: json['id'] ?? json['_id'] ?? '',
      studentId: json['studentId'] ?? '',
      studentName: json['studentName'] ?? '',
      date: json['date'] ?? '',
      month: json['month'] ?? '',
      punchInTime: DateTime.parse(json['punchInTime'] ?? DateTime.now().toIso8601String()),
      punchOutTime: json['punchOutTime'] != null ? DateTime.parse(json['punchOutTime']) : null,
      durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 0,
      mode: json['mode'] ?? 'location',
      classMode: json['classMode'] ?? (json['mode'] == 'online' ? 'online' : 'offline'),
      locationData: LocationData.fromJson(json['locationData']),
      notes: json['notes'],
      audioNote: json['audioNote'],
      status: json['status'] ?? 'active',
    );
  }
}
