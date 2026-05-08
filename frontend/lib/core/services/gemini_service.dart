import 'dart:convert';
import 'dart:io';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/constants/gemini_config.dart';
import '../../data/datasources/remote/auction_data_source.dart';

class PricePredictionResult {
  final int? estimatedMinPrice;
  final int? estimatedMaxPrice;
  final int? suggestedStartPrice;
  final int? suggestedStepPrice;
  final String confidence;
  final String summary;
  final String rawResponse;

  const PricePredictionResult({
    required this.estimatedMinPrice,
    required this.estimatedMaxPrice,
    required this.suggestedStartPrice,
    required this.suggestedStepPrice,
    required this.confidence,
    required this.summary,
    required this.rawResponse,
  });

  bool get hasAnyValue =>
      estimatedMinPrice != null ||
      estimatedMaxPrice != null ||
      suggestedStartPrice != null ||
      suggestedStepPrice != null ||
      summary.isNotEmpty;

  bool get hasHumanSummary =>
      summary.isNotEmpty &&
      !summary.contains('{') &&
      !summary.contains('```') &&
      !summary.contains('"estimatedMinPrice"');

  factory PricePredictionResult.fromModelResponse(String responseText) {
    final normalized = _extractJson(responseText);
    Map<String, dynamic>? decoded;

    if (normalized != null) {
      try {
        final parsed = jsonDecode(normalized);
        if (parsed is Map<String, dynamic>) {
          decoded = parsed;
        }
      } catch (_) {
        decoded = _extractLooseFields(normalized);
      }
    }

    decoded ??= _extractLooseFields(responseText);

    if (decoded == null) {
      return PricePredictionResult(
        estimatedMinPrice: null,
        estimatedMaxPrice: null,
        suggestedStartPrice: null,
        suggestedStepPrice: null,
        confidence: 'medium',
        summary: _sanitizeSummary(responseText),
        rawResponse: responseText,
      );
    }

    final estimatedMinPrice = _parseCurrencyValue(decoded['estimatedMinPrice']);
    final estimatedMaxPrice = _parseCurrencyValue(decoded['estimatedMaxPrice']);
    final suggestedStartPrice = _firstNonNullCurrency([
      decoded['suggestedStartPrice'],
      decoded['recommendedStartPrice'],
      decoded['openingPrice'],
      decoded['startingPrice'],
    ]);
    final suggestedStepPrice = _firstNonNullCurrency([
      decoded['suggestedStepPrice'],
      decoded['recommendedStepPrice'],
      decoded['bidStep'],
      decoded['incrementStep'],
    ]);

    return PricePredictionResult(
      estimatedMinPrice: estimatedMinPrice,
      estimatedMaxPrice: estimatedMaxPrice,
      suggestedStartPrice:
          suggestedStartPrice ??
          _deriveSuggestedStartPrice(estimatedMinPrice, estimatedMaxPrice),
      suggestedStepPrice:
          suggestedStepPrice ??
          _deriveSuggestedStepPrice(
            estimatedMinPrice,
            estimatedMaxPrice,
            suggestedStartPrice,
          ),
      confidence: (decoded['confidence'] ?? 'medium').toString(),
      summary: _sanitizeSummary(
        (decoded['summary'] ?? decoded['reason'] ?? decoded['analysis'] ?? '')
            .toString(),
      ),
      rawResponse: responseText,
    );
  }

