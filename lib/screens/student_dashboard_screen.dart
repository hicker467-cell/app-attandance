import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/user_model.dart';
import '../models/attendance_model.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../theme/apple_theme.dart';

class StudentDashboardScreen extends StatefulWidget {
  final UserModel currentUser;
  final VoidCallback onLogout;

  const StudentDashboardScreen({
    super.key,
    required this.currentUser,
    required this.onLogout,
  });

  @override
  State<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen> with SingleTickerProviderStateMixin {
  late UserModel currentUserState;
  String mode = 'location'; // 'location' (offline) | 'online'
  int _selectedTabIndex = 0;
  DateTime _calendarSelectedMonth = DateTime.now();
  late TextEditingController _profileNameController;
  late TextEditingController _profilePhoneController;
  bool _isSavingProfileInline = false;
  String? _profileInlineError;

  Position? currentPosition;
  int? distFromOffice;
  bool refreshingGps = false;
  bool refreshingLogs = false;
  bool gpsDenied = false;

  // Campus Office Geofence Settings
  double officeLat = 28.470430;
  double officeLng = 77.044326;
  int officeRadius = 200;

  AttendanceModel? activeSession;
  int elapsedSeconds = 0;
  Timer? timer;
  Timer? liveSyncTimer;

  List<AttendanceModel> records = [];
  bool loading = false;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    currentUserState = widget.currentUser;
    _profileNameController = TextEditingController(text: widget.currentUser.name);
    _profilePhoneController = TextEditingController(text: widget.currentUser.phone ?? '');
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _initDashboard();
  }

  @override
  void dispose() {
    timer?.cancel();
    liveSyncTimer?.cancel();
    _profileNameController.dispose();
    _profilePhoneController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initDashboard() async {
    await _fetchOfficeSettings();
    await _fetchAttendanceRecords();
    await _checkLocation();
  }

  Future<void> _launchURL(String urlString) async {
    try {
      final Uri uri = Uri.parse(urlString);
      bool launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      debugPrint('Error launching URL $urlString: $e');
    }
  }

  Future<void> _fetchOfficeSettings() async {
    final settings = await ApiService.fetchCampusSettings();
    if (!mounted) return;
    setState(() {
      officeLat = settings['campusLat'];
      officeLng = settings['campusLng'];
      officeRadius = settings['campusRadiusMeters'];
    });
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final period = local.hour >= 12 ? 'PM' : 'AM';
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    return "${hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} $period";
  }

  bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }

  String get todayFirstCheckInStr {
    final now = DateTime.now();
    final todayFormatted = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    
    if (activeSession != null && (_isToday(activeSession!.punchInTime) || activeSession!.date == todayFormatted)) {
      return _formatTime(activeSession!.punchInTime);
    }
    
    final todayList = records.where((r) => r.date == todayFormatted || _isToday(r.punchInTime)).toList();
    if (todayList.isNotEmpty) {
      return _formatTime(todayList.first.punchInTime);
    }
    return '--:--';
  }

  String get todayLastCheckOutStr {
    final now = DateTime.now();
    final todayFormatted = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    
    final todayCompleted = records.where((r) => (r.date == todayFormatted || _isToday(r.punchInTime)) && r.punchOutTime != null).toList();
    if (todayCompleted.isNotEmpty) {
      return _formatTime(todayCompleted.last.punchOutTime!);
    }
    return '--:--';
  }

  Future<void> _fetchAttendanceRecords() async {
    if (!mounted) return;
    setState(() => refreshingLogs = true);
    try {
      final list = await ApiService.fetchAttendance(widget.currentUser.studentId);
      if (!mounted) return;
      setState(() {
        records = list;
        final activeList = list.where((r) => r.status == 'active').toList();
        if (activeList.isNotEmpty) {
          activeSession = activeList.first;
          _startTimer();
          _startLiveSync();
        } else {
          activeSession = null;
          timer?.cancel();
          liveSyncTimer?.cancel();
        }
      });
    } catch (_) {}
    if (mounted) setState(() => refreshingLogs = false);
  }

  Future<void> _checkLocation() async {
    if (!mounted) return;
    setState(() {
      refreshingGps = true;
      gpsDenied = false;
    });

    final pos = await LocationService.getCurrentLocation();
    if (!mounted) return;
    if (pos != null) {
      final dist = LocationService.calculateDistanceMeters(
        pos.latitude,
        pos.longitude,
        officeLat,
        officeLng,
      );
      setState(() {
        currentPosition = pos;
        distFromOffice = dist;
        gpsDenied = false;
      });
    } else {
      setState(() {
        gpsDenied = true;
      });
    }

    if (mounted) setState(() => refreshingGps = false);
  }

  void _startTimer() {
    timer?.cancel();
    if (activeSession == null) return;

    final start = activeSession!.punchInTime;
    void update() {
      if (!mounted) return;
      final diff = DateTime.now().difference(start).inSeconds;
      setState(() {
        elapsedSeconds = diff > 0 ? diff : 0;
      });
    }

    update();
    timer = Timer.periodic(const Duration(seconds: 1), (_) => update());
  }

