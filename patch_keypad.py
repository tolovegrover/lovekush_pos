with open("lib/main.dart", "r") as f:
    content = f.read()

old_keypad = """                      _buildKeypadRow([_key("7", "G"), _key("8", "H"), _key("9", "I"), _actionKey("ENTER", const Color(0xFF3B82F6), flex: 1, isEnter: true)]),
                      _buildKeypadRow([_key(".", ""), _key("0", ""), _actionKey("📷 SCAN", Colors.black, isScan: true)]),"""

new_keypad = """                      _buildKeypadRow([_key("7", "G"), _key("8", "H"), _key("9", "I"), _key("00", "")]),
                      _buildKeypadRow([_actionKey("📷 SCAN", Colors.black, isScan: true), _key("0", ""), _key(".", ""), _actionKey("ENTER", const Color(0xFF3B82F6), isEnter: true)]),"""

content = content.replace(old_keypad, new_keypad)

with open("lib/main.dart", "w") as f:
    f.write(content)
