#!/usr/bin/env bash
# Kurulumun gerçekten çalışıp çalışmadığını kontrol eder (Debian/Ubuntu).
c_grn=$'\e[32m'; c_red=$'\e[31m'; c_ylw=$'\e[33m'; c_rst=$'\e[0m'
ok()   { printf '%s  ✓%s %s\n' "$c_grn" "$c_rst" "$*"; }
bad()  { printf '%s  ✗%s %s\n' "$c_red" "$c_rst" "$*"; FAIL=1; }
warn() { printf '%s  !%s %s\n' "$c_ylw" "$c_rst" "$*"; }
FAIL=0

echo "zapret durum kontrolü"
echo "---------------------"

[[ -x /opt/zapret/nfq/nfqws ]] && ok "nfqws ikilisi var" || bad "/opt/zapret/nfq/nfqws yok"
systemctl is-enabled --quiet zapret.service && ok "servis boot'ta etkin" || bad "servis boot'ta etkin değil"
systemctl is-active  --quiet zapret.service && ok "servis çalışıyor"     || bad "servis çalışmıyor"
# Not: -q Arch'ın procps-ng'sinde, --quiet Ubuntu 24.04'ün procps'inde yok.
# Çıktıyı yutmak her ikisinde de çalışan tek yol.
if NFQ_N="$(pgrep -c nfqws 2>/dev/null)" && [[ ${NFQ_N:-0} -gt 0 ]]; then
  ok "nfqws süreci ayakta ($NFQ_N adet)"
else
  bad "nfqws süreci yok"
fi

FW=$(grep -oP '^FWTYPE=\K.*' /opt/zapret/config 2>/dev/null)
if [[ $FW == nftables ]]; then
  sudo nft list table inet zapret &>/dev/null && ok "nftables 'inet zapret' tablosu var" || bad "nftables tablosu yok"
else
  sudo iptables -t mangle -S 2>/dev/null | grep -q NFQUEUE && ok "iptables NFQUEUE kuralı var" || bad "iptables kuralı yok"
fi
grep -q '^INIT_APPLY_FW=1' /opt/zapret/config && ok "INIT_APPLY_FW=1" || bad "INIT_APPLY_FW=1 eksik — kurallar uygulanmaz"

echo
echo "Bağlantı testi:"
for h in discord.com gateway.discord.gg google.com; do
  if curl -s -o /dev/null -m 8 -w '%{http_code}' "https://$h" | grep -qE '^[23]'; then
    ok "$h erişilebilir"
  else
    bad "$h erişilemedi"
  fi
done

echo
[[ $FAIL -eq 0 ]] && echo "${c_grn}Her şey yolunda.${c_rst}" || echo "${c_red}Sorun var — yukarıdaki ✗ satırlarına bak.${c_rst}"
exit $FAIL
