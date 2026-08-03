import 'package:flutter/material.dart';
import 'models/user_model.dart';
import 'screens/auth_screen.dart';
import 'screens/student_dashboard_screen.dart';
import 'services/storage_service.dart';
import 'theme/apple_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StudentApp());
}

class StudentApp extends StatefulWidget {
  const StudentApp({super.key});

  @override
  State<StudentApp> createState() => _StudentAppState();
}

class _StudentAppState extends State<StudentApp> {
  UserModel? currentUser;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _checkUserSession();
  }

  Future<void> _checkUserSession() async {
    final user = await StorageService.getUser();
    setState(() {
      currentUser = user;
      loading = false;
    });
  }

  void _handleLoginSuccess(UserModel user) {
    setState(() {
      currentUser = user;
    });
  }

  void _handleLogout() async {
    await StorageService.clearUser();
    setState(() {
      currentUser = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GeoTrack Student',
      debugShowCheckedModeBanner: false,
      theme: AppleTheme.theme,
      home: loading
          ? const Scaffold(
              backgroundColor: AppleTheme.background,
              body: Center(
                child: CircularProgressIndicator(color: AppleTheme.appleGreen),
              ),
            )
          : currentUser != null
              ? StudentDashboardScreen(
                  currentUser: currentUser!,
                  onLogout: _handleLogout,
                )
              : AuthScreen(
                  onLoginSuccess: _handleLoginSuccess,
                ),
    );
  }
}
