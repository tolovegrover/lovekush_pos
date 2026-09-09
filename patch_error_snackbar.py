import re

with open("lib/main.dart", "r") as f:
    content = f.read()

content = re.sub(
    r'catch \(e\) \{\s*debugPrint\("Firebase Link Error: \$e"\);\s*\}',
    """catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Firebase Error: $e"), 
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 10),
      ));
    }""",
    content
)

with open("lib/main.dart", "w") as f:
    f.write(content)
