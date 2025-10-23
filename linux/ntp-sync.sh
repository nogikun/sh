#!/bin/bash

# プロキシ環境対応NTP時刻同期スクリプト
# HTTP経由で時刻を取得します

set -e

echo "=== プロキシ対応時刻同期スクリプト開始 ==="

# root権限チェック
if [ "$EUID" -ne 0 ]; then
    echo "このスクリプトはroot権限で実行してください"
    exit 1
fi

# 環境変数からプロキシ設定を読み込み
HTTP_PROXY="${http_proxy:-${HTTP_PROXY:-}}"
HTTPS_PROXY="${https_proxy:-${HTTPS_PROXY:-}}"

if [ -n "$HTTP_PROXY" ]; then
    echo "[INFO] HTTPプロキシが設定されています: $HTTP_PROXY"
    export http_proxy="$HTTP_PROXY"
    export HTTP_PROXY="$HTTP_PROXY"
fi

if [ -n "$HTTPS_PROXY" ]; then
    echo "[INFO] HTTPSプロキシが設定されています: $HTTPS_PROXY"
    export https_proxy="$HTTPS_PROXY"
    export HTTPS_PROXY="$HTTPS_PROXY"
fi

# 必要なパッケージのインストール
echo "[1] 必要なパッケージの確認..."
apt update -qq
apt install -y util-linux-extra wget curl 2>/dev/null || true

# 現在の状態を確認
echo "[2] 現在の時刻状態"
timedatectl status

# RTCの状態を判定して修正
echo "[3] RTC状態を判定中..."
RTC_IN_LOCAL=$(timedatectl show --property=LocalRTC --value)

if [ "$RTC_IN_LOCAL" = "yes" ]; then
    echo "RTCはローカルタイム(JST)で管理されています"
    hwclock --hctosys --localtime 2>/dev/null || true
    echo "RTCの時刻をJSTとしてシステムに反映しました"
else
    echo "RTCはUTCで管理されています"
    hwclock --hctosys --utc 2>/dev/null || true
fi

# RTCをUTC基準に設定
echo "[4] RTCをUTC基準に設定..."
timedatectl set-local-rtc 0

# HTTP経由で時刻を取得（複数のタイムサーバーを試行）
echo "[5] HTTP経由で正確な時刻を取得中..."

# NICTの日本標準時を提供するURL
TIME_SERVERS=(
    "https://ntp-a1.nict.go.jp/cgi-bin/json"
    "https://ntp-b1.nict.go.jp/cgi-bin/json"
    "http://www.google.com"
    "http://www.cloudflare.com"
)

GET_TIME=""

for SERVER in "${TIME_SERVERS[@]}"; do
    echo "  試行中: $SERVER"
    
    if [[ "$SERVER" == *"nict.go.jp"* ]]; then
        # NICTのJSON APIを使用
        RESPONSE=$(curl -s --max-time 10 "$SERVER" 2>/dev/null || wget -q -O- --timeout=10 "$SERVER" 2>/dev/null || echo "")
        if [ -n "$RESPONSE" ]; then
            # JSONから時刻を抽出（jqがなくても動作）
            JST_TIME=$(echo "$RESPONSE" | grep -o '"st":[0-9.]*' | cut -d: -f2)
            if [ -n "$JST_TIME" ]; then
                # UNIX時刻を日時形式に変換
                GET_TIME=$(date -d "@${JST_TIME%.*}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "")
                if [ -n "$GET_TIME" ]; then
                    echo "  ✓ NICT日本標準時を取得: $GET_TIME"
                    break
                fi
            fi
        fi
    else
        # HTTPヘッダーのDateフィールドから時刻を取得
        HTTP_DATE=$(curl -sI --max-time 10 "$SERVER" 2>/dev/null | grep -i "^Date:" | cut -d' ' -f2- || echo "")
        if [ -z "$HTTP_DATE" ]; then
            HTTP_DATE=$(wget -S --spider --timeout=10 "$SERVER" 2>&1 | grep -i "Date:" | cut -d' ' -f6- || echo "")
        fi
        
        if [ -n "$HTTP_DATE" ]; then
            # HTTPの日時をシステム形式に変換
            GET_TIME=$(date -d "$HTTP_DATE" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "")
            if [ -n "$GET_TIME" ]; then
                echo "  ✓ HTTPヘッダーから時刻を取得: $GET_TIME"
                break
            fi
        fi
    fi
done

if [ -z "$GET_TIME" ]; then
    echo "[ERROR] すべてのタイムサーバーからの時刻取得に失敗しました"
    echo "プロキシ設定を確認してください:"
    echo "  export http_proxy='http://proxy.example.com:8080'"
    echo "  export https_proxy='http://proxy.example.com:8080'"
    exit 1
fi

# 取得した時刻をシステムに設定
echo "[6] システム時刻を設定中..."
systemctl stop systemd-timesyncd 2>/dev/null || true
timedatectl set-ntp false
date -s "$GET_TIME"
echo "  ✓ システム時刻を設定: $(date)"

# ハードウェアクロックを更新
echo "[7] ハードウェアクロックをUTCで更新..."
hwclock --systohc --utc

# systemd-timesyncdを再起動（同期は期待しない）
echo "[8] systemd-timesyncdを再起動..."
timedatectl set-ntp true
systemctl start systemd-timesyncd 2>/dev/null || true

# 最終確認
echo "[9] 最終確認..."
echo ""
timedatectl status

echo ""
echo "=== 時刻同期完了 ==="
echo "現在時刻: $(date '+%Y年 %m月 %d日 %H:%M:%S %Z')"
echo ""
echo "定期的に時刻を同期するには、このスクリプトをcronに登録してください:"
echo "  sudo crontab -e"
echo "  0 */6 * * * /path/to/ntp-sync.sh > /dev/null 2>&1"
