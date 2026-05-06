class Validators {
  // Email validation với regex RFC 5322 compliant
  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Vui lòng nhập email';
    }

    // Trim whitespace
    final trimmedValue = value.trim();

    if (trimmedValue.isEmpty) {
      return 'Email không được để trống';
    }

    // Email regex pattern (RFC 5322 simplified)
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );

    if (!emailRegex.hasMatch(trimmedValue)) {
      return 'Vui lòng nhập đúng định dạng email';
    }

    // Check for consecutive dots
    if (trimmedValue.contains('..')) {
      return 'Email không được chứa hai dấu chấm liên tiếp';
    }

    // Check email length (max 254 characters per RFC 5321)
    if (trimmedValue.length > 254) {
      return 'Email quá dài (tối đa 254 ký tự)';
    }

    // Check local part length (before @)
    final localPart = trimmedValue.split('@')[0];
    if (localPart.length > 64) {
      return 'Phần tên email quá dài (tối đa 64 ký tự)';
    }

    return null;
  }

  // Username validation
  static String? validateUsername(String? value) {
    if (value == null || value.isEmpty) {
      return 'Vui lòng nhập tên đăng nhập';
    }

    final trimmedValue = value.trim();

    if (trimmedValue.isEmpty) {
      return 'Tên đăng nhập không được để trống';
    }

    if (trimmedValue.length < 3) {
      return 'Tên đăng nhập phải có ít nhất 3 ký tự';
    }

    if (trimmedValue.length > 30) {
      return 'Tên đăng nhập không được vượt quá 30 ký tự';
    }

    // Only allow alphanumeric, underscore, and hyphen
    final usernameRegex = RegExp(r'^[a-zA-Z0-9_-]+$');
    if (!usernameRegex.hasMatch(trimmedValue)) {
      return 'Tên đăng nhập chỉ được gồm chữ, số, _ và -';
    }

    // Cannot start or end with special characters
    if (trimmedValue.startsWith('_') ||
        trimmedValue.startsWith('-') ||
        trimmedValue.endsWith('_') ||
        trimmedValue.endsWith('-')) {
      return 'Tên đăng nhập không được bắt đầu hoặc kết thúc bằng _ hoặc -';
    }

    return null;
  }

  // Password validation với multiple security rules
  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Vui lòng nhập mật khẩu';
    }

    if (value.length < 8) {
      return 'Mật khẩu phải có ít nhất 8 ký tự';
    }

    if (value.length > 128) {
      return 'Mật khẩu không được vượt quá 128 ký tự';
    }

    // Check for at least one uppercase letter
    if (!value.contains(RegExp(r'[A-Z]'))) {
      return 'Mật khẩu phải có ít nhất 1 chữ in hoa';
    }

    // Check for at least one lowercase letter
    if (!value.contains(RegExp(r'[a-z]'))) {
      return 'Mật khẩu phải có ít nhất 1 chữ thường';
    }

    // Check for at least one digit
    if (!value.contains(RegExp(r'[0-9]'))) {
      return 'Mật khẩu phải có ít nhất 1 chữ số';
    }

    // Check for at least one special character
    if (!value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      return 'Mật khẩu phải có ít nhất 1 ký tự đặc biệt';
    }

    // Check for common weak passwords
    final weakPasswords = [
      'password',
      'Password1!',
      '12345678',
      'qwerty123',
      'Admin123!',
      'Welcome1!',
      'Test1234!',
    ];

    if (weakPasswords.any(
      (weak) => value.toLowerCase().contains(weak.toLowerCase()),
    )) {
      return 'Mật khẩu quá phổ biến, vui lòng chọn mật khẩu mạnh hơn';
    }

    return null;
  }

  // Simple password validation (for login only)
  static String? validateLoginPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Vui lòng nhập mật khẩu';
    }

    if (value.length < 6) {
      return 'Mật khẩu phải có ít nhất 6 ký tự';
    }

    return null;
  }

  // Confirm password validation
  static String? validateConfirmPassword(String? value, String? password) {
    if (value == null || value.isEmpty) {
      return 'Vui lòng nhập lại mật khẩu';
    }

    if (value != password) {
      return 'Mật khẩu xác nhận không khớp';
    }

    return null;
  }

  static String? validateEthereumAddress(String? value) {
    if (value == null || value.isEmpty) {
      return 'Vui lòng nhập địa chỉ ví';
    }
    if (!value.startsWith('0x') || value.length != 42) {
      return 'Địa chỉ ví Ethereum không hợp lệ';
    }
    return null;
  }

  static String? validateAmount(String? value) {
    if (value == null || value.isEmpty) {
      return 'Vui lòng nhập số tiền';
    }
    try {
      double.parse(value);
      return null;
    } catch (e) {
      return 'Số tiền không hợp lệ';
    }
  }

  // Full name validation
  static String? validateFullName(String? value) {
    if (value == null || value.isEmpty) {
      return 'Vui lòng nhập họ và tên';
    }

    final trimmedValue = value.trim();

    if (trimmedValue.isEmpty) {
      return 'Họ và tên không được để trống';
    }

    if (trimmedValue.length < 2) {
      return 'Họ và tên phải có ít nhất 2 ký tự';
    }

    if (trimmedValue.length > 100) {
      return 'Họ và tên không được vượt quá 100 ký tự';
    }

    // Only allow letters, spaces, and some special characters (apostrophe, hyphen)
    final nameRegex = RegExp(r"^[a-zA-ZÀ-ỹ\s'\-]+$");
    if (!nameRegex.hasMatch(trimmedValue)) {
      return 'Họ và tên chỉ được chứa chữ cái, khoảng trắng, dấu nháy và dấu gạch nối';
    }

    // Check for at least one letter
    if (!trimmedValue.contains(RegExp(r'[a-zA-ZÀ-ỹ]'))) {
      return 'Họ và tên phải chứa ít nhất một chữ cái';
    }

    // Cannot start or end with space
    if (trimmedValue.startsWith(' ') || trimmedValue.endsWith(' ')) {
      return 'Họ và tên không được bắt đầu hoặc kết thúc bằng khoảng trắng';
    }

    // Cannot have consecutive spaces
    if (trimmedValue.contains(RegExp(r'\s{2,}'))) {
      return 'Họ và tên không được chứa nhiều khoảng trắng liên tiếp';
    }

    return null;
  }

  // Phone number validation (international format)
  static String? validatePhoneNumber(String? value) {
    if (value == null || value.isEmpty) {
      return 'Vui lòng nhập số điện thoại';
    }

    final trimmedValue = value.trim();

    if (trimmedValue.isEmpty) {
      return 'Số điện thoại không được để trống';
    }

    // Remove common separators for validation
    final digitsOnly = trimmedValue.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');

    // Check if contains only digits after removing separators
    if (!RegExp(r'^[0-9]+$').hasMatch(digitsOnly)) {
      return 'Số điện thoại chỉ được chứa chữ số và các ký tự phân tách hợp lệ';
    }

    // Check length (international phone numbers: 7-15 digits)
    if (digitsOnly.length < 7) {
      return 'Số điện thoại quá ngắn (ít nhất 7 số)';
    }

    if (digitsOnly.length > 15) {
      return 'Số điện thoại quá dài (tối đa 15 số)';
    }

    // Vietnam phone number specific validation (optional, can be removed for international)
    if (trimmedValue.startsWith('0') && digitsOnly.length == 10) {
      // Vietnamese mobile numbers
      final vnMobileRegex = RegExp(r'^0(3|5|7|8|9)[0-9]{8}$');
      if (!vnMobileRegex.hasMatch(digitsOnly)) {
        return 'Số điện thoại Việt Nam không đúng định dạng';
      }
    }

    return null;
  }

  // Optional phone number validation (can be empty)
  static String? validatePhoneNumberOptional(String? value) {
    if (value == null || value.isEmpty || value.trim().isEmpty) {
      return null; // Valid if empty
    }
    return validatePhoneNumber(value);
  }
}