  static String? _extractJson(String text) {
    final fenced = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```').firstMatch(text);
    final candidate = fenced?.group(1) ?? text;
    final start = candidate.indexOf('{');
    final end = candidate.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) {
      return null;
    }
    return candidate.substring(start, end + 1).trim();
  }

  static int? _parseCurrencyValue(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.round();

    final normalized = value
        .toString()
        .replaceAll(RegExp(r'[^\d.]'), '')
        .trim();
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized)?.round();
  }

  static int? _firstNonNullCurrency(List<dynamic> candidates) {
    for (final candidate in candidates) {
      final parsed = _parseCurrencyValue(candidate);
      if (parsed != null) return parsed;
    }
    return null;
  }

  static Map<String, dynamic>? _extractLooseFields(String text) {
    final map = <String, dynamic>{};

    final minPrice = _extractField(text, 'estimatedMinPrice');
    final maxPrice = _extractField(text, 'estimatedMaxPrice');
    final startPrice =
        _extractField(text, 'suggestedStartPrice') ??
        _extractField(text, 'recommendedStartPrice') ??
        _extractField(text, 'openingPrice') ??
        _extractField(text, 'startingPrice');
    final stepPrice =
        _extractField(text, 'suggestedStepPrice') ??
        _extractField(text, 'recommendedStepPrice') ??
        _extractField(text, 'bidStep') ??
        _extractField(text, 'incrementStep');
    final confidence = _extractField(text, 'confidence');
    final summary =
        _extractField(text, 'summary') ??
        _extractField(text, 'reason') ??
        _extractField(text, 'analysis');

    if (minPrice != null) map['estimatedMinPrice'] = minPrice;
    if (maxPrice != null) map['estimatedMaxPrice'] = maxPrice;
    if (startPrice != null) map['suggestedStartPrice'] = startPrice;
    if (stepPrice != null) map['suggestedStepPrice'] = stepPrice;
    if (confidence != null) map['confidence'] = confidence;
    if (summary != null) map['summary'] = summary;

    return map.isEmpty ? null : map;
  }

  static String? _extractField(String text, String key) {
    final patterns = [
      RegExp('"$key"\\s*:\\s*"([^"]+)"', caseSensitive: false),
      RegExp('"$key"\\s*:\\s*([^,}\\n]+)', caseSensitive: false),
      RegExp('$key\\s*[:=-]\\s*"([^"]+)"', caseSensitive: false),
      RegExp('$key\\s*[:=-]\\s*([^,}\\n]+)', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        return match.group(1)?.trim();
      }
    }
    return null;
  }

  static int? _deriveSuggestedStartPrice(int? minPrice, int? maxPrice) {
    if (minPrice == null && maxPrice == null) return null;
    if (minPrice != null) {
      return (minPrice * 0.75).round();
    }
    return ((maxPrice ?? 0) * 0.55).round();
  }

  static int? _deriveSuggestedStepPrice(
    int? minPrice,
    int? maxPrice,
    int? startPrice,
  ) {
    final base = startPrice ?? minPrice ?? maxPrice;
    if (base == null || base <= 0) return null;

    final range = (maxPrice != null && minPrice != null)
        ? (maxPrice - minPrice)
        : 0;
    final rangeBased = range > 0 ? (range * 0.08).round() : null;
    final baseStep = (base * 0.05).round();
    final suggested = rangeBased != null && rangeBased > baseStep
        ? rangeBased
        : baseStep;
    return suggested < 10000 ? 10000 : suggested;
  }

  static String _sanitizeSummary(String text) {
    final cleaned = text
        .replaceAll(RegExp(r'```(?:json)?', caseSensitive: false), '')
        .replaceAll('```', '')
        .trim();
    if (cleaned == '{}' || cleaned == 'null') {
      return '';
    }
    return cleaned;
  }
}

class GeminiService {
  final String apiKey;
  late List<Map<String, dynamic>> _chatHistory;
  static const String _storageKey = 'chat_history';
  final AuctionDataSource _auctionDataSource = AuctionDataSource();

  late final GenerativeModel _visionModel = GenerativeModel(
    model: GeminiConfig.modelName,
    apiKey: apiKey,
    generationConfig: GenerationConfig(
      temperature: 0.4,
      maxOutputTokens: 512,
      topP: GeminiConfig.topP,
      topK: GeminiConfig.topK,
    ),
  );

  Map<String, dynamic>? _currentAuctionContext;

  GeminiService() : apiKey = GeminiConfig.apiKey {
    _chatHistory = [];
  }

  void setAuctionContext(Map<String, dynamic>? auctionData) {
    _currentAuctionContext = auctionData;
    if (auctionData != null) {
      print('[CHATBOT] Auction context set: ${auctionData['title']}');
    } else {
      print('[CHATBOT] Auction context cleared');
    }
  }

