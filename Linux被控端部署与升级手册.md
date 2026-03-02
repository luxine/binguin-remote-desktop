# BinguinDesk Linux 被控端部署与升级手册

## 1. 文档目标

本文档用于在 Linux 平台部署 `BinguinDesk` 被控端，并尽可能实现以下目标：

- 以最高可用权限运行
- 进程常驻
- 开机自启动
- 网络恢复后自动恢复
- 升级时尽量不丢配置
- 异常退出后自动拉起

需要明确的是：**任何软件都无法保证在断电、硬盘损坏、内核崩溃、主机被强制关机、网络彻底中断等情况下“绝对可用”**。本文档的目标是把可用性尽量拉高，而不是给出不现实的绝对承诺。

## 2. 适用范围

- 适用系统：`Ubuntu` / `Debian` 系列（推荐 `Ubuntu 22.04/24.04`）
- 适用场景：企业内网、长期在线、无人值守被控端
- 安装包：你们自行构建的 `BinguinDesk-*.deb`

注意：

- 当前外显品牌已替换为 `BinguinDesk`，但**内部包名、服务名、可执行名仍然保留为 `rustdesk`**。
- 因此，系统命令、服务名、配置目录等仍然使用 `rustdesk`。

## 3. 安装前准备

### 3.1 基础要求

- 使用固定供电，避免笔记本电池耗尽自动关机
- 推荐使用有线网络
- 推荐给被控端分配固定 IP 或 DHCP 保留地址
- 建议 BIOS/UEFI 开启来电自启（如果硬件支持）
- 建议关闭系统自动休眠、自动挂起

### 3.2 桌面环境建议

如果你需要的是完整桌面远控，而不是仅后台服务在线，建议：

- 优先使用 `Xorg`
- 不建议长期依赖 `Wayland` 做无人值守控制
- 需要图形桌面长期可进入时，建议配置自动登录

## 4. 安装部署

### 4.1 安装包说明

当前构建产物文件名是：

- `BinguinDesk-<version>.deb`

但包的内部名称仍然是：

- `rustdesk`

因此安装后你仍然需要使用 `rustdesk` 相关命令。

### 4.2 正式安装

使用 `apt` 安装，不要优先用 `dpkg -i`，这样依赖会自动补齐：

```bash
cd /path/to/package
sudo apt update
sudo apt install -y ./BinguinDesk-*.deb
```

安装完成后，包的安装脚本会自动完成这些动作：

- 建立 `/usr/bin/rustdesk -> /usr/share/rustdesk/rustdesk`
- 安装 `rustdesk.service`
- 执行 `systemctl enable rustdesk`
- 执行 `systemctl start rustdesk`

### 4.3 安装后立即检查

```bash
systemctl is-enabled rustdesk
systemctl is-active rustdesk
systemctl status rustdesk --no-pager
journalctl -u rustdesk -n 100 --no-pager
```

如果状态不是 `enabled` 和 `active`，不要继续交付，先修复。

## 5. 高可用保活配置

默认安装后的服务已经是 root 运行，但默认保活策略不够强。建议增加 systemd 覆盖配置。

### 5.1 使用 systemd drop-in 覆盖配置

不要直接改 `/usr/lib/systemd/system/rustdesk.service`，因为升级时会被覆盖。

执行：

```bash
sudo systemctl edit rustdesk
```

写入以下内容：

```ini
[Unit]
Wants=network-online.target
After=network-online.target systemd-user-sessions.service
StartLimitIntervalSec=0

[Service]
User=root
Restart=always
RestartSec=5
TimeoutStartSec=60
TimeoutStopSec=30
KillMode=mixed
LimitNOFILE=100000
OOMScoreAdjust=-1000
Environment="PULSE_LATENCY_MSEC=60" "PIPEWIRE_LATENCY=1024/48000"

[Install]
WantedBy=multi-user.target
```

然后执行：

```bash
sudo systemctl daemon-reload
sudo systemctl enable rustdesk
sudo systemctl restart rustdesk
sudo systemctl status rustdesk --no-pager
```

