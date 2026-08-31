#!/usr/bin/env bash
# zapret-tr-config — canlı strateji ölçer
#
# Neden var: blockcheck her stratejiyi varsayılan olarak BİR kez dener. DPI
# kararsızsa (aynı komut bazen geçiyor bazen kesiliyor) tek deneme yanıltır —
# çalışmayan strateji AVAILABLE, çalışan strateji UNAVAILABLE çıkabilir.
# Bu script adayları sırayla /opt/zapret/config'e yazar, servisi yeniden
# başlatır ve her birini N kez ölçer. Sonuç yüzde olarak gelir, ikili değil.
#
# Kullanım:  sudo ./strategy-test.sh [tekrar] [alan_adı]
#            sudo ./strategy-test.sh 10 discord.com
#
# Çıkarken config'i olduğu gibi geri koyar (Ctrl-C dahil).
set -uo pipefail

N="${1:-10}"
DOMAIN="${2:-discord.com}"
CONFIG=/opt/zapret/config
EXCLUDE=--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt

[[ $EUID -eq 0 ]] || { echo "sudo ile çalıştır."; exit 1; }
[[ -f $CONFIG ]] || { echo "$CONFIG yok — önce install.sh."; exit 1; }

BACKUP="$(mktemp)"
cp "$CONFIG" "$BACKUP"
restore() {
  echo
  echo "==> config geri yükleniyor"
  cp "$BACKUP" "$CONFIG"; rm -f "$BACKUP"
  systemctl restart zapret
  echo "==> bitti, eski profil geri yüklendi"
}
trap restore EXIT INT TERM

# UDP blokları her adayda sabit — blockcheck QUIC'i test edemiyor (curl'de
# HTTP/3 yok), o yüzden çalıştığı varsayılan hâli değiştirmiyoruz.
UDP_TAIL="
--new
--filter-udp=443 $EXCLUDE --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic=/opt/zapret/files/fake/quic_initial_www_google_com.bin
--new
--filter-udp=50000-65535 --filter-l7=discord,stun --dpi-desync=fake --dpi-desync-repeats=6
"

# Adaylar: "etiket|strateji". Sıralama kasıtlı — saf split'ler üstte, çünkü
# TTL'e / fooling'e bağlı olanlar hop sayısı veya sunucu OS'u değişince
# sessizce bozulur. Eşit skorda üsttekini seç.
CANDIDATES=(
  "multidisorder-7pos|--dpi-desync=multidisorder --dpi-desync-split-pos=1,sniext+1,host+1,midsld-2,midsld,midsld+2,endhost-1"
  "multidisorder-1|--dpi-desync=multidisorder --dpi-desync-split-pos=1"
  "multisplit-seqovl-10|--dpi-desync=multisplit --dpi-desync-split-pos=10 --dpi-desync-split-seqovl=1"
  "multisplit-seqovl-10-midsld|--dpi-desync=multisplit --dpi-desync-split-pos=10,midsld --dpi-desync-split-seqovl=1"
  "syndata-multisplit|--dpi-desync=syndata,multisplit --dpi-desync-split-pos=1"
  "fakedsplit-altorder|--dpi-desync=fakedsplit --dpi-desync-ttl=1 --dpi-desync-split-pos=1 --dpi-desync-fakedsplit-mod=altorder=1"
  "hostfakesplit-ttl3|--dpi-desync=hostfakesplit --dpi-desync-ttl=3"
  "fake-ttl3|--dpi-desync=fake --dpi-desync-ttl=3"
  "fake-badseq0|--dpi-desync=fake --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=0"
  "fakedsplit-badseq0|--dpi-desync=fakedsplit --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=0 --dpi-desync-split-pos=1"
  "hostfakesplit-badseq0|--dpi-desync=hostfakesplit --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=0"
)

# TLS 1.2 zorlanıyor: blockcheck'in kendi kuralı, 1.2'de geçen 1.3'te de geçer,
# tersi geçerli değil. 1.3 şifreli ServerHello sayesinde zayıf stratejileri de
# bazen geçirir; o yüzden 1.3'e bakıp "çalışıyor" demek yanıltıcı.
probe() {
  curl -sI -o /dev/null -w '%{http_code}' --tlsv1.2 --tls-max 1.2 \
       --max-time 5 "https://$DOMAIN" 2>/dev/null
}

apply() {
  local strat="$1"
  # NFQWS_OPT bloğunu (açılış tırnağından kapanış tırnağına) söküp yenisini koy
  python3 - "$CONFIG" <<PY
import re,sys
p=sys.argv[1]
s=open(p,encoding='utf-8').read()
new='''NFQWS_OPT="
--filter-tcp=443 $EXCLUDE $strat
--new
--filter-tcp=80 $EXCLUDE --dpi-desync=multidisorder --dpi-desync-split-pos=midsld$UDP_TAIL"'''
s2=re.sub(r'NFQWS_OPT="[^"]*"', lambda m: new, s, count=1)
if s2==s and 'NFQWS_OPT' not in s:
    s2=s.rstrip()+"\n"+new+"\n"
open(p,'w',encoding='utf-8').write(s2)
PY
  systemctl restart zapret
  sleep 2
}

echo "==> $DOMAIN · her aday $N istek · TLS 1.2 zorlanıyor"
echo

# Kıyas çizgisi: bypass tamamen kapalıyken kaç tanesi geçiyor. Sıfır değilse
# engel zaten kısmi demektir ve aday skorlarını buna göre okumak gerekir.
systemctl stop zapret; sleep 1
base=0
for ((i=0;i<N;i++)); do
  code="$(probe)"
  [[ "$code" == 2* || "$code" == 3* ]] && ((base++))
done
printf '%-30s %3d/%d  (bypass kapalı)\n\n' "TABAN" "$base" "$N"

best_score=-1; best_label=""
for entry in "${CANDIDATES[@]}"; do
  label="${entry%%|*}"; strat="${entry#*|}"
  apply "$strat"
  ok=0
  for ((i=0;i<N;i++)); do
    code="$(probe)"
    [[ "$code" == 2* || "$code" == 3* ]] && ((ok++))
  done
  pct=$(( ok * 100 / N ))
  mark=""; (( pct == 100 )) && mark=" <<<"
  printf '%-30s %3d/%d  %3d%%%s\n' "$label" "$ok" "$N" "$pct" "$mark"
  if (( ok > best_score )); then best_score=$ok; best_label="$label"; fi
done

echo
echo "==> en iyi: $best_label ($best_score/$N)"
echo "    Beren'e bu tabloyu olduğu gibi yolla."
