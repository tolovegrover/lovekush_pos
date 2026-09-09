import re

with open("lib/main.dart", "r") as f:
    content = f.read()

# 1. Add `isScanning` to `_PosScreenState`
if "bool isScanning = false;" not in content:
    content = content.replace("bool isPreviewingBill = false;", "bool isPreviewingBill = false;\n  bool isScanning = false;")

# 2. Remove the old scanner button from the row
old_input_row = """                Expanded(
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
                _buildInputBox("ITEM", formattedItemCode, focusedField == 0, 0, flex: 6, isCode: true),"""

new_input_row = """                _buildInputBox("ITEM CODE", formattedItemCode, focusedField == 0, 0, flex: 8, isCode: true),"""

content = content.replace(old_input_row, new_input_row)

# 3. Modify the Keypad area to show scanner conditionally
old_keypad_area = """          Expanded(
            flex: 5,
            child: Container(
              color: const Color(0xFF111827), 
              child: Column(
                children: [
                  _buildKeypadRow([_key("1", "A"), _key("2", "B"), _key("3", "C"), _actionKey("⌫", const Color(0xFFEF4444))]), 
                  _buildKeypadRow([_key("4", "D"), _key("5", "E"), _key("6", "F"), _actionKey("◀", const Color(0xFFF59E0B))]),
                  _buildKeypadRow([_key("7", "G"), _key("8", "H"), _key("9", "I"), _actionKey("ENTER", const Color(0xFF3B82F6), flex: 1, isEnter: true)]),
                  _buildKeypadRow([_key(".", ""), _key("0", ""), _key("00", "")]),
                ],
              ),
            ),
          ),"""

new_keypad_area = """          Expanded(
            flex: 5,
            child: isScanning 
              ? Stack(
                  children: [
                    MobileScanner(
                      onDetect: (capture) {
                        final List<Barcode> barcodes = capture.barcodes;
                        if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                          setState(() {
                            rawItemCode = barcodes.first.rawValue!.replaceAll("-", "");
                            focusedField = 1; // jump to qty
                            isScanning = false; // instantly close camera to show keypad
                          });
                        }
                      },
                    ),
                    Positioned(
                      top: 16, right: 16,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 32),
                        onPressed: () => setState(() => isScanning = false),
                      )
                    ),
                    const Positioned(
                      bottom: 24, left: 0, right: 0,
                      child: Center(
                        child: Text("Scanning...", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, backgroundColor: Colors.black54)),
                      )
                    )
                  ]
                )
              : Container(
                  color: const Color(0xFF111827), 
                  child: Column(
                    children: [
                      _buildKeypadRow([_key("1", "A"), _key("2", "B"), _key("3", "C"), _actionKey("⌫", const Color(0xFFEF4444))]), 
                      _buildKeypadRow([_key("4", "D"), _key("5", "E"), _key("6", "F"), _actionKey("◀", const Color(0xFFF59E0B))]),
                      _buildKeypadRow([_key("7", "G"), _key("8", "H"), _key("9", "I"), _actionKey("ENTER", const Color(0xFF3B82F6), flex: 1, isEnter: true)]),
                      _buildKeypadRow([_key(".", ""), _key("0", ""), _actionKey("📷 SCAN", Colors.black, isScan: true)]),
                    ],
                  ),
                ),
          ),"""

content = content.replace(old_keypad_area, new_keypad_area)

# 4. Update _actionKey to handle isScan
old_action_key = """  Widget _actionKey(String action, Color color, {int flex = 1, bool isEnter = false}) {
    return Expanded(
      flex: flex,
      child: Material(
        color: color,
        child: InkWell(
          onTap: () => onKeypadPress(isEnter ? "ENTER" : (action.contains("⌫") ? "DEL" : "BACK")),"""

new_action_key = """  Widget _actionKey(String action, Color color, {int flex = 1, bool isEnter = false, bool isScan = false}) {
    return Expanded(
      flex: flex,
      child: Material(
        color: color,
        child: InkWell(
          onTap: () {
            if (isScan) {
              setState(() => isScanning = true);
            } else {
              onKeypadPress(isEnter ? "ENTER" : (action.contains("⌫") ? "DEL" : "BACK"));
            }
          },"""

content = content.replace(old_action_key, new_action_key)

with open("lib/main.dart", "w") as f:
    f.write(content)
