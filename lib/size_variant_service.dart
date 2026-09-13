import 'dart:convert';
import 'package:flutter/material.dart';
import 'cosmetics_catalog.dart';

/// Represents a single Size Variant of a retail item with its corresponding rate.
class SizeVariant {
  final String sizeLabel; // e.g. "50ml", "100ml", "Small", "2.6", "XL"
  final double rate;      // e.g. 120.0
  final String? barcode;  // Barcode for this specific variant
  final String? fullName; // Full product name e.g. "Glow & Lovely Advanced Multivitamin Cream 50g"
  final String? stockQty; // Optional stock quantity

  const SizeVariant({
    required this.sizeLabel,
    required this.rate,
    this.barcode,
    this.fullName,
    this.stockQty,
  });

  Map<String, dynamic> toJson() => {
    'size': sizeLabel,
    'rate': rate,
    if (barcode != null) 'barcode': barcode,
    if (fullName != null) 'fullName': fullName,
  };

  factory SizeVariant.fromJson(Map<String, dynamic> json) {
    final s = (json['size'] ?? json['sizeLabel'] ?? json['name'] ?? '').toString().trim();
    final r = json['rate'] ?? json['price'] ?? 0.0;
    final double parsedRate = r is num ? r.toDouble() : (double.tryParse(r.toString()) ?? 0.0);
    return SizeVariant(
      sizeLabel: s,
      rate: parsedRate,
      barcode: json['barcode']?.toString(),
      fullName: json['fullName']?.toString(),
    );
  }
}

/// Comprehensive service for extracting, discovering, configuring,
/// and switching product sizes with corresponding rates.
class SizeVariantService {
  // Regex patterns to detect size & volume in product names
  static final RegExp _volumeWeightRegex = RegExp(
    r'\b(\d+(?:\.\d+)?\s*(?:ml|g|gm|kg|ltr|l|oz|fl\s*oz|pcs|piece|cards?|pins?|bangles?|sachet))\b',
    caseSensitive: false,
  );

  static final RegExp _bangleSizeRegex = RegExp(
    r'\b(2[.\-][2468]|2\.10|2\s*No\.?|size\s*2[.\-][2468])\b',
    caseSensitive: false,
  );

  static final RegExp _apparelSizeRegex = RegExp(
    r'\b(Extra\s*Large|Small|Medium|Large|XXXL|XXL|XL|XS|\bS\b|\bM\b|\bL\b)\b',
    caseSensitive: false,
  );

  /// Extract size label from an item name (e.g. "Vaseline Lotion 200ml" -> "200ml")
  static String? extractSizeLabel(String itemName) {
    if (itemName.isEmpty) return null;

    // Check volume/weight (e.g. 50g, 100ml, 500ml)
    final vwMatch = _volumeWeightRegex.firstMatch(itemName);
    if (vwMatch != null) return vwMatch.group(1)?.trim();

    // Check bangle sizes (e.g. 2.4, 2.6, 2.8)
    final bgMatch = _bangleSizeRegex.firstMatch(itemName);
    if (bgMatch != null) return bgMatch.group(1)?.trim();

    // Check apparel / generic sizes (Small, Medium, Large, XL, etc.)
    final apMatch = _apparelSizeRegex.firstMatch(itemName);
    if (apMatch != null) return apMatch.group(1)?.trim();

    return null;
  }

  /// Strip size tokens from item name to get the pure base product name
  /// e.g. "Vaseline Healthy Bright Lotion 200ml" -> "Vaseline Healthy Bright Lotion"
  static String extractBaseProductName(String itemName) {
    if (itemName.isEmpty) return "";
    String base = itemName;

    base = base.replaceAll(_volumeWeightRegex, '');
    base = base.replaceAll(_bangleSizeRegex, '');
    base = base.replaceAll(_apparelSizeRegex, '');
    // Clean up empty parentheses e.g. "()" or "(, )" left behind
    base = base.replaceAll(RegExp(r'\(\s*[,;\-]?\s*\)'), '');
    base = base.replaceAll(RegExp(r'\s{2,}'), ' ').trim();

    return base.isNotEmpty ? base : itemName.trim();
  }

  /// Format an item name by replacing or attaching a new size
  /// e.g. formatItemWithSize("Vaseline Lotion 100ml", "200ml") -> "Vaseline Lotion 200ml"
  static String formatItemWithSize(String currentName, String newSize) {
    if (newSize.trim().isEmpty) return currentName;

    final existingSize = extractSizeLabel(currentName);
    if (existingSize != null && existingSize.isNotEmpty) {
      return currentName.replaceFirst(existingSize, newSize.trim()).replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    } else {
      return "${currentName.trim()} ${newSize.trim()}";
    }
  }

