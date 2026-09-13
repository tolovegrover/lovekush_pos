import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'voice_recognition_service.dart';

/// Model representing a single item detected by AI on the checkout counter
class AiDetectedItem {
  String name;
  int qty;
  double rate;
  String category;
  bool isBranded;
  String confidence;

  AiDetectedItem({
    required this.name,
    this.qty = 1,
    this.rate = 0.0,
    this.category = "General",
    this.isBranded = false,
    this.confidence = "medium",
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
    final branded = json['isBranded'] == true || (json['branded'] == true);
    final conf = (json['confidence'] ?? "medium").toString();

    return AiDetectedItem(
      name: rawName,
      qty: parsedQty,
      rate: parsedRate,
      category: cat,
      isBranded: branded,
      confidence: conf,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
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

  Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefApiKey);
  }

  Future<void> saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefApiKey, key.trim());
  }

  /// Launch camera or image picker to capture checkout counter items
  static Future<List<AiDetectedItem>?> pickAndAnalyzeCounterItems(
    BuildContext context, {
    ImageSource source = ImageSource.camera,
  }) async {
    final service = AiCounterVisionService();
    String? apiKey = await service.getApiKey();

    // If no API key configured yet, prompt setup dialog
    if (apiKey == null || apiKey.trim().isEmpty) {
      final configured = await showApiKeySetupDialog(context);
      if (!configured) return null;
      apiKey = await service.getApiKey();
      if (apiKey == null || apiKey.trim().isEmpty) return null;
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
              children: const [
                CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF7C3AED)),
                SizedBox(height: 20),
                Text(
                  "Analyzing Counter Items...",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                SizedBox(height: 8),
                Text(
                  "Detecting branded items, clutchers, safety pins, bangles & calculating bill...",
                  style: TextStyle(fontSize: 12, color: Colors.black54),
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
      detectedItems = await service.analyzeCounterImage(imageBytes, apiKey: apiKey);
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
      ),
    );
  }

  /// Analyze image bytes with Gemini Flash (Google AI Studio)
  Future<List<AiDetectedItem>> analyzeCounterImage(
    Uint8List imageBytes, {
    required String apiKey,
  }) async {
    final base64Image = base64Encode(imageBytes);

    // Optimized prompt for Indian retail cosmetic & general stores
    const prompt = """
You are an expert AI retail cashier assistant for an Indian retail general and cosmetic shop ("Love Kush").
Analyze this picture of items placed on the checkout counter and extract every single sellable item.

CRITICAL RULES:
1. IDENTIFY BOTH BRANDED AND UNBRANDED / UNNAMED ITEMS:
   - UNBRANDED / UNNAMED / GENERAL ITEMS (Very common):
     * Hair Accessories: Hair Clutcher (small/medium/large/butterfly), Hair Claw Clips, Tic-Tac Pins, Bobby Pins, Hair Rubber Bands, Scrunchie, Hair Band, Juda Pin.
     * Daily Use / General: Safety Pins (card or bunch), Tailoring Thread / Ribbon / Lace, Comb, Nail Clipper, Pocket Mirror, Keychain, Mehendi Cone.
     * Jewellery / Traditional: Bangles / Choori (specify type/size if visible, e.g. "Glass Bangles Set", "Metal Choori", "Chuda"), Bindi Packet / Card, Sindoor, Earring Pair, Payal / Anklet, Mangalsutra.
   - BRANDED / PACKAGED COSMETIC ITEMS:
     * Read brand name and product type (e.g. "Lakme Eyeconic Kajal", "Blue Heaven Nail Polish", "Ponds Powder", "Fair & Lovely Cream", "Dazller Eyeliner", "Elle 18 Lipstick", "Vaseline Lip Balm", "Garnier Face Wash").
     * Look closely for printed MRP (e.g. ₹10, ₹20, ₹50, ₹180). Use the exact printed MRP if visible.

2. QUANTITY ACCURACY:
   - Count the physical number of units for each distinct item.
   - If there are 3 clutchers of the same style, set qty: 3.
   - If there are 2 bindi cards, set qty: 2.
   - For bangles, count each set/dozen as 1 set (qty: 1) or individual bundles.

3. ESTIMATED OR DETECTED RATES (in Indian Rupees ₹):
   - If MRP is clearly visible on packaging, set that amount (e.g. 180.0).
   - If the item is UNBRANDED (like safety pins, hair clutcher, bindi, rubber band):
     * Estimate realistic Indian retail prices:
       - Safety Pin Card: 10.0
       - Small Hair Clutcher: 15.0 - 20.0
       - Medium/Large Hair Clutcher: 30.0 - 50.0
       - Bindi Card / Packet: 10.0 - 20.0
       - Hair Rubber Band / Scrunchie: 10.0 - 20.0
       - Glass Bangles Set: 40.0 - 60.0
       - Mehendi Cone: 10.0 - 15.0
     * If rate is completely unknown, use 0.0 so the cashier can enter it.

4. RESPONSE FORMAT:
   Return ONLY a valid JSON array of objects. No markdown formatting, no code blocks, no backticks, no explanatory text.
   Schema:
   [
     {
       "name": "Specific Item Name (e.g. Hair Clutcher Medium, Safety Pins, Lakme Kajal)",
       "qty": 1,
       "rate": 20.0,
       "category": "Hair Accessories" | "Cosmetics" | "Jewellery" | "General" | "Tailoring",
       "isBranded": false,
       "confidence": "high" | "medium" | "low"
     }
   ]
""";

    // Check Gemini 1.5 Flash endpoint
    final url = Uri.parse(
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey.trim()}",
    );

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

    http.Response response;
    try {
      response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: requestBody,
      ).timeout(const Duration(seconds: 25));
    } catch (e) {
      throw "Network error connecting to Gemini AI: $e. Please check your internet connection.";
    }

    if (response.statusCode != 200) {
      String errMessage = "Gemini API error (Status ${response.statusCode})";
      try {
        final errJson = jsonDecode(response.body);
        if (errJson['error'] != null && errJson['error']['message'] != null) {
          errMessage = errJson['error']['message'];
        }
      } catch (_) {}

      if (response.statusCode == 400 && errMessage.toLowerCase().contains("api_key")) {
        throw "Invalid Gemini API Key. Please check the key in Settings.";
      } else if (response.statusCode == 429) {
        throw "Rate limit reached. Please wait a moment and try again.";
      }
      throw errMessage;
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

    return itemsList.map((item) => AiDetectedItem.fromJson(item as Map<String, dynamic>)).toList();
  }

  /// Show Dialog to configure the Free Gemini API Key
  static Future<bool> showApiKeySetupDialog(BuildContext context) async {
    final service = AiCounterVisionService();
    final currentKey = await service.getApiKey() ?? "";
    final keyCtrl = TextEditingController(text: currentKey);
    bool obscure = true;

    final result = await showDialog<bool>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (ctx, setDState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: const [
                Icon(Icons.auto_awesome, color: Color(0xFF7C3AED)),
                SizedBox(width: 8),
                Text("Gemini AI Setup (100% Free)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F3FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFDDD6FE)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          "✨ 1,500 bills/day completely FREE ($0 / ₹0)",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF6D28D9)),
                        ),
                        SizedBox(height: 4),
                        Text(
                          "Google AI Studio provides 1,500 free requests per day without requiring a credit card or subscription.",
                          style: TextStyle(fontSize: 11, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text("Enter your Google AI Studio API Key:", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: keyCtrl,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      hintText: "AIzaSy...",
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setDState(() => obscure = !obscure),
                      ),
                    ),
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
                  final key = keyCtrl.text.trim();
                  if (key.isNotEmpty) {
                    await service.saveApiKey(key);
                    Navigator.pop(dCtx, true);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Please enter a valid API Key")),
                    );
                  }
                },
                child: const Text("Save Key", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

  const _AiCounterBillReviewSheet({
    Key? key,
    required this.imageBytes,
    required this.initialItems,
  }) : super(key: key);

  @override
  State<_AiCounterBillReviewSheet> createState() => _AiCounterBillReviewSheetState();
}

class _AiCounterBillReviewSheetState extends State<_AiCounterBillReviewSheet> {
  late List<AiDetectedItem> _items;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.initialItems);
  }

  double get _grandTotal => _items.fold(0.0, (sum, it) => sum + it.totalPrice);
  int get _totalItemUnits => _items.fold(0, (sum, it) => sum + it.qty);

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 12),

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
                  child: const Icon(Icons.auto_awesome, color: Color(0xFF7C3AED), size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "AI Counter Bill Review",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                      Text(
                        "${_items.length} items detected • Tap rate/qty to adjust",
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
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
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                        ),
                        Container(
                          padding: const EdgeInsets.all(2),
                          color: Colors.black54,
                          child: const Icon(Icons.zoom_in, color: Colors.white, size: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 24),

          // Items List
          Expanded(
            child: _items.isEmpty
                ? const Center(
                    child: Text("No items in list. Tap '+ Add Item' below."),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 12),
                    itemBuilder: (ctx, index) {
                      final item = _items[index];
                      return _buildItemRow(item, index);
                    },
                  ),
          ),

          // Action Toolbar: Add Item & Retake
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text("Add Item", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _addNewManualItem,
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.camera_alt, size: 16),
                  label: const Text("Retake", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => Navigator.pop(context, null),
                ),
                const Spacer(),
                Text(
                  "Total: ₹${_grandTotal % 1 == 0 ? _grandTotal.toInt() : _grandTotal.toStringAsFixed(2)}",
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                ),
              ],
            ),
          ),

          // Bottom Add All to Cart Button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.shopping_cart_checkout, color: Colors.white),
                label: Text(
                  "Add All to Cart ($_totalItemUnits Units • ₹${_grandTotal % 1 == 0 ? _grandTotal.toInt() : _grandTotal.toStringAsFixed(2)})",
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                onPressed: _items.isEmpty
                    ? null
                    : () {
                        Navigator.pop(context, _items);
                      },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(AiDetectedItem item, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Category Icon
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _getCategoryColor(item.category).withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(_getCategoryIcon(item.category), size: 16, color: _getCategoryColor(item.category)),
          ),
          const SizedBox(width: 8),

          // Name and Edit / Mic
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Quick Voice / Rename button
                    InkWell(
                      onTap: () => _editItemName(index),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(Icons.edit, size: 13, color: Colors.black45),
                      ),
                    ),
                  ],
                ),
                Text(
                  item.category,
                  style: TextStyle(fontSize: 10, color: _getCategoryColor(item.category), fontWeight: FontWeight.w600),
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
                      setState(() => _items.removeAt(index));
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Icon(Icons.remove, size: 14, color: Colors.black87),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    "${item.qty}",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => item.qty++),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Icon(Icons.add, size: 14, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Rate Input
          InkWell(
            onTap: () => _editItemRate(index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: item.rate <= 0 ? const Color(0xFFFEF2F2) : Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: item.rate <= 0 ? Colors.redAccent : Colors.grey.shade300),
              ),
              child: Text(
                item.rate <= 0 ? "₹ Set Rate" : "₹${item.rate % 1 == 0 ? item.rate.toInt() : item.rate.toStringAsFixed(2)}",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: item.rate <= 0 ? Colors.red : const Color(0xFF1E293B),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Line Total
          SizedBox(
            width: 52,
            child: Text(
              "₹${item.totalPrice % 1 == 0 ? item.totalPrice.toInt() : item.totalPrice.toStringAsFixed(2)}",
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF059669)),
            ),
          ),
          const SizedBox(width: 4),

          // Delete Button
          InkWell(
            onTap: () => setState(() => _items.removeAt(index)),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 16, color: Colors.grey),
            ),
          ),
        ],
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

  void _editItemRate(int index) async {
    final item = _items[index];
    final ctrl = TextEditingController(text: item.rate > 0 ? (item.rate % 1 == 0 ? item.rate.toInt().toString() : item.rate.toString()) : "");

    final newRateStr = await showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text("Set Rate for ${item.name}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: "Price / Rate (₹)",
            prefixText: "₹ ",
            border: OutlineInputBorder(),
          ),
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

    if (newRateStr != null) {
      final p = double.tryParse(newRateStr) ?? 0.0;
      setState(() => item.rate = p);
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
