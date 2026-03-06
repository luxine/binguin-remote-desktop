# scripts 命令说明

本目录提供 4 个 Ubuntu 客户端侧脚本，用于安装、更新、加固和一键配置。

## 1. 脚本用途

- `client-install.sh`：安装/重装客户端并写入预设服务器、密钥、无人值守密码等。
- `client-update.sh`：更新客户端（本质调用 `client-install.sh`）。
- `ubuntu24-best-config.sh`：仅做 Ubuntu 24.04 被控端系统级配置（Xorg、自启动、常驻、禁休眠等）。
- `client-all-in-one.sh`：先安装/更新，再应用 Ubuntu 24.04 最佳配置。

## 2. 前置条件

- 系统：Ubuntu/Debian（`ubuntu24-best-config.sh` 最佳适配 Ubuntu 24.04）。
- 权限：必须使用 `root`/`sudo` 执行。
- 包来源：需要本地 `.deb` 或可下载的 `.deb` URL。

## 3. 常用命令（可直接复制）

```bash
# 1) 本地 .deb 安装（推荐）
sudo ./scripts/client-install.sh --deb-file ./BinguinDesk-1.0.0.deb

# 2) 远程 URL 安装
sudo ./scripts/client-install.sh --deb-url "https://example.com/BinguinDesk-1.0.0.deb"

# 3) 指定自建服务器 + 公钥 + 永久密码安装
sudo ./scripts/client-install.sh \
  --deb-file ./BinguinDesk-1.0.0.deb \
  --id-server 3.144.200.111 \
  --key 'nLdVM05GRrC0PCzA1uJFTcuKQ6gitptntaokhFEayb0=' \
  --permanent-password 'Binguin1001'

# 4) 更新客户端（参数与 install 一样）
sudo ./scripts/client-update.sh --deb-file ./BinguinDesk-1.0.1.deb

# 5) 仅做 Ubuntu 24.04 被控端最佳配置
sudo ./scripts/ubuntu24-best-config.sh --autologin-user ubuntu

# 6) 一键完成安装 + 系统配置
sudo ./scripts/client-all-in-one.sh \
  --deb-file ./BinguinDesk-1.0.1.deb \
  --autologin-user ubuntu
```

## 4. 关键参数说明

### client-install.sh / client-update.sh

- `--deb-file <path>`：本地安装包路径。
- `--deb-url <url>`：先下载再安装。
- `--id-server <host[:port]>`：ID 服务器地址。
- `--relay-server <host[:port]>`：中继服务器地址（可选）。
- `--api-server <url>`：API 服务器地址（可选）。
- `--key <public-key>`：服务端公钥。
- `--permanent-password <v>`：永久连接密码。
- `--permanent-password-file <path>`：从文件读取永久密码（推荐生产环境使用）。
- `--no-unattended-password`：不强制无人值守密码模式。
- `--no-watchdog`：不安装 watchdog 定时守护。
- `--no-hardening`：不写入 systemd 加固配置。
- `--skip-apt-update`：跳过 `apt-get update`。

默认内置值（如不覆盖）：

- `ID Server`：`3.144.200.111`
- `Key`：`nLdVM05GRrC0PCzA1uJFTcuKQ6gitptntaokhFEayb0=`
- `Permanent Password`：`Binguin1001`

### ubuntu24-best-config.sh

- `--autologin-user <user>`：启用该用户自动登录（不传会报错，除非显式跳过）。
- `--skip-autologin`：跳过自动登录设置。
- `--skip-gsettings`：跳过 GNOME 锁屏/休眠策略设置。
- `--skip-logind-restart`：不立即重启 `systemd-logind`（减少当前会话中断风险）。

该脚本会做：

- 禁用 Wayland（强制 Ubuntu on Xorg）。
- 禁止自动休眠/挂起/合盖休眠。
- 配置图形目标与 rustdesk 常驻、看门狗。

### client-all-in-one.sh

- 安装类参数：同 `client-install.sh`。
- 配置类参数：同 `ubuntu24-best-config.sh`。
- 推荐用于新机器首次交付。

## 5. 每次使用通常需要改哪些参数

- 必改：`--deb-file` 或 `--deb-url`（安装包来源）。
- 常改：`--autologin-user`（目标机器实际桌面用户）。
- 按需改：`--id-server`、`--key`、`--permanent-password`（当服务器策略调整时）。
- 安全建议：生产环境优先使用 `--permanent-password-file`，避免密码出现在命令历史中。
