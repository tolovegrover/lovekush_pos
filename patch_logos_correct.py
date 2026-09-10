import re

with open("lib/main.dart", "r") as f:
    content = f.read()

# Fix 1: Add B&W logo to Print Preview
old_preview = """                    children: [
                      const Text("लव कुश शॉपिङ्ग सेण्टर", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),"""

new_preview = """                    children: [
                      Image.asset('assets/logo_bw.jpg', height: 100),
                      const SizedBox(height: 16),
                      const Text("लव कुश शॉपिङ्ग सेण्टर", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),"""

if old_preview in content:
    content = content.replace(old_preview, new_preview)
else:
    print("WARNING: Could not find print preview string")

# Fix 2: Add Color Logo to Drawer
old_drawer = """            DrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF111827)), 
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Icon(Icons.storefront, color: Colors.white, size: 40),
                  const SizedBox(height: 12),
                  const Text('लव कुश शॉपिङ्ग सेण्टर', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  Text(widget.userName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                  Text(widget.userEmail, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),"""

new_drawer = """            DrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF111827)), 
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
                  Text(widget.userName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                  Text(widget.userEmail, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),"""

if old_drawer in content:
    content = content.replace(old_drawer, new_drawer)
else:
    print("WARNING: Could not find drawer string")

with open("lib/main.dart", "w") as f:
    f.write(content)
