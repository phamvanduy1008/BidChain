import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../widgets/common/form_input.dart';
import '../../../widgets/common/primary_button.dart';
import '../../../widgets/common/custom_toast.dart';
import '../../../bloc/auth/auth_bloc.dart';
import '../../../bloc/auth/auth_state.dart';
import '../../../bloc/auth/auth_event.dart';

class PasswordChangeForm extends StatefulWidget {
  const PasswordChangeForm({super.key});

  @override
  State<PasswordChangeForm> createState() => _PasswordChangeFormState();
}

class _PasswordChangeFormState extends State<PasswordChangeForm> {
  late TextEditingController _currentCtrl;
  late TextEditingController _newCtrl;
  late TextEditingController _confirmCtrl;

  String _currentErr = '';
  String _newErr = '';
  String _confirmErr = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentCtrl = TextEditingController();
    _newCtrl = TextEditingController();
    _confirmCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _changePassword() {
    setState(() {
      _currentErr = _currentCtrl.text.isEmpty ? 'Vui lòng nhập' : '';
      _newErr = _newCtrl.text.isEmpty
          ? 'Vui lòng nhập'
          : (_newCtrl.text.length < 8 ? 'Tối thiểu 8 ký tự' : '');
      _confirmErr = _confirmCtrl.text != _newCtrl.text ? 'Mật khẩu không khớp' : '';
    });

    if (_currentErr.isEmpty && _newErr.isEmpty && _confirmErr.isEmpty) {
      setState(() => _isLoading = true);
      context.read<AuthBloc>().add(
        AuthChangePasswordEvent(
          currentPassword: _currentCtrl.text,
          newPassword: _newCtrl.text,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthSuccessState && state.message == 'Đổi mật khẩu thành công') {
          setState(() => _isLoading = false);
          _currentCtrl.clear();
          _newCtrl.clear();
          _confirmCtrl.clear();
          Toast.show(
            context,
            message: 'Đổi mật khẩu thành công',
            type: ToastType.success,
          );
        } else if (state is AuthErrorState) {
          setState(() => _isLoading = false);
          Toast.show(context, message: state.message, type: ToastType.error);
        }
      },
      child: Column(
        children: [
          FormInput(
            label: 'Mật khẩu hiện tại',
            value: _currentCtrl.text,
            onChangeText: (v) {
              _currentCtrl.text = v;
              if (_currentErr.isNotEmpty) setState(() => _currentErr = '');
            },
            error: _currentErr,
            secureText: true,
            prefixIcon: Icons.lock_outline,
          ),
          SizedBox(height: 16),
          FormInput(
            label: 'Mật khẩu mới',
            value: _newCtrl.text,
            onChangeText: (v) {
              _newCtrl.text = v;
              if (_newErr.isNotEmpty) setState(() => _newErr = '');
            },
            error: _newErr,
            secureText: true,
            prefixIcon: Icons.lock_outline,
          ),
          SizedBox(height: 16),
          FormInput(
            label: 'Xác nhận mật khẩu mới',
            value: _confirmCtrl.text,
            onChangeText: (v) {
              _confirmCtrl.text = v;
              if (_confirmErr.isNotEmpty) setState(() => _confirmErr = '');
            },
            error: _confirmErr,
            secureText: true,
            prefixIcon: Icons.lock_outline,
          ),
          SizedBox(height: 24),
          PrimaryButton(
            title: 'Đổi mật khẩu',
            loading: _isLoading,
            onPress: _changePassword,
          ),
        ],
      ),
    );
  }
}
