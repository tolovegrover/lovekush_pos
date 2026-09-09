import re

main_path = "/home/love/.gemini/antigravity-cli/brain/3fa88d13-ca99-4f6a-8a6d-9bdcf54154a3/minimal_pos_ui.dart"
with open(main_path, "r") as f:
    main_dart = f.read()

main_dart = main_dart.replace('LOVE KUSH\\\\nSHOPPING CENTER', 'LOVE KUSH\\nSHOPPING CENTER')
main_dart = main_dart.replace('to:\\\\n$submittedEmail', 'to:\\n$submittedEmail')

with open(main_path, "w") as f:
    f.write(main_dart)

