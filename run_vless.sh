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

# --- 3. 环境准备与文件清理 ---
echo "清理旧文件并准备运行环境..."
# 删除不需要的文档、压缩包和旧日志
rm -f xray.zip README.md LICENSE *.log 2>/dev/null

[ -f "cloudflared" ] || { echo "下载 Argo..."; curl -L -o cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 && chmod +x cloudflared; }
[ -f "xray" ] || { echo "下载 Xray..."; curl -L -o xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip && unzip -o xray.zip && chmod +x xray; }

# 【新增】安装完成后立即删除解压产生的多余文件
rm -f xray.zip README.md LICENSE 2>/dev/null
chmod +x cloudflared xray

# --- 4. WARP 密钥获取 (借鉴 argosbx 绕过盾的思路) ---
OUTBOUNDS_JSON='{ "protocol": "freedom", "tag": "direct", "settings": { "domainStrategy": "UseIP" } }'
ROUTING_RULE='{ "type": "field", "outboundTag": "direct", "network": "tcp,udp" }'

if [ "$warp" = "y" ]; then
    if [ -n "$MY_WARP_DATA" ]; then
        echo "检测到环境变量 MY_WARP_DATA，优先解析注入内容..."
        warp_raw="$MY_WARP_DATA"
    else
        echo "正在尝试以 argosbx 模式获取 WARP 密钥..."
        warp_url="https://warp.xijp.eu.org"
        # 借鉴 argosbx：使用 -k 忽略证书，并增加 wget 互补，绕过较弱的 WAF 拦截
        warp_raw=$(curl -s4m5 -k "$warp_url" 2>/dev/null || wget -qO- --tries=2 "$warp_url" 2>/dev/null)
    fi
    
    if echo "$warp_raw" | grep -qE "私钥|Private_key"; then
        pvk=$(echo "$warp_raw" | grep -E "私钥|Private_key" | awk -F '[：:]' '{print $2}' | tr -d ' \r')
        wpv6=$(echo "$warp_raw" | grep -E "IPV6|地址" | awk -F '[：:]' '{print $2}' | tr -d ' \r')
        res=$(echo "$warp_raw" | grep -E "reserved|值" | awk -F '[：:]' '{print $2}' | tr -d '[] \r')
        [ -z "$pvk" ] && pvk=$(echo "$warp_raw" | grep -oE '[A-Za-z0-9+/]{43}=' | head -n 1)
        echo "✅ WARP 密钥获取成功"
    else
        echo "⚠️ 自动获取失败，应用指定的兜底配置..."
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

# --- 6. 启动进程 ---
echo "正在重启服务..."
pkill -f xray
pkill -f cloudflared
rm -f argo.log && touch argo.log

nohup ./xray -c config.json > xray.log 2>&1 &
nohup ./cloudflared tunnel --url http://localhost:8003 --no-autoupdate > argo.log 2>&1 &

# --- 7. 获取域名与地理位置 (基于 IP 纯文本接口) ---
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
