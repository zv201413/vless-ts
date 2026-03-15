#!/bin/bash

# --- 1. 基础配置 ---
WORK_DIR="/home/zv/vless-all"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
# UUID 动态获取：优先使用环境变量，否则随机生成
USER_UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}

# --- 2. 卸载功能 ---
if [ "$1" = "uninstall" ]; then
    echo "正在彻底卸载服务..."
    pkill -f xray
    pkill -f cloudflared
    cd /home/zv && rm -rf "$WORK_DIR"
    echo "卸载完成！所有进程已停止，目录已删除。"
    exit 0
fi

# --- 3. 环境准备 ---
echo "检查运行环境..."
[ -f "cloudflared" ] || { echo "下载 Argo..."; curl -L -o cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 && chmod +x cloudflared; }
[ -f "xray" ] || { echo "下载 Xray..."; curl -L -o xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip && unzip -o xray.zip && chmod +x xray; }
chmod +x cloudflared xray

# --- 4. WARP 密钥与策略构建 ---
OUTBOUNDS_JSON='{ "protocol": "freedom", "tag": "direct", "settings": { "domainStrategy": "UseIP" } }'
ROUTING_RULE='{ "type": "field", "outboundTag": "direct", "network": "tcp,udp" }'

if [ "$warp" = "y" ]; then
    if [ -n "$MY_WARP_DATA" ]; then
        echo "检测到环境变量 MY_WARP_DATA，正在解析..."
        warp_raw="$MY_WARP_DATA"
    else
        echo "正在尝试从云端获取 WARP 密钥..."
        warp_raw=$(curl -sL -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" "https://warp.xijp.eu.org")
    fi
    
    if echo "$warp_raw" | grep -qE "Private_key|私钥"; then
        pvk=$(echo "$warp_raw" | grep -E "Private_key|私钥" | awk -F'[：:]' '{print $2}' | tr -d ' \r')
        wpv6=$(echo "$warp_raw" | grep -E "IPV6|地址" | awk -F'[：:]' '{print $2}' | tr -d ' \r')
        res=$(echo "$warp_raw" | grep -E "reserved|值" | awk -F'[：:]' '{print $2}' | tr -d '[] \r')
        [ -z "$pvk" ] && pvk=$(echo "$warp_raw" | grep -oE '[A-Za-z0-9+/]{43}=' | head -n 1)
    else
        pvk='sBbO/ohZrLRoSFRaQCciqyiRFHwbxZ88nlDO5vNmD2I='
        wpv6='2606:4700:110:8515:e070:6396:54b0:15ba'
        res='0, 0, 0'
    fi

    OUTBOUNDS_JSON='
    {
      "tag": "x-warp-out",
      "protocol": "wireguard",
      "settings": {
        "secretKey": "'$pvk'",
        "address": ["172.16.0.2/32", "'$wpv6'/128"],
        "peers": [{
          "publicKey": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
          "endpoint": "162.159.192.1:2408" 
        }],
        "reserved": ['$res'],
        "mtu": 1280
      }
    },
    {
      "tag": "warp-out",
      "protocol": "freedom",
      "settings": { "domainStrategy": "ForceIPv6v4" },
      "proxySettings": { "tag": "x-warp-out" }
    },
    { "tag": "direct", "protocol": "freedom", "settings": { "domainStrategy": "UseIPv4" } }'
    
    ROUTING_RULE='{ "type": "field", "outboundTag": "warp-out", "network": "tcp,udp" }'
fi

# --- 5. 生成配置文件 ---
cat << JSON > config.json
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": 8003,
    "listen": "0.0.0.0",
    "protocol": "vless",
    "settings": {
      "clients": [{"id": "$USER_UUID"}],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "ws",
      "wsSettings": { "path": "/ws" }
    }
  }],
  "outbounds": [$OUTBOUNDS_JSON],
  "routing": { "domainStrategy": "IPOnDemand", "rules": [$ROUTING_RULE] }
}
JSON

# --- 6. 启动服务 ---
pkill -f xray
pkill -f cloudflared
rm -f argo.log && touch argo.log
nohup ./xray -c config.json > xray.log 2>&1 &
nohup ./cloudflared tunnel --url http://localhost:8003 --no-autoupdate > argo.log 2>&1 &

# --- 7. 获取域名与自动标签命名 ---
echo "正在分配域名并检测地理位置..."
DOMAIN=""
for i in {1..15}; do
    sleep 2
    [ -f "argo.log" ] && DOMAIN=$(grep -oE 'https://[a-z0-9.-]+\.trycloudflare\.com' argo.log | tail -n 1 | sed 's/https:\/\///')
    [ -n "$DOMAIN" ] && break
    echo -n "."
done

# 自动获取国家代码 (例如 US, HK)
COUNTRY=$(curl -s https://ipapi.co/country_code/ || echo "Unknown")

# 拼接备注标签
REMARK="Argo"
[ "$warp" = "y" ] && REMARK="${REMARK}-WARP"
REMARK="${REMARK}-${COUNTRY}"

if [ -n "$DOMAIN" ]; then
    ADDRESS=$DOMAIN
    PORT_LINK=443
    SEC="tls"
else
    ADDRESS=$(curl -s4 icanhazip.com)
    PORT_LINK=8003
    SEC="none"
fi

echo -e "\n--- 部署成功 ---"
echo "UUID: $USER_UUID"
echo "节点链接 (点击复制)："
echo "vless://$USER_UUID@$ADDRESS:$PORT_LINK?encryption=none&security=$SEC&sni=$ADDRESS&type=ws&host=$ADDRESS&path=%2Fws#$REMARK"
