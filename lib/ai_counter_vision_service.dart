import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'voice_recognition_service.dart';
import 'size_variant_service.dart';

/// Model representing a single item detected by AI on the checkout counter
class AiDetectedItem {
  String name;
  String? size;
  int qty;
  double rate;
  String category;
  bool isBranded;
  String confidence;
  bool isLearnedRate;
  bool isVoiceRate;

  AiDetectedItem({
    required this.name,
    this.size,
    this.qty = 1,
    this.rate = 0.0,
    this.category = "General",
    this.isBranded = false,
    this.confidence = "medium",
    this.isLearnedRate = false,
    this.isVoiceRate = false,
  });

  double get totalPrice => qty * rate;

  factory AiDetectedItem.fromJson(Map<String, dynamic> json) {
    // Clean name
    String rawName = (json['name'] ?? json['itemName'] ?? json['item'] ?? "General Item").toString().trim();
    if (rawName.isEmpty) rawName = "General Item";

    // Parse quantity
    int parsedQty = 1;
    final rawQty = json['qty'] ?? json['quantity'];
    if (rawQty is num) {
      parsedQty = rawQty.toInt();
    } else if (rawQty is String) {
      parsedQty = int.tryParse(rawQty) ?? 1;
    }
    if (parsedQty <= 0) parsedQty = 1;

    // Parse rate / price
    double parsedRate = 0.0;
    final rawRate = json['rate'] ?? json['price'] ?? json['mrp'] ?? json['estimatedRate'];
    if (rawRate is num) {
      parsedRate = rawRate.toDouble();
    } else if (rawRate is String) {
      final sanitized = rawRate.replaceAll(RegExp(r'[^\d.]'), '');
      parsedRate = double.tryParse(sanitized) ?? 0.0;
    }

    final cat = (json['category'] ?? "General").toString();
    final src = (json['source'] ?? "").toString().toLowerCase();
    final isVoice = src == "voice" || json['isVoiceRate'] == true;
    final isLearned = src == "learned" || json['isLearnedRate'] == true;
    final branded = json['isBranded'] == true || (json['branded'] == true) || src == "mrp";
    final conf = (json['confidence'] ?? "medium").toString();
    final parsedSize = (json['size'] ?? json['sizeLabel'] ?? SizeVariantService.extractSizeLabel(rawName))?.toString();

    return AiDetectedItem(
      name: rawName,
      size: parsedSize,
      qty: parsedQty,
      rate: parsedRate,
      category: cat,
      isBranded: branded,
      confidence: conf,
      isLearnedRate: isLearned,
      isVoiceRate: isVoice,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (size != null) 'size': size,
    'qty': qty,
    'rate': rate,
    'category': category,
    'isBranded': isBranded,
    'confidence': confidence,
  };
}

/// Service that analyzes pictures of checkout counters using Google Gemini Flash
/// Handles both branded cosmetics (reading packaging/MRP) and unbranded/unnamed items
/// (safety pins, hair clutchers, bangles, bindi, scrunchies, etc.)
class AiCounterVisionService {
  static final AiCounterVisionService _instance = AiCounterVisionService._internal();
  factory AiCounterVisionService() => _instance;
  AiCounterVisionService._internal();

  static const String _prefApiKey = 'gemini_vision_api_key';
  static const String _prefModel = 'gemini_vision_model';
  static const String _prefPriceMemory = 'shop_ai_price_memory';

  static int _currentKeyIndex = 0;
  static final Map<String, DateTime> _exhaustedKeys = {};

  /// Supported Gemini multimodal models in order of fallback priority
  static const List<String> availableModels = [
    'gemini-2.5-flash',
    'gemini-2.0-flash',
    'gemini-2.5-flash-lite',
    'gemini-2.0-flash-lite',
    'gemini-3.5-flash',
  ];

  /// Parse one or multiple API keys separated by commas, newlines, or semicolons
  static List<String> parseApiKeys(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    return raw
        .split(RegExp(r'[,\n\r;\s]+'))
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty && k.length >= 15)
        .toSet() // Deduplicate
        .toList();
  }

