# vless-ts

===========================================================
          VLESS-WS (Argo Tunnel + WARP) 一键管理手册
===========================================================

## 一、 核心功能说明
-----------------------------------------------------------
1. 协议：VLESS (极致轻量，必须配合 encryption=none)
2. 传输：WebSocket (WS) + Argo 隧道 (TryCloudflare)
3. 出站：支持直连 或 WARP 解锁 (解锁 ChatGPT/Netflix)
4. 特点：隐藏 VPS 真实 IP，免除公网端口开放风险，智能容错。

## 二、 一键命令汇总 (直接在终端执行)
-----------------------------------------------------------

### 【1. 普通模式部署】 (默认直连出站)
```
curl -Ls "https://raw.githubusercontent.com/zv201413/vls_ws_ag/refs/heads/main/run_vless.sh?v=$(date +%s)" | bash
```

### 【2. WARP 模式部署】 (解锁流媒体/AI服务)
```
export warp=y && curl -Ls "https://raw.githubusercontent.com/zv201413/vls_ws_ag/refs/heads/main/run_vless.sh?v=$(date +%s)" | bash
```
### 【3. 一键彻底卸载】 (停止所有进程并清空文件)
```
curl -Ls "https://raw.githubusercontent.com/zv201413/vls_ws_ag/refs/heads/main/run_vless.sh?v=$(date +%s)" | bash -s uninstall
```

## 三、 手动配置参数 (客户端对照表)
-----------------------------------------------------------
若脚本自动生成的链接无法导入，请手动输入以下关键参数：

- 协议类型 (Protocol): VLESS
- 地址 (Address): [你的 Argo 域名].trycloudflare.com
- 端口 (Port): 443
- UUID (ID): [脚本输出的 UUID]
- 加密方式 (Encryption): none (必填)
- 传输协议 (Network): ws
- 伪装域名 (Host / SNI): [你的 Argo 域名].trycloudflare.com
- 路径 (Path): /ws
- 底层传输安全 (TLS): 开启 (ON)

## 四、 常见问题 (FAQ)
-----------------------------------------------------------
Q: 为什么生成的链接显示的是 IP 和 8003 端口？
A: 说明 Argo 隧道启动较慢，脚本在域名生成前就读取了配置。请等待 10 秒后再次运行安装命令即可。

Q: 为什么 WARP 注册失败？
A: Cloudflare 对 IP 注册有限制。脚本会自动跳过并使用直连模式，建议过段时间重试。

Q: 为什么重启脚本后域名变了？
A: TryCloudflare 提供的是临时域名。如需固定域名，需在 Cloudflare 后台配置有损隧道 (Named Tunnel)。

## 五、 进阶优化
-----------------------------------------------------------
- 提速建议：在客户端将“地址”项改为 Cloudflare 优选 IP。
- 稳定性：建议保持脚本常驻运行，不要频繁重启以维持域名稳定。

===========================================================
最后更新时间: 2026-03-08
===========================================================
