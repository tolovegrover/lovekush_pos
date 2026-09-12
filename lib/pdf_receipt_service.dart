import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, Clipboard, ClipboardData;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

// ==========================================
// LOVE KUSH POS - PDF RECEIPT & WHATSAPP SERVICE
// ==========================================

/// Language options for receipts and invoices
enum ReceiptLanguage {
  hindi,
  english,
}

class PdfReceiptService {
  static pw.Font? _cachedSiddhantaCalcutta;
  static pw.Font? _cachedHindiRegular;
  static pw.Font? _cachedHindiBold;

  /// Load and cache Siddhanta Calcutta (and Noto Serif fallback) TrueType fonts offline from bundled assets
  static Future<pw.ThemeData> _loadTheme() async {
    if (_cachedSiddhantaCalcutta != null) {
      final fallbacks = <pw.Font>[_cachedSiddhantaCalcutta!];
      if (_cachedHindiRegular != null) fallbacks.add(_cachedHindiRegular!);
      if (_cachedHindiBold != null) fallbacks.add(_cachedHindiBold!);
      return pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
        fontFallback: fallbacks,
      );
    }

    // 1. Primary authentic Calcutta style font: Siddhanta Calcutta
    if (_cachedSiddhantaCalcutta == null) {
      try {
        final data = await rootBundle.load("assets/fonts/siddhanta-calcutta.ttf");
        _cachedSiddhantaCalcutta = pw.Font.ttf(data);
      } catch (_) {
        try {
          final file = File("assets/fonts/siddhanta-calcutta.ttf");
          if (file.existsSync()) {
            final bytes = await file.readAsBytes();
            _cachedSiddhantaCalcutta = pw.Font.ttf(bytes.buffer.asByteData());
          }
        } catch (_) {}
      }
    }

    // 2. Secondary Book Serif fallbacks: Noto Serif Devanagari
    if (_cachedHindiRegular == null) {
      try {
        final data = await rootBundle.load("assets/fonts/NotoSerifDevanagari-Regular.ttf");
        _cachedHindiRegular = pw.Font.ttf(data);
      } catch (_) {
        try {
          final file = File("assets/fonts/NotoSerifDevanagari-Regular.ttf");
          if (file.existsSync()) {
            final bytes = await file.readAsBytes();
            _cachedHindiRegular = pw.Font.ttf(bytes.buffer.asByteData());
          }
        } catch (_) {}
      }
    }

    if (_cachedHindiBold == null) {
      try {
        final data = await rootBundle.load("assets/fonts/NotoSerifDevanagari-Bold.ttf");
        _cachedHindiBold = pw.Font.ttf(data);
      } catch (_) {
        try {
          final file = File("assets/fonts/NotoSerifDevanagari-Bold.ttf");
          if (file.existsSync()) {
            final bytes = await file.readAsBytes();
            _cachedHindiBold = pw.Font.ttf(bytes.buffer.asByteData());
          }
        } catch (_) {}
      }
    }

    final fallbacks = <pw.Font>[];
    if (_cachedSiddhantaCalcutta != null) fallbacks.add(_cachedSiddhantaCalcutta!);
    if (_cachedHindiRegular != null) fallbacks.add(_cachedHindiRegular!);
    if (_cachedHindiBold != null) fallbacks.add(_cachedHindiBold!);

