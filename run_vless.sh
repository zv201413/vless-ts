#!/bin/bash

# --- 1. 基础配置 ---
WORK_DIR="/home/zv/vless-all"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
# UUID 动态获取
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
[ -f "cloudflared" ] || { echo "下载 Argo..."; curl -L -o cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 && chmod +x cloudflared; }
[ -f "xray" ] || { echo "下载 Xray..."; curl -L -o xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip && unzip -o xray.zip && chmod +x xray; }
chmod +x cloudflared xray

# --- 4. WARP 密钥获取 (借鉴 argosbx 核心逻辑) ---
OUTBOUNDS_JSON='{ "protocol": "freedom", "tag": "direct", "settings": { "domainStrategy": "UseIP" } }'
ROUTING_RULE='{ "type": "field", "outboundTag": "direct", "network": "tcp,udp" }'

if [ "$warp" = "y" ]; then
    if [ -n "$MY_WARP_DATA" ]; then
        echo "检测到环境变量 MY_WARP_DATA，优先解析注入内容..."
        warp_raw="$MY_WARP_DATA"
    else
        echo "正在尝试使用 argosbx 兼容模式获取 WARP 密钥..."
        warp_url="https://warp.xijp.eu.org"
        
        # 借鉴 argosbx：增加 -k 参数忽略证书验证，并增加 wget 作为备选，处理某些环境下的 curl 证书库问题
        warp_raw=$(curl -s4m5 -k "$warp_url" 2>/dev/null || wget -qO- --tries=2 "$warp_url" 2>/dev/null)
    fi
    
    # 统一提取逻辑 (兼容 argosbx 的文本处理方式)
    if echo "$warp_raw" | grep -qE "私钥|Private_key"; then
        # 提取私钥 (w_key)
        pvk=$(echo "$warp_raw" | grep -E "私钥|Private_key" | awk -F '[：:]' '{print $2}' | tr -d ' \r')
        # 提取 IPV6 地址 (w_v6)
        wpv6=$(echo "$warp_raw" | grep -E "IPV6|地址" | awk -F '[：:]' '{print $2}' | tr -d ' \r')
        # 提取 Reserved 值 (w_res)
        res=$(echo "$warp_raw" | grep -E "reserved|值" | awk -F '[：:]' '{print $2}' | tr -d '[] \r')
        
        # 再次确认关键变量是否拿到
        [ -z "$pvk" ] && pvk=$(echo "$warp_raw" | grep -oE '[A-Za-z0-9+/]{43}=' | head -n 1)
        echo "✅ WARP 密钥获取成功"
    else
        echo "⚠️  网络直接获取失败，应用指定的兜底配置..."
        pvk='sBbO/ohZrLRoSFRaQCciqyiRFHwbxZ88nlDO5vNmD2I='
        wpv6='2606:4700:110:8515:e070:6396:54b0:15ba'
        res='0, 0, 0'
    fi

    # 构建出站
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

# --- 5. 生成 Xray 配置 ---
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

# --- 7. 获取域名与地理位置 (借鉴 sv66 纯文本思路) ---
echo "正在分配域名并检测地理位置..."
DOMAIN=""
for i in {1..15}; do
    sleep 2
    [ -f "argo.log" ] && DOMAIN=$(grep -oE 'https://[a-z0-9.-]+\.trycloudflare\.com' argo.log | tail -n 1 | sed 's/https:\/\///')
    [ -n "$DOMAIN" ] && break
    echo -n "."
done

SERVER_IP=$(curl -s4 icanhazip.com || curl -s4 ifconfig.me)
COUNTRY=$(curl -s -m 5 "http://ip-api.com/line/$SERVER_IP?fields=countryCode" | tr -d '\n\r')
[ -z "$COUNTRY" ] || [[ "$COUNTRY" == *" "* ]] && COUNTRY="Unknown"

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