  /// Find all size variants for a product by checking:
  /// 1. Explicit `size_variants` stored in description JSON
  /// 2. Related items in `cosmeticDatabase` sharing the same base name
  /// 3. Related items in in-memory `cloudInventory`
  /// 4. Category-based smart size presets
  static List<SizeVariant> findVariantsForProduct({
    required String itemName,
    double currentRate = 0.0,
    String category = "General",
    Map<String, dynamic>? itemData,
    Map<String, Map<String, dynamic>>? inMemoryInventory,
  }) {
    final Map<String, SizeVariant> variantsMap = {};

    // 1. Check explicit size_variants in item metadata (description JSON or dual_rates)
    if (itemData != null) {
      final desc = itemData['description']?.toString() ?? '';
      if (desc.startsWith('{') && desc.contains('size_variants')) {
        try {
          final decoded = json.decode(desc);
          if (decoded is Map && decoded['size_variants'] is List) {
            for (var v in decoded['size_variants']) {
              if (v is Map) {
                final sv = SizeVariant.fromJson(Map<String, dynamic>.from(v));
                if (sv.sizeLabel.isNotEmpty && sv.rate > 0) {
                  variantsMap[sv.sizeLabel.toLowerCase()] = sv;
                }
              }
            }
          }
        } catch (_) {}
      }
    }

    // 2. Discover related items in master cosmetic catalog
    final baseName = extractBaseProductName(itemName).toLowerCase().trim();
    if (baseName.length >= 3) {
      for (final c in cosmeticDatabase) {
        final cName = (c['name'] ?? '').toString();
        final cBase = extractBaseProductName(cName).toLowerCase().trim();
        final cPrice = (c['price'] as num?)?.toDouble() ?? 0.0;
        final cBarcode = c['barcode']?.toString();

        // Check if catalog item is a variant of our product
        if (cBase == baseName || (baseName.length > 5 && (cBase.contains(baseName) || baseName.contains(cBase)))) {
          final size = extractSizeLabel(cName);
          if (size != null && size.isNotEmpty && cPrice > 0) {
            final key = size.toLowerCase();
            if (!variantsMap.containsKey(key)) {
              variantsMap[key] = SizeVariant(
                sizeLabel: size,
                rate: cPrice,
                barcode: cBarcode,
                fullName: cName,
              );
            }
          }
        }
      }
    }

    // 3. Discover related items in store inventory
    if (inMemoryInventory != null && baseName.length >= 3) {
      for (final entry in inMemoryInventory.entries) {
        final it = entry.value;
        final itName = (it['item_name'] ?? '').toString();
        final itBase = extractBaseProductName(itName).toLowerCase().trim();
        final itPrice = (it['price'] as num?)?.toDouble() ?? 0.0;
        final itStock = (it['stock_qty'] as num?)?.toInt();

        if (itBase == baseName || (baseName.length > 5 && (itBase.contains(baseName) || baseName.contains(itBase)))) {
          final size = extractSizeLabel(itName);
          if (size != null && size.isNotEmpty && itPrice > 0) {
            final key = size.toLowerCase();
            if (!variantsMap.containsKey(key)) {
              variantsMap[key] = SizeVariant(
                sizeLabel: size,
                rate: itPrice,
                barcode: it['item_code']?.toString() ?? it['company_barcode']?.toString(),
                fullName: itName,
                stockQty: itStock != null ? "$itStock in stock" : null,
              );
            }
          }
        }
      }
    }

    // 4. Ensure current item's size is included if extracted
    final curSize = extractSizeLabel(itemName);
    if (curSize != null && curSize.isNotEmpty && currentRate > 0) {
      final key = curSize.toLowerCase();
      if (!variantsMap.containsKey(key)) {
        variantsMap[key] = SizeVariant(
          sizeLabel: curSize,
          rate: currentRate,
          fullName: itemName,
        );
      }
    }

    // 5. If no catalog variants found, provide smart retail presets based on category
    if (variantsMap.isEmpty || variantsMap.length == 1) {
      final presets = getCategorySmartPresets(
        category: category,
        itemName: itemName,
        currentRate: currentRate,
      );
      for (final p in presets) {
        final key = p.sizeLabel.toLowerCase();
        if (!variantsMap.containsKey(key)) {
          variantsMap[key] = p;
        }
      }
    }

    final list = variantsMap.values.toList();
    // Sort logically by rate ascending
    list.sort((a, b) => a.rate.compareTo(b.rate));
    return list;
  }