  void _startLiveSync() {
    liveSyncTimer?.cancel();
    liveSyncTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (activeSession == null) return;
      final pos = await LocationService.getCurrentLocation();
      if (pos != null) {
        await ApiService.updateLiveLocation(
          attendanceId: activeSession!.id,
          latitude: pos.latitude,
          longitude: pos.longitude,
        );
      }
    });
  }

  Future<void> _handleFingerprintTap() async {
    // If Offline mode & outside office radius -> Block Punch In/Out and show Animated Red Cross Alert Popup Modal (✕)!
    if (mode == 'location' && distFromOffice != null && distFromOffice! > officeRadius) {
      _showOutsideOfficeRangeDialog();
      return;
    }

    if (activeSession != null) {
      _showPunchOutModal();
    } else {
      // Punch In
      if (mode == 'location' && currentPosition == null) {
        showCupertinoDialog(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('📍 Location Required'),
            content: const Text(
              'Location permission is required for Offline (Location Mode) Punch In.\n\nPlease allow location access in your device settings.',
            ),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
        return;
      }

      setState(() => loading = true);
      try {
        final record = await ApiService.punchIn(
          studentId: widget.currentUser.studentId,
          studentName: widget.currentUser.name,
          mode: mode,
          classMode: mode == 'online' ? 'online' : 'offline',
          latitude: currentPosition?.latitude,
          longitude: currentPosition?.longitude,
        );

        if (!mounted) return;
        setState(() {
          activeSession = record;
          _startTimer();
          _startLiveSync();
        });
        _fetchAttendanceRecords();
      } catch (e) {
        if (!mounted) return;
        showCupertinoDialog(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: Text(e.toString().replaceAll('Exception: ', '')),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
      } finally {
        if (mounted) setState(() => loading = false);
      }
    }
  }

  void _showEditProfileDialog() {
    final nameController = TextEditingController(text: currentUserState.name);
    final phoneController = TextEditingController(text: currentUserState.phone);
    bool isSaving = false;
    String? errorMsg;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '✏️ Edit Profile Details',
                        style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                      IconButton(
                        icon: const Icon(CupertinoIcons.xmark_circle_fill, color: AppleTheme.secondaryText),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (errorMsg != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF0F0),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFF3B30).withOpacity(0.3)),
                      ),
                      child: Text(
                        errorMsg!,
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFFFF3B30)),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text('Full Name *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      hintText: 'Enter full name',
                      filled: true,
                      fillColor: const Color(0xFFF5F5F7),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('10-Digit Mobile Number *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      hintText: 'Enter 10-digit mobile number',
                      filled: true,
                      fillColor: const Color(0xFFF5F5F7),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: isSaving
                          ? null
                          : () async {
                              final name = nameController.text.trim();
                              final phone = phoneController.text.trim();
                              if (name.isEmpty) {
                                setDialogState(() => errorMsg = 'Please enter your full name.');
                                return;
                              }
                              if (phone.replaceAll(RegExp(r'\D'), '').length != 10) {
                                setDialogState(() => errorMsg = 'Please enter a valid 10-digit mobile number.');
                                return;
                              }

                              setDialogState(() {
                                isSaving = true;
                                errorMsg = null;
                              });

                              try {
                                final updated = await ApiService.updateProfile(
                                  studentId: currentUserState.studentId,
                                  email: currentUserState.email,
                                  name: name,
                                  phone: phone,
                                );
                                if (!mounted) return;
                                Navigator.pop(ctx);
                                setState(() {
                                  currentUserState = updated;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Profile details saved successfully!')),
                                );
                              } catch (e) {
                                setDialogState(() {
                                  isSaving = false;
                                  errorMsg = e.toString().replaceAll('Exception: ', '');
                                });
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppleTheme.appleGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: isSaving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text('💾 Save Profile Details', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showHighAuthorityEscalationDialog() {
    final issueController = TextEditingController();
    final discussionController = TextEditingController();
    String? errorMsg;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(color: Color(0xFFFFF0F0), shape: BoxShape.circle),
                        child: const Text('🚨', style: TextStyle(fontSize: 18)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('High Authority Escalation', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800)),
                            Text('Priority Escalation Desk', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppleTheme.appleRose)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(CupertinoIcons.xmark_circle_fill, color: AppleTheme.secondaryText),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0F0),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFF3B30).withOpacity(0.3)),
                    ),
                    child: Text(
                      '⚠️ IMPORTANT: Please contact High Authority ONLY if your issue was NOT resolved after discussing with Primary Support.',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppleTheme.primaryText, height: 1.3),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (errorMsg != null) ...[
                    Text(errorMsg!, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppleTheme.appleRose)),
                    const SizedBox(height: 8),
                  ],
                  Text('1. Describe your attendance or system issue *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: issueController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Describe issue details...',
                      filled: true,
                      fillColor: const Color(0xFFF5F5F7),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('2. What was discussed with Primary Support? *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: discussionController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Describe response from Primary Support...',
                      filled: true,
                      fillColor: const Color(0xFFF5F5F7),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final issue = issueController.text.trim();
                        final disc = discussionController.text.trim();
                        if (issue.isEmpty || disc.isEmpty) {
                          setDialogState(() => errorMsg = 'Please fill in both fields before proceeding.');
                          return;
                        }
                        final text = '🚨 High Authority Escalation Ticket:\n👤 Name: ${currentUserState.name}\n📞 Contact: ${currentUserState.phone}\n❗ Issue Details: $issue\n💬 Discussion with Primary Support: $disc';
                        final url = Uri.parse('https://wa.me/919102130956?text=${Uri.encodeComponent(text)}');
                        Navigator.pop(ctx);
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url, mode: LaunchMode.externalApplication);
                        }
                      },
                      icon: const Icon(CupertinoIcons.chat_bubble_2_fill, size: 16),
                      label: const Text('Proceed to High Authority'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppleTheme.appleRose,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showSupportOptionsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('🎧 Help & Support Center', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800)),
                  IconButton(
                    icon: const Icon(CupertinoIcons.xmark_circle_fill, color: AppleTheme.secondaryText),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final text = 'Student Support Ticket:\n👤 Name: ${currentUserState.name}\n📞 Contact: ${currentUserState.phone}';
                  final url = Uri.parse('https://wa.me/919217031899?text=${Uri.encodeComponent(text)}');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(CupertinoIcons.phone_fill, size: 18),
                label: const Text('🟢 Primary Support Line'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppleTheme.appleGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _showHighAuthorityEscalationDialog();
                },
                icon: const Icon(CupertinoIcons.exclamationmark_shield_fill, color: AppleTheme.appleRose, size: 18),
                label: Text('🚨 Priority Escalation Line', style: GoogleFonts.inter(color: AppleTheme.appleRose, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: AppleTheme.appleRose),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOutsideOfficeRangeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: Tween<double>(begin: 0.95, end: 1.05).animate(_pulseController),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0F0),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFFFE0E0), width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF3B30).withOpacity(0.15),
                        blurRadius: 16,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(CupertinoIcons.xmark, color: Color(0xFFFF3B30), size: 32),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Out of Office Range ✕',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppleTheme.primaryText,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Please come within office range (${officeRadius}m) to Punch In or Check Out.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppleTheme.appleRose,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppleTheme.border),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Your Distance:', style: GoogleFonts.inter(fontSize: 12, color: AppleTheme.secondaryText)),
                        Text('${distFromOffice ?? 0}m away', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: AppleTheme.appleRose)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Radius Limit:', style: GoogleFonts.inter(fontSize: 12, color: AppleTheme.secondaryText)),
                        Text('${officeRadius}m', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppleTheme.primaryText)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _checkLocation();
                  },
                  icon: const Icon(CupertinoIcons.refresh, size: 16),
                  label: const Text('Refresh GPS Location'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppleTheme.appleBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() => mode = 'online');
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppleTheme.appleBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Switch to Online Class Mode'),
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Close', style: GoogleFonts.inter(color: AppleTheme.secondaryText)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCheckoutErrorDialog(String reason) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF0F0),
                  shape: BoxShape.circle,
                ),
                child: const Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Color(0xFFFF3B30), size: 28),
              ),
              const SizedBox(height: 14),
              Text(
                'Checkout Blocked ❌',
                style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: AppleTheme.primaryText),
              ),
              const SizedBox(height: 8),
              Text(
                reason,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: AppleTheme.secondaryText, height: 1.4),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppleTheme.appleRose,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('OK, Got It'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFullImageDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Profile Preview', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800)),
                  IconButton(
                    icon: const Icon(CupertinoIcons.xmark_circle_fill, color: AppleTheme.secondaryText),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              CircleAvatar(
                radius: 64,
                backgroundColor: AppleTheme.appleGreen.withOpacity(0.15),
                child: Text(
                  widget.currentUser.name.isNotEmpty ? widget.currentUser.name[0].toUpperCase() : 'S',
                  style: GoogleFonts.inter(fontSize: 48, fontWeight: FontWeight.w800, color: AppleTheme.appleGreen),
                ),
              ),
              const SizedBox(height: 14),
              Text(widget.currentUser.name, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700)),
              Text(widget.currentUser.email, style: GoogleFonts.inter(fontSize: 13, color: AppleTheme.secondaryText)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Close Preview'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPunchOutModal() {
    final notesController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: AppleTheme.border,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Punch Out & Study Notes',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppleTheme.primaryText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Enter detailed notes about what you studied today (min 30 chars)',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppleTheme.secondaryText,
                      ),
                    ),
                    if (activeSession?.classMode == 'online' || activeSession?.mode == 'online') ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F2FF),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppleTheme.appleBlue.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(CupertinoIcons.globe, color: AppleTheme.appleBlue, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '💻 Online Logout: Your exact logout timestamp will be saved and visible to Admin.',
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppleTheme.appleBlue),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9F9FB),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppleTheme.border),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        controller: notesController,
                        maxLines: 4,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppleTheme.primaryText,
                        ),
                        onChanged: (val) {
                          setModalState(() {});
                        },
                        decoration: InputDecoration(
                          hintText: 'Describe your study session topics, exercises, or tasks completed...',
                          hintStyle: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppleTheme.secondaryText,
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${notesController.text.trim().length} / 30 chars min',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: notesController.text.trim().length >= 30
                              ? AppleTheme.appleGreen
                              : AppleTheme.appleRose,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (notesController.text.trim().length >= 30) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F8EE),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppleTheme.appleGreen.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Text('🎉', style: TextStyle(fontSize: 16)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '30-Character Activity Milestone Unlocked! Ready to Checkout.',
                                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppleTheme.appleGreen),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () async {
                          final text = notesController.text.trim();
                          if (text.length < 30) {
                            Navigator.pop(ctx);
                            _showCheckoutErrorDialog('Session notes must be at least 30 characters long explaining what you studied today. (Current: ${text.length} / 30 characters)');
                            return;
                          }

                          Navigator.pop(ctx);
                          if (!mounted) return;
                          setState(() => loading = true);

                          try {
                            await ApiService.punchOut(
                              attendanceId: activeSession!.id,
                              notes: text,
                            );

                            if (!mounted) return;
                            setState(() {
                              activeSession = null;
                              timer?.cancel();
                              liveSyncTimer?.cancel();
                            });
                            _fetchAttendanceRecords();
                          } catch (e) {
                            if (!mounted) return;
                            _showCheckoutErrorDialog(e.toString().replaceAll('Exception: ', ''));
                          } finally {
                            if (mounted) setState(() => loading = false);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppleTheme.appleRose,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          'Confirm Punch Out',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatTimer(int totalSecs) {
    final hours = totalSecs ~/ 3600;
    final mins = (totalSecs % 3600) ~/ 60;
    final secs = totalSecs % 60;
    return '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final bool isPunchedIn = activeSession != null;

    return Scaffold(
      backgroundColor: AppleTheme.background,
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/logo.png',
                width: 32,
                height: 32,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SSSAM ACADEMY', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
                Text('Student Attendance Portal', style: GoogleFonts.inter(fontSize: 11, color: AppleTheme.secondaryText)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.phone_circle_fill, color: AppleTheme.appleGreen),
            onPressed: _showSupportOptionsDialog,
            tooltip: 'Support Lines',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _initDashboard,
        color: AppleTheme.appleGreen,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: _buildSelectedTabContent(),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFE5E5EA), width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedTabIndex,
          onTap: (index) => setState(() => _selectedTabIndex = index),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppleTheme.appleGreen,
          unselectedItemColor: AppleTheme.secondaryText,
          backgroundColor: Colors.white,
          elevation: 0,
          selectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 11),
          unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 11),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.hand_point_right_fill),
              label: 'Punch',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.calendar),
              label: 'Calendar',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.person_fill),
              label: 'Profile',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.phone_fill),
              label: 'Support',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedTabContent() {
    switch (_selectedTabIndex) {
      case 1:
        return _buildCalendarTabContent();
      case 2:
        return _buildProfileTabContent();
      case 3:
        return _buildSupportTabContent();
      case 0:
      default:
        return _buildPunchTabContent();
    }
  }

  // TAB 0: PUNCH CONSOLE
  Widget _buildPunchTabContent() {
    final bool isPunchedIn = activeSession != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 👋 Dynamic Welcome Greeting Banner
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0071E3), Color(0xFF34C759)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppleTheme.softShadow,
          ),
          child: Row(
            children: [
              const Text('👋', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome Back, ${currentUserState.name}!',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Ready for today's session? Verify location & punch in below.",
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withOpacity(0.95),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 1. Student Profile Header Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppleTheme.border),
            boxShadow: AppleTheme.softShadow,
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: _showFullImageDialog,
                child: CircleAvatar(
                  radius: 26,
                  backgroundColor: AppleTheme.appleGreen.withOpacity(0.12),
                  child: Text(
                    currentUserState.name.isNotEmpty
                        ? currentUserState.name[0].toUpperCase()
                        : 'S',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppleTheme.appleGreen,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          currentUserState.name,
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppleTheme.primaryText,
                          ),
                        ),
                        GestureDetector(
                          onTap: _showEditProfileDialog,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppleTheme.appleBlue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '✏️ Edit',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppleTheme.appleBlue,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2F2F7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            currentUserState.studentId,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppleTheme.appleGreen,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            currentUserState.email,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppleTheme.secondaryText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. Attendance Mode Segmented Control
        if (!isPunchedIn) ...[
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFEFEFF4),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => mode = 'location'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: mode == 'location' ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: mode == 'location' ? AppleTheme.softShadow : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.location_fill,
                            size: 16,
                            color: mode == 'location' ? AppleTheme.appleGreen : AppleTheme.secondaryText,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Offline (Location)',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: mode == 'location' ? AppleTheme.primaryText : AppleTheme.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => mode = 'online'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: mode == 'online' ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: mode == 'online' ? AppleTheme.softShadow : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.globe,
                            size: 16,
                            color: mode == 'online' ? AppleTheme.appleIndigo : AppleTheme.secondaryText,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Online',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: mode == 'online' ? AppleTheme.primaryText : AppleTheme.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // 3. Live Geofence GPS Card / Online Mode Status Pill
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppleTheme.border),
            boxShadow: AppleTheme.softShadow,
          ),
          child: mode == 'online'
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F2FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppleTheme.appleBlue.withOpacity(0.2)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(CupertinoIcons.info_circle_fill, color: AppleTheme.appleBlue, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Online Mode: Attendance will record your IP & device session.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppleTheme.appleBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(CupertinoIcons.location_solid, color: AppleTheme.appleBlue, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              'GPS Distance to Office:',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppleTheme.primaryText,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          distFromOffice != null ? '📍 ${distFromOffice!}m away' : 'Location Pending',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: distFromOffice != null && distFromOffice! <= officeRadius
                                ? AppleTheme.appleGreen
                                : AppleTheme.appleRose,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: distFromOffice != null && distFromOffice! <= officeRadius
                                ? AppleTheme.appleGreen.withOpacity(0.1)
                                : AppleTheme.appleRose.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            distFromOffice != null && distFromOffice! <= officeRadius
                                ? '🟢 Inside Geofence (Radius: ${officeRadius}m)'
                                : '🔴 Outside Office Area',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: distFromOffice != null && distFromOffice! <= officeRadius
                                  ? AppleTheme.appleGreen
                                  : AppleTheme.appleRose,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _checkLocation,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF2F2F7),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                refreshingGps
                                    ? const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(CupertinoIcons.refresh, size: 12, color: AppleTheme.appleBlue),
                                const SizedBox(width: 4),
                                Text(
                                  'Refresh GPS',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppleTheme.appleBlue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 28),

        // 4. Central Apple Pulsing Action Button (Punch In / Punch Out)
        Center(
          child: GestureDetector(
            onTap: loading ? null : _handleFingerprintTap,
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final scale = isPunchedIn ? 1.0 + (_pulseController.value * 0.05) : 1.0;
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: isPunchedIn
                            ? [AppleTheme.appleRose, const Color(0xFFFF6B63)]
                            : [AppleTheme.appleGreen, const Color(0xFF00C7BE)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (isPunchedIn ? AppleTheme.appleRose : AppleTheme.appleGreen)
                              .withOpacity(0.35),
                          blurRadius: 30,
                          spreadRadius: isPunchedIn ? 4 : 0,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isPunchedIn ? CupertinoIcons.square_fill : Icons.fingerprint,
                          color: Colors.white,
                          size: 54,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isPunchedIn ? 'PUNCH OUT' : 'PUNCH IN',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 1.0,
                          ),
                        ),
                        if (isPunchedIn) ...[
                          const SizedBox(height: 4),
                          Text(
                            _formatTimer(elapsedSeconds),
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 28),

        // 5a. Today's Quick Data Grid (Today Only!)
        Row(
          children: [
            Expanded(
              child: _buildKpiCard(
                title: "Today's Check-In",
                value: todayFirstCheckInStr,
                icon: CupertinoIcons.clock_fill,
                iconColor: AppleTheme.appleGreen,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKpiCard(
                title: "Today's Check-Out",
                value: todayLastCheckOutStr,
                icon: CupertinoIcons.clock_fill,
                iconColor: AppleTheme.appleBlue,
              ),
            ),
          ],
        ),

        // ⭐ LEAVE A STUDENT REVIEW BANNER
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => _launchURL('https://sudhirkr85.github.io/review/'),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFF8E7), Color(0xFFFFE8B3)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFF9500).withOpacity(0.4)),
              boxShadow: AppleTheme.softShadow,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF9500),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(CupertinoIcons.star_fill, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Leave Student Review', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: AppleTheme.primaryText)),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: const Color(0xFFFF9500), borderRadius: BorderRadius.circular(10)),
                            child: Text('⭐ 5.0 Star', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('Share your feedback directly on our review portal', style: GoogleFonts.inter(fontSize: 11, color: AppleTheme.secondaryText)),
                    ],
                  ),
                ),
                const Icon(CupertinoIcons.arrow_up_right, color: Color(0xFFFF9500), size: 16),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 5b. Quick Links Row (WhatsApp & Coding With Sudhir YouTube)
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _launchURL('https://chat.whatsapp.com/IoJv1FFdbNNGsSUN52ZZdS'),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppleTheme.border),
                    boxShadow: AppleTheme.softShadow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F8EE),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(CupertinoIcons.chat_bubble_text_fill, color: AppleTheme.appleGreen, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('WhatsApp', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppleTheme.primaryText)),
                            Text('Placement', style: GoogleFonts.inter(fontSize: 10, color: AppleTheme.secondaryText)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () => _launchURL('https://www.youtube.com/@CodingWithSudhir'),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppleTheme.border),
                    boxShadow: AppleTheme.softShadow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF0F0),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(CupertinoIcons.play_rectangle_fill, color: Color(0xFFFF0000), size: 18),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('YouTube', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppleTheme.primaryText)),
                            Text('CodingWithSudhir', style: GoogleFonts.inter(fontSize: 10, color: AppleTheme.secondaryText)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 5c. Social Hub Row (Instagram & LinkedIn)
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _launchURL('https://www.instagram.com/sssamacademy'),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppleTheme.border),
                    boxShadow: AppleTheme.softShadow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF0F6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(CupertinoIcons.camera_fill, color: Color(0xFFE1306C), size: 18),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Instagram', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppleTheme.primaryText)),
                            Text('@sssamacademy', style: GoogleFonts.inter(fontSize: 10, color: AppleTheme.secondaryText)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () => _launchURL('https://www.linkedin.com/company/sssamacademy'),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppleTheme.border),
                    boxShadow: AppleTheme.softShadow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F2FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(CupertinoIcons.briefcase_fill, color: Color(0xFF0A66C2), size: 18),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('LinkedIn', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppleTheme.primaryText)),
                            Text('SSSAM Academy', style: GoogleFonts.inter(fontSize: 10, color: AppleTheme.secondaryText)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSmallMetricCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppleTheme.border),
        boxShadow: AppleTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: AppleTheme.secondaryText)),
          const SizedBox(height: 2),
          Text(value, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }

  // TAB 1: CALENDAR & ATTENDANCE HISTORY
  Widget _buildCalendarTabContent() {
    final String monthYearStr = DateFormat('MMMM yyyy').format(_calendarSelectedMonth);
    
    // Filter records for selected month
    final filteredRecords = records.where((r) {
      return r.punchInTime.year == _calendarSelectedMonth.year && r.punchInTime.month == _calendarSelectedMonth.month;
    }).toList();

    final int presentDays = filteredRecords.map((r) => DateFormat('yyyy-MM-dd').format(r.punchInTime)).toSet().length;
    final int sessionsCount = filteredRecords.length;
    final int totalMins = filteredRecords.fold(0, (sum, r) => sum + r.durationMinutes);
    final double totalHours = totalMins / 60.0;
    final double avgHours = presentDays > 0 ? (totalHours / presentDays) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Month Selector Header Bar (Prev, Title, Next)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppleTheme.border),
            boxShadow: AppleTheme.softShadow,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () {
                  setState(() {
                    _calendarSelectedMonth = DateTime(_calendarSelectedMonth.year, _calendarSelectedMonth.month - 1);
                  });
                },
                icon: const Icon(CupertinoIcons.chevron_left_circle_fill, color: AppleTheme.appleBlue, size: 28),
                tooltip: 'Previous Month',
              ),
              Column(
                children: [
                  Text(
                    monthYearStr,
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: AppleTheme.primaryText),
                  ),
                  Text(
                    'Monthly Attendance Summary',
                    style: GoogleFonts.inter(fontSize: 10, color: AppleTheme.secondaryText),
                  ),
                ],
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _calendarSelectedMonth = DateTime(_calendarSelectedMonth.year, _calendarSelectedMonth.month + 1);
                  });
                },
                icon: const Icon(CupertinoIcons.chevron_right_circle_fill, color: AppleTheme.appleBlue, size: 28),
                tooltip: 'Next Month',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. Summary Metrics Grid
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          children: [
            _buildSmallMetricCard('PRESENT DAYS', '$presentDays Days', AppleTheme.appleGreen),
            _buildSmallMetricCard('SESSIONS ATTENDED', '$sessionsCount Sessions', AppleTheme.appleBlue),
            _buildSmallMetricCard('TOTAL HOURS', '${totalHours.toStringAsFixed(1)} Hrs', const Color(0xFF30B0C7)),
            _buildSmallMetricCard('AVG HOURS / DAY', '${avgHours.toStringAsFixed(1)} Hrs', const Color(0xFFFF9500)),
          ],
        ),
        const SizedBox(height: 16),

        // 3. Monthly Visual Calendar Grid (Tap Date for details)
        _buildMonthlyCalendarGrid(),
        const SizedBox(height: 20),

        // 4. Attendance History Logs List
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Attendance Logs ($monthYearStr)',
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppleTheme.primaryText),
            ),
            if (refreshingLogs)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
        const SizedBox(height: 12),

        if (filteredRecords.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppleTheme.border),
            ),
            child: Center(
              child: Text(
                'No attendance records found for $monthYearStr.',
                style: GoogleFonts.inter(fontSize: 13, color: AppleTheme.secondaryText),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filteredRecords.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = filteredRecords[index];
              final String formattedDate = DateFormat('EEE, d MMM yyyy').format(item.punchInTime);
              final String inTime = DateFormat('hh:mm a').format(item.punchInTime);
              final String outTime = item.punchOutTime != null
                  ? DateFormat('hh:mm a').format(item.punchOutTime!)
                  : 'Active Session';

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppleTheme.border),
                  boxShadow: AppleTheme.softShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(formattedDate, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppleTheme.primaryText)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: item.status == 'active' ? AppleTheme.appleGreen.withOpacity(0.1) : const Color(0xFFF2F2F7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            item.status == 'active' ? '● PUNCHED IN' : '${item.durationMinutes} Mins',
                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: item.status == 'active' ? AppleTheme.appleGreen : AppleTheme.secondaryText),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('In: $inTime   ➔   Out: $outTime', style: GoogleFonts.inter(fontSize: 12, color: AppleTheme.secondaryText)),
                        Text(
                          item.classMode == 'online' || item.mode == 'online' ? '💻 ONLINE' : '🏫 OFFLINE',
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: item.classMode == 'online' || item.mode == 'online' ? AppleTheme.appleBlue : AppleTheme.appleGreen),
                        ),
                      ],
                    ),
                    if (item.notes != null && item.notes!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: const Color(0xFFF9F9FB), borderRadius: BorderRadius.circular(10)),
                        child: Text('📝 Notes: ${item.notes}', style: GoogleFonts.inter(fontSize: 12, color: AppleTheme.primaryText)),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildMonthlyCalendarGrid() {
    final int daysInMonth = DateTime(_calendarSelectedMonth.year, _calendarSelectedMonth.month + 1, 0).day;
    final int firstWeekday = DateTime(_calendarSelectedMonth.year, _calendarSelectedMonth.month, 1).weekday;
    final int leadingEmpty = firstWeekday - 1;

    final Map<String, List<AttendanceModel>> dateRecordMap = {};
    for (var r in records) {
      final key = DateFormat('yyyy-MM-dd').format(r.punchInTime);
      dateRecordMap.putIfAbsent(key, () => []).add(r);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppleTheme.border),
        boxShadow: AppleTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Monthly Attendance Calendar', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: AppleTheme.primaryText)),
              Text('👉 Tap date for details', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: AppleTheme.appleBlue)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: ['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((day) {
              return Expanded(
                child: Center(
                  child: Text(day, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppleTheme.secondaryText)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: leadingEmpty + daysInMonth,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 1.0,
            ),
            itemBuilder: (context, index) {
              if (index < leadingEmpty) {
                return const SizedBox.shrink();
              }
              final int dayNum = index - leadingEmpty + 1;
              final DateTime dateObj = DateTime(_calendarSelectedMonth.year, _calendarSelectedMonth.month, dayNum);
              final String dateKey = DateFormat('yyyy-MM-dd').format(dateObj);
              final dayRecords = dateRecordMap[dateKey] ?? [];
              final bool isPresent = dayRecords.isNotEmpty;
              final bool isToday = _isToday(dateObj);

              return GestureDetector(
                onTap: () {
                  _showDateDetailModal(dateObj, dayRecords);
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isPresent ? const Color(0xFFE8F8EE) : (isToday ? const Color(0xFFE8F2FF) : const Color(0xFFF9F9FB)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isPresent
                          ? const Color(0xFF34C759).withOpacity(0.5)
                          : (isToday ? AppleTheme.appleBlue : AppleTheme.border),
                      width: isToday ? 1.5 : 1.0,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$dayNum',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: isPresent ? AppleTheme.appleGreen : AppleTheme.primaryText,
                        ),
                      ),
                      if (isPresent)
                        FittedBox(
                          child: Text(
                            '${dayRecords.length} sess',
                            style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.w700, color: AppleTheme.appleGreen),
                          ),
                        )
                      else if (isToday)
                        FittedBox(
                          child: Text(
                            'Today',
                            style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.w700, color: AppleTheme.appleBlue),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showDateDetailModal(DateTime dateObj, List<AttendanceModel> dayRecords) {
    final String formattedFullDate = DateFormat('EEEE, d MMMM yyyy').format(dateObj);
    final bool isPresent = dayRecords.isNotEmpty;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(formattedFullDate, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: AppleTheme.primaryText)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isPresent ? const Color(0xFFE8F8EE) : const Color(0xFFFFF0F0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      isPresent ? 'PRESENT' : 'NO SESSION',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: isPresent ? AppleTheme.appleGreen : const Color(0xFFFF3B30)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (!isPresent)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text('No attendance recorded for this date.', style: GoogleFonts.inter(fontSize: 13, color: AppleTheme.secondaryText)),
                  ),
                )
              else ...[
                Text('Sessions Recorded (${dayRecords.length}):', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppleTheme.primaryText)),
                const SizedBox(height: 10),
                ...dayRecords.map((item) {
                  final String inTime = DateFormat('hh:mm a').format(item.punchInTime);
                  final String outTime = item.punchOutTime != null
                      ? DateFormat('hh:mm a').format(item.punchOutTime!)
                      : 'Active Session';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9F9FB),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppleTheme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('In: $inTime   ➔   Out: $outTime', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppleTheme.primaryText)),
                            Text('${item.durationMinutes} mins', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppleTheme.appleBlue)),
                          ],
                        ),
                        if (item.notes != null && item.notes!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('Notes: ${item.notes}', style: GoogleFonts.inter(fontSize: 11, color: AppleTheme.secondaryText)),
                        ],
                      ],
                    ),
                  );
                }),
              ],
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  // TAB 2: PROFILE & SETTINGS
  Widget _buildProfileTabContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Profile Avatar Header Card with Camera Overlay
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppleTheme.border),
            boxShadow: AppleTheme.softShadow,
          ),
          child: Column(
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  GestureDetector(
                    onTap: _showFullImageDialog,
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: AppleTheme.appleGreen.withOpacity(0.12),
                      child: Text(
                        currentUserState.name.isNotEmpty ? currentUserState.name[0].toUpperCase() : 'S',
                        style: GoogleFonts.inter(fontSize: 36, fontWeight: FontWeight.w800, color: AppleTheme.appleGreen),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _showEditProfileDialog,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: AppleTheme.appleBlue,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(CupertinoIcons.camera_fill, color: Colors.white, size: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(currentUserState.name, style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: AppleTheme.primaryText)),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFFE8F8EE), borderRadius: BorderRadius.circular(10)),
                    child: Text('Student ID: ${currentUserState.studentId}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppleTheme.appleGreen)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFFE8F2FF), borderRadius: BorderRadius.circular(10)),
                    child: Text('Active Student', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppleTheme.appleBlue)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. Inline Profile Details Edit Card (Name & Phone)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppleTheme.border),
            boxShadow: AppleTheme.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('✏️ Edit Profile Details', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: AppleTheme.primaryText)),
                  const Icon(CupertinoIcons.person_crop_circle_badge_checkmark, color: AppleTheme.appleBlue, size: 20),
                ],
              ),
              const SizedBox(height: 14),
              if (_profileInlineError != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFFFF0F0), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFF3B30).withOpacity(0.3))),
                  child: Text(_profileInlineError!, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFFFF3B30))),
                ),
                const SizedBox(height: 12),
              ],
              Text('Full Name *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppleTheme.primaryText)),
              const SizedBox(height: 6),
              TextField(
                controller: _profileNameController,
                decoration: InputDecoration(
                  hintText: 'Enter full name',
                  filled: true,
                  fillColor: const Color(0xFFF5F5F7),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 14),
              Text('10-Digit Mobile Number *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppleTheme.primaryText)),
              const SizedBox(height: 6),
              TextField(
                controller: _profilePhoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: 'Enter 10-digit mobile number',
                  filled: true,
                  fillColor: const Color(0xFFF5F5F7),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 14),
              Text('Registered Email', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppleTheme.secondaryText)),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(12)),
                child: Text(currentUserState.email, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppleTheme.secondaryText)),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: _isSavingProfileInline
                      ? null
                      : () async {
                          final name = _profileNameController.text.trim();
                          final phone = _profilePhoneController.text.trim();
                          if (name.isEmpty) {
                            setState(() => _profileInlineError = 'Full Name is required.');
                            return;
                          }
                          if (phone.isNotEmpty && phone.length != 10) {
                            setState(() => _profileInlineError = 'Mobile Number must be exactly 10 digits.');
                            return;
                          }
                          setState(() {
                            _isSavingProfileInline = true;
                            _profileInlineError = null;
                          });
                          try {
                            final updatedUser = await ApiService.updateProfile(
                              studentId: currentUserState.studentId,
                              name: name,
                              email: currentUserState.email,
                              phone: phone,
                            );
                            if (mounted) {
                              setState(() {
                                currentUserState = updatedUser;
                                _isSavingProfileInline = false;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('🎉 Profile details saved successfully!')),
                              );
                            }
                          } catch (err) {
                            if (mounted) {
                              setState(() {
                                _isSavingProfileInline = false;
                                _profileInlineError = err.toString().replaceAll('Exception: ', '');
                              });
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppleTheme.appleBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _isSavingProfileInline
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(CupertinoIcons.checkmark_seal_fill, color: Colors.white, size: 18),
                  label: Text('Save Profile Changes', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 3. Campus Info Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppleTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('🏫 Campus Geofence Settings', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppleTheme.primaryText)),
              const SizedBox(height: 6),
              Text('Campus Radius: ${officeRadius}m', style: GoogleFonts.inter(fontSize: 12, color: AppleTheme.secondaryText)),
              Text('Location: Sector 14, Old DLF, Gurugram', style: GoogleFonts.inter(fontSize: 12, color: AppleTheme.secondaryText)),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // 4. Sign Out Button
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: widget.onLogout,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFFF3B30)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(CupertinoIcons.square_arrow_right, color: Color(0xFFFF3B30), size: 18),
            label: Text('Sign Out', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFFFF3B30))),
          ),
        ),
      ],
    );
  }

  // TAB 3: SUPPORT & ESCALATION DESK
  Widget _buildSupportTabContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Primary Support Line Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF34C759).withOpacity(0.3)),
            boxShadow: AppleTheme.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFFE8F8EE), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(CupertinoIcons.phone_fill, color: AppleTheme.appleGreen, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Primary Support Line', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: AppleTheme.primaryText)),
                      Text('Standard Help & Student Queries', style: GoogleFonts.inter(fontSize: 11, color: AppleTheme.secondaryText)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('+91 9517447689  /  +91 9217031899', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppleTheme.appleGreen)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final url = Uri.parse('tel:+919517447689');
                    if (await canLaunchUrl(url)) await launchUrl(url);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppleTheme.appleGreen,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(CupertinoIcons.phone, color: Colors.white, size: 16),
                  label: Text('Contact Primary Support', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // High Authority Escalation Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFF3B30).withOpacity(0.3)),
            boxShadow: AppleTheme.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFFFFF0F0), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Color(0xFFFF3B30), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('High Authority Escalation', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: AppleTheme.primaryText)),
                        Text('Priority Review for Unresolved Issues', style: GoogleFonts.inter(fontSize: 11, color: AppleTheme.secondaryText)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _showHighAuthorityEscalationDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF3B30),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(CupertinoIcons.shield_fill, color: Colors.white, size: 16),
                  label: Text('Submit Escalation Request', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Placement Group Card
        GestureDetector(
          onTap: () async {
            final url = Uri.parse('https://chat.whatsapp.com/IoJv1FFdbNNGsSUN52ZZdS');
            if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppleTheme.border),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFE8F2FF), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(CupertinoIcons.chat_bubble_2_fill, color: AppleTheme.appleBlue, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Official WhatsApp Group', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppleTheme.primaryText)),
                      Text('Join SSSAM Placement Community', style: GoogleFonts.inter(fontSize: 11, color: AppleTheme.secondaryText)),
                    ],
                  ),
                ),
                const Icon(CupertinoIcons.arrow_up_right, color: AppleTheme.appleBlue, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppleTheme.border),
        boxShadow: AppleTheme.softShadow,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppleTheme.secondaryText,
                ),
              ),
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppleTheme.primaryText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
