#!/bin/bash

# --- 1. 基础配置 ---
WORK_DIR="/home/zv/vless-all"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
# UUID 动态获取：优先使用环境变量，否则随机生成
USER_UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "8e6290c1-b97e-40c0-b9a3-7e7ed11ce248")}

# --- 2. 卸载功能 ---
if [ "$1" = "uninstall" ]; then
    echo "正在彻底卸载服务..."
    pkill -f xray
    pkill -f cloudflared
    cd /home/zv && rm -rf "$WORK_DIR"
    echo "卸载完成！"
    exit 0
fi

# --- 3. 环境准备 ---
echo "检查运行环境..."
[ -f "cloudflared" ] || { echo "下载 Argo..."; curl -L -o cloudflared https://github.com/cloudflare/cloudflare-linux-amd64 && chmod +x cloudflared; }
[ -f "xray" ] || { echo "下载 Xray..."; curl -L -o xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip && unzip -o xray.zip && chmod +x xray; }
chmod +x cloudflared xray

# --- 4. WARP 密钥与策略构建 ---
OUTBOUNDS_JSON='{ "protocol": "freedom", "tag": "direct", "settings": { "domainStrategy": "UseIP" } }'
ROUTING_RULE='{ "type": "field", "outboundTag": "direct", "network": "tcp,udp" }'

if [ "$warp" = "y" ]; then
    if [ -n "$MY_WARP_DATA" ]; then
        echo "检测到环境变量 MY_WARP_DATA，正在解析注入的内容..."
        warp_raw="$MY_WARP_DATA"
    else
        echo "正在尝试从云端获取 WARP 密钥..."
        # --- 核心修改：应用更强的浏览器伪装 ---
        warp_raw=$(curl -sL -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36" "https://warp.xijp.eu.org")
    fi
    
    # 增强解析逻辑
    if echo "$warp_raw" | grep -qE "Private_key|私钥"; then
        pvk=$(echo "$warp_raw" | grep -E "Private_key|私钥" | awk -F'[：:]' '{print $2}' | tr -d ' \r')
        wpv6=$(echo "$warp_raw" | grep -E "IPV6|地址" | awk -F'[：:]' '{print $2}' | tr -d ' \r')
        res=$(echo "$warp_raw" | grep -E "reserved|值" | awk -F'[：:]' '{print $2}' | tr -d '[] \r')
        
        # 兜底正则匹配（防止网页格式微调）
        [ -z "$pvk" ] && pvk=$(echo "$warp_raw" | grep -oE '[A-Za-z0-9+/]{43}=' | head -n 1)
        echo "WARP 参数提取成功"
    else
        echo "自动提取失败（可能触发了五秒盾），应用指定的兜底配置..."
        # 注意：如果自动获取失败，建议使用本地复制网页内容后 export MY_WARP_DATA="..." 运行
        pvk='sBbO/ohZrLRoSFRaQCciqyiRFHwbxZ88nlDO5vNmD2I='
        wpv6='2606:4700:110:8515:e070:6396:54b0:15ba'
        res='0, 0, 0'
    fi

    # 构建 V6 优先的 WARP 出站
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

# --- 5. 生成 Xray 配置文件 ---
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
    },
    "sniffing": {
      "enabled": true,
      "destOverride": ["http", "tls", "quic"]
    }
  }],
  "outbounds": [$OUTBOUNDS_JSON],
  "routing": {
    "domainStrategy": "IPOnDemand",
    "rules": [$ROUTING_RULE]
  }
}
JSON

# --- 6. 启动进程 ---
echo "正在重启服务..."
pkill -f xray
pkill -f cloudflared
rm -f argo.log && touch argo.log

nohup ./xray -c config.json > xray.log 2>&1 &
nohup ./cloudflared tunnel --url http://localhost:8003 --no-autoupdate > argo.log 2>&1 &

# --- 7. 获取域名与自动标签命名 (借鉴 sv66 接口逻辑) ---
echo "正在分配域名并检测地理位置..."
DOMAIN=""
for i in {1..15}; do
    sleep 2
    [ -f "argo.log" ] && DOMAIN=$(grep -oE 'https://[a-z0-9.-]+\.trycloudflare\.com' argo.log | tail -n 1 | sed 's/https:\/\///')
    [ -n "$DOMAIN" ] && break
    echo -n "."
done

# 获取服务器 IP
SERVER_IP=$(curl -s4 icanhazip.com || curl -s4 ifconfig.me)
# 借鉴思路：使用 line 接口并只取 countryCode，防止报错
COUNTRY=$(curl -s -m 5 "http://ip-api.com/line/$SERVER_IP?fields=countryCode" | tr -d '\n\r')

# 状态自检：如果获取地理位置失败
[ -z "$COUNTRY" ] || [[ "$COUNTRY" == *" "* ]] && COUNTRY="Unknown"

# 拼接备注标签
REMARK="Argo"
[ "$warp" = "y" ] && REMARK="${REMARK}-WARP"
REMARK="${REMARK}-${COUNTRY}"

if [ -n "$DOMAIN" ]; then
    ADDRESS=$DOMAIN
    PORT_LINK=443
    SEC="tls"
else
    ADDRESS=$SERVER_IP
    PORT_LINK=8003
    SEC="none"
fi

echo -e "\n--- 部署成功 ---"
echo "UUID: $USER_UUID"
echo "节点链接 (点击复制)："
echo "vless://$USER_UUID@$ADDRESS:$PORT_LINK?encryption=none&security=$SEC&sni=$ADDRESS&type=ws&host=$ADDRESS&path=%2Fws#$REMARK"
