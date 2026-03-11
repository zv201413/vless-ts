# 🚀 VLESS-WS (Argo Tunnel + WARP) 一键管理手册

---

## 一、 核心功能说明

- **协议架构**：`VLESS` (极致轻量) + `WebSocket` (WS)
- **隐匿传输**：利用 `Argo 隧道` (TryCloudflare) 穿透内网，隐藏 VPS 真实 IP
- **出站解锁**：支持 `WARP` IPv6 优先出站，完美解锁 **ChatGPT / Netflix** 等流媒体
- **全能特性**：vps或者各类容器改造后的没有修改tun或网卡权限的docker版vps均可使用

---

## 二、 一键命令汇总

请根据你的需求选择以下命令在终端直接执行：

### 1. 普通模式部署 (默认直连出站)
```bash
curl -Ls "https://raw.githubusercontent.com/zv201413/vls_ws_ag/refs/heads/main/run_vless.sh?v=$(date +%s)" | bash
```

### 2. WARP 模式部署 (强制 IPv6 优先出站)
> [!TIP]
> 此模式将通过 WireGuard 隧道优先进行 IPv6 路由。

```bash
export warp=y && curl -Ls "https://raw.githubusercontent.com/zv201413/vls_ws_ag/refs/heads/main/run_vless.sh?v=$(date +%s)" | bash
```

### 3. 一键彻底卸载 (停止进程并清空文件)

```bash
curl -Ls "https://raw.githubusercontent.com/zv201413/vls_ws_ag/refs/heads/main/run_vless.sh?v=$(date +%s)" | bash -s uninstall
```
---

## 三、 客户端手动配置对照表

若自动生成的链接无法直接导入，请手动输入以下关键参数：

| 参数项 | 配置内容 |
| :--- | :--- |
| **协议类型 (Protocol)** | `VLESS` |
| **地址 (Address)** | `[你的 Argo 域名].trycloudflare.com` |
| **端口 (Port)** | `443` |
| **UUID (ID)** | `[脚本输出的 UUID]` |
| **加密方式 (Encryption)** | `none` (必填) |
| **传输协议 (Network)** | `ws` |
| **伪装域名 (SNI / Host)** | `[你的 Argo 域名].trycloudflare.com` |
| **路径 (Path)** | `/ws` |
| **底层传输安全 (TLS)** | `开启 (ON)` |

> [!NOTE]
> **手动维护命令：**
> - **Argo 隧道运行**：
> - ```bash
>   nohup ./cloudflared tunnel --url http://localhost:8003 --protocol quic --no-autoupdate > ./argo.log 2>&1 &
>   ```
> - **Xray 核心运行**：
> - ```bash
>   nohup ./xray -c ./config.json > ./xray.log 2>&1 &
>   ```
---

## 四、 常见问题 (FAQ)

- **Q: 为什么生成的链接显示的是 IP 和 8003 端口？**
  - **A:** 说明 Argo 隧道启动较慢，脚本在域名生成前就读取了配置。**解决方法：** 等待 10-15 秒后再次运行安装命令即可。

- **Q: 为什么 WARP 模式依然无法显示 IPv6 出口？**
  - **A:** 可能是 Cloudflare 对当前 IP 注册有限制。脚本会自动使用指定的兜底密钥进行握手。你可以通过 `tail -f xray.log` 观察是否有 `Handshake established` 字样。

- **Q: 为什么重启脚本后域名变了？**
  - **A:** TryCloudflare 提供的是临时域名。如需固定域名，请在 Cloudflare 控制台配置 `Named Tunnel`。

---

## 五、 进阶优化

- [x] **提速建议**：在客户端将“地址”项改为 Cloudflare **优选 IP**，SNI/Host 保持 Argo 域名不变。
- [x] **稳定性**：建议保持脚本在后台持续运行，避免频繁重启导致隧道域名变更。
- [x] **分流策略**：本脚本已实现 `ForceIPv6` 逻辑，确保流量优先通过 WARP 隧道。