    if (fallbacks.isNotEmpty) {
      return pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
        fontFallback: fallbacks,
      );
    }
    return pw.ThemeData.base();
  }

  /// Format Devanagari text for dart_pdf rendering by reordering Chhoti-Ee (U+093F)
  /// before preceding consonant clusters so it displays in the visually correct order.
  static String _fixDevanagari(String text) {
    if (text.isEmpty) return text;
    final exp = RegExp(r'((?:[\u0915-\u0939\u0958-\u095F][\u094D])*[\u0915-\u0939\u0958-\u095F])[\u093F]');
    return text.replaceAllMapped(exp, (m) => '\u093F${m.group(1)}');
  }

  /// Format payment method in Hindi
  static String _paymentModeHindi(String method) {
    final m = method.toLowerCase();
    if (m.contains("cash")) return "नकद (CASH)";
    if (m.contains("online") || m.contains("upi") || m.contains("gpay") || m.contains("paytm")) return "ऑनलाइन / UPI";
    if (m.contains("card")) return "कार्ड (CARD)";
    return method;
  }
  /// Robust double parser for String, num, double, int, or null
  static double _toDouble(dynamic val, [double defaultVal = 0.0]) {
    if (val == null) return defaultVal;
    if (val is num) return val.toDouble();
    if (val is String) {
      if (val.trim().isEmpty) return defaultVal;
      final cleaned = val.replaceAll(RegExp(r'[^0-9.-]'), '').trim();
      return double.tryParse(cleaned) ?? defaultVal;
    }
    return defaultVal;
  }

  /// Robust int parser for String, num, int, or null
  static int _toInt(dynamic val, [int defaultVal = 1]) {
    if (val == null) return defaultVal;
    if (val is num) return val.toInt();
    if (val is String) {
      if (val.trim().isEmpty) return defaultVal;
      final cleaned = val.replaceAll(RegExp(r'[^0-9.-]'), '').trim();
      final d = double.tryParse(cleaned);
      if (d != null) return d.toInt();
    }
    return defaultVal;
  }

  /// Robust items extractor supporting List or JSON-encoded String
  static List<dynamic> _extractItems(dynamic raw) {
    if (raw is List) return raw;
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = json.decode(raw);
        if (decoded is List) return decoded;
      } catch (_) {}
    }
    return [];
  }

  /// Generate a clean, minimal, thermal-style PDF receipt document for a bill
  static Future<Uint8List> generateReceiptPdf(
    Map<String, dynamic> bill, {
    Uint8List? logoBytes,
    PdfPageFormat? pageFormat,
    ReceiptLanguage language = ReceiptLanguage.hindi,
  }) async {
    final theme = await _loadTheme();
    final doc = pw.Document(theme: theme);

    // 1. Extract and sanitize bill metadata
    final String billNo = (bill['bill_number'] ?? "N/A").toString();
    final String counterName = (bill['counter_name'] ?? "Basement Counter").toString();
    final String staffName = (bill['staff_name'] ?? "Staff").toString();
    final double totalAmount = _toDouble(bill['total_amount']);
    final String paymentMethod = (bill['payment_method'] ?? "Cash").toString();
    final double amountTendered = _toDouble(bill['amount_tendered'], totalAmount);
    final double changeDue = _toDouble(bill['change_due'], amountTendered > totalAmount ? (amountTendered - totalAmount) : 0.0);

    DateTime billDate = DateTime.now();
    if (bill['created_at'] != null) {
      try {
        billDate = DateTime.parse(bill['created_at']).toLocal();
      } catch (_) {}
    }
    final String formattedDate =
        "${billDate.day.toString().padLeft(2, '0')}-${billDate.month.toString().padLeft(2, '0')}-${billDate.year} ${billDate.hour.toString().padLeft(2, '0')}:${billDate.minute.toString().padLeft(2, '0')}";

    // 2. Load store logo image if not provided
    Uint8List? effectiveLogo = logoBytes;
    if (effectiveLogo == null) {
      try {
        final byteData = await rootBundle.load("assets/logo_bw.jpg");
        effectiveLogo = byteData.buffer.asUint8List();
      } catch (_) {
        try {
          final file = File("assets/logo_bw.jpg");
          if (file.existsSync()) {
            effectiveLogo = await file.readAsBytes();
          }
        } catch (_) {}
      }
    }

    final pw.ImageProvider? logoImage = effectiveLogo != null ? pw.MemoryImage(effectiveLogo) : null;

    // 3. Extract items safely
    final rawItems = _extractItems(bill['items_json']);
    final List<_ReceiptItem> receiptItems = [];
    int totalQty = 0;

    for (int i = 0; i < rawItems.length; i++) {
      final item = rawItems[i] is Map ? rawItems[i] as Map : {};
      String itemName = (item['itemName'] ?? item['item'] ?? 'General Item').toString().split('\n').first.trim();
      final qty = _toInt(item['qty'], 1);
      final rate = _toDouble(item['rate'], 0.0);
      final lineTotal = _toDouble(item['total'] ?? item['price'], qty * rate);
      totalQty += qty;

      receiptItems.add(_ReceiptItem(
        name: itemName,
        qty: qty,
        rate: rate,
        lineTotal: lineTotal,
      ));
    }

    // 4. Build Minimal Thermal-Style Receipt Content
    List<pw.Widget> buildReceiptWidgets(pw.Context context) {
      return [
        // Store Logo (Centered & Crisp)
        if (logoImage != null) ...[
          pw.Center(
            child: pw.Container(
              width: 48,
              height: 48,
              margin: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Image(logoImage, fit: pw.BoxFit.contain),
            ),
          ),
        ],

        // Store Titles & Header
        if (language == ReceiptLanguage.hindi) ...[
          pw.Center(
            child: pw.Text(
              _fixDevanagari("लव कुश शॉपिङ्ग सेण्टर"),
              style: pw.TextStyle(
                fontSize: 13.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
          ),
          pw.SizedBox(height: 1),
          pw.Center(
            child: pw.Text(
              _fixDevanagari(counterName.toLowerCase().contains("basement") ? "बेसमेंट काउंटर" : counterName),
              style: const pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey800,
              ),
            ),
          ),
          pw.Center(
            child: pw.Text(
              _fixDevanagari("*** खुदरा रोकड़ पर्ची ***"),
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700,
              ),
            ),
          ),
        ] else ...[
          pw.Center(
            child: pw.Text(
              "LOVE KUSH",
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
          ),
          pw.Center(
            child: pw.Text(
              "SHOPPING CENTER",
              style: pw.TextStyle(
                fontSize: 10.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
          ),
          pw.SizedBox(height: 1),
          pw.Center(
            child: pw.Text(
              counterName.toUpperCase(),
              style: const pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey800,
              ),
            ),
          ),
          pw.Center(
            child: pw.Text(
              "*** RETAIL CASH MEMO ***",
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700,
              ),
            ),
          ),
        ],

        // Bill No & Code 128 Barcode
        if (billNo != "N/A" && billNo.isNotEmpty) ...[
          pw.SizedBox(height: 3),
          pw.Center(
            child: pw.Text(
              language == ReceiptLanguage.hindi
                  ? _fixDevanagari("बिल सं. (BILL NO): $billNo")
                  : "BILL NO: $billNo",
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.code128(),
              data: billNo,
              width: 140,
              height: 26,
              drawText: false,
            ),
          ),
        ],

        // Date, Cashier, Payment Mode
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              language == ReceiptLanguage.hindi
                  ? _fixDevanagari("दिनांक: $formattedDate")
                  : "Date: $formattedDate",
              style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.black),
            ),
            pw.Text(
              language == ReceiptLanguage.hindi
                  ? _fixDevanagari("कैशियर: $staffName")
                  : "Cashier: $staffName",
              style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.black),
            ),
          ],
        ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              language == ReceiptLanguage.hindi
                  ? _fixDevanagari("भुगतान: ${_paymentModeHindi(paymentMethod)}")
                  : "Payment: ${paymentMethod.toUpperCase()}",
              style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
            ),
          ],
        ),

        // Dashed Tear Line
        pw.SizedBox(height: 2),
        pw.Divider(thickness: 0.8, color: PdfColors.black, borderStyle: pw.BorderStyle.dashed),

        // Column Headers
        pw.Row(
          children: [
            pw.Expanded(
              flex: 5,
              child: pw.Text(
                language == ReceiptLanguage.hindi
                    ? _fixDevanagari("सामान (ITEM)")
                    : "ITEM",
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
              ),
            ),
            pw.Expanded(
              flex: 4,
              child: pw.Text(
                language == ReceiptLanguage.hindi
                    ? _fixDevanagari("मात्रा x दर")
                    : "QTY x RATE",
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
              ),
            ),
            pw.Expanded(
              flex: 3,
              child: pw.Text(
                language == ReceiptLanguage.hindi
                    ? _fixDevanagari("रकम (AMOUNT)")
                    : "AMOUNT",
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
              ),
            ),
          ],
        ),
        pw.Divider(thickness: 0.5, color: PdfColors.grey600, borderStyle: pw.BorderStyle.dashed),

        // Minimal Item Rows (Item names in English as requested)
        for (final item in receiptItems) ...[
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  _fixDevanagari(item.name),
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                ),
                pw.SizedBox(height: 1),
                pw.Row(
                  children: [
                    pw.SizedBox(width: 4),
                    pw.Expanded(
                      child: pw.Text(
                        language == ReceiptLanguage.hindi
                            ? "${item.qty} x Rs ${item.rate.toStringAsFixed(2)}"
                            : "${item.qty} x Rs ${item.rate.toStringAsFixed(2)}",
                        style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800),
                      ),
                    ),
                    pw.Text(
                      language == ReceiptLanguage.hindi
                          ? "Rs ${item.lineTotal.toStringAsFixed(2)}"
                          : "Rs ${item.lineTotal.toStringAsFixed(2)}",
                      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],

        // Dashed Divider
        pw.Divider(thickness: 0.8, color: PdfColors.black, borderStyle: pw.BorderStyle.dashed),

        // Totals & Paid Details
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              language == ReceiptLanguage.hindi
                  ? _fixDevanagari("कुल सामान: ${receiptItems.length} (संख्या: $totalQty)")
                  : "Total Items: ${receiptItems.length} (Qty: $totalQty)",
              style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800),
            ),
          ],
        ),
        pw.SizedBox(height: 2),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              language == ReceiptLanguage.hindi
                  ? _fixDevanagari("कुल योग (TOTAL):")
                  : "TOTAL AMOUNT:",
              style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
            ),
            pw.Text(
              "Rs ${totalAmount.toStringAsFixed(2)}",
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
            ),
          ],
        ),
        if (paymentMethod.toLowerCase().contains("cash") || amountTendered > totalAmount) ...[
          pw.SizedBox(height: 2),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                language == ReceiptLanguage.hindi
                    ? _fixDevanagari("प्राप्त राशि:")
                    : "Paid Money:",
                style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800),
              ),
              pw.Text(
                "Rs ${amountTendered.toStringAsFixed(2)}",
                style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.black),
              ),
            ],
          ),
          if (changeDue > 0) ...[
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  language == ReceiptLanguage.hindi
                      ? _fixDevanagari("वापसी राशि:")
                      : "Change Return:",
                  style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800),
                ),
                pw.Text(
                  "Rs ${changeDue.toStringAsFixed(2)}",
                  style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                ),
              ],
            ),
          ],
        ],

        // Dashed Divider
        pw.Divider(thickness: 0.8, color: PdfColors.black, borderStyle: pw.BorderStyle.dashed),

        // Terms & Conditions (Strict shop return/exchange policy)
        if (language == ReceiptLanguage.hindi) ...[
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(
                  child: pw.Text(
                    _fixDevanagari("नियम एवं शर्तें (जरूरी सूचना)"),
                    style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                  ),
                ),
                pw.SizedBox(height: 2.5),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: 2.5,
                      height: 2.5,
                      margin: const pw.EdgeInsets.only(top: 3, right: 3.5),
                      decoration: const pw.BoxDecoration(color: PdfColors.black, shape: pw.BoxShape.circle),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        _fixDevanagari("बिका हुआ माल वापस या रिफंड नहीं होगा।"),
                        style: pw.TextStyle(fontSize: 6.8, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 1.5),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: 2.5,
                      height: 2.5,
                      margin: const pw.EdgeInsets.only(top: 3, right: 3.5),
                      decoration: const pw.BoxDecoration(color: PdfColors.black, shape: pw.BoxShape.circle),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        _fixDevanagari("केवल 24 घंटे के अंदर असली बिल के साथ सामान बदला (Exchange) जा सकता है।"),
                        style: const pw.TextStyle(fontSize: 6.8, color: PdfColors.black),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 1.5),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: 2.5,
                      height: 2.5,
                      margin: const pw.EdgeInsets.only(top: 3, right: 3.5),
                      decoration: const pw.BoxDecoration(color: PdfColors.black, shape: pw.BoxShape.circle),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        _fixDevanagari("लिपस्टिक, नेलपॉलिश, क्रीम, कटा अस्तर, लेस/गोटा (थान से कटा या प्रयोग होने वाला सामान) और खुली शीशी/बोतल बदली नहीं जाएगी।"),
                        style: const pw.TextStyle(fontSize: 6.8, color: PdfColors.black),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ] else ...[
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(
                  child: pw.Text(
                    "TERMS & CONDITIONS (IMPORTANT)",
                    style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                  ),
                ),
                pw.SizedBox(height: 2.5),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: 2.5,
                      height: 2.5,
                      margin: const pw.EdgeInsets.only(top: 3, right: 3.5),
                      decoration: const pw.BoxDecoration(color: PdfColors.black, shape: pw.BoxShape.circle),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        "Goods once sold will not be returned or refunded.",
                        style: pw.TextStyle(fontSize: 6.8, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 1.5),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: 2.5,
                      height: 2.5,
                      margin: const pw.EdgeInsets.only(top: 3, right: 3.5),
                      decoration: const pw.BoxDecoration(color: PdfColors.black, shape: pw.BoxShape.circle),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        "Exchange permitted within 24 hours only with original bill.",
                        style: const pw.TextStyle(fontSize: 6.8, color: PdfColors.black),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 1.5),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      width: 2.5,
                      height: 2.5,
                      margin: const pw.EdgeInsets.only(top: 3, right: 3.5),
                      decoration: const pw.BoxDecoration(color: PdfColors.black, shape: pw.BoxShape.circle),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        "No exchange on cosmetics (lipstick, nail polish, cream), cut fabrics (cut astar, lace/gota), or opened bottles.",
                        style: const pw.TextStyle(fontSize: 6.8, color: PdfColors.black),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],

        // Footer Thank You
        pw.Divider(thickness: 0.5, color: PdfColors.grey600, borderStyle: pw.BorderStyle.dashed),
        pw.Center(
          child: pw.Column(
            children: [
              pw.Text(
                language == ReceiptLanguage.hindi
                    ? _fixDevanagari("*** धन्यवाद! फिर पधारें! ***")
                    : "*** THANK YOU FOR SHOPPING! VISIT AGAIN ***",
                style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
              ),
            ],
          ),
        ),
      ];
    }

    // Default to standard 80mm continuous receipt roll
    final PdfPageFormat format = pageFormat ??
        const PdfPageFormat(
          80 * PdfPageFormat.mm,
          double.infinity,
          marginAll: 4 * PdfPageFormat.mm,
        );

    if (format.height == double.infinity) {
      doc.addPage(
        pw.Page(
          pageFormat: format,
          build: (pw.Context context) {
            return pw.Container(
              color: PdfColors.white,
              child: pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: buildReceiptWidgets(context),
              ),
            );
          },
        ),
      );
    } else {
      doc.addPage(
        pw.MultiPage(
          pageFormat: format,
          margin: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          build: (pw.Context context) => [
            pw.Center(
              child: pw.Container(
                width: 76 * PdfPageFormat.mm,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  mainAxisSize: pw.MainAxisSize.min,
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: buildReceiptWidgets(context),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return doc.save();
  }

  /// Format a clean, human-readable WhatsApp text receipt message (Hindi or English)
  static String formatWhatsAppBillMessage(
    Map<String, dynamic> bill, {
    ReceiptLanguage language = ReceiptLanguage.hindi,
  }) {
    final String billNo = (bill['bill_number'] ?? "N/A").toString();
    final String counterName = (bill['counter_name'] ?? "Basement Counter").toString();
    final double totalAmount = _toDouble(bill['total_amount']);
    final String paymentMethod = (bill['payment_method'] ?? "Cash").toString();
    final rawItems = _extractItems(bill['items_json']);

    DateTime billDate = DateTime.now();
    if (bill['created_at'] != null) {
      try {
        billDate = DateTime.parse(bill['created_at']).toLocal();
      } catch (_) {}
    }
    final String formattedDate =
        "${billDate.day.toString().padLeft(2, '0')}-${billDate.month.toString().padLeft(2, '0')}-${billDate.year} ${billDate.hour.toString().padLeft(2, '0')}:${billDate.minute.toString().padLeft(2, '0')}";

    final StringBuffer buffer = StringBuffer();

    if (language == ReceiptLanguage.hindi) {
      buffer.writeln("🧾 *लव कुश शॉपिङ्ग सेण्टर*");
      buffer.writeln("   *LOVE KUSH SHOPPING CENTER*");
      buffer.writeln("📍 _${counterName.toLowerCase().contains("basement") ? "बेसमेंट काउंटर" : counterName}_");
      buffer.writeln("━━━━━━━━━━━━━━━━━━━━");
      buffer.writeln("📋 *बिल सं. (Bill No):* $billNo");
      buffer.writeln("📅 *दिनांक (Date):* $formattedDate");
      buffer.writeln("━━━━━━━━━━━━━━━━━━━━");
      buffer.writeln("*खरीदा गया सामान (Items Purchased):*");

      for (int i = 0; i < rawItems.length; i++) {
        final item = rawItems[i] is Map ? rawItems[i] as Map : {};
        // Item names always preserved in English as requested
        String itemName = (item['itemName'] ?? item['item'] ?? 'Item').toString().split('\n').first.trim();
        final qty = _toInt(item['qty'], 1);
        final rate = _toDouble(item['rate'], 0.0);
        final lineTotal = _toDouble(item['total'] ?? item['price'], qty * rate);
        buffer.writeln("${i + 1}. $itemName");
        buffer.writeln("    └ ${qty}x @ ₹${rate.toStringAsFixed(2)} = ₹${lineTotal.toStringAsFixed(2)}");
      }

      buffer.writeln("━━━━━━━━━━━━━━━━━━━━");
      buffer.writeln("💰 *कुल योग (GRAND TOTAL): ₹${totalAmount.toStringAsFixed(2)}*");
      buffer.writeln("💳 *भुगतान माध्यम (Payment):* ${_paymentModeHindi(paymentMethod)}");
      buffer.writeln("━━━━━━━━━━━━━━━━━━━━");
      buffer.writeln("📌 *नियम एवं शर्तें (जरूरी सूचना):*");
      buffer.writeln("• बिका हुआ माल वापस या रिफंड नहीं होगा।");
      buffer.writeln("• केवल 24 घंटे के अंदर असली बिल के साथ सामान बदला (Exchange) जा सकता है।");
      buffer.writeln("• लिपस्टिक, नेलपॉलिश, क्रीम, कटा अस्तर, लेस/गोटा और खुली बोतल बदली नहीं जाएगी।");
      buffer.writeln("  _(No Return / No Refund. Exchange within 24h with bill)_");
      buffer.writeln("━━━━━━━━━━━━━━━━━━━━");
      buffer.writeln("🙏 *हमारे यहाँ खरीदारी के लिए धन्यवाद! फिर पधारें!*");
      buffer.writeln("🌿 _डिजिटल पीडीएफ बिल संलग्न है (Digital PDF Bill attached)._");
    } else {
      buffer.writeln("🧾 *LOVE KUSH SHOPPING CENTER*");
      buffer.writeln("📍 _${counterName.toUpperCase()}_");
      buffer.writeln("━━━━━━━━━━━━━━━━━━━━");
      buffer.writeln("📋 *Bill No:* $billNo");
      buffer.writeln("📅 *Date:* $formattedDate");
      buffer.writeln("━━━━━━━━━━━━━━━━━━━━");
      buffer.writeln("*Items Purchased:*");

      for (int i = 0; i < rawItems.length; i++) {
        final item = rawItems[i] is Map ? rawItems[i] as Map : {};
        // Item names preserved in English
        String itemName = (item['itemName'] ?? item['item'] ?? 'Item').toString().split('\n').first.trim();
        final qty = _toInt(item['qty'], 1);
        final rate = _toDouble(item['rate'], 0.0);
        final lineTotal = _toDouble(item['total'] ?? item['price'], qty * rate);
        buffer.writeln("${i + 1}. $itemName");
        buffer.writeln("    └ ${qty}x @ ₹${rate.toStringAsFixed(2)} = ₹${lineTotal.toStringAsFixed(2)}");
      }

      buffer.writeln("━━━━━━━━━━━━━━━━━━━━");
      buffer.writeln("💰 *GRAND TOTAL: ₹${totalAmount.toStringAsFixed(2)}*");
      buffer.writeln("💳 *Payment Method:* ${paymentMethod.toUpperCase()}");
      buffer.writeln("━━━━━━━━━━━━━━━━━━━━");
      buffer.writeln("📌 *TERMS & CONDITIONS (IMPORTANT):*");
      buffer.writeln("• Goods once sold will not be returned or refunded.");
      buffer.writeln("• Exchange permitted within 24 hours only with original bill.");
      buffer.writeln("• No exchange on cosmetics (lipstick, nail polish, cream), cut fabrics (cut astar, lace/gota), or opened bottles.");
      buffer.writeln("━━━━━━━━━━━━━━━━━━━━");
      buffer.writeln("🙏 *THANK YOU FOR SHOPPING! VISIT AGAIN!*");
      buffer.writeln("🌿 _Digital PDF Bill attached._");
    }

    return buffer.toString();
  }

  /// Clean and validate an Indian mobile number
  static String? sanitizeIndianPhoneNumber(String raw) {
    String clean = raw.replaceAll(RegExp(r'[^0-9]'), '').trim();
    if (clean.length == 10) {
      return "91$clean";
    } else if (clean.length == 11 && clean.startsWith('0')) {
      return "91${clean.substring(1)}";
    } else if (clean.length == 12 && clean.startsWith('91')) {
      return clean;
    }
    return null;
  }

  /// Send PDF bill file directly via WhatsApp / system share sheet
  static Future<void> sharePdfBill({
    required BuildContext context,
    required Map<String, dynamic> bill,
    String? phone,
    ReceiptLanguage language = ReceiptLanguage.hindi,
  }) async {
    try {
      final String billNo = (bill['bill_number'] ?? "N/A").toString();
      final String safeBillNo = billNo.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final pdfBytes = await generateReceiptPdf(bill, language: language);
      final double totalAmount = _toDouble(bill['total_amount']);
      final langTag = language == ReceiptLanguage.hindi ? "Hindi" : "English";

      final cleanPhone = phone != null ? sanitizeIndianPhoneNumber(phone) : null;
      if (cleanPhone != null) {
        await Clipboard.setData(ClipboardData(text: cleanPhone));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Phone +$cleanPhone copied! Select contact in WhatsApp to send PDF."),
              duration: const Duration(seconds: 4),
              backgroundColor: const Color(0xFF047857),
            ),
          );
        }
      }

      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: "LoveKush_${langTag}_Bill_$safeBillNo.pdf",
        subject: "Love Kush Shopping Center ($langTag) - Bill #$billNo (₹${totalAmount.toStringAsFixed(2)})",
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("PDF Share Error: $e"), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  /// Send formatted text summary directly to customer's WhatsApp chat
  static Future<void> sendWhatsAppTextMessage({
    required BuildContext context,
    required Map<String, dynamic> bill,
    String? phone,
    ReceiptLanguage language = ReceiptLanguage.hindi,
  }) async {
    try {
      final String messageText = formatWhatsAppBillMessage(bill, language: language);
      final cleanPhone = phone != null ? sanitizeIndianPhoneNumber(phone) : null;

      if (cleanPhone != null) {
        final waUri = Uri.parse("https://wa.me/$cleanPhone?text=${Uri.encodeComponent(messageText)}");
        final launched = await launchUrl(waUri, mode: LaunchMode.externalApplication);
        if (!launched) {
          await sharePdfBill(context: context, bill: bill, phone: phone, language: language);
        }
      } else {
        await sharePdfBill(context: context, bill: bill, language: language);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("WhatsApp Error: $e"), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  /// Default shareBill now defaults to sending the PDF document directly!
  static Future<void> shareBill({
    required BuildContext context,
    required Map<String, dynamic> bill,
    String? phone,
    ReceiptLanguage language = ReceiptLanguage.hindi,
  }) => sharePdfBill(context: context, bill: bill, phone: phone, language: language);

  /// Show interactive WhatsApp & PDF options dialog with bilingual switcher
  static void showWhatsAppPdfDialog({
    required BuildContext context,
    required Map<String, dynamic> bill,
    ReceiptLanguage initialLanguage = ReceiptLanguage.hindi,
  }) {
    final phoneController = TextEditingController();
    final String billNo = (bill['bill_number'] ?? "N/A").toString();
    final double totalAmount = _toDouble(bill['total_amount']);
    final rawItems = _extractItems(bill['items_json']);
    ReceiptLanguage selectedLanguage = initialLanguage;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isHindi = selectedLanguage == ReceiptLanguage.hindi;
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Title Row
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF25D366).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.share, color: Color(0xFF25D366), size: 24),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              "Send Bill on WhatsApp / PDF",
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Bilingual Switcher Segmented Control
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () {
                                  setDialogState(() {
                                    selectedLanguage = ReceiptLanguage.hindi;
                                  });
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isHindi ? const Color(0xFF111827) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: isHindi ? [const BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))] : null,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Text("🇮🇳 ", style: TextStyle(fontSize: 14)),
                                      Text(
                                        "हिन्दी बिल",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: isHindi ? Colors.white : Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: InkWell(
                                onTap: () {
                                  setDialogState(() {
                                    selectedLanguage = ReceiptLanguage.english;
                                  });
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: !isHindi ? const Color(0xFF111827) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: !isHindi ? [const BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))] : null,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Text("🇬🇧 ", style: TextStyle(fontSize: 14)),
                                      Text(
                                        "English Bill",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: !isHindi ? Colors.white : Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Bill Info Chip
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("Bill: #$billNo", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            Text("${rawItems.length} items", style: const TextStyle(color: Colors.black54, fontSize: 12)),
                            Text(
                              "₹${totalAmount.toStringAsFixed(2)}",
                              style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF047857), fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Customer Phone Number Input
                      const Text(
                        "Customer Mobile (Optional):",
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: "Enter 10-digit number (e.g. 9812345678)",
                          prefixIcon: const Icon(Icons.phone_android, color: Colors.teal),
                          prefixText: "+91 ",
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Action Button 1: Send PDF Bill on WhatsApp (Primary)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 20),
                        label: Text(
                          isHindi ? "SEND HINDI PDF BILL" : "SEND ENGLISH PDF BILL",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          final phone = phoneController.text.trim();
                          Navigator.pop(ctx);
                          sharePdfBill(
                            context: context,
                            bill: bill,
                            phone: phone.isNotEmpty ? phone : null,
                            language: selectedLanguage,
                          );
                        },
                      ),
                      const SizedBox(height: 8),

                      // Action Button 2: Send Text Summary (Optional alternative)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF047857), size: 17),
                        label: Text(
                          isHindi ? "Send Hindi Text Summary Instead" : "Send English Text Summary Instead",
                          style: const TextStyle(color: Color(0xFF047857), fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          side: const BorderSide(color: Color(0xFF10B981)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          final phone = phoneController.text.trim();
                          Navigator.pop(ctx);
                          sendWhatsAppTextMessage(
                            context: context,
                            bill: bill,
                            phone: phone.isNotEmpty ? phone : null,
                            language: selectedLanguage,
                          );
                        },
                      ),
                      const SizedBox(height: 8),

                      // Action Button 3: Print or View PDF Directly
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.visibility, color: Color(0xFF2563EB), size: 18),
                              label: Text(
                                isHindi ? "PREVIEW HINDI" : "PREVIEW ENGLISH",
                                style: const TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                side: const BorderSide(color: Color(0xFF2563EB)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () {
                                Navigator.pop(ctx);
                                openPdfPreviewDialog(
                                  context: context,
                                  bill: bill,
                                  initialLanguage: selectedLanguage,
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                side: const BorderSide(color: Colors.grey),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text("CANCEL", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Open local interactive vector PDF preview screen inside the app with bilingual toggle
  static void openPdfPreviewDialog({
    required BuildContext context,
    required Map<String, dynamic> bill,
    ReceiptLanguage initialLanguage = ReceiptLanguage.hindi,
  }) {
    final String billNo = (bill['bill_number'] ?? "N/A").toString();
    final String safeBillNo = billNo.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    ReceiptLanguage selectedLanguage = initialLanguage;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setPreviewState) {
            final isHindi = selectedLanguage == ReceiptLanguage.hindi;
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680, maxHeight: 820),
                child: Scaffold(
                  backgroundColor: Colors.white,
                  appBar: AppBar(
                    title: Text(
                      "PDF Invoice - Bill #$billNo",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    backgroundColor: const Color(0xFF111827),
                    iconTheme: const IconThemeData(color: Colors.white),
                    actions: [
                      // Language Toggle Buttons in AppBar
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () {
                                if (selectedLanguage != ReceiptLanguage.hindi) {
                                  setPreviewState(() {
                                    selectedLanguage = ReceiptLanguage.hindi;
                                  });
                                }
                              },
                              borderRadius: const BorderRadius.horizontal(left: Radius.circular(7)),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isHindi ? const Color(0xFF2563EB) : Colors.transparent,
                                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(7)),
                                ),
                                child: Text(
                                  "🇮🇳 हिन्दी",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isHindi ? FontWeight.bold : FontWeight.normal,
                                    color: isHindi ? Colors.white : Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                if (selectedLanguage != ReceiptLanguage.english) {
                                  setPreviewState(() {
                                    selectedLanguage = ReceiptLanguage.english;
                                  });
                                }
                              },
                              borderRadius: const BorderRadius.horizontal(right: Radius.circular(7)),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: !isHindi ? const Color(0xFF2563EB) : Colors.transparent,
                                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(7)),
                                ),
                                child: Text(
                                  "🇬🇧 English",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: !isHindi ? FontWeight.bold : FontWeight.normal,
                                    color: !isHindi ? Colors.white : Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(Icons.share, color: Color(0xFF25D366)),
                        tooltip: "Send on WhatsApp",
                        onPressed: () {
                          Navigator.pop(ctx);
                          showWhatsAppPdfDialog(
                            context: context,
                            bill: bill,
                            initialLanguage: selectedLanguage,
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        tooltip: "Close",
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  body: PdfPreview(
                    key: ValueKey(selectedLanguage),
                    build: (format) => generateReceiptPdf(
                      bill,
                      pageFormat: format,
                      language: selectedLanguage,
                    ),
                    allowPrinting: true,
                    allowSharing: true,
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    initialPageFormat: const PdfPageFormat(
                      80 * PdfPageFormat.mm,
                      double.infinity,
                      marginAll: 4 * PdfPageFormat.mm,
                    ),
                    pdfFileName: "LoveKush_${selectedLanguage == ReceiptLanguage.hindi ? 'Hindi' : 'English'}_Bill_$safeBillNo.pdf",
                    maxPageWidth: 420,
                    loadingWidget: const Center(
                      child: CircularProgressIndicator(),
                    ),
                    onError: (context, error) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text("Error previewing PDF: $error", style: const TextStyle(color: Colors.red)),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ReceiptItem {
  final String name;
  final int qty;
  final double rate;
  final double lineTotal;

  const _ReceiptItem({
    required this.name,
    required this.qty,
    required this.rate,
    required this.lineTotal,
  });
}
