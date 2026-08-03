import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
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
  String mode = 'location'; // 'location' (offline) | 'online'
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
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initDashboard() async {
    await _fetchOfficeSettings();
    await _fetchAttendanceRecords();
    await _checkLocation();
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

      // Check geofence if offline mode
      if (mode == 'location' && distFromOffice != null && distFromOffice! > officeRadius) {
        showCupertinoDialog(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('⚠️ Outside Office Area'),
            content: Text(
              'You are currently ${distFromOffice!}m away from Office.\nAllowed distance is within ${officeRadius}m.\n\nPlease move closer to Office to punch in.',
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

  void _showPunchOutModal() {
    final notesController = TextEditingController();
    String? errorText;

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
                    const SizedBox(height: 16),
                    if (errorText != null) ...[
                      Text(
                        errorText!,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppleTheme.appleRose,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
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
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () async {
                          final text = notesController.text.trim();
                          if (text.length < 30) {
                            setModalState(() {
                              errorText = 'Study notes must be at least 30 characters!';
                            });
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
                            showCupertinoDialog(
                              context: context,
                              builder: (c) => CupertinoAlertDialog(
                                title: const Text('Error'),
                                content: Text(e.toString().replaceAll('Exception: ', '')),
                                actions: [
                                  CupertinoDialogAction(
                                    child: const Text('OK'),
                                    onPressed: () => Navigator.pop(c),
                                  ),
                                ],
                              ),
                            );
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
            icon: const Icon(CupertinoIcons.square_arrow_right, color: AppleTheme.appleRose),
            onPressed: widget.onLogout,
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _initDashboard,
        color: AppleTheme.appleGreen,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: AppleTheme.appleGreen.withOpacity(0.12),
                      child: Text(
                        widget.currentUser.name.isNotEmpty
                            ? widget.currentUser.name[0].toUpperCase()
                            : 'S',
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppleTheme.appleGreen,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.currentUser.name,
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppleTheme.primaryText,
                            ),
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
                                  widget.currentUser.studentId,
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
                                  widget.currentUser.email,
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

              // 3. Live Geofence GPS Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppleTheme.border),
                  boxShadow: AppleTheme.softShadow,
                ),
                child: Column(
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

              // 5. KPI Summary Cards Row
              Row(
                children: [
                  Expanded(
                    child: _buildKpiCard(
                      title: 'Total Sessions',
                      value: '${records.length}',
                      icon: CupertinoIcons.calendar_badge_plus,
                      iconColor: AppleTheme.appleBlue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildKpiCard(
                      title: 'Current Mode',
                      value: isPunchedIn
                          ? activeSession!.mode.toUpperCase()
                          : mode.toUpperCase(),
                      icon: CupertinoIcons.location_circle,
                      iconColor: AppleTheme.appleGreen,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 6. Recent Attendance Log History Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'My Attendance History',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppleTheme.primaryText,
                    ),
                  ),
                  if (refreshingLogs)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Attendance History Items
              if (records.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppleTheme.border),
                  ),
                  child: Center(
                    child: Text(
                      'No attendance records found yet.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppleTheme.secondaryText,
                      ),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: records.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = records[index];
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
                              Text(
                                formattedDate,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppleTheme.primaryText,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: item.status == 'active'
                                      ? AppleTheme.appleGreen.withOpacity(0.1)
                                      : const Color(0xFFF2F2F7),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  item.status == 'active' ? '● PUNCHED IN' : '${item.durationMinutes} Mins',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: item.status == 'active' ? AppleTheme.appleGreen : AppleTheme.secondaryText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'In: $inTime   ➔   Out: $outTime',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppleTheme.secondaryText,
                                ),
                              ),
                              Text(
                                'Mode: ${item.mode.toUpperCase()}',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppleTheme.appleBlue,
                                ),
                              ),
                            ],
                          ),
                          if (item.notes != null && item.notes!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF9F9FB),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '📝 Notes: ${item.notes}',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppleTheme.primaryText,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
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
