#!/bin/bash

# --- 1. 环境准备 ---
WORK_DIR="/home/zv/vless-all"
mkdir -p $WORK_DIR
cd $WORK_DIR

# --- 2. 自动下载 cloudflared (新增逻辑) ---
if [ ! -f "cloudflared" ]; then
    echo "正在下载 cloudflared..."
    curl -L -o cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
    chmod +x cloudflared
fi

# 启动临时隧道 (如果没在跑的话)
if ! pgrep -f cloudflared >/dev/null; then
    echo "正在启动 Argo 隧道..."
    nohup ./cloudflared tunnel --url http://localhost:8003 --no-autoupdate > argo.log 2>&1 &
    sleep 5 # 等待隧道分配域名
fi

# --- 3. 下载 Xray ---
if [ ! -f "xray" ]; then
    curl -L -o xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
    unzip -o xray.zip && chmod +x xray
fi

# --- 4. WARP 注册 (改进了提取方式，不依赖 jq) ---
if [ "$warp" = "y" ]; then
    echo "正在自动获取 WARP 账户信息..."
    priv_key=$(./xray x25519 | head -n 1 | awk '{print $3}')
    pub_key=$(echo "$priv_key" | ./xray x25519 | tail -n 1 | awk '{print $3}')
    
    # 模拟注册
    auth=$(curl -sX POST "https://api.cloudflareclient.com/v0a1922/reg" -H "Content-Type: application/json" -d '{"install_id":"","tos":"2020-01-22T00:00:00.000Z","key":"'$pub_key'","fcm_token":""}')
    
    # 使用 sed 提取，防止没有 jq 的情况
    W_V6=$(echo "$auth" | sed 's/.*"v6":"\([^"]*\)".*/\1/')
    W_ID=$(echo "$auth" | sed 's/.*"id":"\([^"]*\)".*/\1/')
    W_TOKEN=$(echo "$auth" | sed 's/.*"token":"\([^"]*\)".*/\1/')
    
    # 获取 Reserved
    res_raw=$(curl -sX GET "https://api.cloudflareclient.com/v0a1922/reg/$W_ID" -H "Authorization: Bearer $W_TOKEN")
    W_RES=$(echo "$res_raw" | grep -oP '"reserved":\[\K[^\]]+')
    
    OUTBOUND_JSON='{ "protocol": "wireguard", "settings": { "secretKey": "'$priv_key'", "address": ["172.16.0.2/32", "'$W_V6'/128"], "peers": [{ "publicKey": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=", "endpoint": "engage.cloudflareclient.com:2408" }], "reserved": ['$W_RES'] } }'
else
    OUTBOUND_JSON='{ "protocol": "freedom", "settings": { "domainStrategy": "UseIP" } }'
fi

# --- 5. 写入配置并重启 ---
cat << JSON > config.json
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": 8003, "protocol": "vless",
    "settings": { "clients": [{"id": "8e6290c1-b97e-40c0-b9a3-7e7ed11ce248"}], "decryption": "none" },
    "streamSettings": { "network": "ws", "wsSettings": { "path": "/ws" } }
  }],
  "outbounds": [$OUTBOUND_JSON]
}
JSON

pkill -f xray
nohup ./xray -c config.json > xray.log 2>&1 &

# --- 6. 生成链接 ---
DOMAIN=$(grep -oE 'https://[a-z0-9.-]+\.trycloudflare\.com' argo.log | tail -n 1 | sed 's/https:\/\///')
if [ -z "$DOMAIN" ]; then
    ADDRESS=$(curl -s4m5 icanhazip.com)
    PORT_LINK=8003
    SEC="none"
else
    ADDRESS=$DOMAIN
    PORT_LINK=443
    SEC="tls"
fi

echo -e "\n--- 部署完成 ---"
echo "节点链接："
echo "vless://8e6290c1-b97e-40c0-b9a3-7e7ed11ce248@$ADDRESS:$PORT_LINK?encryption=none&security=$SEC&sni=$ADDRESS&type=ws&host=$ADDRESS&path=%2Fws#Argo-VLESS"
