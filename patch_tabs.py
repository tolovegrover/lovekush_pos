import re

with open("lib/main.dart", "r") as f:
    content = f.read()

# Add _deleteTab method
delete_tab_code = """
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

content = content.replace("  @override\n  Widget build(BuildContext context) {", delete_tab_code)

# Wrap ChoiceChip with GestureDetector
old_chip = """                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip("""
new_chip = """                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: GestureDetector(
                    onLongPress: () => _deleteTab(index),
                    child: ChoiceChip("""
content = content.replace(old_chip, new_chip)

# close the parenthesis for GestureDetector
old_chip_end = """                    selectedColor: Colors.black,
                    labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87),
                  ),
                );"""
new_chip_end = """                    selectedColor: Colors.black,
                    labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87),
                  ),
                  ),
                );"""
content = content.replace(old_chip_end, new_chip_end)

with open("lib/main.dart", "w") as f:
    f.write(content)
