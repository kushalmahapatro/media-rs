# Fix the ISS file paths — remove extra backslashes
path = r"C:\Users\kusha\Documents\Projects\media-rs\media_flutter\example\build\windows-x86_64-installer.iss"
with open(path, "r") as f:
    content = f.read()

# Fix double backslashes
content = content.replace("\\\\", "\\")
# Fix the empty quote lines
content = content.replace('""', "")
# Fix extra spaces after lines
lines = [line.rstrip() for line in content.split("\n")]
content = "\n".join(lines)

with open(path, "w") as f:
    f.write(content)

print("Fixed!")
