import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'vedic_clock_screen.dart';

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
        title: const Text("सेटिंग्स एवं प्राथमिकताएं (Settings)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 1. VEDIC TIME & PANCHANG SECTION
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    "वैदिक समय एवं काल गणना (VEDIC TIME & PANCHANG)",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFB45309), letterSpacing: 1.1),
                  ),
                ),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.amber.shade200),
                  ),
                  color: const Color(0xFFFFFBEB),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: const Color(0xFFD97706), borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.wb_sunny, color: Colors.white, size: 22),
                        ),
                        title: const Text(
                          "वैदिक घड़ी एवं काल परिवर्तक (Live Vedic Clock)",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF92400E)),
                        ),
                        subtitle: const Text("घटी • पल • विपल, सूर्योदय (New Delhi) एवं शुद्ध पञ्चाङ्ग"),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFF92400E)),
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const VedicClockScreen()));
                        },
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      SwitchListTile(
                        title: const Text("रसीद पर वैदिक पञ्चाङ्ग दिखाएं", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: const Text("भाद्रपद, शुक्ल प्रतिपदा, संवत् एवं प्रहर बिल पर मुद्रित करें"),
                        activeColor: const Color(0xFFD97706),
                        value: _showVedicInReceipt,
                        onChanged: (val) {
                          setState(() => _showVedicInReceipt = val);
                          _savePreference('show_vedic_in_receipt', val);
                        },
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.location_on, color: Colors.grey, size: 20),
                        title: const Text("पञ्चाङ्ग वेधशाला निर्देशांक (New Delhi)", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        subtitle: const Text("अक्षांश: 28.6139° N • रेखांश: 77.2090° E (UTC+05:30 IST)"),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 2. RECEIPT & PRINTING PREFERENCES
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    "बिल एवं मुद्रण सेटिंग्स (BILLING & RECEIPT)",
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
                        title: const Text("डिफ़ॉल्ट रसीद भाषा (Default Language)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text("वर्तमान चयन: ${_defaultReceiptLang == 'Hindi' ? 'हिन्दी (Hindi)' : 'English'}"),
                        trailing: DropdownButton<String>(
                          value: _defaultReceiptLang,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(value: "Hindi", child: Text("हिन्दी (Hindi)")),
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
                        title: const Text("भगवान वंदना शीर्ष पंक्ति (Divine Invocation)", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: const Text("卐 श्री गणेशाय नमः • ॐ नमः शिवाय • श्री महालक्ष्म्यै नमः"),
                        activeColor: Colors.blueAccent,
                        value: _enableSanskritInvocation,
                        onChanged: (val) {
                          setState(() => _enableSanskritInvocation = val);
                          _savePreference('enable_sanskrit_invocation', val);
                        },
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.print_outlined, color: Colors.black87),
                        title: const Text("थर्मल प्रिंटर कॉन्फ़िगरेशन (Thermal Printer)", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: const Text("58mm / 80mm ब्लूटूथ थर्मल प्रिंटर पेयरिंग"),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("प्रिंटर सेटिंग्स मुख्य POS मेनू या साइडबार से प्रबंधित की जा सकती हैं")),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 3. STORE PROFILE
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    "स्टोर विवरण (STORE PROFILE)",
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
                        Text("लव कुश शॉपिङ्ग सेण्टर (Love Kush Shopping Center)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        SizedBox(height: 4),
                        Text("पता: 8/212, सुभाष नगर, नई दिल्ली - 110027", style: TextStyle(fontSize: 12, color: Colors.black54)),
                        SizedBox(height: 2),
                        Text("सम्पर्क सूत्र: +91 98991 26211 / +91 98112 05211", style: TextStyle(fontSize: 12, color: Colors.black54)),
                        SizedBox(height: 8),
                        Text("Love Kush POS v2.5.0 • Enterprise Edition", style: TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
