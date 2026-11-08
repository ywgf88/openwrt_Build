# openwrt_Build · ImmortalWrt 25.12 × x86_64 自动编译

由 GitHub Actions 一键编译的 OpenWrt / ImmortalWrt 固件仓库，Fork 自 [kenzok8/openwrt_Build](https://github.com/kenzok8/openwrt_Build)，面向 **x86_64 软路由**，默认按 IPv4 出网、自带代理插件全家桶，成品发布在本仓库 [Releases](../../releases)。

## 固件概览

| 项目 | 说明 |
| --- | --- |
| 设备名称 | **x86/64 Generic**（`CONFIG_TARGET_x86_64_DEVICE_generic`），适用于 x86_64 软路由、工控机、虚拟机 |
| 固件分支 | **immortalwrt `openwrt-25.12`**（源码 `immortalwrt/immortalwrt`） |
| 内核 / 工具链 | Linux 6.6 · musl · GCC 13.3.0 · **apk** 包管理（不是 opkg） |
| 配置文件 | `ctc_25.12.config`，对应流水线 `openwrt_25.12`（`.github/workflows/ctc_25.12.yml`） |
| 默认管理地址 | **192.168.100.1**，用户名 `root`，密码 `password` |
| 默认主题 | **Argon**（`luci-theme-argon` 3.1.3 + `luci-app-argon-config`）；`luci-theme-bootstrap` 也在固件内，可在「系统 → 语言和界面 → 设计」切换 |
| 默认网络 | 仅 IPv4：IPv6 的 RA / DHCPv6 / `wan6` / `ula_prefix` 均关闭，需要时在 LuCI 里手动开启 |
| 镜像格式 | `squashfs-combined-efi`（UEFI 启动）、`squashfs-combined`（传统 BIOS / GRUB）、`rootfs.tar.gz` |

## 编译流水线

| 流水线 | 源码 | 分支 | 配置 | 产物设备 |
| --- | --- | --- | --- | --- |
| `openwrt_25.12`（ctc_25.12.yml） | `immortalwrt/immortalwrt` | `openwrt-25.12` | `ctc_25.12.config` | x86/64 Generic |
| `Lean`（Lean.yml） | `coolsnowwolf/lede` | `master` | `feeds/smpackage/.github/diy/Lean.config` | 随上游配置 |
| `Lienol`（Lienol.yml） | `Lienol/openwrt` | `25.12` | `feeds/smpackage/.github/diy/Lienol.config` | 随上游配置 |
| `Update`（Update.yml） | `kenzok8/small-package` | `main` | — | 每周六 09:00 检测插件包更新并触发编译 |

三条编译流水线共用 `customize.sh` 与 `ipv4-default.sh`，插件来自 `kenzok8/small-package` 与 `kenzok8/golang`。

## 已集成插件

**代理 / 分流**

- Passwall2：`luci-app-passwall2` + `Basic_Core_All`（xray-core、sing-box 等内核全量）
- clashoo：`clashoo` + `luci-app-clashoo`（mihomo 内核）
- dae / daed：`daed` + `luci-app-daede`
- SSR Plus（bypass）：`luci-app-bypass`，含 Shadowsocks / SSR libev 客户端与服务端、Trojan、Xray、simple-obfs、socks 服务端
- `chinadns-ng`

**DNS / 去广告**

- `dnsmasq-full`（DHCP、DHCPv6、DNSSEC、nftset、TFTP 全特性）
- `knot-resolver`（dnstap）
- AdGuardHome（`luci-app-adguardhome`，内置二进制）

**网络 / 系统**

- `firewall4` + `nftables-json` + `kmod-nft-fullcone`（NAT1 全锥）
- UPnP 自动端口转发（`luci-app-upnp`）、动态 DDNS（`luci-app-ddns`）
- `ip-full`、`ipset`、`ethtool`、`lm-sensors`

**存储 / NAS**

- 磁盘管理：`luci-app-diskman`（含 btrfs-progs、lsblk）
- `rclone`（含 rclone-webui、rclone-ng）、`webd`
- `automount`、`block-mount`，kmod 覆盖 ext4 / f2fs / exfat / ntfs3 / vfat / USB 存储

**实用工具**

- `bash`、`coreutils`、`nano`、`yq`、`unzip`、`cfdisk` / `partx-utils`、`e2fsprogs`、`mkf2fs`、`sysfsutils`
- 网易云解锁：`luci-app-unblockmusic`（UnblockNeteaseMusic Go）

**主题**

- `luci-theme-argon`（默认）+ `luci-app-argon-config`、`luci-theme-bootstrap`

## 定制点

`customize.sh` 在 `make defconfig` 之前执行，目前实际生效的只有两项：

```bash
# 默认管理 IP：192.168.1.1 → 192.168.100.1
sed -i 's/192.168.1.1/192.168.100.1/g' openwrt/package/base-files/files/bin/config_generate

# 默认 IPv4：关闭 IPv6 自动配置与地址下发（RA / DHCPv6 / wan6 / ula_prefix）
bash ipv4-default.sh openwrt
```

默认主题不在这里改（对应 `sed` 已注释），由 `luci-theme-argon` 自带的 `uci-defaults/30_luci-theme-argon` 在首启时写入 `luci.main.mediaurlbase=/luci-static/argon`，因此开箱即 Argon。

改默认密码（`package/emortal/default-settings` 中的 shadow 段，当前为 `password`）：

```bash
sed -i "s?/root:[^:]*:?/root:$(openssl passwd -1 新密码):?" openwrt/package/emortal/default-settings/files/99-default-settings
```

`ipv4-default.sh` 支持两个开关，在 workflow 的 `env` 里设置：

- `IPV6_HARD_DISABLE=1`：连内核 IPv6 栈一起禁用（`sysctl disable_ipv6=1`）
- `IPV6_FILTER_AAAA=1`：仅让 dnsmasq 不返回 AAAA 记录

## 目录结构

```
.github/workflows/   Lean.yml / Lienol.yml / ctc_25.12.yml / Update.yml
ctc_25.12.config     ImmortalWrt 25.12 x86_64 编译配置
customize.sh         编译前的源码定制（默认 IP、IPv4）
ipv4-default.sh      关闭 IPv6 默认值的公共脚本
patches/             上游补丁（如 nftables-fix.patch）
Dockerfile           Docker 镜像构建
```

## 使用方法

1. Fork 本仓库，在 **Settings → Secrets and variables → Actions** 配好所需密钥（至少 `REPO_TOKEN` 供 `Update` 触发编译；`DOCKER_ID` / `DOCKER_PASSWD`、`R2_*`、`SSH_PRIVATE_KEY` 等按需可选）。
2. 进入 **Actions**，选 `openwrt_25.12`，点 **Run workflow**；也可由 `Update` 定时任务自动 `repository_dispatch` 触发。
3. 编译完成后在 **Releases** 下载 `squashfs-combined-efi.img.gz`（UEFI）或 `squashfs-combined.img.gz`（BIOS），解压写盘即可。

> 流水线带 `github.event.repository.owner.id == github.event.sender.id` 判断，只允许仓库所有者触发编译。固件首次启动后请立刻修改 root 密码与 LAN 网段。

## 许可

继承上游，遵循 GPLv2，详见 [LICENSE](LICENSE)。源码版权归 ImmortalWrt / OpenWrt / kenzok8 各上游项目所有。
