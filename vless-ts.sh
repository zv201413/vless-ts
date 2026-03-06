#!/bin/sh
# VLESS + TCP + Reality + Argo 一键脚本
# 无 enc 层，纯 VLESS Vision Reality
export LANG=en_US.UTF-8

[ -z "${vlpt+x}" ] || vlp=yes
[ -z "${argo+x}" ] || agp=yes

v46url="https://icanhazip.com"
REPO_URL="https://github.com/zv201413/vless-ts"

showmode(){
echo "=================================================="
echo "VLESS-TS-Argo 一键脚本"
echo "=================================================="
echo "主脚本下载:"
echo "  bash <(curl -Ls ${REPO_URL}/releases/latest/download/vless-ts.sh)"
echo ""
echo "快捷命令:"
echo "  查看节点: bash vless-ts.sh list"
echo "  重置配置: vlpt=8443 argo=vlpt bash vless-ts.sh rep"
echo "  卸载: bash vless-ts.sh del"
echo "=================================================="
}

if [ "$1" != "del" ] && [ "$1" != "list" ] && [ "$vlp" != "yes" ] && [ "$agp" != "yes" ]; then
    showmode
    echo ""
    echo "【使用示例】"
    echo "1. 基础安装 (直连):"
    echo "   vlpt=8443 bash vless-ts.sh"
    echo ""
    echo "2. 临时 Argo 隧道:"
    echo "   vlpt=8443 argo=vlpt bash vless-ts.sh"
    echo ""
    echo "3. 固定 Argo 隧道 (推荐):"
    echo "   vlpt=8443 argo=vlpt agn=xxx.trycloudflare.com agk=eyJ... bash vless-ts.sh"
    echo ""
    echo "4. 自定义 UUID:"
    echo "   uuid=xxxx vlpt=8443 argo=vlpt bash vless-ts.sh"
    exit
fi

mkdir -p "$HOME/vless-ts"
hostname=$(cat /proc/sys/kernel/hostname 2>/dev/null || uname -n)

case $(uname -m) in
    arm64|aarch64) cpu=arm64;;
    amd64|x86_64) cpu=amd64;;
    *) echo "不支持架构 $(uname -m)" && exit 1;;
esac

getip(){
    curl -s4m5 https://icanhazip.com 2>/dev/null || \
    curl -s6m5 https://icanhazip.com 2>/dev/null || \
    wget -4qO- https://icanhazip.com 2>/dev/null || \
    wget -6qO- https://icanhazip.com 2>/dev/null
}

del(){
    echo "正在卸载 VLESS-TS-Argo..."
    pkill -f "vless-ts/xray" 2>/dev/null
    pkill -f "vless-ts/cloudflared" 2>/dev/null
    systemctl stop vless-ts vless-ts-argo 2>/dev/null
    systemctl disable vless-ts vless-ts-argo 2>/dev/null
    rm -f /etc/systemd/system/vless-ts*.service
    rm -rf "$HOME/vless-ts"
    crontab -l 2>/dev/null | grep -v vless-ts | crontab - 2>/dev/null
    echo "卸载完成"
}

list(){
    [ ! -d "$HOME/vless-ts" ] && { echo "未安装"; exit 1; }
    
    uuid=$(cat "$HOME/vless-ts/uuid" 2>/dev/null)
    port=$(cat "$HOME/vless-ts/port_vl" 2>/dev/null)
    public_key=$(cat "$HOME/vless-ts/xrk/public_key" 2>/dev/null)
    short_id=$(cat "$HOME/vless-ts/xrk/short_id" 2>/dev/null)
    ym_vl=$(cat "$HOME/vless-ts/ym_vl" 2>/dev/null || echo "www.cloudflare.com")
    argodomain=$(cat "$HOME/vless-ts/argo_domain.log" 2>/dev/null)
    server_ip=$(getip)
    
    echo ""
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║           VLESS + TCP + Reality + Argo               ║"
    echo "╠════════════════════════════════════════════════════════╣"
    echo "║ UUID:     ${uuid}                      ║"
    echo "║ 端口:     ${port}                                        ║"
    echo "║ SNI:      ${ym_vl}                              ║"
    echo "║ Public:   ${public_key:0:20}...              ║"
    echo "║ Short ID: ${short_id}                                         ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo ""
    
    # 直连节点
    if [ -n "$port" ] && [ -n "$server_ip" ]; then
        echo "───────────【直连节点】───────────"
        echo "" 
        vless_link="vless://${uuid}@${server_ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${ym_vl}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#VLESS-TS-${hostname}"
        echo "$vless_link"
        echo ""
    fi
    
    # Argo节点
    if [ -n "$argodomain" ]; then
        echo "───────────【Argo 节点】───────────"
        echo ""
        vless_argo="vless://${uuid}@${argodomain}:443?encryption=none&flow=xtls-rprx-vision&security=tls&sni=${argodomain}&fp=chrome&type=tcp&headerType=none#VLESS-TS-Argo-${hostname}"
        echo "$vless_argo"
        echo ""
        echo "Argo 域名: ${argodomain}"
        echo ""
    fi
    
    # 保存汇总
    {
        echo "VLESS-TS-${hostname}:"
        [ -n "$vless_link" ] && echo "$vless_link"
        [ -n "$vless_argo" ] && echo "$vless_argo"
    } > "$HOME/vless-ts/nodes.txt"
}

