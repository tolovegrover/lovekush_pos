with open("/home/love/.gemini/antigravity-cli/brain/3fa88d13-ca99-4f6a-8a6d-9bdcf54154a3/minimal_pos_ui.dart", "r") as f:
    content = f.read()

old_keypad = """                      _buildKeypadRow([_key("7", "G"), _key("8", "H"), _key("9", "I"), _actionKey("ENTER", const Color(0xFF3B82F6), flex: 1, isEnter: true)]),
                      _buildKeypadRow([_key(".", ""), _key("0", ""), _actionKey("📷 SCAN", Colors.black, isScan: true)]),"""

new_keypad = """                      _buildKeypadRow([_key("7", "G"), _key("8", "H"), _key("9", "I"), _key("00", "")]),
                      _buildKeypadRow([_actionKey("📷 SCAN", Colors.black, isScan: true), _key("0", ""), _key(".", ""), _actionKey("ENTER", const Color(0xFF3B82F6), isEnter: true)]),"""

content = content.replace(old_keypad, new_keypad)

with open("/home/love/.gemini/antigravity-cli/brain/3fa88d13-ca99-4f6a-8a6d-9bdcf54154a3/minimal_pos_ui.dart", "w") as f:
    f.write(content)
