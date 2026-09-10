import re

with open("lib/main.dart", "r") as f:
    content = f.read()

# 1. Add counterName variable and _loadCounterName method
init_code = """  int focusedField = 0; 
  String counterName = "Basement Counter";

  @override
  void initState() {
    super.initState();
    _loadCounterName();
  }

  void _loadCounterName() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        counterName = prefs.getString('counterName') ?? "Basement Counter";
      });
    }
  }

  void _changeCounterName() {
    TextEditingController ctrl = TextEditingController(text: counterName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Change Counter Name"),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: "Counter Name (e.g. Ground Floor)"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Colors.black54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
            onPressed: () async {
              if (ctrl.text.trim().isNotEmpty) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('counterName', ctrl.text.trim());
                setState(() => counterName = ctrl.text.trim());
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text("SAVE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ]
      )
    );
  }"""

content = content.replace("  int focusedField = 0; ", init_code)


# 2. Add ListTile in Drawer
old_drawer = """            ListTile(
              leading: const Icon(Icons.qr_code_2),
              title: const Text('Generate QR Labels'),"""

new_drawer = """            ListTile(
              leading: const Icon(Icons.storefront),
              title: const Text('Change Counter Name'),
              onTap: () {
                Navigator.pop(context);
                _changeCounterName();
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_2),
              title: const Text('Generate QR Labels'),"""

content = content.replace(old_drawer, new_drawer)


# 3. Use counterName in print preview
old_preview = """                      const Text("LOVE KUSH SHOPPING CENTER", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      const Text("Basement Counter", style: TextStyle(fontSize: 16, color: Colors.black54)),"""

new_preview = """                      const Text("LOVE KUSH SHOPPING CENTER", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text(counterName.toUpperCase(), style: const TextStyle(fontSize: 16, color: Colors.black54, fontWeight: FontWeight.bold)),"""

content = content.replace(old_preview, new_preview)

with open("lib/main.dart", "w") as f:
    f.write(content)
