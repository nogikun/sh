#!/bin/bash
# dvd_to_iso.sh - macOS用 DVDをISOイメージとしてバックアップするスクリプト
# -------------------------------------------------------------

# 設定
OUTPUT_DIR="$HOME/Desktop/DVD_ISOs"
mkdir -p "$OUTPUT_DIR"

# DVDボリュームを検出（CSJを含むもの優先、なければ他のボリューム）
DVD_PATH=$(ls /Volumes/ | grep -v "Macintosh HD" | grep CSJ | head -n 1)

if [ -z "$DVD_PATH" ]; then
    echo "❌ エラー: DVDが見つかりません"
    exit 1
fi

# --------------------------------------------



echo "💿 DVDを発見: /Volumes/$DVD_PATH"

# 出力ファイル名
DVD_NAME=$(echo "$DVD_PATH" | sed 's/[^a-zA-Z0-9_-]/_/g')
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="$OUTPUT_DIR/${DVD_NAME}_${TIMESTAMP}.iso"

# デバイス名を取得
DEVICE=$(diskutil info "/Volumes/$DVD_PATH" | grep "Device Node" | awk '{print $3}')

echo "📀 デバイス: $DEVICE"
echo "📦 ISO作成中...（数分〜数十分かかります）"

# raw読み取りでISOを作成
sudo hdiutil create -srcdevice "$DEVICE" -format UDTO -o "$OUTPUT_FILE" -verbose

if [ $? -ne 0 ]; then
    echo "❌ エラー: ISO作成に失敗しました"
    exit 1
fi

# UDTOは.cdrになるので、拡張子を.isoに変更
mv "${OUTPUT_FILE}.cdr" "$OUTPUT_FILE"

# DVDをイジェクト
diskutil eject "$DEVICE" > /dev/null 2>&1

echo "✅ 完了: $OUTPUT_FILE"