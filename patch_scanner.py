import re

with open("lib/main.dart", "r") as f:
    content = f.read()

# Add import
if "import 'package:mobile_scanner/mobile_scanner.dart';" not in content:
    content = content.replace("import 'package:qr_flutter/qr_flutter.dart';", "import 'package:qr_flutter/qr_flutter.dart';\nimport 'package:mobile_scanner/mobile_scanner.dart';")

# Add the new screen at the bottom
scanner_screen = """
// ==========================================
// QR CAMERA SCANNER SCREEN
// ==========================================
class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({Key? key}) : super(key: key);
  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final MobileScannerController controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan QR Label"), backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: MobileScanner(
        controller: controller,
        onDetect: (BarcodeCapture capture) {
          final List<Barcode> barcodes = capture.barcodes;
          if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
            final String code = barcodes.first.rawValue!;
            controller.stop();
            Navigator.pop(context, code);
          }
        },
      ),
    );
  }
}
"""
if "class QRScannerScreen" not in content:
    content += "\n" + scanner_screen

# Add the scan button next to the ITEM CODE box
old_ui_row = """                _buildInputBox("ITEM CODE", formattedItemCode, focusedField == 0, 0, flex: 8, isCode: true),
                const SizedBox(width: 8),"""
new_ui_row = """                Expanded(
                  flex: 2,
                  child: InkWell(
                    onTap: () async {
                      final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const QRScannerScreen()));
                      if (result != null && result is String) {
                        setState(() {
                          rawItemCode = result.replaceAll("-", "");
                          focusedField = 1; // auto-jump to qty
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
                      child: const Center(child: Icon(Icons.qr_code_scanner, color: Colors.white, size: 32)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildInputBox("ITEM", formattedItemCode, focusedField == 0, 0, flex: 6, isCode: true),
                const SizedBox(width: 8),"""
content = content.replace(old_ui_row, new_ui_row)

with open("lib/main.dart", "w") as f:
    f.write(content)
