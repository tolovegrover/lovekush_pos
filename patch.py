import re

with open("lib/main.dart", "r") as f:
    content = f.read()

# 1. Update State variables
content = content.replace(
    "List<Map<String, dynamic>> cart = [];",
    "List<List<Map<String, dynamic>>> activeBills = [[]];\n  int currentBillIndex = 0;\n  List<Map<String, dynamic>> get cart => activeBills[currentBillIndex];"
)

# 2. Update confirmPrint
old_confirm = """  void confirmPrint() {
    setState(() {
      cart.clear();
      rawItemCode = "";
      qty = "1";
      rate = "";
      focusedField = 0;
      isPreviewingBill = false;
    });
  }"""
new_confirm = """  void confirmPrint() {
    setState(() {
      cart.clear();
      if (activeBills.length > 1) {
        activeBills.removeAt(currentBillIndex);
        currentBillIndex = currentBillIndex > 0 ? currentBillIndex - 1 : 0;
      }
      rawItemCode = "";
      qty = "1";
      rate = "";
      focusedField = 0;
      isPreviewingBill = false;
    });
  }"""
content = content.replace(old_confirm, new_confirm)

# 3. Add Tabs UI
old_body = """      body: Column(
        children: [
          Expanded("""
new_body = """      body: Column(
        children: [
          Container(
            height: 55,
            color: Colors.white,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: activeBills.length + 1,
              itemBuilder: (context, index) {
                if (index == activeBills.length) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: ActionChip(
                      backgroundColor: Colors.green.shade50,
                      side: BorderSide(color: Colors.green),
                      label: const Text("+ New Customer", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                      onPressed: () {
                        setState(() {
                          activeBills.add([]);
                          currentBillIndex = activeBills.length - 1;
                        });
                      }
                    ),
                  );
                }
                bool isSelected = index == currentBillIndex;
                int itemCount = activeBills[index].length;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text("Bill ${index + 1} ($itemCount items)", style: TextStyle(fontWeight: FontWeight.bold)),
                    selected: isSelected,
                    showCheckmark: false,
                    onSelected: (bool selected) {
                      if (selected) setState(() => currentBillIndex = index);
                    },
                    selectedColor: Colors.black,
                    labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87),
                  ),
                );
              },
            ),
          ),
          Expanded("""
content = content.replace(old_body, new_body)

with open("lib/main.dart", "w") as f:
    f.write(content)
