#!/usr/bin/env bash
set -e

if [ ! -f "BlockBlast.ipa" ]; then
    echo "LOI: Hay copy file BlockBlast.ipa (ban da giai ma / decrypted) vao cung thu muc nay!"
    exit 1
fi

export THEOS="${THEOS:-$HOME/theos}"
if [ ! -d "$THEOS" ]; then
    echo "LOI: Chua cai Theos. Hay chay lenh cai Theos trong HUONG_DAN.txt truoc."
    exit 1
fi

echo "[1/4] Dang bien dich NHNZMClient.dylib (ARM64)..."
make clean && make FINALPACKAGE=1
DYLIB=$(find .theos/obj -name "NHNZMClient.dylib" | head -n 1)

if [ -z "$DYLIB" ]; then
    echo "LOI: Khong tim thay NHNZMClient.dylib sau khi bien dich."
    exit 1
fi

echo "[2/4] Dang giai nen BlockBlast.ipa..."
rm -rf unpacked NHNZM_BlockBlast.ipa
unzip -q BlockBlast.ipa -d unpacked
APP_DIR=$(find unpacked/Payload -maxdepth 1 -name "*.app" | head -n 1)
EXEC_NAME=$(python3 -c "import plistlib, sys; print(plistlib.load(open(sys.argv[1], 'rb'))['CFBundleExecutable'])" "$APP_DIR/Info.plist")

echo "[3/4] Dang nhung NHNZMClient.dylib vao $EXEC_NAME..."
mkdir -p "$APP_DIR/Frameworks"
cp "$DYLIB" "$APP_DIR/Frameworks/NHNZMClient.dylib"
python3 inject.py "$APP_DIR/$EXEC_NAME"

echo "[4/4] Dang nen lai thanh NHNZM_BlockBlast.ipa..."
(cd unpacked && zip -qr ../NHNZM_BlockBlast.ipa Payload)
rm -rf unpacked

echo "=========================================="
echo "HOAN TAT! File thanh pham: NHNZM_BlockBlast.ipa"
echo "Copy file nay len iPhone va cai bang ESign/Feather/Sideloadly."
echo "=========================================="
