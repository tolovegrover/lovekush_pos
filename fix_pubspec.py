with open("pubspec.yaml", "r") as f:
    lines = f.readlines()

new_lines = []
skip = False
for i, line in enumerate(lines):
    if line.startswith("flutter:") and i > 60:
        skip = True
        continue
    if skip:
        if line.startswith("  assets:") or "- assets/logo.jpg" in line or "- assets/logo_bw.jpg" in line:
            continue
        else:
            skip = False
    new_lines.append(line)

# Now inject the assets under the first flutter block
flutter_idx = -1
for i, line in enumerate(new_lines):
    if line.startswith("flutter:"):
        flutter_idx = i
        break

if flutter_idx != -1:
    new_lines.insert(flutter_idx + 1, "  assets:\n    - assets/logo.jpg\n    - assets/logo_bw.jpg\n")

with open("pubspec.yaml", "w") as f:
    f.writelines(new_lines)
