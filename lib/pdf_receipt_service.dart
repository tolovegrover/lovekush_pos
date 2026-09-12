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

class PdfReceiptService {
  static pw.Font? _cachedHindiRegular;
  static pw.Font? _cachedHindiBold;

  /// Load and cache Hindi TrueType fonts offline from bundled assets (with local File fallback for tests)
  static Future<pw.ThemeData> _loadTheme() async {
    if (_cachedHindiRegular != null && _cachedHindiBold != null) {
      return pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
        fontFallback: [_cachedHindiRegular!, _cachedHindiBold!],
      );
    }

    pw.Font? regular = _cachedHindiRegular;
    pw.Font? bold = _cachedHindiBold;

    if (regular == null) {
      try {
        final data = await rootBundle.load("assets/fonts/NotoSerifDevanagari-Regular.ttf");
        regular = pw.Font.ttf(data);
        _cachedHindiRegular = regular;
      } catch (_) {
        try {
          final file = File("assets/fonts/NotoSerifDevanagari-Regular.ttf");
          if (file.existsSync()) {
            final bytes = await file.readAsBytes();
            regular = pw.Font.ttf(bytes.buffer.asByteData());
            _cachedHindiRegular = regular;
          }
        } catch (_) {}
      }
    }

    if (bold == null) {
      try {
        final data = await rootBundle.load("assets/fonts/NotoSerifDevanagari-Bold.ttf");
        bold = pw.Font.ttf(data);
        _cachedHindiBold = bold;
      } catch (_) {
        try {
          final file = File("assets/fonts/NotoSerifDevanagari-Bold.ttf");
          if (file.existsSync()) {
            final bytes = await file.readAsBytes();
            bold = pw.Font.ttf(bytes.buffer.asByteData());
            _cachedHindiBold = bold;
          }
        } catch (_) {}
      }
    }

    final fallbacks = <pw.Font>[];
    if (regular != null) fallbacks.add(regular);
    if (bold != null) fallbacks.add(bold);

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

        // Store Titles (Hindi & English)
        pw.Center(
          child: pw.Text(
            _fixDevanagari("लव कुश शॉपिंग सेंटर"),
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),
        ),
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

        // Bill No & Code 128 Barcode
        if (billNo != "N/A" && billNo.isNotEmpty) ...[
          pw.SizedBox(height: 3),
          pw.Center(
            child: pw.Text(
              "BILL NO: $billNo",
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
            pw.Text("Date: $formattedDate", style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.black)),
            pw.Text("Cashier: $staffName", style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.black)),
          ],
        ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              "Payment: ${paymentMethod.toUpperCase()}",
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
              child: pw.Text("ITEM", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
            ),
            pw.Expanded(
              flex: 4,
              child: pw.Text("QTY x RATE", textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
            ),
            pw.Expanded(
              flex: 3,
              child: pw.Text("AMOUNT", textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
            ),
          ],
        ),
        pw.Divider(thickness: 0.5, color: PdfColors.grey600, borderStyle: pw.BorderStyle.dashed),

