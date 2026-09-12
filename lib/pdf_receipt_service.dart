import 'dart:convert';
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

  /// Generate a clean, high-resolution PDF receipt document for a bill
  static Future<Uint8List> generateReceiptPdf(
    Map<String, dynamic> bill, {
    Uint8List? logoBytes,
    PdfPageFormat pageFormat = PdfPageFormat.a5,
  }) async {
    final doc = pw.Document();

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
      } catch (_) {}
    }

    final pw.ImageProvider? logoImage = effectiveLogo != null ? pw.MemoryImage(effectiveLogo) : null;

    // 3. Extract items safely
    final rawItems = _extractItems(bill['items_json']);
    final List<List<String>> tableData = [];
    int totalQty = 0;

    for (int i = 0; i < rawItems.length; i++) {
      final item = rawItems[i] is Map ? rawItems[i] as Map : {};
      String itemName = (item['itemName'] ?? item['item'] ?? 'General Item').toString().split('\n').first.trim();
      final qty = _toInt(item['qty'], 1);
      final rate = _toDouble(item['rate'], 0.0);
      final lineTotal = _toDouble(item['total'] ?? item['price'], qty * rate);
      totalQty += qty;

      tableData.add([
        (i + 1).toString(),
        itemName,
        qty.toString(),
        "Rs ${rate.toStringAsFixed(2)}",
        "Rs ${lineTotal.toStringAsFixed(2)}",
      ]);
    }

    // 4. Build Document Pages
    doc.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(18),
        build: (pw.Context context) {
          return [
            // Store Header with Logo and Details
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logoImage != null) ...[
                  pw.Container(
                    width: 52,
                    height: 52,
                    decoration: pw.BoxDecoration(
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                    ),
                    child: pw.ClipRRect(
                      horizontalRadius: 6,
                      verticalRadius: 6,
                      child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                    ),
                  ),
                  pw.SizedBox(width: 12),
                ],
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        "LOVE KUSH SHOPPING CENTER",
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue900,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        "${counterName.toUpperCase()} | RETAIL CASH MEMO",
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                ),
                // Bill Barcode
                if (billNo != "N/A" && billNo.isNotEmpty) ...[
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.BarcodeWidget(
                        barcode: pw.Barcode.code128(),
                        data: billNo,
                        width: 120,
                        height: 32,
                        drawText: false,
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        "BILL: $billNo",
                        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Divider(thickness: 0.8, color: PdfColors.grey400),

            // Metadata Row: Date, Cashier, Payment Method
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("Date: $formattedDate", style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey800)),
                pw.Text("Cashier: $staffName", style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey800)),
                pw.Text(
                  "Payment: ${paymentMethod.toUpperCase()}",
                  style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800),
                ),
              ],
            ),
            pw.SizedBox(height: 6),

            // Items Table
            pw.TableHelper.fromTextArray(
              context: context,
              headers: ["#", "Item Description", "Qty", "Rate", "Amount"],
              data: tableData,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1E3A8A)),
              cellStyle: const pw.TextStyle(fontSize: 8.5),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              columnWidths: {
                0: const pw.FixedColumnWidth(22),
                1: const pw.FlexColumnWidth(5),
                2: const pw.FixedColumnWidth(32),
                3: const pw.FixedColumnWidth(58),
                4: const pw.FixedColumnWidth(64),
              },
              cellAlignments: {
                0: pw.Alignment.center,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.center,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerRight,
              },
            ),
            pw.SizedBox(height: 8),

            // Summary / Totals Section
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        "Total Items: ${rawItems.length}  |  Total Qty: $totalQty",
                        style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
                      ),
                      if (paymentMethod == "Cash" || paymentMethod == "Hybrid") ...[
                        pw.SizedBox(height: 2),
                        pw.Text(
                          "Paid: Rs ${amountTendered.toStringAsFixed(2)}${changeDue > 0 ? "  |  Change: Rs ${changeDue.toStringAsFixed(2)}" : ""}",
                          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                        ),
                      ],
                    ],
                  ),
                  pw.Row(
                    children: [
                      pw.Text(
                        "GRAND TOTAL: ",
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
                      ),
                      pw.Text(
                        "Rs ${totalAmount.toStringAsFixed(2)}",
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: const PdfColor.fromInt(0xFF047857),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),

            // Footer Notice
            pw.Center(
              child: pw.Column(
                children: [
                  pw.Text(
                    "Thank you for shopping with us! Visit Again.",
                    style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    "No Exchange / No Refund without original bill | Digital WhatsApp Invoice",
                    style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
                  ),
                ],
              ),
            ),
          ];
        },
      ),
    );

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
    buffer.writeln("🧾 *LOVE KUSH SHOPPING CENTER*");
    buffer.writeln("📍 _${counterName}_");
    buffer.writeln("━━━━━━━━━━━━━━━━━━━━");
    buffer.writeln("📋 *Bill No:* $billNo");
    buffer.writeln("📅 *Date:* $formattedDate");
    buffer.writeln("━━━━━━━━━━━━━━━━━━━━");
    buffer.writeln("*Items Purchased:*");

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
    buffer.writeln("💰 *GRAND TOTAL: ₹${totalAmount.toStringAsFixed(2)}*");
    buffer.writeln("💳 *Payment:* ${paymentMethod.toUpperCase()}");
    buffer.writeln("━━━━━━━━━━━━━━━━━━━━");
    buffer.writeln("🙏 *Thank you for shopping with us!*");
    buffer.writeln("🌿 _Digital PDF Bill attached below._");

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
                initialPageFormat: PdfPageFormat.a5,
                pdfFileName: "LoveKush_Bill_$safeBillNo.pdf",
                maxPageWidth: 550,
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
