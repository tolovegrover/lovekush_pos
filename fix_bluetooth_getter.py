import re

with open("lib/main.dart", "r") as f:
    content = f.read()

old_code = "List<BluetoothDevice> devices = await bluetooth.getBluetooths ?? [];"
new_code = "List<BluetoothDevice> devices = await bluetooth.getBondedDevices();"

content = content.replace(old_code, new_code)

with open("lib/main.dart", "w") as f:
    f.write(content)
