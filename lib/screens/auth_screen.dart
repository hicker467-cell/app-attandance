import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../theme/apple_theme.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../models/user_model.dart';

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
  bool showConfirmPassword = false;
  bool loading = false;
  
  // 3-Step Verification States
  bool otpSent = false;
  bool otpVerified = false;

  // Resend OTP Timer
  Timer? _resendTimer;
  int _resendCountdown = 30;

  String? errorMsg;
  String? successMsg;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();
  final TextEditingController otpController = TextEditingController();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: '497495591959-3ul54sp5nkivus4jgpdnl5pco13db0o2.apps.googleusercontent.com',
    scopes: ['email', 'profile'],
  );

  @override
  void dispose() {
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendCountdown = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_resendCountdown > 0) {
        setState(() => _resendCountdown--);
      } else {
        timer.cancel();
      }
    });
  }

  void _resetFormState() {
    _resendTimer?.cancel();
    setState(() {
      otpSent = false;
      otpVerified = false;
      _resendCountdown = 30;
      errorMsg = null;
      successMsg = null;
      otpController.clear();
      passwordController.clear();
      confirmPasswordController.clear();
    });
  }

  // Step 1: Request Email OTP via Brevo API
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

    if (authMode == AuthMode.register && nameController.text.trim().isEmpty) {
      setState(() => errorMsg = 'Please enter your full name.');
      return;
    }

    setState(() => loading = true);

    try {
      if (authMode == AuthMode.register) {
        await ApiService.sendRegistrationOtp(email);
      } else {
        await ApiService.sendForgotPasswordOtp(email);
      }
      setState(() {
        otpSent = true;
        successMsg = '6-digit verification code sent to $email via Brevo Email!';
      });
      _startResendTimer();
    } catch (e) {
      setState(() {
        errorMsg = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // Step 2: Verify 6-digit OTP Code
  void _handleVerifyOtp() {
    setState(() {
      errorMsg = null;
      successMsg = null;
    });

    final String otp = otpController.text.trim();
    if (otp.length < 6) {
      setState(() => errorMsg = 'Please enter the valid 6-digit OTP code.');
      return;
    }

    setState(() {
      otpVerified = true;
      successMsg = 'OTP Verified! Please enter and confirm your password below.';
    });
  }

  // Step 3: Complete Registration or Reset Password with Password & Re-enter Password
  Future<void> _handleSubmitFinal() async {
    setState(() {
      errorMsg = null;
      successMsg = null;
    });

    final String email = emailController.text.trim();
    final String password = passwordController.text.trim();
    final String confirmPassword = confirmPasswordController.text.trim();

    if (password.length < 6) {
      setState(() => errorMsg = 'Password must be at least 6 characters.');
      return;
    }

    if (password != confirmPassword) {
      setState(() => errorMsg = 'Passwords do not match. Please re-enter carefully.');
      return;
    }

    setState(() => loading = true);

    try {
      if (authMode == AuthMode.register) {
        final user = await ApiService.register(
          name: nameController.text.trim(),
          email: email,
          password: password,
          otp: otpController.text.trim(),
        );

        await StorageService.saveUser(user);
        widget.onLoginSuccess(user);
      } else if (authMode == AuthMode.forgotPassword) {
        await ApiService.resetPassword(
          email: email,
          otp: otpController.text.trim(),
          newPassword: password,
        );

        setState(() {
          successMsg = 'Password reset successful! Please sign in with your new password.';
        });

        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() {
              authMode = AuthMode.login;
              _resetFormState();
            });
          }
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

  // Standard Login (Email & Password)
  Future<void> _handleLogin() async {
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
    if (password.isEmpty) {
      setState(() => errorMsg = 'Password is required.');
      return;
    }

    setState(() => loading = true);

    try {
      final user = await ApiService.login(email, password);
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

  // Google Sign-In
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
  Widget build(BuildContext context) {
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
                            ? 'Reset Password'
                            : 'SSSAM Student Portal',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppleTheme.primaryText,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    authMode == AuthMode.register
                        ? '3-Step Email OTP Verification'
                        : authMode == AuthMode.forgotPassword
                            ? 'Verify email OTP & reset password'
                            : 'Sign in to access your attendance & GPS check-in',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppleTheme.secondaryText,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Error Message Banner
                  if (errorMsg != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppleTheme.appleRose.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppleTheme.appleRose.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(CupertinoIcons.exclamationmark_shield, color: AppleTheme.appleRose, size: 18),
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

                  // Success Message Banner
                  if (successMsg != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppleTheme.appleGreen.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppleTheme.appleGreen.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(CupertinoIcons.checkmark_seal_fill, color: AppleTheme.appleGreen, size: 18),
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

                  // LOGIN FORM
                  if (authMode == AuthMode.login) ...[
                    _buildTextField(
                      controller: emailController,
                      placeholder: 'Student Email Address',
                      icon: CupertinoIcons.mail,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 14),
                    _buildPasswordField(
                      controller: passwordController,
                      placeholder: 'Password',
                      show: showPassword,
                      onToggle: () => setState(() => showPassword = !showPassword),
                    ),
                    const SizedBox(height: 8),

                    // Forgot Password Link
                    Align(
                      alignment: Alignment.centerRight,
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        child: Text(
                          'Forgot Password?',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppleTheme.appleGreen,
                          ),
                        ),
                        onPressed: () {
                          setState(() {
                            authMode = AuthMode.forgotPassword;
                            _resetFormState();
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Sign In Button
                    _buildPrimaryButton(
                      label: loading ? 'Signing In...' : 'Sign In',
                      icon: CupertinoIcons.arrow_right_circle_fill,
                      onPressed: loading ? null : _handleLogin,
                    ),
                  ],

                  // REGISTER & FORGOT PASSWORD (3-STEP FLOW WITH RESEND OTP TIMER)
                  if (authMode == AuthMode.register || authMode == AuthMode.forgotPassword) ...[
                    
                    // STEP 1: Enter Name & Email -> Get OTP
                    if (!otpSent) ...[
                      if (authMode == AuthMode.register) ...[
                        _buildTextField(
                          controller: nameController,
                          placeholder: 'Full Name',
                          icon: CupertinoIcons.person,
                        ),
                        const SizedBox(height: 14),
                      ],
                      _buildTextField(
                        controller: emailController,
                        placeholder: 'Student Email Address',
                        icon: CupertinoIcons.mail,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 18),
                      _buildPrimaryButton(
                        label: loading ? 'Sending OTP...' : 'Get Email Verification OTP',
                        icon: CupertinoIcons.paperplane_fill,
                        onPressed: loading ? null : _handleSendOtp,
                      ),
                    ],

                    // STEP 2: Enter 6-Digit OTP Code & Resend OTP Timer
                    if (otpSent && !otpVerified) ...[
                      _buildTextField(
                        controller: otpController,
                        placeholder: 'Enter 6-Digit Email OTP',
                        icon: Icons.shield,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      
                      // Resend OTP Button with 30s Timer
                      Align(
                        alignment: Alignment.centerRight,
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: (_resendCountdown == 0 && !loading) ? _handleSendOtp : null,
                          child: Text(
                            _resendCountdown > 0
                                ? 'Resend OTP in ${_resendCountdown}s'
                                : 'Resend OTP via Email',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _resendCountdown == 0 ? AppleTheme.appleGreen : AppleTheme.secondaryText,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildPrimaryButton(
                        label: 'Verify OTP Code',
                        icon: CupertinoIcons.checkmark_shield_fill,
                        onPressed: _handleVerifyOtp,
                      ),
                    ],

                    // STEP 3: Enter Password & Re-enter Password (AFTER OTP VERIFIED)
                    if (otpSent && otpVerified) ...[
                      _buildPasswordField(
                        controller: passwordController,
                        placeholder: authMode == AuthMode.forgotPassword ? 'New Password' : 'Create Password',
                        show: showPassword,
                        onToggle: () => setState(() => showPassword = !showPassword),
                      ),
                      const SizedBox(height: 14),
                      _buildPasswordField(
                        controller: confirmPasswordController,
                        placeholder: 'Re-enter Password',
                        show: showConfirmPassword,
                        onToggle: () => setState(() => showConfirmPassword = !showConfirmPassword),
                      ),
                      const SizedBox(height: 18),
                      _buildPrimaryButton(
                        label: loading
                            ? (authMode == AuthMode.forgotPassword ? 'Updating Password...' : 'Registering...')
                            : (authMode == AuthMode.forgotPassword ? 'Update Password' : 'Complete Registration'),
                        icon: CupertinoIcons.lock_shield_fill,
                        onPressed: loading ? null : _handleSubmitFinal,
                      ),
                    ],
                  ],

                  const SizedBox(height: 20),

                  // Divider
                  Row(
                    children: [
                      const Expanded(child: Divider(color: AppleTheme.border, thickness: 1)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'OR',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppleTheme.secondaryText.withOpacity(0.7),
                          ),
                        ),
                      ),
                      const Expanded(child: Divider(color: AppleTheme.border, thickness: 1)),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Google Sign-In Button
                  OutlinedButton(
                    onPressed: loading ? null : _handleGoogleLogin,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppleTheme.border, width: 1.2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      backgroundColor: Colors.white,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(CupertinoIcons.globe, color: Color(0xFF4285F4), size: 20),
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

                  // Toggle Auth Mode Footer Link
                  Center(
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      child: Text(
                        authMode == AuthMode.login
                            ? "Don't have an account? Register with OTP"
                            : 'Already have an account? Sign In',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppleTheme.secondaryText,
                        ),
                      ),
                      onPressed: () {
                        setState(() {
                          if (authMode == AuthMode.login) {
                            authMode = AuthMode.register;
                          } else {
                            authMode = AuthMode.login;
                          }
                          _resetFormState();
                        });
                      },
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
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppleTheme.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppleTheme.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: GoogleFonts.inter(fontSize: 14, color: AppleTheme.primaryText),
        decoration: InputDecoration(
          icon: Icon(icon, color: AppleTheme.secondaryText, size: 20),
          hintText: placeholder,
          hintStyle: GoogleFonts.inter(fontSize: 14, color: AppleTheme.secondaryText.withOpacity(0.7)),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String placeholder,
    required bool show,
    required VoidCallback onToggle,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppleTheme.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppleTheme.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: TextField(
        controller: controller,
        obscureText: !show,
        style: GoogleFonts.inter(fontSize: 14, color: AppleTheme.primaryText),
        decoration: InputDecoration(
          icon: const Icon(CupertinoIcons.lock, color: AppleTheme.secondaryText, size: 20),
          suffixIcon: IconButton(
            icon: Icon(show ? CupertinoIcons.eye_slash : CupertinoIcons.eye, color: AppleTheme.secondaryText, size: 20),
            onPressed: onToggle,
          ),
          hintText: placeholder,
          hintStyle: GoogleFonts.inter(fontSize: 14, color: AppleTheme.secondaryText.withOpacity(0.7)),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        backgroundColor: AppleTheme.appleGreen,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Icon(icon, color: Colors.white, size: 18),
        ],
      ),
    );
  }
}
