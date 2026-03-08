#!/bin/bash

# --- 1. 基础配置 ---
WORK_DIR="/home/zv/vless-all"
mkdir -p $WORK_DIR
cd $WORK_DIR

# --- 2. 核心：卸载模块 ---
# 只有把这段代码写进脚本，uninstall 参数才会生效
if [ "$1" = "uninstall" ]; then
    echo "正在彻底卸载服务..."
    pkill -f xray
    pkill -f cloudflared
    cd /home/zv && rm -rf "$WORK_DIR"
    echo "卸载完成！所有进程已停止，目录已删除。"
    exit 0
fi

# --- 3. 环境准备 ---
# 检查并下载依赖
[ -f "cloudflared" ] || { echo "下载 Argo..."; curl -L -o cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 && chmod +x cloudflared; }
[ -f "xray" ] || { echo "下载 Xray..."; curl -L -o xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip && unzip -o xray.zip && chmod +x xray; }

# 启动隧道 (如果没在跑)
pgrep -f cloudflared >/dev/null || nohup ./cloudflared tunnel --url http://localhost:8003 --no-autoupdate > argo.log 2>&1 &

# --- 4. WARP 注册与容错 ---
OUTBOUND_JSON='{ "protocol": "freedom", "settings": { "domainStrategy": "UseIP" } }'
if [ "$warp" = "y" ]; then
    echo "尝试注册 WARP..."
    priv_key=$(./xray x25519 | head -n 1 | awk '{print $3}')
    pub_key=$(echo "$priv_key" | ./xray x25519 | tail -n 1 | awk '{print $3}')
    auth=$(curl -sX POST "https://api.cloudflareclient.com/v0a1922/reg" -H "Content-Type: application/json" -d '{"install_id":"","tos":"2020-01-22T00:00:00.000Z","key":"'$pub_key'","fcm_token":""}')
    
    if echo "$auth" | grep -q "public_key" && ! echo "$auth" | grep -q "false"; then
        W_V6=$(echo "$auth" | sed 's/.*"v6":"\([^"]*\)".*/\1/')
        W_ID=$(echo "$auth" | sed 's/.*"id":"\([^"]*\)".*/\1/')
        W_TOKEN=$(echo "$auth" | sed 's/.*"token":"\([^"]*\)".*/\1/')
        res_raw=$(curl -sX GET "https://api.cloudflareclient.com/v0a1922/reg/$W_ID" -H "Authorization: Bearer $W_TOKEN")
        W_RES=$(echo "$res_raw" | grep -oP '"reserved":\[\K[^\]]+' || echo "0,0,0")
        OUTBOUND_JSON='{ "protocol": "wireguard", "settings": { "secretKey": "'$priv_key'", "address": ["172.16.0.2/32", "'$W_V6'/128"], "peers": [{ "publicKey": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=", "endpoint": "engage.cloudflareclient.com:2408" }], "reserved": ['$W_RES'] } }'
        echo "WARP 已启用"
    else
        echo "WARP 注册失败，退回直连模式"
    fi
fi

# --- 5. 生成 Xray 配置 ---
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

# --- 6. 启动与链接输出 ---
pkill -f xray
nohup ./xray -c config.json > xray.log 2>&1 &

echo "正在等待 Argo 隧道分配域名 (最多等待 30 秒)..."
ITERATION=0
DOMAIN=""
while [ -z "$DOMAIN" ] && [ $ITERATION -lt 15 ]; do
    sleep 2
    DOMAIN=$(grep -oE 'https://[a-z0-9.-]+\.trycloudflare\.com' argo.log | tail -n 1 | sed 's/https:\/\///')
    ITERATION=$((ITERATION+1))
done

if [ -n "$DOMAIN" ]; then
    ADDRESS=$DOMAIN
    PORT_LINK=443
    SEC="tls"
else
    ADDRESS=$(curl -s4 icanhazip.com)
    PORT_LINK=8003
    SEC="none"
    echo "警告：Argo 隧道启动超时，切换至 IP 直连模式。"
fi

echo -e "\n--- 部署完成 (WARP: ${warp:-n}) ---"
echo "节点链接："
echo "vless://8e6290c1-b97e-40c0-b9a3-7e7ed11ce248@$ADDRESS:$PORT_LINK?encryption=none&security=$SEC&sni=$ADDRESS&type=ws&host=$ADDRESS&path=%2Fws#Argo-VLESS"
