#!/usr/bin/env bash
# Zapret çalışıyor ama site açılmıyorsa: kanıt toplar. Çıktının tamamını yolla.
# Kullanım: ./diag.sh 2>&1 | tee diag.txt
echo "================ 1. SİSTEM ================"
. /etc/os-release 2>/dev/null; echo "distro: ${PRETTY_NAME:-?}"; uname -r
echo "zapret sürüm: $(/opt/zapret/nfq/nfqws --version 2>&1 | head -1)"

echo; echo "================ 2. DİSKTEKİ CONFIG ================"
grep -vE '^\s*#|^\s*$' /opt/zapret/config
echo "--- exclude listesi ---"; cat /opt/zapret/ipset/zapret-hosts-user-exclude.txt 2>/dev/null

echo; echo "================ 3. ÇALIŞAN SÜREÇ (asıl argümanlar) ================"
pgrep -a nfqws || echo "nfqws SÜRECİ YOK"

echo; echo "================ 4. SERVİS ================"
systemctl is-enabled zapret.service; systemctl is-active zapret.service
sudo journalctl -u zapret.service -b --no-pager | tail -25

echo; echo "================ 5. FIREWALL ================"
sudo nft list table inet zapret 2>&1 | head -40
echo "--- başka kim kural koymuş (ufw/docker/başka bypass) ---"
# DİKKAT: nft çıktısında ifade "queue flags bypass to 200" olabilir, "queue num" DEĞİL.
# Sadece "queue num" araman yanlış negatif verir — kural var sanırsın ki yok, ya da tersi.
sudo nft list ruleset 2>/dev/null | grep -E '^table|NFQUEUE|queue (num|flags|to)' | head -30
echo "--- kuyruga giden kural sayisi (0 ise firewall gercekten yok) ---"
sudo nft list table inet zapret 2>/dev/null | grep -cE 'queue (num|flags|to)'
command -v ufw >/dev/null && sudo ufw status 2>&1 | head -3

echo; echo "================ 6. PAKET DAEMON'A ULAŞIYOR MU ================"
echo "--- ÖNCE (8. sütun = kuyruğa alınan kümülatif paket) ---"
sudo cat /proc/net/netfilter/nfnetlink_queue 2>&1
curl -s -o /dev/null --max-time 8 https://discord.com/ ; echo "curl çıkış kodu: $?"
echo "--- SONRA ---"
sudo cat /proc/net/netfilter/nfnetlink_queue 2>&1

echo; echo "================ 7. BAĞLANTI TESTLERİ ================"
echo "-- DNS --"; getent hosts discord.com gateway.discord.gg
for h in discord.com gateway.discord.gg cdn.discordapp.com google.com; do
  printf '%-24s -> %s\n' "$h" "$(curl -s -o /dev/null -m 8 -w '%{http_code}' "https://$h" 2>&1)"
done
echo "-- TLS 1.2 zorlayarak (blockcheck bunu test etmişti) --"
curl -s -o /dev/null -m 8 --tlsv1.2 --tls-max 1.2 -w 'tls1.2 discord.com -> %{http_code}\n' https://discord.com/
echo "-- TLS 1.3 --"
curl -s -o /dev/null -m 8 --tlsv1.3 -w 'tls1.3 discord.com -> %{http_code}\n' https://discord.com/
echo "-- IPv6 kapalı mı --"
sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null

echo; echo "================ 8. ZAPRET KAPALIYKEN (fark var mı) ================"
sudo systemctl stop zapret.service; sleep 1
curl -s -o /dev/null -m 8 -w 'zapret KAPALI discord.com -> %{http_code}\n' https://discord.com/
sudo systemctl start zapret.service; sleep 2
curl -s -o /dev/null -m 8 -w 'zapret AÇIK   discord.com -> %{http_code}\n' https://discord.com/
echo; echo "bitti."
