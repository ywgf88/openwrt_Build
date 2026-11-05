#!/bin/bash
# 让编译出的固件默认走 IPv4（关闭 IPv6 的自动配置与地址下发）
#
# 用法：bash ipv4-default.sh [源码目录]      默认 openwrt
# 由 customize.sh 在 make defconfig 之前调用，剩余三条流水线
# （ctc_25.12 / Lean / Lienol）共用此脚本。
#
# 本仓库的上游分两类，IPv6 默认值的来源并不相同，两处都必须处理：
#   A. immortalwrt(24.10/25.12)、coolsnowwolf-lede：
#      config_generate 用 [ -e /proc/sys/net/ipv6 ] 生成 ula_prefix / ip6assign / wan6；
#      dhcp.conf 里没有 ra/dhcpv6，LAN 的 RA 是 odhcpd 的 uci-defaults(15_odhcpd)
#      在首启时按 V6MODE=server 写入的 → 要改 odhcpd.defaults。
#   B. Lienol(25.12)：config_generate 同上，且 dhcp.conf 直接写死 ra/dhcpv6 server。
#
# 可选开关（在 workflow env 里设即可）：
#   IPV6_HARD_DISABLE=1  连内核 IPv6 栈一起禁用（sysctl disable_ipv6=1）
#   IPV6_FILTER_AAAA=1   只让 dnsmasq 不返回 AAAA，双栈下强制解析走 IPv4

SRC="${1:-openwrt}"
IPV6_HARD_DISABLE="${IPV6_HARD_DISABLE:-0}"
IPV6_FILTER_AAAA="${IPV6_FILTER_AAAA:-0}"

log() { echo "[ipv4-default] $*"; }

if [ ! -d "$SRC" ]; then
	log "错误: 源码目录 $SRC 不存在"
	exit 1
fi

# ---------- 1. 默认 network 生成逻辑（所有上游一致） ----------
# 该判断在编译机上恒为真，于是固件首启就写入 ula_prefix / ip6assign / wan6。
CFG_GENERATE="$SRC/package/base-files/files/bin/config_generate"
if [ -f "$CFG_GENERATE" ]; then
	n=$(grep -c '\[ -e /proc/sys/net/ipv6 \]' "$CFG_GENERATE")
	sed -i 's#\[ -e /proc/sys/net/ipv6 \]#false#g' "$CFG_GENERATE"
	log "config_generate: 关闭 $n 处 IPv6 判断（ula_prefix / ip6assign / wan6）"
else
	log "警告: 未找到 config_generate，跳过"
fi

# ---------- 2. A 类上游：odhcpd 首启写入 ra=server ----------
ODHCPD_DEFAULTS="$SRC/package/network/services/odhcpd/files/odhcpd.defaults"
if [ -f "$ODHCPD_DEFAULTS" ]; then
	sed -i 's#\[ -e /proc/sys/net/ipv6 \]#false#g' "$ODHCPD_DEFAULTS"
	log "odhcpd.defaults: V6MODE 恒为 disabled（不再向 LAN 发 RA）"
fi

# ---------- 3. B 类上游：dhcp.conf 静态写死的 ra / dhcpv6 ----------
DHCP_CONF="$SRC/package/network/services/dnsmasq/files/dhcp.conf"
if [ -f "$DHCP_CONF" ]; then
	if grep -qE "^[[:space:]]*option[[:space:]]+ra[[:space:]]" "$DHCP_CONF"; then
		sed -i -E "s/^([[:space:]]*option[[:space:]]+ra[[:space:]]+).*/\1disabled/" "$DHCP_CONF"
		log "dhcp.conf: ra 已置为 disabled"
	fi
	if grep -qE "^[[:space:]]*option[[:space:]]+dhcpv6[[:space:]]" "$DHCP_CONF"; then
		sed -i -E "s/^([[:space:]]*option[[:space:]]+dhcpv6[[:space:]]+).*/\1disabled/" "$DHCP_CONF"
		log "dhcp.conf: dhcpv6 已置为 disabled"
	fi
	if [ "$IPV6_FILTER_AAAA" = "1" ]; then
		sed -i -E "s/^([[:space:]]*option[[:space:]]+filter_aaaa[[:space:]]+).*/\11/" "$DHCP_CONF"
		log "dhcp.conf: filter_aaaa=1（DNS 不再返回 AAAA）"
	fi
	# 没有 ra/dhcpv6 行时说明是 A 类上游，由 odhcpd.defaults 负责，这里无需补写