### 5.2 为什么这样配置

- `User=root`
  保持最高权限，避免因普通用户权限不足导致的功能受限
- `Restart=always`
  只要进程退出，就尝试拉起
- `RestartSec=5`
  避免瞬时崩溃后频繁重启把系统打满
- `Wants/After=network-online.target`
  系统网络恢复后再启动，减少启动时网络未就绪导致的异常
- `StartLimitIntervalSec=0`
  不因为短时间内重启次数过多而永久放弃拉起
- `OOMScoreAdjust=-1000`
  尽量降低被 OOM Killer 杀掉的概率

## 6. 让主机尽可能持续在线

仅仅让 `rustdesk.service` 自启动还不够。如果系统自己挂起、锁屏、无人登录，远控体验仍可能下降。

### 6.1 禁用休眠和挂起

```bash
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

验证：

```bash
systemctl list-unit-files | grep -E 'sleep|suspend|hibernate'
```

应看到相关目标处于 `masked`。

### 6.2 保持图形目标启动

```bash
sudo systemctl set-default graphical.target
```

### 6.3 推荐启用自动登录（仅限受控内网环境）

如果目标是无人值守的完整桌面控制，建议配置桌面自动登录。  
这会降低本地物理安全性，只适用于企业内网、受限访问机房或受信办公环境。

以 `gdm3` 为例：

```bash
sudo cp /etc/gdm3/custom.conf /etc/gdm3/custom.conf.bak
sudo editor /etc/gdm3/custom.conf
```

建议配置：

```ini
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=<你的桌面用户名>
WaylandEnable=false
```

说明：

- `AutomaticLoginEnable=true`：系统启动后自动进入桌面会话
- `WaylandEnable=false`：尽量强制走 Xorg，减少无人值守兼容性问题

修改后重启验证：

```bash
sudo reboot
```

### 6.4 关闭自动锁屏（GNOME 场景）

如果你依赖 GNOME，且希望重启后自动进入桌面并长期可远控，可对登录用户执行：

```bash
gsettings set org.gnome.desktop.session idle-delay 0
gsettings set org.gnome.desktop.screensaver lock-enabled false
```

## 7. 增强型保活（推荐）

在核心服务之外，再加一层轻量 watchdog，可以减少“服务被禁用”或“异常停掉未恢复”的情况。

### 7.1 创建 watchdog 脚本

创建文件 `/usr/local/sbin/rustdesk-watchdog.sh`：

```bash
sudo install -d -m 755 /usr/local/sbin
sudo editor /usr/local/sbin/rustdesk-watchdog.sh
```

内容如下：

```bash
#!/usr/bin/env bash
set -euo pipefail

if ! systemctl is-enabled rustdesk >/dev/null 2>&1; then
  systemctl enable rustdesk
fi

if ! systemctl is-active rustdesk >/dev/null 2>&1; then
  systemctl restart rustdesk
fi
```

赋予执行权限：

```bash
sudo chmod 755 /usr/local/sbin/rustdesk-watchdog.sh
```

### 7.2 创建 systemd 服务

创建 `/etc/systemd/system/rustdesk-watchdog.service`：

```ini
[Unit]
Description=RustDesk Watchdog
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/rustdesk-watchdog.sh
User=root
```

### 7.3 创建 systemd 定时器

创建 `/etc/systemd/system/rustdesk-watchdog.timer`：

```ini
[Unit]
Description=Run RustDesk Watchdog Every Minute

[Timer]
OnBootSec=2min
OnUnitActiveSec=1min
Unit=rustdesk-watchdog.service
Persistent=true

[Install]
WantedBy=timers.target
```

启用：

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now rustdesk-watchdog.timer
systemctl list-timers | grep rustdesk-watchdog
```

这层 watchdog 的作用是：

- 如果主服务被手动禁用，会重新启用
- 如果主服务未运行，会在一分钟内再次拉起

## 8. 配置备份

升级前必须备份配置，尤其是长期运行的被控端。

### 8.1 备份目录

重点备份：

- `/root/.config/rustdesk`