  /// Get all configured family API keys
  Future<List<String>> getApiKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefApiKey);
    return parseApiKeys(raw);
  }

  Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefApiKey);
  }

  Future<void> saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefApiKey, key.trim());
  }

  Future<String> getSelectedModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefModel) ?? 'auto';
  }

  Future<void> saveSelectedModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefModel, model);
  }

  /// Get shop's confirmed price memory (learned from cashier edits/confirmations)
  Future<Map<String, double>> getShopPriceMemory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefPriceMemory);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString().toLowerCase().trim(), (v as num).toDouble()));
        }
      }
    } catch (e) {
      debugPrint("Error loading shop price memory: $e");
    }
    return {};
  }

  /// Learn/Update store confirmed rates whenever cashier checks out or edits prices
  Future<void> learnConfirmedPrices(List<AiDetectedItem> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = await getShopPriceMemory();
      bool changed = false;
      for (final it in items) {
        if (it.rate > 0 && it.name.trim().isNotEmpty) {
          final k = it.name.trim().toLowerCase();
          if (current[k] != it.rate) {
            current[k] = it.rate;
            changed = true;
          }
        }
      }
      if (changed) {
        await prefs.setString(_prefPriceMemory, jsonEncode(current));
        debugPrint("AI Vision learned/updated ${items.length} item rates in shop price memory");
      }
    } catch (e) {
      debugPrint("Error saving shop price memory: $e");
    }
  }

  /// Remove a specific learned item from price memory
  Future<void> removeLearnedPrice(String itemName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = await getShopPriceMemory();
      current.remove(itemName.trim().toLowerCase());
      await prefs.setString(_prefPriceMemory, jsonEncode(current));
    } catch (e) {
      debugPrint("Error removing item from price memory: $e");
    }
  }

  /// Reset all learned shop price memory
  Future<void> clearAllPriceMemory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefPriceMemory);
  }

  /// Launch camera or image picker to capture checkout counter items
  static Future<List<AiDetectedItem>?> pickAndAnalyzeCounterItems(
    BuildContext context, {
    ImageSource source = ImageSource.camera,
  }) async {
    final service = AiCounterVisionService();
    List<String> keys = await service.getApiKeys();

    // If no API key configured yet, prompt setup dialog
    if (keys.isEmpty) {
      final configured = await showApiKeySetupDialog(context);
      if (!configured) return null;
      keys = await service.getApiKeys();
      if (keys.isEmpty) return null;
    }

    // Capture or pick image
    final picker = ImagePicker();
    XFile? pickedFile;
    try {
      pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 70, // Compresses to ~150-250KB for fast 1s upload
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error accessing camera/gallery: $e")),
        );
      }
      return null;
    }

    if (pickedFile == null) return null;

    final imageBytes = await pickedFile.readAsBytes();

    // Option C (Default): Counter Photo Preview & Voice Hint Sheet
    String? voiceHint;
    if (context.mounted) {
      voiceHint = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _AiCounterVoicePromptSheet(imageBytes: imageBytes),
      );
    }

    // Cashier cancelled or dismissed sheet
    if (voiceHint == "__CANCEL__") return null;

    // Show Progress Dialog
    if (!context.mounted) return null;
    final nav = Navigator.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false,
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF7C3AED)),
                const SizedBox(height: 20),
                const Text(
                  "AI Counter Scanning...",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  voiceHint != null && voiceHint.isNotEmpty
                      ? "Applying voice hint & visual rules with Gemini 2.5 Flash..."
                      : "Calculating bill with Gemini 2.5 Flash visual rules...",
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    List<AiDetectedItem> detectedItems = [];
    String? errorMessage;

    try {
      detectedItems = await service.analyzeCounterImage(
        imageBytes,
        voiceHint: voiceHint,
      );
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      if (nav.canPop()) nav.pop(); // Close progress dialog
    }

    if (errorMessage != null) {
      if (context.mounted) {
        _showErrorDialog(context, errorMessage);
      }
      return null;
    }

    if (detectedItems.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No items clearly identified. Try snapping closer or in better light.")),
        );
      }
      return null;
    }

    // Show Interactive Confirmation Sheet
    if (!context.mounted) return null;
    return showModalBottomSheet<List<AiDetectedItem>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AiCounterBillReviewSheet(
        imageBytes: imageBytes,
        initialItems: detectedItems,
        voiceHint: voiceHint,
      ),
    );
  }

  /// Analyze image bytes with Gemini Flash (Google AI Studio)
  Future<List<AiDetectedItem>> analyzeCounterImage(
    Uint8List imageBytes, {
    String? apiKey,
    String? voiceHint,
  }) async {
    final base64Image = base64Encode(imageBytes);

    String voiceHintBlock = "";
    if (voiceHint != null && voiceHint.trim().isNotEmpty) {
      voiceHintBlock = """

CASHIER'S LIVE SPOKEN VOICE HINT:
The cashier looked at the counter and spoke this instruction in Hindi/Hinglish/Indian English:
"$voiceHint"
- If the cashier explicitly stated a price for an item (e.g. "clutcher 40 ka hai", "lipstick 150"), set "rate" to that price and "source": "voice".
""";
    }

    // Optimized prompt: ONLY write names and quantities; DO NOT suggest or estimate prices!
    final prompt = """
You are an expert AI retail item detector for an Indian retail general, jewellery, and cosmetic shop ("Love Kush Shopping Center").
Analyze this picture of items placed on the checkout counter and list all items accurately.

CRITICAL INSTRUCTION - DO NOT GUESS OR ESTIMATE ANY PRICES:
Do NOT suggest, guess, or estimate any prices! The cashier will enter the exact numbers line-by-line using a fast calculator keypad.
- Set "rate": 0.0 for all items (UNLESS the cashier explicitly stated a price in the live voice hint).
- Set "source": "counter_scan" (or "voice" if from cashier's voice hint).
- Focus 100% of your intelligence on accurately identifying the specific ITEM NAMES, SIZES, and QUANTITIES.

RULES:
1. IDENTIFY BOTH BRANDED AND UNBRANDED / UNNAMED ITEMS:
   - UNBRANDED / UNNAMED / GENERAL ITEMS (Common on counter):
     * Hair Accessories: Hair Clutcher / Claw Clip (specify size/style, e.g. "Butterfly Hair Clutcher Medium", "Small Metal Hair Clip", "Tic-Tac Pins Card", "Bobby Pins", "Hair Rubber Bands", "Velvet Scrunchie", "Hair Band", "Juda Pin").
     * Daily Use / General: Safety Pins (card or bunch), Tailoring Thread / Ribbon / Lace, Comb, Nail Clipper, Pocket Mirror, Keychain, Mehendi Cone.
     * Jewellery / Traditional: Bangles / Choori (specify type/size if visible, e.g. "Glass Bangles Set 2.4", "Metal Choori Set 2.6", "Chuda"), Bindi Packet / Card, Sindoor, Earring Pair, Payal / Anklet, Mangalsutra.
   - BRANDED / PACKAGED COSMETIC ITEMS:
     * Read brand name, product line, and size/variant if visible (e.g. "Lakme Eyeconic Kajal", "Blue Heaven Nail Polish", "Ponds Powder 100g", "Fair & Lovely Cream 50g", "Dazller Eyeliner", "Elle 18 Matte Lipstick", "Vaseline Lip Balm", "Garnier Face Wash 100ml").

2. QUANTITY ACCURACY:
   - Count the physical number of units for each distinct item.
   - If there are 3 clutchers of the same style, set qty: 3.
   - If there are 2 bindi cards, set qty: 2.
   - For bangles, count each set/dozen as 1 set (qty: 1) or individual bundles.

$voiceHintBlock

3. RESPONSE FORMAT:
   Return ONLY a valid JSON array of objects. No markdown formatting, no code blocks, no backticks, no explanatory text.
   Schema:
   [
     {
       "name": "Specific Descriptive Item Name (e.g. Butterfly Hair Clutcher Medium, Safety Pins Card, Elle 18 Matte Lipstick, Ponds Cream 50g)",
       "qty": 1,
       "rate": 0.0,
       "category": "Hair Accessories" | "Cosmetics" | "Jewellery" | "General" | "Tailoring",
       "isBranded": false,
       "source": "counter_scan",
       "confidence": "high" | "medium" | "low"
     }
   ]
""";

    final requestBody = jsonEncode({
      "contents": [
        {
          "parts": [
            {"text": prompt},
            {
              "inline_data": {
                "mime_type": "image/jpeg",
                "data": base64Image,
              }
            }
          ]
        }
      ],
      "generationConfig": {
        "temperature": 0.1,
        "response_mime_type": "application/json",
      }
    });

    // Determine family key pool
    List<String> keyPool;
    if (apiKey != null && apiKey.trim().isNotEmpty) {
      keyPool = parseApiKeys(apiKey);
    } else {
      keyPool = await getApiKeys();
    }

    if (keyPool.isEmpty) {
      throw "No Gemini API Key configured. Please enter your API Key in Settings.";
    }

    // Prune exhausted keys older than 5 minutes
    final now = DateTime.now();
    _exhaustedKeys.removeWhere((_, time) => now.difference(time).inMinutes >= 5);

    // Order keys: non-exhausted keys first, rotated by _currentKeyIndex
    List<String> sortedKeys = List.from(keyPool);
    if (sortedKeys.length > 1) {
      final shift = _currentKeyIndex % sortedKeys.length;
      sortedKeys = [...sortedKeys.sublist(shift), ...sortedKeys.sublist(0, shift)];
      sortedKeys.sort((a, b) {
        final aEx = _exhaustedKeys.containsKey(a);
        final bEx = _exhaustedKeys.containsKey(b);
        if (aEx && !bEx) return 1;
        if (!aEx && bEx) return -1;
        return 0;
      });
    }

    // Query active Gemini model with automatic fallback
    final savedModelPref = await getSelectedModel();
    List<String> modelsToTry;
    if (savedModelPref != 'auto' && availableModels.contains(savedModelPref)) {
      modelsToTry = [savedModelPref, ...availableModels.where((m) => m != savedModelPref)];
    } else {
      modelsToTry = List.from(availableModels);
    }

    http.Response? response;
    String lastErrorMessage = "Unknown error";
    bool anyQuotaExceeded = false;

    for (int kIdx = 0; kIdx < sortedKeys.length; kIdx++) {
      final activeKey = sortedKeys[kIdx];
      final keyDisplay = activeKey.length > 8
          ? "${activeKey.substring(0, 6)}...${activeKey.substring(activeKey.length - 4)}"
          : activeKey;

      for (final model in modelsToTry) {
        final url = Uri.parse(
          "https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=${activeKey.trim()}",
        );

        try {
          debugPrint("AI Counter Vision: Trying model '$model' with family key #$kIdx ($keyDisplay)...");
          final res = await http.post(
            url,
            headers: {"Content-Type": "application/json"},
            body: requestBody,
          ).timeout(const Duration(seconds: 25));

          if (res.statusCode == 200) {
            response = res;
            _exhaustedKeys.remove(activeKey);
            _currentKeyIndex = (_currentKeyIndex + 1) % keyPool.length;
            debugPrint("AI Counter Vision: Success with key $keyDisplay and model '$model'");
            break;
          }

          String errMessage = "Gemini API error (Status ${res.statusCode})";
          try {
            final errJson = jsonDecode(res.body);
            if (errJson['error'] != null && errJson['error']['message'] != null) {
              errMessage = errJson['error']['message'];
            }
          } catch (_) {}

          lastErrorMessage = errMessage;
          debugPrint("AI Counter Vision: Model '$model' with key $keyDisplay returned ${res.statusCode}: $errMessage");

          if (res.statusCode == 429) {
            _exhaustedKeys[activeKey] = DateTime.now();
            anyQuotaExceeded = true;
            debugPrint("AI Counter Vision: Family key $keyDisplay reached rate limit (429). Rotating to next key in pool...");
            break; // Break model loop, proceed to next family key
          }

          if (res.statusCode == 400 && errMessage.toLowerCase().contains("api_key")) {
            debugPrint("AI Counter Vision: Family key $keyDisplay is invalid (400). Trying next key...");
            break; // Break model loop, proceed to next family key
          }
        } catch (e) {
          lastErrorMessage = e.toString();
          debugPrint("AI Counter Vision: Exception on model '$model' with key $keyDisplay: $e");
        }
      }

      if (response != null && response.statusCode == 200) {
        break; // Successfully received response, stop key iteration
      }
    }

    if (response == null || response.statusCode != 200) {
      if (anyQuotaExceeded && sortedKeys.length > 1) {
        throw "All ${keyPool.length} family API keys in your pool reached their daily/minute rate limit. Please wait a few moments or add another family account key in Settings.";
      } else if (anyQuotaExceeded) {
        throw "Gemini API rate limit reached (429). Tip: Add keys from your family members' Google accounts in Settings to combine quotas!";
      }
      throw "AI Vision error: $lastErrorMessage. (Models attempted: ${modelsToTry.join(', ')}). Please check your API keys in Settings.";
    }

    final Map<String, dynamic> data = jsonDecode(response.body);
    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw "No response received from Gemini model.";
    }

    final content = candidates[0]['content'];
    final parts = content != null ? content['parts'] as List? : null;
    if (parts == null || parts.isEmpty) {
      throw "Empty content received from Gemini model.";
    }

    String rawText = parts[0]['text'] ?? "";
    rawText = rawText.trim();

    // Strip any backticks if present
    if (rawText.startsWith("```json")) {
      rawText = rawText.substring(7);
    } else if (rawText.startsWith("```")) {
      rawText = rawText.substring(3);
    }
    if (rawText.endsWith("```")) {
      rawText = rawText.substring(0, rawText.length - 3);
    }
    rawText = rawText.trim();

    final dynamic parsed = jsonDecode(rawText);
    List<dynamic> itemsList = [];
    if (parsed is List) {
      itemsList = parsed;
    } else if (parsed is Map && parsed['items'] is List) {
      itemsList = parsed['items'];
    }

    final List<AiDetectedItem> resultItems = itemsList
        .map((item) => AiDetectedItem.fromJson(item as Map<String, dynamic>))
        .toList();

    return resultItems;
  }

  /// Show Dialog to configure the Free Gemini API Key Pool and Model
  static Future<bool> showApiKeySetupDialog(BuildContext context) async {
    final service = AiCounterVisionService();
    final currentKey = await service.getApiKey() ?? "";
    final currentModel = await service.getSelectedModel();
    final keyCtrl = TextEditingController(text: currentKey);
    String selectedModel = currentModel;
    bool obscure = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (ctx, setDState) {
          final parsedKeys = parseApiKeys(keyCtrl.text);

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: const [
                Icon(Icons.auto_awesome, color: Color(0xFF7C3AED)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Gemini AI Setup (Family Pool)",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F3FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFDDD6FE)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.family_restroom, size: 18, color: Color(0xFF6D28D9)),
                            SizedBox(width: 6),
                            Text(
                              "Family Multi-Key Pool (Unlimited)",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF6D28D9)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          "Each Google account provides 1,500 free daily scans (\$0 / ₹0). Paste keys from your family members' accounts below (separate with a new line or comma). The app will automatically share and failover between them so quota never runs out!",
                          style: TextStyle(fontSize: 11, color: Colors.black87, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text("Google AI Studio API Keys:", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: keyCtrl,
                    obscureText: obscure,
                    minLines: 2,
                    maxLines: 4,
                    onChanged: (_) => setDState(() {}),
                    decoration: InputDecoration(
                      hintText: "Paste 1 or more keys:\nAIzaSy...Key1\nAIzaSy...Key2",
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.all(12),
                      suffixIcon: IconButton(
                        icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setDState(() => obscure = !obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Live Pool Counter Indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: parsedKeys.length > 1
                          ? const Color(0xFFECFDF5)
                          : (parsedKeys.length == 1 ? const Color(0xFFEFF6FF) : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: parsedKeys.length > 1
                            ? const Color(0xFFA7F3D0)
                            : (parsedKeys.length == 1 ? const Color(0xFFBFDBFE) : Colors.grey.shade300),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          parsedKeys.length > 1
                              ? Icons.verified
                              : (parsedKeys.length == 1 ? Icons.check_circle_outline : Icons.info_outline),
                          size: 15,
                          color: parsedKeys.length > 1
                              ? const Color(0xFF059669)
                              : (parsedKeys.length == 1 ? const Color(0xFF2563EB) : Colors.grey),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            parsedKeys.length > 1
                                ? "🎉 ${parsedKeys.length} Family Keys Active (~${parsedKeys.length * 1500} scans/day capacity)"
                                : (parsedKeys.length == 1
                                    ? "1 Key Active (~1,500 scans/day). Tip: Add family keys to combine quotas!"
                                    : "No valid API key entered yet"),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: parsedKeys.length > 1
                                  ? const Color(0xFF065F46)
                                  : (parsedKeys.length == 1 ? const Color(0xFF1E40AF) : Colors.black54),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text("Gemini Vision Model:", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: selectedModel,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'auto',
                        child: Text("Auto: Gemini 2.5 Flash (Fallback: 2.0)", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      ),
                      DropdownMenuItem(
                        value: 'gemini-2.5-flash',
                        child: Text("gemini-2.5-flash (Google Recommended)", style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: 'gemini-2.0-flash',
                        child: Text("gemini-2.0-flash (Stable Multi-modal)", style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: 'gemini-2.5-flash-lite',
                        child: Text("gemini-2.5-flash-lite (Fastest / Budget)", style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: 'gemini-2.0-flash-lite',
                        child: Text("gemini-2.0-flash-lite (Lightweight)", style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: 'gemini-3.5-flash',
                        child: Text("gemini-3.5-flash (Next-Gen Flash)", style: TextStyle(fontSize: 13)),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setDState(() => selectedModel = val);
                    },
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Note: Google deprecated gemini-1.5-flash. Love Kush POS now uses gemini-2.5-flash with automatic multi-model fallback.",
                    style: TextStyle(fontSize: 10, color: Colors.black54),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    icon: const Icon(Icons.open_in_new, size: 15),
                    label: const Text("Get Free Key from Google AI Studio", style: TextStyle(fontSize: 12)),
                    onPressed: () async {
                      final uri = Uri.parse("https://aistudio.google.com/app/apikey");
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx, false),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C3AED)),
                onPressed: () async {
                  final raw = keyCtrl.text.trim();
                  final parsed = parseApiKeys(raw);
                  if (parsed.isNotEmpty) {
                    await service.saveApiKey(raw);
                    await service.saveSelectedModel(selectedModel);
                    Navigator.pop(dCtx, true);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Please enter at least 1 valid API Key")),
                    );
                  }
                },
                child: const Text("Save Keys & Model", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    return result ?? false;
  }

  static void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text("AI Scan Failed"),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              showApiKeySetupDialog(context);
            },
            child: const Text("Check API Key"),
          ),
        ],
      ),
    );
  }
}

/// Interactive Bottom Sheet for Cashier to Review, Edit, or Add Items Detected by AI
class _AiCounterBillReviewSheet extends StatefulWidget {
  final Uint8List imageBytes;
  final List<AiDetectedItem> initialItems;
  final String? voiceHint;

  const _AiCounterBillReviewSheet({
    Key? key,
    required this.imageBytes,
    required this.initialItems,
    this.voiceHint,
  }) : super(key: key);

  @override
  State<_AiCounterBillReviewSheet> createState() => _AiCounterBillReviewSheetState();
}

class _AiCounterBillReviewSheetState extends State<_AiCounterBillReviewSheet> {
  late List<AiDetectedItem> _items;
  int _focusedIndex = 0;
  String _calcBuffer = "";
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.initialItems);
    final firstUnpriced = _items.indexWhere((it) => it.rate <= 0);
    _focusedIndex = firstUnpriced != -1 ? firstUnpriced : 0;
    if (_items.isNotEmpty && _items[_focusedIndex].rate > 0) {
      final r = _items[_focusedIndex].rate;
      _calcBuffer = r % 1 == 0 ? r.toInt().toString() : r.toString();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  double get _grandTotal => _items.fold(0.0, (sum, it) => sum + it.totalPrice);
  int get _totalItemUnits => _items.fold(0, (sum, it) => sum + it.qty);

  void _setFocused(int index) {
    if (index < 0 || index >= _items.length) return;
    setState(() {
      _focusedIndex = index;
      final curRate = _items[index].rate;
      _calcBuffer = curRate > 0
          ? (curRate % 1 == 0 ? curRate.toInt().toString() : curRate.toString())
          : "";
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final target = (index * 72.0).clamp(0.0, _scrollController.position.maxScrollExtent);
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onDigit(String d) {
    if (_focusedIndex < 0 || _focusedIndex >= _items.length) return;
    setState(() {
      if (_calcBuffer == "0" && d != ".") {
        _calcBuffer = d;
      } else {
        _calcBuffer += d;
      }
      final parsed = double.tryParse(_calcBuffer) ?? 0.0;
      _items[_focusedIndex].rate = parsed;
    });
  }

  void _onQuickAdd(double amount) {
    if (_focusedIndex < 0 || _focusedIndex >= _items.length) return;
    setState(() {
      final cur = double.tryParse(_calcBuffer) ?? _items[_focusedIndex].rate;
      final next = cur + amount;
      _calcBuffer = next % 1 == 0 ? next.toInt().toString() : next.toString();
      _items[_focusedIndex].rate = next;
    });
  }

  void _onClear() {
    if (_focusedIndex < 0 || _focusedIndex >= _items.length) return;
    setState(() {
      _calcBuffer = "";
      _items[_focusedIndex].rate = 0.0;
    });
  }

  void _onBackspace() {
    if (_focusedIndex < 0 || _focusedIndex >= _items.length) return;
    setState(() {
      if (_calcBuffer.isNotEmpty) {
        _calcBuffer = _calcBuffer.substring(0, _calcBuffer.length - 1);
        final parsed = double.tryParse(_calcBuffer) ?? 0.0;
        _items[_focusedIndex].rate = parsed;
      } else {
        _items[_focusedIndex].rate = 0.0;
      }
    });
  }

  void _onPrevItem() {
    if (_focusedIndex > 0) {
      _setFocused(_focusedIndex - 1);
    }
  }

  void _onNextOrDone() {
    if (_focusedIndex < _items.length - 1) {
      _setFocused(_focusedIndex + 1);
    } else {
      // Completed all lines, commit to cart
      AiCounterVisionService().learnConfirmedPrices(_items);
      Navigator.pop(context, _items);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.94,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 10),

          // Header Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F3FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFDDD6FE)),
                  ),
                  child: const Icon(Icons.calculate, color: Color(0xFF7C3AED), size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "AI Items • Calculator Entry",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                      Text(
                        "${_items.length} items ($_totalItemUnits pcs) • Enter rates line-by-line",
                        style: const TextStyle(fontSize: 11.5, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                // Counter thumbnail with preview
                GestureDetector(
                  onTap: () => _showPhotoPreview(context),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Image.memory(
                          widget.imageBytes,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                        ),
                        Container(
                          padding: const EdgeInsets.all(2),
                          color: Colors.black54,
                          child: const Icon(Icons.zoom_in, color: Colors.white, size: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 16),

          // Voice Hint Banner (if provided by cashier)
          if (widget.voiceHint != null && widget.voiceHint!.trim().isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.mic, size: 14, color: Color(0xFF2563EB)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Voice Hint: "${widget.voiceHint!.trim()}"',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E40AF)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],

          // Items List
          Expanded(
            child: _items.isEmpty
                ? const Center(
                    child: Text("No items in list. Tap '+ Add Item' below."),
                  )
                : ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (ctx, index) {
                      final item = _items[index];
                      return _buildItemRow(item, index);
                    },
                  ),
          ),

          // Compact Toolbar: Add Item & Retake
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text("Add Item", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: const Size(0, 30),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: _addNewManualItem,
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  icon: const Icon(Icons.camera_alt, size: 14),
                  label: const Text("Retake", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: const Size(0, 30),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: () => Navigator.pop(context, null),
                ),
                const Spacer(),
                Text(
                  "Total: ₹${_grandTotal % 1 == 0 ? _grandTotal.toInt() : _grandTotal.toStringAsFixed(2)}",
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                ),
              ],
            ),
          ),

          // Line-by-Line Calculator Keypad Panel
          _buildCalculatorKeypad(),
        ],
      ),
    );
  }

  Widget _buildCalculatorKeypad() {
    if (_items.isEmpty) return const SizedBox.shrink();
    final currentItem = (_focusedIndex >= 0 && _focusedIndex < _items.length)
        ? _items[_focusedIndex]
        : null;
    final bool isLastItem = _focusedIndex >= _items.length - 1;
    final bool allPriced = _items.every((it) => it.rate > 0);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300, width: 1.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Active item line banner
          if (currentItem != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFAF5FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFDDD6FE)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      "${_focusedIndex + 1}/${_items.length}",
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "${currentItem.qty}x ${currentItem.name}",
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4C1D95)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    "₹ ${_calcBuffer.isEmpty ? (currentItem.rate > 0 ? (currentItem.rate % 1 == 0 ? currentItem.rate.toInt() : currentItem.rate.toStringAsFixed(2)) : "0") : _calcBuffer}",
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF059669),
                    ),
                  ),
                ],
              ),
            ),

          // Keypad Grid (compact, easy to tap)
          Row(
            children: [
              _buildCalcKey("1", () => _onDigit("1")),
              _buildCalcKey("2", () => _onDigit("2")),
              _buildCalcKey("3", () => _onDigit("3")),
              _buildQuickAddKey("+10", 10),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _buildCalcKey("4", () => _onDigit("4")),
              _buildCalcKey("5", () => _onDigit("5")),
              _buildCalcKey("6", () => _onDigit("6")),
              _buildQuickAddKey("+20", 20),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _buildCalcKey("7", () => _onDigit("7")),
              _buildCalcKey("8", () => _onDigit("8")),
              _buildCalcKey("9", () => _onDigit("9")),
              _buildQuickAddKey("+50", 50),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _buildCalcKey("C", _onClear, color: const Color(0xFFFEE2E2), textColor: const Color(0xFFDC2626)),
              _buildCalcKey("0", () => _onDigit("0")),
              _buildCalcKey("00", () => _onDigit("00")),
              _buildCalcKey("⌫", _onBackspace, color: const Color(0xFFF1F5F9), textColor: const Color(0xFF475569)),
            ],
          ),
          const SizedBox(height: 6),

          // Action Navigation Row
          Row(
            children: [
              if (_focusedIndex > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: SizedBox(
                    height: 40,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      icon: const Icon(Icons.arrow_back_ios, size: 11),
                      label: const Text("PREV", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      onPressed: _onPrevItem,
                    ),
                  ),
                ),
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isLastItem || allPriced
                          ? const Color(0xFF059669)
                          : const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 1,
                    ),
                    onPressed: _onNextOrDone,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          isLastItem
                              ? "ADD ALL TO CART (₹${_grandTotal % 1 == 0 ? _grandTotal.toInt() : _grandTotal.toStringAsFixed(2)}) ➔"
                              : "NEXT ITEM ➔",
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 4),
                        Icon(isLastItem ? Icons.shopping_cart_checkout : Icons.arrow_forward_ios, size: 14),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCalcKey(String label, VoidCallback onTap, {Color? color, Color? textColor, int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.0),
        child: SizedBox(
          height: 38,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: color ?? const Color(0xFFF8FAFC),
              foregroundColor: textColor ?? const Color(0xFF1E293B),
              elevation: 0,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            onPressed: onTap,
            child: Text(
              label,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textColor ?? const Color(0xFF1E293B)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAddKey(String label, double amount) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.0),
        child: SizedBox(
          height: 38,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEFF6FF),
              foregroundColor: const Color(0xFF2563EB),
              elevation: 0,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: const BorderSide(color: Color(0xFFBFDBFE)),
              ),
            ),
            onPressed: () => _onQuickAdd(amount),
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItemRow(AiDetectedItem item, int index) {
    final bool isFocused = index == _focusedIndex;

    return InkWell(
      onTap: () => _setFocused(index),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isFocused ? const Color(0xFFFAF5FF) : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isFocused ? const Color(0xFF7C3AED) : Colors.grey.shade200,
            width: isFocused ? 2.0 : 1.0,
          ),
          boxShadow: isFocused
              ? [
                  BoxShadow(
                    color: const Color(0xFF7C3AED).withOpacity(0.12),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // Focused Indicator or Category Icon
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isFocused
                    ? const Color(0xFF7C3AED)
                    : _getCategoryColor(item.category).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: isFocused
                  ? const Icon(Icons.edit, size: 14, color: Colors.white)
                  : Icon(_getCategoryIcon(item.category), size: 15, color: _getCategoryColor(item.category)),
            ),
            const SizedBox(width: 8),

            // Name and Edit / Size
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.name,
                          style: TextStyle(
                            fontWeight: isFocused ? FontWeight.w800 : FontWeight.bold,
                            fontSize: 13,
                            color: isFocused ? const Color(0xFF4C1D95) : Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Quick Voice / Rename button
                      InkWell(
                        onTap: () => _editItemName(index),
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(Icons.edit, size: 12, color: Colors.black45),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        item.category,
                        style: TextStyle(fontSize: 9.5, color: _getCategoryColor(item.category), fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => _pickSizeForItem(index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFF59E0B)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.straighten, size: 9, color: Color(0xFFB45309)),
                              const SizedBox(width: 3),
                              Text(
                                item.size != null && item.size!.isNotEmpty
                                    ? "Size: ${item.size}"
                                    : (SizeVariantService.extractSizeLabel(item.name) != null
                                        ? "Size: ${SizeVariantService.extractSizeLabel(item.name)}"
                                        : "📏 Size"),
                                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (item.isVoiceRate) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.5)),
                          ),
                          child: const Text("Voice Rate 🎤", style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8))),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Quantity Stepper [-] [qty] [+]
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () {
                      if (item.qty > 1) {
                        setState(() => item.qty--);
                      } else {
                        setState(() {
                          _items.removeAt(index);
                          if (_focusedIndex >= _items.length && _items.isNotEmpty) {
                            _focusedIndex = _items.length - 1;
                          }
                        });
                      }
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      child: Icon(Icons.remove, size: 13, color: Colors.black87),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Text(
                      "${item.qty}",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => item.qty++),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      child: Icon(Icons.add, size: 13, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Rate Display Pill (Active highlighted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: isFocused
                    ? const Color(0xFF7C3AED)
                    : (item.rate <= 0 ? const Color(0xFFFEF2F2) : Colors.white),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isFocused
                      ? const Color(0xFF6D28D9)
                      : (item.rate <= 0 ? Colors.redAccent : Colors.grey.shade300),
                  width: isFocused ? 1.5 : 1.0,
                ),
              ),
              child: Text(
                item.rate <= 0
                    ? (isFocused ? (_calcBuffer.isNotEmpty ? "₹ $_calcBuffer" : "₹ __") : "₹ --")
                    : (isFocused && _calcBuffer.isNotEmpty
                        ? "₹ $_calcBuffer"
                        : "₹${item.rate % 1 == 0 ? item.rate.toInt() : item.rate.toStringAsFixed(2)}"),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  color: isFocused
                      ? Colors.white
                      : (item.rate <= 0 ? Colors.red : const Color(0xFF1E293B)),
                ),
              ),
            ),
            const SizedBox(width: 6),

            // Line Total
            SizedBox(
              width: 48,
              child: Text(
                "₹${item.totalPrice % 1 == 0 ? item.totalPrice.toInt() : item.totalPrice.toStringAsFixed(2)}",
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: isFocused ? const Color(0xFF7C3AED) : const Color(0xFF059669),
                ),
              ),
            ),
            const SizedBox(width: 4),

            // Delete Button
            InkWell(
              onTap: () {
                setState(() {
                  _items.removeAt(index);
                  if (_focusedIndex >= _items.length && _items.isNotEmpty) {
                    _focusedIndex = _items.length - 1;
                  }
                });
              },
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 15, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _editItemName(int index) async {
    final item = _items[index];
    final ctrl = TextEditingController(text: item.name);

    final newName = await showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text("Edit Item Name", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.mic, color: Color(0xFFEF4444)),
                  tooltip: "Speak name",
                  onPressed: () async {
                    final spoken = await VoiceRecognitionService.showVoiceInputSheet(
                      dCtx,
                      initialText: ctrl.text,
                    );
                    if (spoken != null && spoken.isNotEmpty) {
                      ctrl.text = spoken;
                    }
                  },
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(dCtx, ctrl.text.trim()),
            child: const Text("Save"),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      setState(() => item.name = newName);
    }
  }

  void _pickSizeForItem(int index) async {
    final item = _items[index];
    final selectedVariant = await SizeVariantService.showSizeSelectorModal(
      context,
      itemName: item.name,
      currentRate: item.rate,
      category: item.category,
    );
    if (selectedVariant != null) {
      setState(() {
        item.size = selectedVariant.sizeLabel;
        item.rate = selectedVariant.rate;
        item.name = selectedVariant.fullName ?? SizeVariantService.formatItemWithSize(item.name, selectedVariant.sizeLabel);
        item.isLearnedRate = true;
      });
      AiCounterVisionService().learnConfirmedPrices([item]);
    }
  }

  void _addNewManualItem() async {
    final nameCtrl = TextEditingController();
    final rateCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: "1");

    await showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text("Add Missing Item", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: "Item Name",
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.mic, color: Color(0xFFEF4444)),
                  onPressed: () async {
                    final spoken = await VoiceRecognitionService.showVoiceInputSheet(dCtx);
                    if (spoken != null && spoken.isNotEmpty) {
                      nameCtrl.text = spoken;
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: rateCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: "Rate (₹)",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Qty",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              final n = nameCtrl.text.trim();
              if (n.isNotEmpty) {
                final r = double.tryParse(rateCtrl.text.trim()) ?? 0.0;
                final q = int.tryParse(qtyCtrl.text.trim()) ?? 1;
                setState(() {
                  _items.add(AiDetectedItem(name: n, rate: r, qty: q > 0 ? q : 1));
                });
                Navigator.pop(dCtx);
              }
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  void _showPhotoPreview(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(widget.imageBytes),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white24),
              child: const Text("Close", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case "hair accessories":
        return const Color(0xFFD946EF);
      case "cosmetics":
        return const Color(0xFFEC4899);
      case "jewellery":
        return const Color(0xFFF59E0B);
      case "tailoring":
        return const Color(0xFF06B6D4);
      default:
        return const Color(0xFF6B7280);
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case "hair accessories":
        return Icons.brush;
      case "cosmetics":
        return Icons.face;
      case "jewellery":
        return Icons.diamond;
      case "tailoring":
        return Icons.straighten;
      default:
        return Icons.category;
    }
  }
}

