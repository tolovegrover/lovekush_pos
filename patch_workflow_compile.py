with open(".github/workflows/build-apk.yml", "r") as f:
    content = f.read()

old_run = """      - name: Patch blue_thermal_printer namespace
        run: |
          find /home/runner/.pub-cache/hosted/pub.dev/blue_thermal_printer-*/android -name build.gradle -exec sed -i '/android {/a \    namespace "id.kakzaki.blue_thermal_printer"' {} +"""

new_run = """      - name: Patch blue_thermal_printer namespace and compileSdk
        run: |
          find /home/runner/.pub-cache/hosted/pub.dev/blue_thermal_printer-*/android -name build.gradle -exec sed -i '/android {/a \    namespace "id.kakzaki.blue_thermal_printer"' {} +
          find /home/runner/.pub-cache/hosted/pub.dev/blue_thermal_printer-*/android -name build.gradle -exec sed -i 's/compileSdkVersion [0-9]*/compileSdkVersion 34/g' {} +
          find /home/runner/.pub-cache/hosted/pub.dev/blue_thermal_printer-*/android -name build.gradle -exec sed -i 's/targetSdkVersion [0-9]*/targetSdkVersion 34/g' {} +"""

content = content.replace(old_run, new_run)

with open(".github/workflows/build-apk.yml", "w") as f:
    f.write(content)
