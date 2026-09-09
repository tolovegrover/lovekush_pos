import re

with open("lib/main.dart", "r") as f:
    content = f.read()

# Add import
if "import 'package:qr_flutter/qr_flutter.dart';" not in content:
    content = content.replace("import 'package:firebase_core/firebase_core.dart';", "import 'package:firebase_core/firebase_core.dart';\nimport 'package:qr_flutter/qr_flutter.dart';")

# Drawer insertion
drawer_injection = """
            if (widget.isAdmin)
              ListTile(
                leading: const Icon(Icons.qr_code_2),
                title: const Text("Print Item QR Codes"),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const InventoryQrScreen()));
                },
              ),
"""
if "Print Item QR Codes" not in content:
    content = content.replace("              ListTile(\n                leading: const Icon(Icons.group),", drawer_injection + "              ListTile(\n                leading: const Icon(Icons.group),")

# Screen injection
qr_screen_code = """
// ==========================================
// INVENTORY QR LABEL PRINTER
// ==========================================
class InventoryQrScreen extends StatefulWidget {
  const InventoryQrScreen({Key? key}) : super(key: key);
  @override
  State<InventoryQrScreen> createState() => _InventoryQrScreenState();
}

class _InventoryQrScreenState extends State<InventoryQrScreen> {
  final TextEditingController _floorCtrl = TextEditingController(text: "1");
  final TextEditingController _rackCtrl = TextEditingController(text: "01");
  final TextEditingController _shelfCtrl = TextEditingController(text: "A");
  final TextEditingController _itemCtrl = TextEditingController(text: "1");
  
  String get locationCode => "${_floorCtrl.text}-${_rackCtrl.text}-${_shelfCtrl.text}-${_itemCtrl.text}".toUpperCase();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Item QR Generator"), backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text("Enter Location Code Parts", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: TextField(controller: _floorCtrl, decoration: const InputDecoration(labelText: "Floor"), onChanged: (_) => setState((){}))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _rackCtrl, decoration: const InputDecoration(labelText: "Rack"), onChanged: (_) => setState((){}))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _shelfCtrl, decoration: const InputDecoration(labelText: "Shelf"), onChanged: (_) => setState((){}))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _itemCtrl, decoration: const InputDecoration(labelText: "Item"), onChanged: (_) => setState((){}))),
              ],
            ),
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black12, width: 2),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)]
              ),
              child: Column(
                children: [
                  Text("Item Location", style: const TextStyle(fontSize: 16, color: Colors.black54)),
                  Text(locationCode, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 2)),
                  const SizedBox(height: 24),
                  QrImageView(
                    data: locationCode,
                    version: QrVersions.auto,
                    size: 200.0,
                    backgroundColor: Colors.white,
                  ),
                ],
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity, height: 56,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.print),
                label: const Text("PRINT QR LABEL", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B82F6), foregroundColor: Colors.white),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sending to Bluetooth/USB Printer...")));
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}
"""

if "class InventoryQrScreen" not in content:
    content += "\n" + qr_screen_code

with open("lib/main.dart", "w") as f:
    f.write(content)
