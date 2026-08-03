import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../theme/apple_theme.dart';

class AuthScreen extends StatefulWidget {
  final Function(UserModel) onLoginSuccess;

  const AuthScreen({super.key, required this.onLoginSuccess});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isRegister = false;
  bool showPassword = false;
  bool loading = false;
  String? errorMsg;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  Future<void> _handleSubmit() async {
    setState(() {
      errorMsg = null;
    });

    final String email = emailController.text.trim();
    final String password = passwordController.text.trim();
    final String name = nameController.text.trim();

    if (email.isEmpty) {
      setState(() => errorMsg = 'Email address is required.');
      return;
    }
    if (password.isEmpty) {
      setState(() => errorMsg = 'Password is required.');
      return;
    }
    if (isRegister && name.isEmpty) {
      setState(() => errorMsg = 'Full name is required.');
      return;
    }
    if (password.length < 6) {
      setState(() => errorMsg = 'Password must be at least 6 characters.');
      return;
    }

    setState(() => loading = true);

    try {
      UserModel user;
      if (isRegister) {
        user = await ApiService.register(name, email, password);
      } else {
        user = await ApiService.login(email, password);
      }

      await StorageService.saveUser(user);
      widget.onLoginSuccess(user);
    } catch (e) {
      setState(() {
        errorMsg = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _handleGoogleLogin() async {
    final String email = emailController.text.trim();
    String targetEmail = email;

    if (targetEmail.isEmpty) {
      final String? input = await showCupertinoDialog<String>(
        context: context,
        builder: (ctx) {
          final textCtrl = TextEditingController(text: 'student.google@gmail.com');
          return CupertinoAlertDialog(
            title: const Text('Google Sign-In'),
            content: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: CupertinoTextField(
                controller: textCtrl,
                placeholder: 'Enter Google Email',
                keyboardType: TextInputType.emailAddress,
              ),
            ),
            actions: [
              CupertinoDialogAction(
                child: const Text('Cancel'),
                onPressed: () => Navigator.pop(ctx, null),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                child: const Text('Sign In'),
                onPressed: () => Navigator.pop(ctx, textCtrl.text.trim()),
              ),
            ],
          );
        },
      );

      if (input == null || input.isEmpty) return;
      targetEmail = input;
    }

    setState(() {
      loading = true;
      errorMsg = null;
    });

    try {
      final user = await ApiService.googleLogin(
        targetEmail,
        nameController.text.trim().isNotEmpty
            ? nameController.text.trim()
            : targetEmail.split('@')[0],
      );

      await StorageService.saveUser(user);
      widget.onLoginSuccess(user);
    } catch (e) {
      setState(() {
        errorMsg = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext me) {
    return Scaffold(
      backgroundColor: AppleTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppleTheme.border, width: 1),
                boxShadow: AppleTheme.softShadow,
              ),
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Apple Icon Badge
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppleTheme.appleEmerald, Color(0xFF00B0A6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppleTheme.appleEmerald.withOpacity(0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.fingerprint,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Title & Description
                  Text(
                    isRegister ? 'Create Account' : 'Student Portal',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppleTheme.primaryText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isRegister
                        ? 'Register your student details for attendance'
                        : 'Sign in to access your attendance & GPS check-in',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppleTheme.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Error Alert
                  if (errorMsg != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppleTheme.appleRose.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppleTheme.appleRose.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(CupertinoIcons.exclamationmark_triangle_fill,
                              color: AppleTheme.appleRose, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              errorMsg!,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppleTheme.appleRose,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Registration Name Input
                  if (isRegister) ...[
                    _buildTextField(
                      controller: nameController,
                      placeholder: 'Full Name',
                      icon: CupertinoIcons.person,
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Email Input
                  _buildTextField(
                    controller: emailController,
                    placeholder: 'Student Email Address',
                    icon: CupertinoIcons.mail,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 14),

                  // Password Input
                  _buildTextField(
                    controller: passwordController,
                    placeholder: 'Password',
                    icon: CupertinoIcons.lock,
                    isPassword: true,
                    showPassword: showPassword,
                    onTogglePassword: () => setState(() => showPassword = !showPassword),
                  ),
                  const SizedBox(height: 24),

                  // Primary Submit Button
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: loading ? null : _handleSubmit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppleTheme.appleGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  isRegister ? 'Register Account' : 'Sign In',
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(CupertinoIcons.arrow_right, size: 18),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Divider
                  Row(
                    children: [
                      const Expanded(child: Divider(color: AppleTheme.border)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'OR',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppleTheme.secondaryText,
                          ),
                        ),
                      ),
                      const Expanded(child: Divider(color: AppleTheme.border)),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Google Sign-In Button
                  OutlinedButton(
                    onPressed: loading ? null : _handleGoogleLogin,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      side: const BorderSide(color: AppleTheme.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      backgroundColor: Colors.white,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(CupertinoIcons.globe, color: AppleTheme.appleBlue, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          'Continue with Google',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppleTheme.primaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Switch between Login and Register
                  Center(
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          isRegister = !isRegister;
                          errorMsg = null;
                        });
                      },
                      child: Text(
                        isRegister
                            ? 'Already have an account? Sign In'
                            : 'Don\'t have an account? Register',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppleTheme.appleBlue,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String placeholder,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool isPassword = false,
    bool showPassword = false,
    VoidCallback? onTogglePassword,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppleTheme.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: TextField(
        controller: controller,
        obscureText: isPassword && !showPassword,
        keyboardType: keyboardType,
        style: GoogleFonts.inter(fontSize: 14, color: AppleTheme.primaryText),
        decoration: InputDecoration(
          icon: Icon(icon, color: AppleTheme.secondaryText, size: 18),
          hintText: placeholder,
          hintStyle: GoogleFonts.inter(fontSize: 14, color: AppleTheme.secondaryText),
          border: InputBorder.none,
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    showPassword ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                    color: AppleTheme.secondaryText,
                    size: 18,
                  ),
                  onPressed: onTogglePassword,
                )
              : null,
        ),
      ),
    );
  }
}
