with open(".github/workflows/build-apk.yml", "r") as f:
    content = f.read()

old_run = """      - run: flutter pub get
      - run: flutter build apk --release"""

new_run = """      - run: flutter pub get
      - name: Patch blue_thermal_printer namespace
        run: |
          find /home/runner/.pub-cache/hosted/pub.dev/blue_thermal_printer-*/android -name build.gradle -exec sed -i '/android {/a \    namespace "id.kakzaki.blue_thermal_printer"' {} +
      - run: flutter build apk --release"""

content = content.replace(old_run, new_run)

with open(".github/workflows/build-apk.yml", "w") as f:
    f.write(content)