  /// Generate intelligent retail size presets when product is not in catalog
  static List<SizeVariant> getCategorySmartPresets({
    required String category,
    required String itemName,
    required double currentRate,
  }) {
    final lowerName = itemName.toLowerCase();
    final lowerCat = category.toLowerCase();
    final double baseRate = currentRate > 0 ? currentRate : 50.0;

    // A. Bangles / Churi / Kangan
    if (lowerName.contains("bangle") || lowerName.contains("churi") || lowerName.contains("kangan") || lowerName.contains("kada")) {
      return [
        SizeVariant(sizeLabel: "Size 2.2", rate: baseRate),
        SizeVariant(sizeLabel: "Size 2.4", rate: baseRate),
        SizeVariant(sizeLabel: "Size 2.6", rate: baseRate),
        SizeVariant(sizeLabel: "Size 2.8", rate: (baseRate * 1.1).roundToDouble()),
        SizeVariant(sizeLabel: "Size 2.10", rate: (baseRate * 1.2).roundToDouble()),
      ];
    }

    // B. Hair accessories (Clutchers, Pins, Clips, Scrunchies, Rubber bands)
    if (lowerCat.contains("hair") || lowerName.contains("clutcher") || lowerName.contains("pin") || lowerName.contains("clip") || lowerName.contains("band")) {
      final double s = (baseRate * 0.6).roundToDouble().clamp(10, 9999);
      final double m = baseRate;
      final double l = (baseRate * 1.5).roundToDouble();
      final double j = (baseRate * 2.2).roundToDouble();
      return [
        SizeVariant(sizeLabel: "Small (Chhota)", rate: s),
        SizeVariant(sizeLabel: "Medium", rate: m),
        SizeVariant(sizeLabel: "Large (Bada)", rate: l),
        SizeVariant(sizeLabel: "Jumbo", rate: j),
      ];
    }

    // C. Cosmetics / Liquids (Lotions, Creams, Shampoos, Oils, Face Wash)
    if (lowerCat.contains("cosmetic") || lowerCat.contains("skincare") || lowerName.contains("lotion") || lowerName.contains("cream") || lowerName.contains("oil") || lowerName.contains("shampoo") || lowerName.contains("wash")) {
      final double smallRate = (baseRate * 0.55).roundToDouble().clamp(20, 9999);
      final double medRate = baseRate;
      final double lrgRate = (baseRate * 1.8).roundToDouble();
      final double fmlRate = (baseRate * 3.2).roundToDouble();
      return [
        SizeVariant(sizeLabel: "Small (50g / 50ml)", rate: smallRate),
        SizeVariant(sizeLabel: "Medium (100g / 100ml)", rate: medRate),
        SizeVariant(sizeLabel: "Large (200g / 200ml)", rate: lrgRate),
        SizeVariant(sizeLabel: "Family (400g / 400ml)", rate: fmlRate),
      ];
    }

    // D. Apparel / Hosiery / Undergarments
    if (lowerName.contains("bra") || lowerName.contains("panty") || lowerName.contains("towel") || lowerName.contains("socks") || lowerName.contains("suit") || lowerName.contains("legging") || lowerName.contains("tshirt")) {
      return [
        SizeVariant(sizeLabel: "S (Small)", rate: baseRate),
        SizeVariant(sizeLabel: "M (Medium)", rate: baseRate),
        SizeVariant(sizeLabel: "L (Large)", rate: baseRate),
        SizeVariant(sizeLabel: "XL", rate: (baseRate * 1.1).roundToDouble()),
        SizeVariant(sizeLabel: "XXL", rate: (baseRate * 1.2).roundToDouble()),
      ];
    }

    // E. General default sizes
    final double sRate = (baseRate * 0.7).roundToDouble().clamp(10, 9999);
    final double lRate = (baseRate * 1.4).roundToDouble();
    return [
      SizeVariant(sizeLabel: "Small", rate: sRate),
      SizeVariant(sizeLabel: "Medium", rate: baseRate),
      SizeVariant(sizeLabel: "Large", rate: lRate),
    ];
  }

