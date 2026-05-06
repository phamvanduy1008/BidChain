import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../widgets/common/custom_app_bar.dart';
import '../../widgets/common/custom_button.dart';
import '../../widgets/common/custom_text_field.dart';
import '../../widgets/common/custom_back_button.dart';
import '../../../config/routes/app_routes.dart';

class CreateAuctionPage extends StatefulWidget {
  const CreateAuctionPage({super.key});

  @override
  State<CreateAuctionPage> createState() => _CreateAuctionPageState();
}

class _CreateAuctionPageState extends State<CreateAuctionPage> {
  final _formKey = GlobalKey<FormState>();
  final _startingController = TextEditingController();
  final _durationController = TextEditingController();
  final _metadataController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _startingController.dispose();
    _durationController.dispose();
    _metadataController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    // TODO: convert starting ETH to wei, call createAuction usecase -> backend
    await Future.delayed(const Duration(seconds: 1));

    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã tạo phiên đấu giá (mô phỏng)')),
    );
    context.go(AppRoutes.auctionList);
  }

  String? _validateNumber(String? v) {
    if (v == null || v.trim().isEmpty) return 'Vui lòng nhập thông tin';
    if (double.tryParse(v) == null) return 'Số không hợp lệ';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Tạo phiên đấu giá',
        leading: const CustomBackButton(),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Text('Tạo phiên đấu giá mới', style: AppTextStyles.h3),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _startingController,
                label: 'Giá khởi điểm (ETH)',
                hint: '0.1',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: _validateNumber,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _durationController,
                label: 'Thời lượng (giây)',
                hint: '3600',
                keyboardType: TextInputType.number,
                validator: _validateNumber,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _metadataController,
                label: 'Đường dẫn metadata (không bắt buộc)',
                hint: 'https://ipfs.io/...',
                validator: (v) => null,
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 20),
              CustomButton(
                text: _submitting ? 'Đang tạo...' : 'Tạo phiên đấu giá',
                isLoading: _submitting,
                onPressed: _submitting ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