/// Bottom Sheet displayed immediately after counter photo capture
/// Enables Cashier to speak an optional voice hint (e.g. "Do clutcher 40 wale, ek lipstick")
/// or tap directly to calculate bill using visual pricing rules (Option C by default)
class _AiCounterVoicePromptSheet extends StatefulWidget {
  final Uint8List imageBytes;

  const _AiCounterVoicePromptSheet({
    Key? key,
    required this.imageBytes,
  }) : super(key: key);

  @override
  State<_AiCounterVoicePromptSheet> createState() => _AiCounterVoicePromptSheetState();
}

class _AiCounterVoicePromptSheetState extends State<_AiCounterVoicePromptSheet> with SingleTickerProviderStateMixin {
  late TextEditingController _hintCtrl;
  final VoiceRecognitionService _voiceService = VoiceRecognitionService();
  bool _isListening = false;
  late AnimationController _pulseAnim;
  String _activeLocale = 'hi_IN';

  @override
  void initState() {
    super.initState();
    _hintCtrl = TextEditingController();
    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _initVoice();
  }

  Future<void> _initVoice() async {
    await _voiceService.init();
    if (mounted) {
      setState(() {
        _activeLocale = _voiceService.currentLocaleId;
      });
    }
  }

  @override
  void dispose() {
    _hintCtrl.dispose();
    _pulseAnim.dispose();
    if (_isListening) {
      _voiceService.stopListening();
    }
    super.dispose();
  }