建议执行：

```bash
sudo install -d -m 700 /var/backups/rustdesk
sudo tar czf /var/backups/rustdesk/rustdesk-config-$(date +%F-%H%M%S).tar.gz /root/.config/rustdesk
```

### 8.2 为什么必须备份

因为在执行 `apt purge rustdesk` 时，安装包的卸载脚本会删除：

- `/root/.config/rustdesk`

因此：

- 升级时不要用 `purge`
- 卸载前必须先做备份

## 9. 升级流程（推荐标准流程）

### 9.1 升级前检查

```bash
systemctl is-active rustdesk
systemctl status rustdesk --no-pager
sudo tar czf /var/backups/rustdesk/rustdesk-config-$(date +%F-%H%M%S).tar.gz /root/.config/rustdesk
```

### 9.2 原地升级

将新包上传到目标主机后执行：

```bash
cd /path/to/package
sudo apt install -y ./BinguinDesk-*.deb
```

这是推荐升级方式，特点是：

- 保留包管理状态
- 自动执行升级脚本
- 依赖自动处理
- 比手工替换二进制更稳

### 9.3 升级后检查

```bash
systemctl daemon-reload
systemctl enable rustdesk
systemctl restart rustdesk
systemctl is-active rustdesk
systemctl status rustdesk --no-pager
journalctl -u rustdesk -n 100 --no-pager
```

如果你启用了 watchdog，还要检查：

```bash
systemctl is-active rustdesk-watchdog.timer
```

## 10. 回滚流程

### 10.1 保留旧包

每次升级前都建议保留上一版安装包，例如：

- `BinguinDesk-1.4.6.deb`
- `BinguinDesk-1.4.5.deb`

### 10.2 包回滚

如果新版本异常，执行：

```bash
cd /path/to/old/package
sudo apt install -y ./BinguinDesk-旧版本.deb --allow-downgrades
```

### 10.3 配置恢复

如果需要恢复配置：

```bash
sudo tar xzf /var/backups/rustdesk/rustdesk-config-<timestamp>.tar.gz -C /
sudo systemctl restart rustdesk
```

## 11. 运维检查清单

建议至少每天或通过监控系统周期性检查以下项目：

```bash
systemctl is-enabled rustdesk
systemctl is-active rustdesk
systemctl status rustdesk --no-pager
journalctl -u rustdesk -n 50 --no-pager
```

建议关注：

- 服务是否为 `enabled`
- 服务是否为 `active (running)`
- 最近日志中是否有频繁崩溃重启
- 机器是否误进入挂起
- 桌面是否仍可进入（无人值守场景）

## 12. 常见故障排查

### 12.1 服务未启动

```bash
systemctl status rustdesk --no-pager
journalctl -u rustdesk -n 200 --no-pager
```

优先检查：

- 依赖是否缺失
- 安装包是否完整
- 是否被安全策略拦截
- 是否被手动禁用

### 12.2 开机后服务在线，但桌面无法控制

优先检查：

- 是否仍在使用 `Wayland`
- 是否没有图形会话
- 是否没有自动登录
- 是否桌面被锁屏

### 12.3 升级后配置异常

优先检查：

- 是否误用了 `apt purge`
- `/root/.config/rustdesk` 是否被覆盖或丢失
- 直接恢复备份后重启服务

## 13. 最终建议（生产环境）

生产环境建议至少做到以下基线：

1. 使用 `apt install ./BinguinDesk-*.deb` 安装和升级。
2. 使用 `systemctl edit rustdesk` 增加 `Restart=always` 和 `network-online.target`。
3. 禁用系统休眠和挂起。
4. 需要完整桌面无人值守时，启用 `Xorg + 自动登录 + 关闭锁屏`。
5. 增加 `rustdesk-watchdog.timer` 作为第二层保活。
6. 每次升级前备份 `/root/.config/rustdesk`。
7. 不要使用 `apt purge rustdesk` 做常规升级。

如果你的目标是“尽可能不掉线”，这已经是 Linux 被控端比较稳妥的一套落地方案。