fi

# ---------- 4. 防火墙不再生成 IPv6 规则 ----------
FW_CONF="$SRC/package/network/config/firewall/files/firewall.config"
if [ -f "$FW_CONF" ]; then
	if grep -qE "^[[:space:]]*#?[[:space:]]*option[[:space:]]+disable_ipv6" "$FW_CONF"; then
		sed -i -E "/disable ipv6 rules/d" "$FW_CONF"
		sed -i -E "s/^[[:space:]]*#?[[:space:]]*(option[[:space:]]+disable_ipv6).*/\t\1 1/" "$FW_CONF"
		log "firewall.config: disable_ipv6 已开启"
	else
		log "firewall.config: 无 disable_ipv6 选项，跳过（不影响 IPv4）"
	fi
fi

# ---------- 5. 首启兜底：清掉已生成的 IPv6 配置 ----------
UCI_DEFAULTS_DIR="$SRC/package/base-files/files/etc/uci-defaults"
mkdir -p "$UCI_DEFAULTS_DIR"
cat > "$UCI_DEFAULTS_DIR/99-ipv4-default" <<'EOF'
#!/bin/sh
# 默认使用 IPv4：清理 IPv6 上行与地址下发
# 排在 15_odhcpd、99-default-settings 之后执行，保证最终生效
[ -f /etc/config/network ] || exit 0

uci -q delete network.globals.ula_prefix

if uci -q get network.lan >/dev/null; then
	uci -q set network.lan.ipv6='0'
	uci -q delete network.lan.ip6assign
	uci -q delete network.lan.ip6hint
	uci -q delete network.lan.ip6prefix
	uci -q delete network.lan.ip6class
	uci -q delete network.lan.ip6ifaceid
	uci -q delete network.lan.ip6weight
	uci -q delete network.lan.extendprefix
fi

if uci -q get network.wan >/dev/null; then
	uci -q set network.wan.ipv6='0'
	uci -q delete network.wan.ip6assign
fi
uci -q delete network.wan6

# 匿名段按索引倒序删，避免索引位移
ipv6_ifaces=$(uci -q show network 2>/dev/null | sed -n "s/^network\.\([^.=]*\)\.proto='\(dhcpv6\|static6\|6in4\|6to4\|6rd\|dslite\|map\)'$/\1/p")
for iface in $(echo "$ipv6_ifaces" | grep '^@' | awk -F'[][]' '{print $2"\t"$0}' | sort -rn | cut -f2); do
	uci -q delete network."$iface"
done
for iface in $(echo "$ipv6_ifaces" | grep -v '^@' | grep .); do
	uci -q delete network."$iface"
done

for sec in $(uci -q show dhcp 2>/dev/null | sed -n "s/^dhcp\.\([^.=]*\)=dhcp$/\1/p"); do
	uci -q set dhcp."$sec".ra='disabled'
	uci -q set dhcp."$sec".dhcpv6='disabled'
	uci -q set dhcp."$sec".ndp='disabled'
	uci -q delete dhcp."$sec".ra_flags
	uci -q delete dhcp."$sec".ra_slaac
done

uci -q get firewall.@defaults[0] >/dev/null && uci -q set firewall.@defaults[0].disable_ipv6='1'

uci -q commit network
uci -q commit dhcp
uci -q commit firewall

exit 0
EOF
chmod +x "$UCI_DEFAULTS_DIR/99-ipv4-default"
log "已投放 uci-defaults/99-ipv4-default（首启兜底清理）"

# ---------- 6. 可选：连内核 IPv6 栈一起关掉 ----------
SYSCTL_DIR="$SRC/package/base-files/files/etc/sysctl.d"
if [ "$IPV6_HARD_DISABLE" = "1" ]; then
	mkdir -p "$SYSCTL_DIR"
	cat > "$SYSCTL_DIR/11-disable-ipv6.conf" <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
	log "已写入 sysctl.d/11-disable-ipv6.conf（内核 IPv6 彻底禁用）"
elif [ -f "$SYSCTL_DIR/11-disable-ipv6.conf" ]; then
	rm -f "$SYSCTL_DIR/11-disable-ipv6.conf"
fi

log "完成：本固件默认 IPv4，IPv6 需在 LuCI 里手动开启"
