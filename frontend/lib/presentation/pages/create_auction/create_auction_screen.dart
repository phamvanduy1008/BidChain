import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../config/theme/app_colors.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/services/gemini_service.dart';
import '../../../data/models/category_model.dart';
import '../../../data/models/create_auction_request.dart';
import '../../bloc/create_auction/create_auction_bloc.dart';
import '../../widgets/common/custom_button.dart';
import '../../widgets/common/custom_text_field.dart';

class CreateAuctionScreen extends StatelessWidget {
  const CreateAuctionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          InjectionContainer.getCreateAuctionBloc()..add(LoadCategoriesEvent()),
      child: const _CreateAuctionView(),
    );
  }
}

class _CreateAuctionView extends StatefulWidget {
  const _CreateAuctionView();

  @override
  State<_CreateAuctionView> createState() => _CreateAuctionViewState();
}

class _CreateAuctionViewState extends State<_CreateAuctionView> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _startPriceController = TextEditingController();
  final _stepPriceController = TextEditingController();
  final GeminiService _geminiService = InjectionContainer.getGeminiService();

  DateTime? _startTime;
  DateTime? _endTime;
  String? _selectedCategoryId;
  final List<File> _selectedImages = [];
  final List<String> _imageUrls = [];
  List<CategoryModel> _categories = [];
  bool _isUploading = false;
  bool _isPredictingPrice = false;
  PricePredictionResult? _pricePrediction;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_clearPredictionIfNeeded);
    _descriptionController.addListener(_clearPredictionIfNeeded);
  }

  @override
  void dispose() {
    _titleController.removeListener(_clearPredictionIfNeeded);
    _descriptionController.removeListener(_clearPredictionIfNeeded);
    _titleController.dispose();
    _descriptionController.dispose();
    _startPriceController.dispose();
    _stepPriceController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final images = await _picker.pickMultiImage();
    if (images.isEmpty) return;

    final newImages = images.map((e) => File(e.path)).toList();
    setState(() {
      _selectedImages.addAll(newImages);
      _isUploading = true;
      _pricePrediction = null;
    });
    context.read<CreateAuctionBloc>().add(UploadImagesEvent(newImages));
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
      if (index < _imageUrls.length) {
        _imageUrls.removeAt(index);
      }
      _pricePrediction = null;
    });
  }

  void _clearPredictionIfNeeded() {
    if (_pricePrediction == null) return;
    setState(() => _pricePrediction = null);
  }

  Future<void> _predictPrice() async {
    if (_selectedImages.isEmpty) {
      _showSnackBar(context, 'Vui lòng tải lên ít nhất một ảnh để AI phân tích');
      return;
    }

    if (_titleController.text.trim().isEmpty) {
      _showSnackBar(context, 'Vui lòng nhập tên sản phẩm trước khi dự đoán giá');
      return;
    }

    if (_descriptionController.text.trim().isEmpty) {
      _showSnackBar(context, 'Vui lòng nhập mô tả sản phẩm trước khi dự đoán giá');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isPredictingPrice = true);

    try {
      final result = await _geminiService.predictAuctionPrice(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _selectedCategoryName,
        images: _selectedImages,
      );

      if (!mounted) return;
      setState(() {
        _pricePrediction = result;
      });
      _showSnackBar(context, 'AI đã đưa ra gợi ý giá cho sản phẩm này');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isPredictingPrice = false);
      }
    }
  }

  void _applyPrediction() {
    final prediction = _pricePrediction;
    if (prediction == null) return;

    setState(() {
      if (prediction.suggestedStartPrice != null) {
        _startPriceController.text =
            prediction.suggestedStartPrice!.toString();
      }
      if (prediction.suggestedStepPrice != null) {
        _stepPriceController.text = prediction.suggestedStepPrice!.toString();
      }
    });

    _showSnackBar(context, 'Đã áp dụng giá khởi điểm và bước giá từ AI');
  }

  String? get _selectedCategoryName {
    for (final category in _categories) {
      if (category.id == _selectedCategoryId) {
        return category.name;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<CreateAuctionBloc, CreateAuctionState>(
      listener: _handleStateChange,
      child: Scaffold(
        backgroundColor: AppColors.white,
        appBar: _buildAppBar(context),
        body: BlocBuilder<CreateAuctionBloc, CreateAuctionState>(
          builder: (context, state) {
            final isLoading = state is CreateAuctionLoading && !_isUploading;
            return _buildBody(isLoading);
          },
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: CustomButton(
              color: AppColors.accent,
              text: 'Đăng phiên đấu giá',
              onPressed: _submitAuction,
            ),
          ),
        ),
      ),
    );
  }

  void _handleStateChange(BuildContext context, CreateAuctionState state) {
    if (state is CategoriesLoaded) {
      setState(() {
        _categories = state.categories;
      });
    } else if (state is ImagesUploaded) {
      setState(() {
        _imageUrls.addAll(state.imageUrls);
        _isUploading = false;
      });
      _showSnackBar(context, 'Tải ảnh lên thành công');
    } else if (state is CreateAuctionSuccess) {
      _showSnackBar(context, 'Tạo phiên đấu giá thành công');
      context.pop();
    } else if (state is CreateAuctionFailure) {
      setState(() {
        _isUploading = false;
      });
      _showSnackBar(context, state.message);
    }
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      title: const Text(
        'Tạo phiên đấu giá',
        style: TextStyle(
          color: AppColors.black,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: AppColors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        color: AppColors.accent,
        onPressed: () => Navigator.of(context).pop(),
      ),
      centerTitle: true,
    );
  }

  Widget _buildBody(bool isLoading) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_selectedImages.isEmpty) _buildImageUploadPlaceholder(),
            if (_selectedImages.isNotEmpty) _buildImagePreview(),
            const SizedBox(height: 20),
            
            _buildTextField(
              label: 'Tên sản phẩm',
              controller: _titleController,
              hint: 'Nhập tên sản phẩm',
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Vui lòng nhập tên sản phẩm';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            _buildTextField(
              label: 'Mô tả sản phẩm',
              controller: _descriptionController,
              hint: 'Nhập mô tả chi tiết sản phẩm',
              maxLines: 4,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Vui lòng nhập mô tả sản phẩm';
                }
                if (value.trim().length < 20) {
                  return 'Mô tả nên chi tiết hơn một chút để AI dự đoán tốt hơn';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            _buildLabel('Danh mục'),
            _buildCategoryDropdown(),
            
            const SizedBox(height: 20),
            _buildLabel('Thời gian bắt đầu'),
            _buildDatePicker(
              selectedTime: _startTime,
              placeholder: 'Chọn ngày và giờ bắt đầu',
              onTap: () => _selectDateTime(isStartTime: true),
            ),
            const SizedBox(height: 20),
            _buildLabel('Thời gian kết thúc'),
            _buildDatePicker(
              selectedTime: _endTime,
              placeholder: 'Chọn ngày và giờ kết thúc',
              onTap: () => _selectDateTime(isStartTime: false),
            ),
            const SizedBox(height: 20),
            _buildTextField(
              label: 'Giá khởi điểm',
              controller: _startPriceController,
              hint: '100000',
              keyboardType: TextInputType.number,
              validator: _validatePriceField,
            ),
            const SizedBox(height: 20),
            _buildTextField(
              label: 'Bước giá',
              controller: _stepPriceController,
              hint: '500000',
              keyboardType: TextInputType.number,
              validator: _validatePriceField,
            ),
            const SizedBox(height: 32),
            _buildAiPriceSection(),
            const SizedBox(height: 20),
            if (isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: CircularProgressIndicator(color: AppColors.black),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(label),
        CustomTextField(
          controller: controller,
          hint: hint,
          keyboardType: keyboardType ?? TextInputType.text,
          maxLines: maxLines,
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.black,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildCategoryDropdown() {
    return DropdownMenuTheme(
      data: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          // ignore: deprecated_member_use
          shape: MaterialStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.white,
          border: Border.all(color: AppColors.greyLight),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedCategoryId,
            isExpanded: true,
            hint: const Text(
              'Chọn danh mục',
              style: TextStyle(color: AppColors.grey, fontSize: 14),
            ),
            icon: const Icon(Icons.keyboard_arrow_down),
            items: _categories.map((category) {
              return DropdownMenuItem<String>(
                value: category.id,
                child: Text(category.name),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedCategoryId = value;
                _pricePrediction = null;
              });
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDatePicker({
    required DateTime? selectedTime,
    required String placeholder,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.white,
          border: Border.all(color: AppColors.greyLight),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              selectedTime != null
                  ? DateFormat('yyyy-MM-dd HH:mm').format(selectedTime)
                  : placeholder,
              style: TextStyle(
                fontSize: 14,
                color: selectedTime != null ? AppColors.black : AppColors.grey,
              ),
            ),
            const Icon(Icons.calendar_today, color: AppColors.grey, size: 18),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDateTime({required bool isStartTime}) async {
    final initialBase = isStartTime
        ? (_startTime ?? DateTime.now().add(const Duration(minutes: 10)))
        : (_endTime ??
              _startTime?.add(const Duration(hours: 1)) ??
              DateTime.now().add(const Duration(hours: 1)));
    final date = await showDatePicker(
      context: context,
      initialDate: initialBase,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initialBase),
      );
      if (time != null && mounted) {
        final selected = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        );
        setState(() {
          if (isStartTime) {
            _startTime = selected;
            if (_endTime != null && !_endTime!.isAfter(selected)) {
              _endTime = selected.add(const Duration(hours: 1));
            }
          } else {
            _endTime = selected;
          }
        });
      }
    }
  }

  Widget _buildImageUploadPlaceholder() {
    return GestureDetector(
      onTap: _pickImages,
      child: Container(
        height: 180,
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.black, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.black,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_upward,
                color: AppColors.white,
                size: 32,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Tải ảnh lên',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildImagePreviewHeader(),
        const SizedBox(height: 12),
        _buildImageGrid(),
      ],
    );
  }

  Widget _buildImagePreviewHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Đã chọn ${_selectedImages.length} ảnh',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.black,
          ),
        ),
        TextButton.icon(
          onPressed: _pickImages,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Thêm ảnh'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.info,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
        ),
      ],
    );
  }

  Widget _buildImageGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      itemCount: _selectedImages.length,
      itemBuilder: (context, index) => _buildImageGridItem(index),
    );
  }

  Widget _buildImageGridItem(int index) {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.greyLight),
            image: DecorationImage(
              image: FileImage(_selectedImages[index]),
              fit: BoxFit.cover,
            ),
          ),
        ),
        if (_isUploading && index >= _imageUrls.length) _buildUploadingOverlay(),
        Positioned(top: 4, right: 4, child: _buildRemoveButton(index)),
      ],
    );
  }

  Widget _buildUploadingOverlay() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: AppColors.black.withOpacity(0.5),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
        ),
      ),
    );
  }

  Widget _buildRemoveButton(int index) {
    return GestureDetector(
      onTap: () => _removeImage(index),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: const BoxDecoration(
          color: AppColors.error,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close, color: AppColors.white, size: 16),
      ),
    );
  }

  Widget _buildAiPriceSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.greyLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.tertiary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AI dự đoán giá đấu giá',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.black,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Gemini sẽ dựa vào ảnh, tiêu đề, mô tả và danh mục để gợi ý khoảng giá tham khảo.',
            style: TextStyle(fontSize: 13, color: AppColors.greyDark),
          ),
          const SizedBox(height: 16),
          CustomButton(
            text: 'AI dự đoán giá',
            color: AppColors.accent,
            isLoading: _isPredictingPrice,
            onPressed: _isUploading ? null : _predictPrice,
            height: 48,
          ),
          if (_isUploading) ...[
            const SizedBox(height: 10),
            const Text(
              'Ảnh vẫn đang được tải lên. Bạn vẫn có thể dự đoán bằng ảnh local, nhưng nên chờ upload xong trước khi đăng phiên.',
              style: TextStyle(fontSize: 12, color: AppColors.greyDark),
            ),
          ],
          if (_pricePrediction != null) ...[
            const SizedBox(height: 16),
            _buildPredictionResultCard(_pricePrediction!),
          ],
        ],
      ),
    );
  }

  Widget _buildPredictionResultCard(PricePredictionResult prediction) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.tertiary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPredictionRow(
            'Khoảng giá tham khảo',
            _formatRange(
              prediction.estimatedMinPrice,
              prediction.estimatedMaxPrice,
            ),
          ),
          const SizedBox(height: 8),
          _buildPredictionRow(
            'Giá khởi điểm gợi ý',
            _formatCurrency(prediction.suggestedStartPrice),
          ),
          const SizedBox(height: 8),
          _buildPredictionRow(
            'Bước giá gợi ý',
            _formatCurrency(prediction.suggestedStepPrice),
          ),
          const SizedBox(height: 8),
          _buildPredictionRow('Độ tin cậy', _mapConfidence(prediction.confidence)),
          if (prediction.summary.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              prediction.summary,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.greyDark,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _applyPrediction,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.black,
                side: const BorderSide(color: AppColors.black),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Áp dụng vào giá khởi điểm và bước giá',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPredictionRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.greyDark,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.black,
            ),
          ),
        ),
      ],
    );
  }

  String _formatCurrency(int? value) {
    if (value == null || value <= 0) return 'Chưa có';
    return '${NumberFormat('#,###', 'vi_VN').format(value)} VND';
  }

  String _formatRange(int? minValue, int? maxValue) {
    if (minValue == null && maxValue == null) return 'Chưa có';
    if (minValue != null && maxValue != null) {
      return '${_formatCurrency(minValue)} - ${_formatCurrency(maxValue)}';
    }
    return _formatCurrency(minValue ?? maxValue);
  }

  String _mapConfidence(String confidence) {
    switch (confidence.toLowerCase()) {
      case 'high':
        return 'Cao';
      case 'low':
        return 'Thấp';
      default:
        return 'Trung bình';
    }
  }

  void _submitAuction() {
    if (!_validateForm()) return;

    final request = CreateAuctionRequest(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      startPrice: double.tryParse(_startPriceController.text) ?? 0,
      stepPrice: double.tryParse(_stepPriceController.text) ?? 0,
      startTime: _startTime!,
      endTime: _endTime!,
      images: _imageUrls,
      categoryId: _selectedCategoryId!,
    );

    context.read<CreateAuctionBloc>().add(SubmitAuctionEvent(request));
  }

  bool _validateForm() {
    if (!_formKey.currentState!.validate()) {
      _showSnackBar(context, 'Vui lòng nhập đầy đủ thông tin bắt buộc');
      return false;
    }

    if (_selectedCategoryId == null) {
      _showSnackBar(context, 'Vui lòng chọn danh mục');
      return false;
    }

    if (_startTime == null) {
      _showSnackBar(context, 'Vui lòng chọn thời gian bắt đầu');
      return false;
    }

    if (_endTime == null) {
      _showSnackBar(context, 'Vui lòng chọn thời gian kết thúc');
      return false;
    }

    if (!_endTime!.isAfter(_startTime!)) {
      _showSnackBar(context, 'Thời gian kết thúc phải sau thời gian bắt đầu');
      return false;
    }

    if (_imageUrls.isEmpty) {
      if (_selectedImages.isNotEmpty && _isUploading) {
        _showSnackBar(context, 'Vui lòng chờ tải ảnh lên hoàn tất');
      } else {
        _showSnackBar(context, 'Vui lòng tải lên ít nhất một ảnh');
      }
      return false;
    }

    return true;
  }

  String? _validatePriceField(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Vui lòng nhập giá';
    }

    final price = double.tryParse(value.trim());
    if (price == null || price <= 0) {
      return 'Giá phải là số lớn hơn 0';
    }

    return null;
  }
}
