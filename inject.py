import sys
import lief

if len(sys.argv) < 2:
    print("Usage: python3 inject.py <path_to_macho_binary>")
    sys.exit(1)

exec_path = sys.argv[1]
dylib_path = "@executable_path/Frameworks/NHNZMClient.dylib"

fat = lief.MachO.parse(exec_path)
if fat is None:
    print("Khong the doc file Mach-O:", exec_path)
    sys.exit(1)

for binary in fat:
    if binary.has_code_signature:
        binary.remove_signature()
    if not any(lib.name == dylib_path for lib in binary.libraries):
        binary.add_library(dylib_path)

fat.write(exec_path)
print("Da nhung thanh cong:", dylib_path)
