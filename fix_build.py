import re

with open("lib/main.dart", "r") as f:
    content = f.read()

# The injected code looks like this:
injected_code = """
  void _deleteTab(int index) {
    if (activeBills.length <= 1) {
      setState(() => activeBills[0].clear());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cleared the active bill.")));
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Customer Bill?"),
        content: Text("Are you sure you want to permanently delete Bill ${index + 1}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Colors.black54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              setState(() {
                activeBills.removeAt(index);
                if (currentBillIndex >= activeBills.length) {
                  currentBillIndex = activeBills.length - 1;
                } else if (currentBillIndex > index) {
                  currentBillIndex--;
                }
              });
              Navigator.pop(context);
            },
            child: const Text("DELETE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ]
      )
    );
  }

  @override
"""

# Remove ALL instances
content = content.replace(injected_code, "  @override\n")

# Add it BACK specifically into _PosScreenState right before confirmPrint
old_confirm = "  void confirmPrint() {"
new_confirm = injected_code.replace("  @override\n", "") + "\n  void confirmPrint() {"

content = content.replace(old_confirm, new_confirm)

with open("lib/main.dart", "w") as f:
    f.write(content)
