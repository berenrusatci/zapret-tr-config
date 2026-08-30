#!/usr/bin/env bash
# DNS kaçırmayı düzeltir. zapret'ten BAĞIMSIZ bir iş — zapret DNS'e hiç dokunmaz.
#
# Belirti:  dig +short discord.com  ->  195.175.254.2  (TTNet blok sunucusu)
#           dig @8.8.8.8 ...        ->  connection refused (53/UDP dışarı kapalı)
#
# Bu script şifreli DNS kurar: 853 açıksa systemd-resolved + DoT, değilse dnscrypt-proxy (DoH/443).
# Tekrar tekrar çalıştırılabilir. Geri alma: ./fix-dns.sh --undo
set -euo pipefail

STAMP="$(date +%Y%m%d-%H%M%S)"
NM_CONF=/etc/NetworkManager/conf.d/00-zapret-dns.conf

c_red=$'\e[31m'; c_grn=$'\e[32m'; c_ylw=$'\e[33m'; c_rst=$'\e[0m'
info() { printf '%s==>%s %s\n' "$c_grn" "$c_rst" "$*"; }
warn() { printf '%s==>%s %s\n' "$c_ylw" "$c_rst" "$*"; }
die()  { printf '%s==>%s %s\n' "$c_red" "$c_rst" "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] && die "root olarak çalıştırma; sudo gerektiğinde kendisi sorar."
command -v apt-get >/dev/null || die "apt-get yok — bu script Debian/Ubuntu içindir."

# --- geri alma --------------------------------------------------------------
if [[ "${1:-}" == "--undo" ]]; then
  info "Geri alınıyor..."
  sudo rm -f "$NM_CONF"
  sudo systemctl disable --now dnscrypt-proxy 2>/dev/null || true
  if [[ -f /etc/systemd/resolved.conf.bak-zapret ]]; then
    sudo mv /etc/systemd/resolved.conf.bak-zapret /etc/systemd/resolved.conf
    sudo systemctl restart systemd-resolved 2>/dev/null || true
  fi
  sudo systemctl reload NetworkManager 2>/dev/null || sudo systemctl restart NetworkManager 2>/dev/null || true
  info "Bitti. DHCP'den gelen DNS'e dönüldü."
  exit 0
fi

sudo -v

# --- 0. mevcut durum --------------------------------------------------------
before="$(dig +short A discord.com 2>/dev/null | head -1 || true)"
info "Şu anki cevap: ${before:-<yok>}"
if [[ "$before" == 195.175.* ]]; then
  warn "DNS kaçırılıyor (blok sunucusu IP'si). Düzeltiliyor."
else
  info "DNS zaten sahte görünmüyor — yine de şifreli DNS kurmak zararsız, devam."
fi

# --- 1. hangi taşıyıcı geçiyor ----------------------------------------------
info "853/tcp (DoT) test ediliyor..."
if timeout 5 bash -c 'cat < /dev/null > /dev/tcp/1.1.1.1/853' 2>/dev/null; then
  TRANSPORT=dot; info "DoT açık."
else
  TRANSPORT=doh; warn "853 kapalı — DoH (443) kullanılacak."
fi

# systemd-resolved yoksa DoT yolunu seçemeyiz
if [[ $TRANSPORT == dot ]] && ! systemctl list-unit-files systemd-resolved.service >/dev/null 2>&1; then
  warn "systemd-resolved kurulu değil — DoH yoluna geçiliyor."
  TRANSPORT=doh
fi

# --- 2a. DoT yolu: systemd-resolved -----------------------------------------
if [[ $TRANSPORT == dot ]]; then
  info "systemd-resolved + DNSOverTLS kuruluyor..."
  [[ -f /etc/systemd/resolved.conf.bak-zapret ]] || \
    sudo cp -a /etc/systemd/resolved.conf "/etc/systemd/resolved.conf.bak-zapret"

  sudo tee /etc/systemd/resolved.conf >/dev/null <<'EOF'
[Resolve]
DNS=1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com
FallbackDNS=9.9.9.9#dns.quad9.net
DNSOverTLS=yes
DNSSEC=allow-downgrade
Domains=~.
EOF

  sudo systemctl enable --now systemd-resolved
  sudo systemctl restart systemd-resolved
  sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

  # NetworkManager DHCP DNS'ini üste yazmasın
  sudo mkdir -p "$(dirname "$NM_CONF")"
  sudo tee "$NM_CONF" >/dev/null <<'EOF'
[main]
dns=systemd-resolved
EOF

# --- 2b. DoH yolu: dnscrypt-proxy -------------------------------------------
else
  info "dnscrypt-proxy kuruluyor (DoH, 443 üstünden)..."
  sudo apt-get update -qq
  sudo apt-get install -y --no-install-recommends dnscrypt-proxy

  TOML=/etc/dnscrypt-proxy/dnscrypt-proxy.toml
  [[ -f "$TOML" ]] || die "$TOML yok — paket beklenenden farklı kurulmuş."
  [[ -f "$TOML.bak-zapret" ]] || sudo cp -a "$TOML" "$TOML.bak-zapret"

  # DoH sunucularını sabitle, DNSCrypt'i kapat (53/UDP zaten dışarı kapalı olabilir)
  sudo sed -i \
    -e "s|^#\?\s*server_names\s*=.*|server_names = ['cloudflare', 'cloudflare-security', 'quad9-doh-ip4-port443-nofilter-pri']|" \
    -e "s|^#\?\s*doh_servers\s*=.*|doh_servers = true|" \
    -e "s|^#\?\s*dnscrypt_servers\s*=.*|dnscrypt_servers = false|" \
    -e "s|^#\?\s*require_dnssec\s*=.*|require_dnssec = false|" \
    "$TOML"

  # Dinlediği adresi öğren (Debian paketi genelde socket activation kullanır)
  sudo systemctl enable --now dnscrypt-proxy.socket 2>/dev/null || true
  sudo systemctl enable --now dnscrypt-proxy.service
  sudo systemctl restart dnscrypt-proxy.service

  LISTEN="$(ss -lnup 2>/dev/null | grep -o '127\.0\.[0-9.]*:53' | head -1 | cut -d: -f1 || true)"
  LISTEN="${LISTEN:-127.0.2.1}"
  info "dnscrypt-proxy dinliyor: $LISTEN:53"

  # NetworkManager DNS'e karışmasın, resolv.conf'u sabitle
  sudo mkdir -p "$(dirname "$NM_CONF")"
  sudo tee "$NM_CONF" >/dev/null <<'EOF'
[main]
dns=none
EOF
  [[ -L /etc/resolv.conf ]] && sudo rm -f /etc/resolv.conf
  [[ -f /etc/resolv.conf ]] && sudo cp -a /etc/resolv.conf "/etc/resolv.conf.bak-$STAMP"
  printf 'nameserver %s\noptions edns0 trust-ad\n' "$LISTEN" | sudo tee /etc/resolv.conf >/dev/null
fi

sudo systemctl reload NetworkManager 2>/dev/null || sudo systemctl restart NetworkManager 2>/dev/null || true
sleep 3

# --- 3. doğrula -------------------------------------------------------------
echo
info "Doğrulama:"
after="$(dig +short A discord.com 2>/dev/null | head -1 || true)"
printf '  discord.com -> %s\n' "${after:-<cevap yok>}"

if [[ -z "$after" ]]; then
  die "Cevap gelmiyor. 'sudo systemctl status dnscrypt-proxy systemd-resolved' ve 'cat /etc/resolv.conf' çıktısına bak."
elif [[ "$after" == 195.175.* ]]; then
  die "HÂLÂ sahte IP. Bir şey resolv.conf'u eziyor — 'cat /etc/resolv.conf' ve 'resolvectl status' çıktısını yolla."
else
  info "DNS düzeldi (taşıyıcı: $TRANSPORT)."
  echo
  info "Sırada: zapret'i kapat, blockcheck çalıştır."
  echo "  sudo systemctl stop zapret"
  echo "  sudo /opt/zapret/blockcheck.sh    # discord.com · standard · TLS 1.2 · IPv6 no"
  echo "  sudo systemctl start zapret"
fi