  Future<PricePredictionResult> predictAuctionPrice({
    required String title,
    required String description,
    String? category,
    required List<File> images,
  }) async {
    if (images.isEmpty) {
      throw Exception('Vui lòng chọn ít nhất một ảnh để AI phân tích.');
    }

    final prompt =
        '''
Bạn là chuyên gia định giá sản phẩm đấu giá tại Việt Nam.
Hãy phân tích ảnh, tiêu đề, mô tả và danh mục để dự đoán giá trị thị trường.

Thông tin sản phẩm:
- Tiêu đề: $title
- Mô tả: $description
- Danh mục: ${category?.trim().isNotEmpty == true ? category : 'Chưa chọn'}

Yêu cầu:
1. Ước lượng khoảng giá thị trường bằng VND.
2. Gợi ý giá khởi điểm phù hợp để dễ thu hút người bid.
3. Gợi ý bước giá phù hợp.
4. Tóm tắt ngắn lý do định giá.
5. Nếu độ chắc chắn thấp, nói rõ trong confidence.

Chỉ trả về JSON hợp lệ, không thêm markdown, không thêm giải thích ngoài JSON.
Schema:
{
  "estimatedMinPrice": 0,
  "estimatedMaxPrice": 0,
  "suggestedStartPrice": 0,
  "suggestedStepPrice": 0,
  "confidence": "low|medium|high",
  "summary": "..."
}
''';

    try {
      final parts = <Part>[TextPart(prompt)];
      for (final image in images.take(4)) {
        final bytes = await image.readAsBytes();
        parts.add(DataPart(_detectMimeType(image.path), bytes));
      }

      final response = await _visionModel
          .generateContent([Content.multi(parts)])
          .timeout(const Duration(seconds: 30));

      final text = response.text?.trim();
      if (text == null || text.isEmpty) {
        throw Exception('Gemini không trả về nội dung dự đoán.');
      }

      return PricePredictionResult.fromModelResponse(text);
    } on GenerativeAIException catch (e) {
      throw Exception(_mapPredictionError(e.message));
    } catch (e) {
      throw Exception(_mapPredictionError(e.toString()));
    }
  }

  String _buildAuctionContextString() {
    if (_currentAuctionContext == null) return '';

    final auction = _currentAuctionContext!;
    final endTime = auction['end_time'];
    String timeRemaining = 'N/A';

    if (endTime != null) {
      try {
        final end = DateTime.parse(endTime.toString());
        final now = DateTime.now();
        final diff = end.difference(now);
        if (diff.isNegative) {
          timeRemaining = 'Đã kết thúc';
        } else if (diff.inDays > 0) {
          timeRemaining = '${diff.inDays} ngày ${diff.inHours % 24} giờ';
        } else if (diff.inHours > 0) {
          timeRemaining = '${diff.inHours} giờ ${diff.inMinutes % 60} phút';
        } else {
          timeRemaining = '${diff.inMinutes} phút';
        }
      } catch (_) {
        timeRemaining = 'N/A';
      }
    }

    return '''

THÔNG TIN PHIÊN ĐẤU GIÁ HIỆN TẠI:
- Tên sản phẩm: ${auction['title'] ?? 'N/A'}
- Mô tả: ${auction['description'] ?? 'N/A'}
- Danh mục: ${auction['category'] ?? auction['category_name'] ?? 'N/A'}
- Giá hiện tại: ${_formatPrice(auction['current_price'])} VND
- Giá khởi điểm: ${_formatPrice(auction['start_price'])} VND
- Bước giá: ${_formatPrice(auction['step_price'])} VND
- Số lượt đặt giá: ${auction['bid_count'] ?? 0}
- Thời gian còn lại: $timeRemaining
- Trạng thái: ${auction['status'] ?? 'N/A'}
- Verified on-chain: ${auction['blockchain_id'] != null ? 'Có' : 'Chưa'}
- Contract address: ${auction['contract_address'] ?? 'N/A'}
''';
  }

