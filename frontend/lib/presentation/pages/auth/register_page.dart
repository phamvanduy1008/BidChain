import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../config/routes/app_routes.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/validators.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/auth/auth_event.dart';
import '../../bloc/auth/auth_state.dart';
import '../../widgets/common/primary_button.dart';
import '../../widgets/common/form_input.dart';
import '../../widgets/common/full_screen_loading.dart';
import '../../widgets/common/custom_toast.dart';
import '../../widgets/common/custom_back_button.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String? _usernameError;
  String? _emailError;
  String? _fullNameError;
  String? _passwordError;
  String? _confirmPasswordError;

  bool _agreeToTerms = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _fullNameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _validateUsername() {
    setState(() {
      _usernameError = Validators.validateUsername(_usernameController.text);
    });
  }

  void _validateEmail() {
    setState(() {
      _emailError = Validators.validateEmail(_emailController.text);
    });
  }

  void _validateFullName() {
    setState(() {
      _fullNameError = Validators.validateFullName(_fullNameController.text);
    });
  }

  void _validatePassword() {
    setState(() {
      _passwordError = Validators.validatePassword(_passwordController.text);
    });
  }

  void _validateConfirmPassword() {
    setState(() {
      _confirmPasswordError = Validators.validateConfirmPassword(
        _confirmPasswordController.text,
        _passwordController.text,
      );
    });
  }

  bool _validateForm() {
    _validateUsername();
    _validateEmail();
    _validateFullName();
    _validatePassword();
    _validateConfirmPassword();

    return _usernameError == null &&
        _emailError == null &&
        _fullNameError == null &&
        _passwordError == null &&
        _confirmPasswordError == null;
  }

  void _handleRegister() {
    if (!_agreeToTerms) {
      Toast.error(context, 'Vui lòng đồng ý với điều khoản sử dụng');
      return;
    }

    if (!_validateForm()) {
      Toast.error(context, 'Vui lòng kiểm tra lại thông tin trước khi tiếp tục');
      return;
    }

    context.read<AuthBloc>().add(
          AuthRegisterEvent(
            username: _usernameController.text.trim(),
            password: _passwordController.text,
            email: _emailController.text.trim(),
            fullName: _fullNameController.text.trim(),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthLoadingState) {
          LoadingOverlay.show(context, message: 'Đang tạo tài khoản...');
        } else if (state is AuthSuccessState) {
          LoadingOverlay.hide();
          Toast.success(context, 'Tạo tài khoản thành công');
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted) context.go(AppRoutes.login);
          });
        } else if (state is AuthErrorState) {
          LoadingOverlay.hide();
          Toast.error(context, state.message);
        }
      },
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primary.withOpacity(0.05),
                AppColors.accent.withOpacity(0.05),
              ],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    CustomBackButton(
                      onPressed: () => context.go(AppRoutes.login),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Tạo tài khoản',
                      style: AppTextStyles.h1.copyWith(
                        color: AppColors.black,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Đăng ký để bắt đầu tham gia đấu giá',
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: AppColors.grey,
                      ),
                    ),
                    const SizedBox(height: 40),
                    FormInput(
                      label: 'Họ và tên',
                      value: _fullNameController.text,
                      onChangeText: (value) {
                        _fullNameController.text = value;
                        _validateFullName();
                      },
                      error: _fullNameError,
                      hint: 'Nhập họ và tên',
                      prefixIcon: Icons.badge_outlined,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 20),
                    FormInput(
                      label: 'Email',
                      value: _emailController.text,
                      onChangeText: (value) {
                        _emailController.text = value;
                        _validateEmail();
                      },
                      error: _emailError,
                      hint: 'Nhập địa chỉ email',
                      prefixIcon: Icons.email_outlined,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 20),
                    FormInput(
                      label: 'Tên đăng nhập',
                      value: _usernameController.text,
                      onChangeText: (value) {
                        _usernameController.text = value;
                        _validateUsername();
                      },
                      error: _usernameError,
                      hint: 'Chọn tên đăng nhập (ít nhất 3 ký tự)',
                      prefixIcon: Icons.person_outline,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 20),
                    FormInput(
                      label: 'Mật khẩu',
                      value: _passwordController.text,
                      onChangeText: (value) {
                        _passwordController.text = value;
                        _validatePassword();
                      },
                      error: _passwordError,
                      hint: 'Tạo mật khẩu mạnh (ít nhất 8 ký tự)',
                      secureText: true,
                      prefixIcon: Icons.lock_outline,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 20),
                    FormInput(
                      label: 'Xác nhận mật khẩu',
                      value: _confirmPasswordController.text,
                      onChangeText: (value) {
                        _confirmPasswordController.text = value;
                        _validateConfirmPassword();
                      },
                      error: _confirmPasswordError,
                      hint: 'Nhập lại mật khẩu',
                      secureText: true,
                      prefixIcon: Icons.lock_outline,
                      textInputAction: TextInputAction.done,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: _agreeToTerms,
                            onChanged: (value) {
                              setState(() => _agreeToTerms = value ?? false);
                            },
                            activeColor: AppColors.accent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _agreeToTerms = !_agreeToTerms);
                            },
                            child: Text.rich(
                              TextSpan(
                                text: 'Tôi đồng ý với ',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.grey,
                                ),
                                children: [
                                  TextSpan(
                                    text: 'Điều khoản sử dụng',
                                    style: AppTextStyles.labelMedium.copyWith(
                                      color: AppColors.accent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' và ',
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      color: AppColors.grey,
                                    ),
                                  ),
                                  TextSpan(
                                    text: 'Chính sách bảo mật',
                                    style: AppTextStyles.labelMedium.copyWith(
                                      color: AppColors.accent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    BlocBuilder<AuthBloc, AuthState>(
                      builder: (context, state) {
                        final isLoading = state is AuthLoadingState;
                        return Align(
                          alignment: Alignment.center,
                          child: PrimaryButton(
                            title: 'Tạo tài khoản',
                            onPress: isLoading ? null : _handleRegister,
                            loading: isLoading,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 32),
                    Align(
                      alignment: Alignment.center,
                      child: TextButton(
                        onPressed: () => context.go(AppRoutes.login),
                        child: RichText(
                          text: TextSpan(
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.grey,
                            ),
                            children: [
                              const TextSpan(text: 'Đã có tài khoản? '),
                              TextSpan(
                                text: 'Đăng nhập',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