        // Minimal Item Rows (Thermal printer style)
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
                        "${item.qty} x Rs ${item.rate.toStringAsFixed(2)}",
                        style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800),
                      ),
                    ),
                    pw.Text(
                      "Rs ${item.lineTotal.toStringAsFixed(2)}",
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
            pw.Text("Total Items: ${receiptItems.length} (Qty: $totalQty)", style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800)),
          ],
        ),
        pw.SizedBox(height: 2),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              "TOTAL AMOUNT:",
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
              pw.Text("Paid Money:", style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800)),
              pw.Text("Rs ${amountTendered.toStringAsFixed(2)}", style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.black)),
            ],
          ),
          if (changeDue > 0) ...[
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("Change Return:", style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800)),
                pw.Text("Rs ${changeDue.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
              ],
            ),
          ],
        ],

        // Dashed Divider
        pw.Divider(thickness: 0.8, color: PdfColors.black, borderStyle: pw.BorderStyle.dashed),

        // Terms & Conditions (Strict Hindi policy for shop audience)
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
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.Text(
                  "(No Return/Refund. Exchange within 24h with bill)",
                  style: const pw.TextStyle(fontSize: 6.0, color: PdfColors.grey700),
                ),
              ),
            ],
          ),
        ),

        // Footer Thank You
        pw.Divider(thickness: 0.5, color: PdfColors.grey600, borderStyle: pw.BorderStyle.dashed),
        pw.Center(
          child: pw.Column(
            children: [
              pw.Text(
                _fixDevanagari("*** धन्यवाद! फिर पधारें! ***"),
                style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
              ),
              pw.SizedBox(height: 1),
              pw.Text(
                "*** THANK YOU FOR SHOPPING! VISIT AGAIN ***",
                style: const pw.TextStyle(fontSize: 6.8, color: PdfColors.grey700),
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

  /// Format a clean, human-readable WhatsApp text receipt message
  static String formatWhatsAppBillMessage(Map<String, dynamic> bill) {
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
    buffer.writeln("🧾 *लव कुश शॉपिङ्ग सेण्टर*");
    buffer.writeln("   *LOVE KUSH SHOPPING CENTER*");
    buffer.writeln("📍 _${counterName}_");
    buffer.writeln("━━━━━━━━━━━━━━━━━━━━");
    buffer.writeln("📋 *Bill No:* $billNo");
    buffer.writeln("📅 *Date:* $formattedDate");
    buffer.writeln("━━━━━━━━━━━━━━━━━━━━");
    buffer.writeln("*खरीदा गया सामान (Items Purchased):*");

    for (int i = 0; i < rawItems.length; i++) {
      final item = rawItems[i] is Map ? rawItems[i] as Map : {};
      String itemName = (item['itemName'] ?? item['item'] ?? 'Item').toString().split('\n').first.trim();
      final qty = _toInt(item['qty'], 1);
      final rate = _toDouble(item['rate'], 0.0);
      final lineTotal = _toDouble(item['total'] ?? item['price'], qty * rate);
      buffer.writeln("${i + 1}. $itemName");
      buffer.writeln("    └ ${qty}x @ ₹${rate.toStringAsFixed(2)} = ₹${lineTotal.toStringAsFixed(2)}");
    }

    buffer.writeln("━━━━━━━━━━━━━━━━━━━━");
    buffer.writeln("💰 *कुल योग (GRAND TOTAL): ₹${totalAmount.toStringAsFixed(2)}*");
    buffer.writeln("💳 *भुगतान (Payment):* ${paymentMethod.toUpperCase()}");
    buffer.writeln("━━━━━━━━━━━━━━━━━━━━");
    buffer.writeln("📌 *नियम एवं शर्तें (जरूरी सूचना):*");
    buffer.writeln("• बिका हुआ माल वापस या रिफंड नहीं होगा।");
    buffer.writeln("• केवल 24 घंटे के अंदर असली बिल के साथ सामान बदला (Exchange) जा सकता है।");
    buffer.writeln("• लिपस्टिक, नेलपॉलिश, क्रीम, कटा अस्तर, लेस/गोटा और खुली बोतल बदली नहीं जाएगी।");
    buffer.writeln("  _(No Return / No Refund. Exchange within 24h with bill)_");
    buffer.writeln("━━━━━━━━━━━━━━━━━━━━");
    buffer.writeln("🙏 *हमारे यहाँ खरीदारी के लिए धन्यवाद! फिर पधारें!*");
    buffer.writeln("🌿 _डिजिटल पीडीएफ बिल संलग्न है (Digital PDF Bill attached)._");

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
  }) async {
    try {
      final String billNo = (bill['bill_number'] ?? "N/A").toString();
      final String safeBillNo = billNo.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final pdfBytes = await generateReceiptPdf(bill);
      final double totalAmount = _toDouble(bill['total_amount']);

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
        filename: "LoveKush_Bill_$safeBillNo.pdf",
        subject: "Love Kush Shopping Center - Bill #$billNo (₹${totalAmount.toStringAsFixed(2)})",
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
  }) async {
    try {
      final String messageText = formatWhatsAppBillMessage(bill);
      final cleanPhone = phone != null ? sanitizeIndianPhoneNumber(phone) : null;

      if (cleanPhone != null) {
        final waUri = Uri.parse("https://wa.me/$cleanPhone?text=${Uri.encodeComponent(messageText)}");
        final launched = await launchUrl(waUri, mode: LaunchMode.externalApplication);
        if (!launched) {
          await sharePdfBill(context: context, bill: bill, phone: phone);
        }
      } else {
        await sharePdfBill(context: context, bill: bill);
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
  }) => sharePdfBill(context: context, bill: bill, phone: phone);

  /// Show interactive WhatsApp & PDF options dialog
  static void showWhatsAppPdfDialog({
    required BuildContext context,
    required Map<String, dynamic> bill,
  }) {
    final phoneController = TextEditingController();
    final String billNo = (bill['bill_number'] ?? "N/A").toString();
    final double totalAmount = _toDouble(bill['total_amount']);
    final rawItems = _extractItems(bill['items_json']);

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
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
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

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
                  const SizedBox(height: 16),

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
                  const SizedBox(height: 18),

                  // Action Button 1: Send PDF Bill on WhatsApp (Primary)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 20),
                    label: const Text(
                      "SEND PDF BILL ON WHATSAPP",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      final phone = phoneController.text.trim();
                      Navigator.pop(ctx);
                      sharePdfBill(context: context, bill: bill, phone: phone.isNotEmpty ? phone : null);
                    },
                  ),
                  const SizedBox(height: 8),

                  // Action Button 2: Send Text Summary (Optional alternative)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF047857), size: 17),
                    label: const Text(
                      "Send Text Summary Instead",
                      style: TextStyle(color: Color(0xFF047857), fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      side: const BorderSide(color: Color(0xFF10B981)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      final phone = phoneController.text.trim();
                      Navigator.pop(ctx);
                      sendWhatsAppTextMessage(context: context, bill: bill, phone: phone.isNotEmpty ? phone : null);
                    },
                  ),
                  const SizedBox(height: 8),

                  // Action Button 3: Print or View PDF Directly
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.visibility, color: Color(0xFF2563EB), size: 18),
                          label: const Text(
                            "PREVIEW PDF",
                            style: TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            side: const BorderSide(color: Color(0xFF2563EB)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            openPdfPreviewDialog(context: context, bill: bill);
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
  }

  /// Open local interactive vector PDF preview screen inside the app
  static void openPdfPreviewDialog({
    required BuildContext context,
    required Map<String, dynamic> bill,
  }) {
    final String billNo = (bill['bill_number'] ?? "N/A").toString();
    final String safeBillNo = billNo.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680, maxHeight: 820),
            child: Scaffold(
              backgroundColor: Colors.white,
              appBar: AppBar(
                title: Text("PDF Invoice - Bill #$billNo", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                backgroundColor: const Color(0xFF111827),
                iconTheme: const IconThemeData(color: Colors.white),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.share, color: Color(0xFF25D366)),
                    tooltip: "Send on WhatsApp",
                    onPressed: () {
                      Navigator.pop(ctx);
                      showWhatsAppPdfDialog(context: context, bill: bill);
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
                build: (format) => generateReceiptPdf(bill, pageFormat: format),
                allowPrinting: true,
                allowSharing: true,
                canChangePageFormat: false,
                canChangeOrientation: false,
                initialPageFormat: const PdfPageFormat(
                  80 * PdfPageFormat.mm,
                  double.infinity,
                  marginAll: 4 * PdfPageFormat.mm,
                ),
                pdfFileName: "LoveKush_Bill_$safeBillNo.pdf",
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
