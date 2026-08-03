import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../theme/apple_theme.dart';

enum AuthMode { login, register, forgotPassword }

class AuthScreen extends StatefulWidget {
  final Function(UserModel) onLoginSuccess;

  const AuthScreen({super.key, required this.onLoginSuccess});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  AuthMode authMode = AuthMode.login;
  bool showPassword = false;
  bool loading = false;
  bool otpSent = false;
  String? errorMsg;
  String? successMsg;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController otpController = TextEditingController();
  final TextEditingController newPasswordController = TextEditingController();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: '497495591959-n4jkv915l9mtmuidof19j3dfqo5d9r64.apps.googleusercontent.com',
    scopes: ['email', 'profile'],
  );

  // Send OTP for Registration or Password Reset
  Future<void> _handleSendOtp() async {
    setState(() {
      errorMsg = null;
      successMsg = null;
    });

    final String email = emailController.text.trim();
    if (email.isEmpty) {
      setState(() => errorMsg = 'Please enter your email address.');
      return;
    }

    if (authMode == AuthMode.register) {
      if (nameController.text.trim().isEmpty) {
        setState(() => errorMsg = 'Please enter your full name.');
        return;
      }
      if (passwordController.text.trim().length < 6) {
        setState(() => errorMsg = 'Password must be at least 6 characters.');
        return;
      }
    }

    setState(() => loading = true);

    try {
      if (authMode == AuthMode.register) {
        await ApiService.sendRegistrationOtp(email);
        setState(() {
          otpSent = true;
          successMsg = '6-digit OTP code sent to $email via Brevo Email!';
        });
      } else if (authMode == AuthMode.forgotPassword) {
        await ApiService.sendForgotPasswordOtp(email);
        setState(() {
          otpSent = true;
          successMsg = 'Password reset OTP code sent to $email via Brevo Email!';
        });
      }
    } catch (e) {
      setState(() {
        errorMsg = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // Handle Form Submission (Login, Register with OTP, or Reset Password)
  Future<void> _handleSubmit() async {
    setState(() {
      errorMsg = null;
      successMsg = null;
    });

    final String email = emailController.text.trim();
    final String password = passwordController.text.trim();

    if (email.isEmpty) {
      setState(() => errorMsg = 'Email address is required.');
      return;
    }

    setState(() => loading = true);

    try {
      if (authMode == AuthMode.login) {
        if (password.isEmpty) {
          setState(() => errorMsg = 'Password is required.');
          return;
        }
        final user = await ApiService.login(email, password);
        await StorageService.saveUser(user);
        widget.onLoginSuccess(user);
      } else if (authMode == AuthMode.register) {
        final String otp = otpController.text.trim();
        if (otp.length < 6) {
          setState(() => errorMsg = 'Please enter 6-digit OTP verification code.');
          return;
        }

        final user = await ApiService.register(
          name: nameController.text.trim(),
          email: email,
          password: password,
          otp: otp,
        );

        await StorageService.saveUser(user);
        widget.onLoginSuccess(user);
      } else if (authMode == AuthMode.forgotPassword) {
        final String otp = otpController.text.trim();
        final String newPass = newPasswordController.text.trim();

        if (otp.length < 6) {
          setState(() => errorMsg = 'Please enter 6-digit OTP verification code.');
          return;
        }
        if (newPass.length < 6) {
          setState(() => errorMsg = 'New password must be at least 6 characters.');
          return;
        }

        await ApiService.resetPassword(
          email: email,
          otp: otp,
          newPassword: newPass,
        );

        setState(() {
          authMode = AuthMode.login;
          otpSent = false;
          successMsg = 'Password reset successfully! Please sign in with your new password.';
        });
      }
    } catch (e) {
      setState(() {
        errorMsg = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // Handle Google Sign-In
  Future<void> _handleGoogleLogin() async {
    setState(() {
      loading = true;
      errorMsg = null;
    });

    try {
      try {
        await _googleSignIn.signOut();
      } catch (_) {}

      final GoogleSignInAccount? account = await _googleSignIn.signIn();

      if (account == null) {
        setState(() => loading = false);
        return;
      }

      final String googleEmail = account.email;
      final String googleName = account.displayName ?? account.email.split('@')[0];

      final user = await ApiService.googleLogin(googleEmail, googleName);
      await StorageService.saveUser(user);
      widget.onLoginSuccess(user);
    } catch (e) {
      setState(() {
        errorMsg = 'Google Sign-In Error: ${e.toString().replaceAll('Exception: ', '')}';
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
                  // SSSAM Official Logo Badge
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        'assets/logo.png',
                        width: 64,
                        height: 64,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'SSSAM ACADEMY',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppleTheme.appleGreen,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Title & Subtitle
                  Text(
                    authMode == AuthMode.register
                        ? 'Create Student Account'
                        : authMode == AuthMode.forgotPassword
                            ? 'Forgot Password'
                            : 'SSSAM Student Portal',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppleTheme.primaryText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    authMode == AuthMode.register
                        ? 'Verify email OTP to register your account'
                        : authMode == AuthMode.forgotPassword
                            ? 'Enter your email to receive password reset OTP'
                            : 'Sign in to access your attendance & GPS check-in',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppleTheme.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Success Alert
                  if (successMsg != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppleTheme.appleGreen.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppleTheme.appleGreen.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(CupertinoIcons.checkmark_circle_fill,
                              color: AppleTheme.appleGreen, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              successMsg!,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppleTheme.appleGreen,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

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

                  // Registration Full Name
                  if (authMode == AuthMode.register) ...[
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

                  // Password Input (For Login & Registration)
                  if (authMode != AuthMode.forgotPassword) ...[
                    _buildTextField(
                      controller: passwordController,
                      placeholder: 'Password',
                      icon: CupertinoIcons.lock,
                      isPassword: true,
                      showPassword: showPassword,
                      onTogglePassword: () => setState(() => showPassword = !showPassword),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // OTP Code Field (If OTP sent during Register or Forgot Password)
                  if ((authMode == AuthMode.register || authMode == AuthMode.forgotPassword) && otpSent) ...[
                    _buildTextField(
                      controller: otpController,
                      placeholder: 'Enter 6-Digit Email OTP',
                      icon: Icons.shield,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 14),
                  ],

                  // New Password Field (For Forgot Password Reset)
                  if (authMode == AuthMode.forgotPassword && otpSent) ...[
                    _buildTextField(
                      controller: newPasswordController,
                      placeholder: 'New Password',
                      icon: CupertinoIcons.lock_shield,
                      isPassword: true,
                      showPassword: showPassword,
                      onTogglePassword: () => setState(() => showPassword = !showPassword),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Forgot Password Link (In Login Mode)
                  if (authMode == AuthMode.login) ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          setState(() {
                            authMode = AuthMode.forgotPassword;
                            errorMsg = null;
                            successMsg = null;
                            otpSent = false;
                          });
                        },
                        child: Text(
                          'Forgot Password?',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppleTheme.appleBlue,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Action Buttons
                  if ((authMode == AuthMode.register || authMode == AuthMode.forgotPassword) && !otpSent) ...[
                    // Step 1: Request OTP
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: loading ? null : _handleSendOtp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppleTheme.appleEmerald,
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
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Get Email Verification OTP',
                                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(CupertinoIcons.paperplane, size: 16),
                                ],
                              ),
                      ),
                    ),
                  ] else ...[
                    // Step 2: Submit Form (Login / Complete Register / Reset Password)
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: loading ? null : _handleSubmit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: authMode == AuthMode.forgotPassword
                              ? AppleTheme.appleRose
                              : AppleTheme.appleGreen,
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
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    authMode == AuthMode.register
                                        ? 'Verify OTP & Register'
                                        : authMode == AuthMode.forgotPassword
                                            ? 'Reset Password'
                                            : 'Sign In',
                                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(CupertinoIcons.arrow_right, size: 18),
                                ],
                              ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Divider & Google Auth (For Login / Register)
                  if (authMode != AuthMode.forgotPassword) ...[
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
                  ],

                  // Mode Toggle Button (Sign In <-> Register <-> Forgot)
                  Center(
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          if (authMode == AuthMode.login) {
                            authMode = AuthMode.register;
                          } else {
                            authMode = AuthMode.login;
                          }
                          errorMsg = null;
                          successMsg = null;
                          otpSent = false;
                        });
                      },
                      child: Text(
                        authMode == AuthMode.register
                            ? 'Already have an account? Sign In'
                            : authMode == AuthMode.forgotPassword
                                ? 'Back to Sign In'
                                : 'Don\'t have an account? Register with OTP',
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
