import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _defaultReceiptLang = "Hindi";
  bool _enableSanskritInvocation = true;
  bool _showVedicInReceipt = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _defaultReceiptLang = prefs.getString('default_receipt_lang') ?? "Hindi";
      _enableSanskritInvocation = prefs.getBool('enable_sanskrit_invocation') ?? true;
      _showVedicInReceipt = prefs.getBool('show_vedic_in_receipt') ?? true;
      _isLoading = false;
    });
  }

  Future<void> _savePreference(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is String) {
      await prefs.setString(key, value);
    } else if (value is bool) {
      await prefs.setBool(key, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Settings",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 1. RECEIPT & PRINTING PREFERENCES
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    "RECEIPT & BILLING PREFERENCES",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueAccent, letterSpacing: 1.1),
                  ),
                ),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  color: Colors.white,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.language, color: Colors.blueAccent),
                        title: const Text(
                          "Default Receipt Language",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        subtitle: Text(
                          "Active format: ${_defaultReceiptLang == 'Hindi' ? 'Hindi (हिन्दी)' : 'English'}",
                        ),
                        trailing: DropdownButton<String>(
                          value: _defaultReceiptLang,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(value: "Hindi", child: Text("Hindi (हिन्दी)")),
                            DropdownMenuItem(value: "English", child: Text("English")),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _defaultReceiptLang = val);
                              _savePreference('default_receipt_lang', val);
                            }
                          },
                        ),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      SwitchListTile(
                        title: const Text(
                          "Auspicious Sanskrit Mantra on Bills",
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text("Prints sacred invocation banner at the top of bills"),
                        activeColor: Colors.blueAccent,
                        value: _enableSanskritInvocation,
                        onChanged: (val) {
                          setState(() => _enableSanskritInvocation = val);
                          _savePreference('enable_sanskrit_invocation', val);
                        },
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      SwitchListTile(
                        title: const Text(
                          "Include Vedic Date & Panchang on Bills",
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text("Prints Vedic Vaar, Tithi, Samvat and Ghati timestamp"),
                        activeColor: Colors.blueAccent,
                        value: _showVedicInReceipt,
                        onChanged: (val) {
                          setState(() => _showVedicInReceipt = val);
                          _savePreference('show_vedic_in_receipt', val);
                        },
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.print_outlined, color: Colors.black87),
                        title: const Text(
                          "Thermal Printer Configuration",
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text("58mm / 80mm ESC/POS Bluetooth thermal printer pairing"),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Manage thermal printer from the POS drawer menu")),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 2. STORE PROFILE
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    "STORE PROFILE",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.1),
                  ),
                ),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          "Love Kush Shopping Center",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        SizedBox(height: 4),
                        Text(
                          "Address: A-2/392, Subhash Kansal Marg, Harsh Vihar, Delhi - 110093",
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                        SizedBox(height: 2),
                        Text(
                          "Contact: +91 98991 26211 / +91 98112 05211",
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "Love Kush POS v2.5.0 • Enterprise Edition",
                          style: TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