case "$1" in
    del) del; exit 0 ;;
    list) list; exit 0 ;;
    rep) echo "正在重置配置..."; del >/dev/null 2>&1 ;;
esac

echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║        VLESS + TCP + Reality + Argo 安装中             ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

# 下载 Xray
if [ ! -f "$HOME/vless-ts/xray" ]; then
    echo "[1/5] 下载 Xray 内核..."
    url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${cpu}.zip"
    curl -sLo /tmp/xray.zip "$url" || wget -qO /tmp/xray.zip "$url"
    unzip -o /tmp/xray.zip -d "$HOME/vless-ts" 2>/dev/null
    chmod +x "$HOME/vless-ts/xray"
    rm -f /tmp/xray.zip
fi

# UUID
if [ -z "$uuid" ] && [ ! -f "$HOME/vless-ts/uuid" ]; then
    uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)
elif [ -n "$uuid" ]; then
    echo "$uuid" > "$HOME/vless-ts/uuid"
fi
[ -f "$HOME/vless-ts/uuid" ] && uuid=$(cat "$HOME/vless-ts/uuid")
echo "[2/5] UUID: ${uuid}"

# 端口
if [ -z "$vlpt" ] && [ ! -f "$HOME/vless-ts/port_vl" ]; then
    port=$(shuf -i 10000-65535 -n 1)
elif [ -n "$vlpt" ]; then
    port=$vlpt
elif [ -f "$HOME/vless-ts/port_vl" ]; then
    port=$(cat "$HOME/vless-ts/port_vl")
fi
echo "$port" > "$HOME/vless-ts/port_vl"
echo "[3/5] 端口: ${port}"

# SNI
ym_vl=${reym:-www.cloudflare.com}
echo "$ym_vl" > "$HOME/vless-ts/ym_vl"
echo "[4/5] SNI: ${ym_vl}"

# Reality 密钥
if [ ! -f "$HOME/vless-ts/xrk/private_key" ]; then
    mkdir -p "$HOME/vless-ts/xrk"
    key_pair=$("$HOME/vless-ts/xray" x25519 2>/dev/null)
    if [ -n "$key_pair" ]; then
        private_key=$(echo "$key_pair" | awk '/PrivateKey/{print $2}')
        public_key=$(echo "$key_pair" | awk '/Public/{print $2}')
    fi
    # 备用密钥
    if [ -z "$private_key" ]; then
        private_key="uJo7N1nO1FuKm6Lq6yZ_tybR7pwC6OEwiEICsN8VSmA"
        public_key="FG_jC9C13KQs7tBpTCudF5U3B8HpdPe3yKN_zxSJnAg"
    fi
    short_id=$(openssl rand -hex 4 2>/dev/null || date +%s | md5sum | cut -c1-8)
    echo "$private_key" > "$HOME/vless-ts/xrk/private_key"
    echo "$public_key" > "$HOME/vless-ts/xrk/public_key"
    echo "$short_id" > "$HOME/vless-ts/xrk/short_id"
fi

private_key=$(cat "$HOME/vless-ts/xrk/private_key")
public_key=$(cat "$HOME/vless-ts/xrk/public_key")
short_id=$(cat "$HOME/vless-ts/xrk/short_id")

# 生成配置cat > "$HOME/vless-ts/config.json" <<CFG
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "tag": "vless-tcp-reality",
    "listen": "::",
    "port": ${port},
    "protocol": "vless",
    "settings": {
      "clients": [{ "id": "${uuid}", "flow": "xtls-rprx-vision" }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "fingerprint": "chrome",
        "dest": "${ym_vl}:443",
        "serverNames": ["${ym_vl}"],
        "privateKey": "${private_key}",
        "shortIds": ["${short_id}"]
      }
    },
    "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
  }],
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
CFG

echo "[5/5] 启动 Xray 服务..."

# 启动 Xray
pkill -f "vless-ts/xray" 2>/dev/null

if pidof systemd >/dev/null 2>&1 && [ "$EUID" -eq
