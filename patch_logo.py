import re

with open("lib/main.dart", "r") as f:
    content = f.read()

# 1. Login Screen Logo
old_login_header = """            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.black, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)]),
              child: const Icon(Icons.storefront, size: 80, color: Colors.white),
            ),
            const SizedBox(height: 24),
            const Text("लव कुश शॉपिङ्ग सेण्टर", textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 2, height: 1.2)),
            const SizedBox(height: 8),
            const Text("Point of Sale", style: TextStyle(fontSize: 16, color: Colors.black54, letterSpacing: 4, fontWeight: FontWeight.bold)),"""

new_login_header = """            Container(
              height: 200,
              width: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 10))],
                image: const DecorationImage(image: AssetImage('assets/logo.jpg'), fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 24),
            const Text("लव कुश शॉपिङ्ग सेण्टर", textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 2, height: 1.2)),
            const SizedBox(height: 8),
            const Text("Point of Sale", style: TextStyle(fontSize: 16, color: Colors.black54, letterSpacing: 4, fontWeight: FontWeight.bold)),"""

content = content.replace(old_login_header, new_login_header)

# 2. Drawer Header Logo
old_drawer_header = """          DrawerHeader(
            decoration: const BoxDecoration(color: Colors.black),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(Icons.storefront, color: Colors.white, size: 48),
                const SizedBox(height: 16),
                const Text('लव कुश शॉपिङ्ग सेण्टर', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                Text(widget.userName, style: const TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),"""

new_drawer_header = """          DrawerHeader(
            decoration: const BoxDecoration(color: Colors.black),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Row(
                  children: [
                    Container(
                      height: 50,
                      width: 50,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        image: DecorationImage(image: AssetImage('assets/logo.jpg'), fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(child: Text('लव कुश शॉपिङ्ग सेण्टर', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5))),
                  ],
                ),
                const SizedBox(height: 16),
                Text(widget.userName, style: const TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),"""

content = content.replace(old_drawer_header, new_drawer_header)

with open("lib/main.dart", "w") as f:
    f.write(content)