  void _toggleListening() async {
    if (_isListening) {
      await _voiceService.stopListening();
      if (mounted) setState(() => _isListening = false);
    } else {
      if (!_voiceService.isInitialized) {
        await _voiceService.init();
      }
      setState(() => _isListening = true);
      _voiceService.startListening(
        onResult: (words) {
          if (mounted) {
            setState(() {
              _hintCtrl.text = words;
            });
          }
        },
        localeId: _activeLocale,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final hasHint = _hintCtrl.text.trim().isNotEmpty;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 12),

          // Header Row with photo preview
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  widget.imageBytes,
                  width: 46,
                  height: 46,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      "Counter Photo Captured",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    SizedBox(height: 2),
                    Text(
                      "Option C: Visual Rules + Voice Hint (No inventory)",
                      style: TextStyle(fontSize: 11, color: Color(0xFF7C3AED), fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.black54),
                onPressed: () => Navigator.pop(context, "__CANCEL__"),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Voice Hint Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F3FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isListening ? const Color(0xFF7C3AED) : const Color(0xFFDDD6FE),
                width: _isListening ? 1.8 : 1.0,
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.mic, color: Color(0xFF7C3AED), size: 18),
                        SizedBox(width: 6),
                        Text(
                          "Voice Rate & Item Hint (Optional)",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF5B21B6)),
                        ),
                      ],
                    ),
                    // Language toggle (Hindi / English)
                    InkWell(
                      onTap: () {
                        final newLoc = _activeLocale == 'hi_IN' ? 'en_IN' : 'hi_IN';
                        setState(() => _activeLocale = newLoc);
                        _voiceService.setLocale(newLoc);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFDDD6FE)),
                        ),
                        child: Text(
                          _activeLocale == 'hi_IN' ? "🇮🇳 हिन्दी" : "🇬🇧 English",
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF7C3AED)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Mic Pulse button & status
                GestureDetector(
                  onTap: _toggleListening,
                  child: AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (ctx, child) {
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isListening
                              ? const Color(0xFF7C3AED).withOpacity(0.15 + (_pulseAnim.value * 0.15))
                              : Colors.white,
                          boxShadow: _isListening
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF7C3AED).withOpacity(0.3 * _pulseAnim.value),
                                    blurRadius: 16 * _pulseAnim.value,
                                    spreadRadius: 4 * _pulseAnim.value,
                                  )
                                ]
                              : [
                                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 2))
                                ],
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isListening ? const Color(0xFFDC2626) : const Color(0xFF7C3AED),
                          ),
                          child: Icon(
                            _isListening ? Icons.stop : Icons.mic,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),

                Text(
                  _isListening ? "Listening... Speak clearly in Hindi or English" : "Tap mic to speak (or skip to scan directly)",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: _isListening ? FontWeight.bold : FontWeight.normal,
                    color: _isListening ? const Color(0xFFDC2626) : Colors.black54,
                  ),
                ),

                if (hasHint) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.record_voice_over, size: 16, color: Color(0xFF7C3AED)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '"${_hintCtrl.text.trim()}"',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                        ),
                        InkWell(
                          onTap: () => setState(() => _hintCtrl.clear()),
                          child: const Icon(Icons.close, size: 16, color: Colors.black45),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Quick Spoken Example Chips
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _buildHintChip("Do clutcher 40"),
              _buildHintChip("Lipstick 150"),
              _buildHintChip("Safety pin 10"),
              _buildHintChip("Bangles 80"),
            ],
          ),
          const SizedBox(height: 14),

          // Primary Scan Action Button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
            ),
            icon: Icon(hasHint ? Icons.auto_awesome : Icons.bolt, color: Colors.white),
            label: Text(
              hasHint ? "Calculate Bill (Photo + Voice Hint)" : "Calculate Bill with AI (Visual Rules)",
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            onPressed: () {
              if (_isListening) _voiceService.stopListening();
              Navigator.pop(context, _hintCtrl.text.trim());
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHintChip(String text) {
    return InkWell(
      onTap: () {
        setState(() {
          if (_hintCtrl.text.isEmpty) {
            _hintCtrl.text = text;
          } else {
            _hintCtrl.text = "${_hintCtrl.text}, $text";
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Text(
          '+ "$text"',
          style: const TextStyle(fontSize: 10, color: Colors.black87, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