  String _formatPrice(dynamic price) {
    if (price == null) return 'N/A';
    try {
      final numPrice = price is String
          ? int.tryParse(price) ?? 0
          : price as int;
      return numPrice.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (match) => '${match[1]},',
      );
    } catch (_) {
      return price.toString();
    }
  }

  Future<void> loadChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);

      if (jsonString != null) {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        _chatHistory = List<Map<String, dynamic>>.from(
          jsonList.map((item) => Map<String, dynamic>.from(item as Map)),
        );
        print('Loaded ${_chatHistory.length} messages from storage');
      } else {
        _chatHistory = [];
      }
    } catch (e) {
      print('Error loading chat history: $e');
      _chatHistory = [];
    }
  }

  Future<void> _saveChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(_chatHistory);
      await prefs.setString(_storageKey, jsonString);
      print('Chat history saved');
    } catch (e) {
      print('Error saving chat history: $e');
    }
  }

  Future<void> clearStoredChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
      _chatHistory.clear();
      print('Chat history cleared');
    } catch (e) {
      print('Error clearing chat history: $e');
    }
  }

  Future<String> sendMessage(String userMessage) async {
    try {
      String contextualMessage = userMessage;
      final lowerMessage = userMessage.toLowerCase();

      if (lowerMessage.contains('đắt nhất') ||
          lowerMessage.contains('expensive') ||
          lowerMessage.contains('cao nhất') ||
          lowerMessage.contains('highest') ||
          lowerMessage.contains('most valuable') ||
          (lowerMessage.contains('đắt') &&
              lowerMessage.contains('trên hệ thống')) ||
          lowerMessage.contains('top') && lowerMessage.contains('price')) {
        try {
          print('[CHATBOT] Detected auction query, fetching data...');
          final topAuctions = await _auctionDataSource.getTopExpensiveAuctions(
            limit: 5,
          );
          if (topAuctions.isNotEmpty) {
            final formattedAuctions = _auctionDataSource.formatAuctionsForChat(
              topAuctions,
            );
            contextualMessage =
                '''$userMessage

Current high-value items on BidChain:
$formattedAuctions

Please reference ONLY these real items when answering. Do not make up or assume any items not in this list.''';
          }
        } catch (e) {
          print('[CHATBOT] Error fetching auction data: $e');
        }
      }

      _chatHistory.add({
        'role': 'user',
        'parts': [
          {'text': userMessage},
        ],
      });
      await _saveChatHistory();

      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1/models/${GeminiConfig.modelName}:generateContent?key=$apiKey',
      );

      final auctionContext = _buildAuctionContextString();
      final messageWithContext =
          '${GeminiConfig.systemPrompt}$auctionContext\n\nUser: $contextualMessage';

      final requestBody = {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': messageWithContext},
            ],
          },
        ],
        'generationConfig': {
          'temperature': GeminiConfig.temperature,
          'maxOutputTokens': GeminiConfig.maxOutputTokens,
          'topP': GeminiConfig.topP,
          'topK': GeminiConfig.topK,
        },
      };

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(requestBody),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'];

        if (text != null && text.isNotEmpty) {
          _chatHistory.add({
            'role': 'model',
            'parts': [
              {'text': text},
            ],
          });
          await _saveChatHistory();
          return text;
        }
        return 'No response from AI';
      } else if (response.statusCode == 400) {
        final errorBody = jsonDecode(response.body);
        final errorMessage = errorBody['error']?['message'] ?? '';

        if (errorMessage.contains('expired') ||
            errorMessage.contains('invalid')) {
          return 'API key đã hết hạn hoặc không hợp lệ. Hãy cập nhật GEMINI_API_KEY trong file .env.';
        } else if (errorMessage.contains('not enabled')) {
          return 'Gemini API chưa được bật trong Google Cloud project.';
        }
        return 'Lỗi cấu hình API: $errorMessage';
      } else if (response.statusCode == 429) {
        return 'Đang bị giới hạn lượt gọi. Vui lòng chờ một phút rồi thử lại.';
      } else if (response.statusCode == 401) {
        return 'API key không hợp lệ. Kiểm tra lại GEMINI_API_KEY.';
      } else {
        return 'Lỗi: ${response.statusCode} - ${response.reasonPhrase}';
      }
    } catch (e) {
      return 'Unexpected error: $e';
    }
  }

  List<Map<String, dynamic>> getChatHistory() {
    return _chatHistory;
  }

  void clearChatHistory() {
    _chatHistory.clear();
  }

  String formatAuctionContext(Map<String, dynamic> auctionData) {
    return '''
Current Auction Information:
- Title: ${auctionData['title'] ?? 'N/A'}
- Current Price: ${auctionData['current_price'] ?? 'N/A'} VND
- Start Price: ${auctionData['start_price'] ?? 'N/A'} VND
- Category: ${auctionData['category'] ?? 'N/A'}
- Condition: ${auctionData['condition'] ?? 'N/A'}
- End Time: ${auctionData['end_time'] ?? 'N/A'}
- Bid Count: ${auctionData['bid_count'] ?? 0}
- Description: ${auctionData['description'] ?? 'N/A'}
''';
  }

  String _detectMimeType(String path) {
    final lowerPath = path.toLowerCase();
    if (lowerPath.endsWith('.png')) return 'image/png';
    if (lowerPath.endsWith('.webp')) return 'image/webp';
    if (lowerPath.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  String _mapPredictionError(String error) {
    final normalized = error.toLowerCase();
    if (normalized.contains('api key') || normalized.contains('invalid')) {
      return 'Gemini API key chưa đúng hoặc đã hết hạn.';
    }
    if (normalized.contains('429') || normalized.contains('quota')) {
      return 'Gemini đang hết quota hoặc bị giới hạn lượt gọi.';
    }
    if (normalized.contains('deadline') || normalized.contains('timeout')) {
      return 'Gemini phản hồi quá chậm, vui lòng thử lại.';
    }
    return 'Không thể dự đoán giá bằng AI lúc này: $error';
  }
}