  /// Show interactive Modal Sheet to choose a size with corresponding rate
  static Future<SizeVariant?> showSizeSelectorModal(
    BuildContext context, {
    required String itemName,
    required double currentRate,
    String category = "General",
    Map<String, dynamic>? itemData,
    Map<String, Map<String, dynamic>>? inMemoryInventory,
  }) async {
    final variants = findVariantsForProduct(
      itemName: itemName,
      currentRate: currentRate,
      category: category,
      itemData: itemData,
      inMemoryInventory: inMemoryInventory,
    );

    final currentSizeLabel = extractSizeLabel(itemName);

    return showModalBottomSheet<SizeVariant>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SizeSelectorSheet(
        itemName: itemName,
        currentRate: currentRate,
        currentSizeLabel: currentSizeLabel,
        initialVariants: variants,
      ),
    );
  }
}

class _SizeSelectorSheet extends StatefulWidget {
  final String itemName;
  final double currentRate;
  final String? currentSizeLabel;
  final List<SizeVariant> initialVariants;

  const _SizeSelectorSheet({
    required this.itemName,
    required this.currentRate,
    this.currentSizeLabel,
    required this.initialVariants,
  });

  @override
  State<_SizeSelectorSheet> createState() => _SizeSelectorSheetState();
}

class _SizeSelectorSheetState extends State<_SizeSelectorSheet> {
  late List<SizeVariant> _variants;
  bool _showCustomInput = false;
  final TextEditingController _customSizeCtrl = TextEditingController();
  final TextEditingController _customRateCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _variants = List.from(widget.initialVariants);
    if (widget.currentRate > 0) {
      _customRateCtrl.text = widget.currentRate % 1 == 0
          ? widget.currentRate.toInt().toString()
          : widget.currentRate.toString();
    }
  }

  @override
  void dispose() {
    _customSizeCtrl.dispose();
    _customRateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseName = SizeVariantService.extractBaseProductName(widget.itemName);

    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Sheet Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: const BoxDecoration(
                  color: Color(0xFF1F2937),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.straighten, color: Colors.amberAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            baseName.isNotEmpty ? baseName : widget.itemName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            "Select size to automatically apply corresponding rate",
                            style: TextStyle(fontSize: 11, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Available Size Variants List
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: const Text(
                  "AVAILABLE SIZES & RATES",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54, letterSpacing: 1.0),
                ),
              ),
              const SizedBox(height: 8),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _variants.map((v) {
                    final bool isSelected = (widget.currentSizeLabel != null &&
                            widget.currentSizeLabel!.toLowerCase() == v.sizeLabel.toLowerCase()) ||
                        (widget.currentRate > 0 && (widget.currentRate - v.rate).abs() < 0.01);

                    return Material(
                      color: isSelected ? const Color(0xFFECFDF5) : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(context, v);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? const Color(0xFF059669) : Colors.grey.shade300,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        v.sizeLabel,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: isSelected ? const Color(0xFF065F46) : Colors.black87,
                                        ),
                                      ),
                                      if (isSelected) ...[
                                        const SizedBox(width: 4),
                                        const Icon(Icons.check_circle, size: 14, color: Color(0xFF059669)),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "₹${v.rate % 1 == 0 ? v.rate.toInt() : v.rate.toStringAsFixed(2)}",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                      color: isSelected ? const Color(0xFF059669) : const Color(0xFF1D4ED8),
                                    ),
                                  ),
                                  if (v.stockQty != null) ...[
                                    const SizedBox(height: 1),
                                    Text(
                                      v.stockQty!,
                                      style: const TextStyle(fontSize: 9, color: Colors.black45),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 14),

              // Add Custom Size & Rate Section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _showCustomInput
                    ? Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Add Custom Size & Rate:",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: TextField(
                                    controller: _customSizeCtrl,
                                    autofocus: true,
                                    decoration: const InputDecoration(
                                      labelText: "Size (e.g. 250ml, XL, 2.7)",
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: _customRateCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: const InputDecoration(
                                      labelText: "Rate (₹)",
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => setState(() => _showCustomInput = false),
                                  child: const Text("Cancel"),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2563EB),
                                  ),
                                  onPressed: () {
                                    final size = _customSizeCtrl.text.trim();
                                    final rate = double.tryParse(_customRateCtrl.text.trim()) ?? 0.0;
                                    if (size.isNotEmpty && rate > 0) {
                                      final newVariant = SizeVariant(sizeLabel: size, rate: rate);
                                      Navigator.pop(context, newVariant);
                                    }
                                  },
                                  child: const Text("Apply Size & Rate", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    : OutlinedButton.icon(
                        icon: const Icon(Icons.add, size: 16, color: Color(0xFF2563EB)),
                        label: const Text("Add Custom Size & Rate", style: TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF93C5FD)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: () => setState(() => _showCustomInput = true),
                      ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
