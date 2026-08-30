#!/usr/bin/env bash
# Kurulumun gerçekten çalışıp çalışmadığını kontrol eder.
c_grn=$'\e[32m'; c_red=$'\e[31m'; c_ylw=$'\e[33m'; c_rst=$'\e[0m'
ok()   { printf '%s  ✓%s %s\n' "$c_grn" "$c_rst" "$*"; }
bad()  { printf '%s  ✗%s %s\n' "$c_red" "$c_rst" "$*"; FAIL=1; }
warn() { printf '%s  !%s %s\n' "$c_ylw" "$c_rst" "$*"; }
FAIL=0

echo "zapret durum kontrolü"
echo "---------------------"

systemctl is-enabled --quiet zapret.service && ok "servis boot'ta etkin" || bad "servis boot'ta etkin değil"
systemctl is-active  --quiet zapret.service && ok "servis çalışıyor"     || bad "servis çalışmıyor"
pgrep -q nfqws && ok "nfqws süreci ayakta ($(pgrep -c nfqws) adet)" || bad "nfqws süreci yok"
sudo nft list table inet zapret &>/dev/null && ok "nftables 'inet zapret' tablosu var" || bad "nftables tablosu yok"

grep -q '^FWTYPE=nftables' /opt/zapret/config && ok "FWTYPE=nftables" || warn "FWTYPE nftables değil"
grep -q '^INIT_APPLY_FW=1'  /opt/zapret/config && ok "INIT_APPLY_FW=1" || bad "INIT_APPLY_FW=1 eksik — kurallar uygulanmaz"

echo
echo "Bağlantı testi (Discord + genel TLS):"
for h in discord.com gateway.discord.gg google.com; do
  if curl -s -o /dev/null -m 8 -w '%{http_code}' "https://$h" | grep -qE '^[23]'; then
    ok "$h erişilebilir"
  else
    bad "$h erişilemedi"
  fi
done

echo
[[ $FAIL -eq 0 ]] && echo "${c_grn}Her şey yolunda.${c_rst}" || echo "${c_red}Sorun var — yukarıdaki ✗ satırlarına bak.${c_rst}"
exit ${FAIL:-0}
