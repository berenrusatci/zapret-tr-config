#!/usr/bin/env bash
# zapret-tr-config — Debian / Ubuntu tak çalıştır kurulum
# Kullanım:  ./install.sh
set -euo pipefail

ZAPRET_BASE=/opt/zapret
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"

c_red=$'\e[31m'; c_grn=$'\e[32m'; c_ylw=$'\e[33m'; c_rst=$'\e[0m'
info() { printf '%s==>%s %s\n' "$c_grn" "$c_rst" "$*"; }
warn() { printf '%s==>%s %s\n' "$c_ylw" "$c_rst" "$*"; }
die()  { printf '%s==>%s %s\n' "$c_red" "$c_rst" "$*" >&2; exit 1; }

# --- 0. ön kontroller -------------------------------------------------------
[[ $EUID -eq 0 ]] && die "Bunu root olarak çalıştırma. Normal kullanıcı ol, sudo gerektiğinde kendisi sorar."
command -v apt-get >/dev/null || die "apt-get yok — bu script Debian/Ubuntu içindir. Arch için üst dizindeki install.sh'yi kullan."
command -v systemctl >/dev/null || die "systemd yok."

info "sudo yetkisi isteniyor..."
sudo -v

# --- 1. temel paketler ------------------------------------------------------
info "Temel paketler kuruluyor (curl, git, nftables, ipset)..."
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends curl git ca-certificates nftables ipset iptables

# --- 2. zapret'i getir ------------------------------------------------------
# Sadece nfqws'e bakmak yetmiyor: eski sürüm script embedded arşivi kurmuş olabilir,
# o ağaçta systemd unit'i yok. İkisi birden yoksa yeniden kur.
if [[ -x "$ZAPRET_BASE/nfq/nfqws" && -f "$ZAPRET_BASE/init.d/systemd/zapret.service" ]]; then
  info "zapret zaten kurulu: $ZAPRET_BASE"
else
  if [[ -x "$ZAPRET_BASE/nfq/nfqws" ]]; then
    warn "$ZAPRET_BASE var ama systemd unit'i eksik — ağaç yeniden kuruluyor."
  fi
  info "zapret kuruluyor..."
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

  # 2a. Önce hazır ikili içeren son sürüm arşivini dene (derleyici gerekmez).
  info "Son sürüm arşivi aranıyor..."
  # Not: release'te iki tarball var; "-openwrt-embedded" olanda init.d/systemd yok.
  # Desen sürüm numarasından hemen sonra .tar.gz istiyor, embedded olanı elemek için.
  url="$(curl -fsSL https://api.github.com/repos/bol-van/zapret/releases/latest \
        | grep -oE 'https://[^"]*/zapret-v[0-9][0-9.]*\.tar\.gz' | head -1 || true)"

  installed=0
  if [[ -n "$url" ]]; then
    info "İndiriliyor: $(basename "$url")"
    if curl -fsSL "$url" -o "$tmp/zapret.tar.gz"; then
      mkdir -p "$tmp/x" && tar -xzf "$tmp/zapret.tar.gz" -C "$tmp/x"
      src="$(find "$tmp/x" -maxdepth 2 -name install_bin.sh -printf '%h\n' | head -1)"
      if [[ -n "$src" && ! -f "$src/init.d/systemd/zapret.service" ]]; then
        warn "Arşivde systemd unit'i yok (embedded sürüm?), kaynaktan derlenecek."
        src=""
      fi
      if [[ -n "$src" ]]; then
        sudo mkdir -p "$ZAPRET_BASE"
        sudo cp -a "$src/." "$ZAPRET_BASE/"
        info "Mimarine uygun ikililer seçiliyor (install_bin.sh)..."
        if sudo "$ZAPRET_BASE/install_bin.sh" && [[ -x "$ZAPRET_BASE/nfq/nfqws" ]]; then
          installed=1
        else
          warn "Hazır ikililer bu mimaride çalışmadı, kaynaktan derlenecek."
        fi
      fi
    else
      warn "Arşiv indirilemedi."
    fi
  else
    warn "Sürüm arşivi bulunamadı."
  fi

  # 2b. Olmadıysa kaynaktan derle.
  if [[ $installed -eq 0 ]]; then
    info "Derleme bağımlılıkları kuruluyor..."
    sudo apt-get install -y --no-install-recommends \
      build-essential zlib1g-dev libnetfilter-queue-dev libnfnetlink-dev \
      libmnl-dev libcap-dev libsystemd-dev
    info "Kaynak çekiliyor..."
    git clone --depth=1 https://github.com/bol-van/zapret.git "$tmp/src"
    info "Derleniyor (systemd hedefi)..."
    make -C "$tmp/src" systemd
    [[ -x "$tmp/src/nfq/nfqws" ]] || die "Derleme başarısız — nfqws üretilmedi."
    sudo mkdir -p "$ZAPRET_BASE"
    sudo cp -a "$tmp/src/." "$ZAPRET_BASE/"
    sudo rm -rf "$ZAPRET_BASE/.git"
  fi
fi

[[ -x "$ZAPRET_BASE/nfq/nfqws" ]] || die "$ZAPRET_BASE/nfq/nfqws yok — kurulum başarısız."
info "nfqws hazır: $("$ZAPRET_BASE/nfq/nfqws" --version 2>&1 | head -1)"

# --- 3. firewall tipi -------------------------------------------------------
FW=nftables
if ! command -v nft >/dev/null; then
  warn "nft komutu yok — iptables moduna geçiliyor."
  FW=iptables
fi

# --- 4. config'i yerleştir --------------------------------------------------
if [[ -f "$ZAPRET_BASE/config" ]] && ! cmp -s "$REPO_DIR/files/config" "$ZAPRET_BASE/config"; then
  info "Mevcut config yedekleniyor: config.bak-$STAMP"
  sudo cp -a "$ZAPRET_BASE/config" "$ZAPRET_BASE/config.bak-$STAMP"
fi
sudo install -m 644 "$REPO_DIR/files/config" "$ZAPRET_BASE/config"
sudo sed -i "s/^FWTYPE=.*/FWTYPE=$FW/" "$ZAPRET_BASE/config"
info "config yerleştirildi (FWTYPE=$FW)."

EXC="$ZAPRET_BASE/ipset/zapret-hosts-user-exclude.txt"
if [[ -f "$EXC" ]] && ! cmp -s "$REPO_DIR/files/zapret-hosts-user-exclude.txt" "$EXC"; then
  sudo cp -a "$EXC" "$EXC.bak-$STAMP"
fi
sudo mkdir -p "$ZAPRET_BASE/ipset"
sudo install -m 644 "$REPO_DIR/files/zapret-hosts-user-exclude.txt" "$EXC"
info "exclude listesi yerleştirildi."

# --- 5. systemd unit --------------------------------------------------------
UNIT_SRC="$ZAPRET_BASE/init.d/systemd/zapret.service"
[[ -f "$UNIT_SRC" ]] || die "$UNIT_SRC yok — zapret ağacı eksik görünüyor."
sudo install -m 644 "$UNIT_SRC" /etc/systemd/system/zapret.service
sudo chmod +x "$ZAPRET_BASE/init.d/sysv/zapret"
sudo systemctl daemon-reload
info "systemd unit kuruldu."

# --- 6. başlat --------------------------------------------------------------
[[ $FW == nftables ]] && sudo systemctl enable --now nftables.service >/dev/null 2>&1 || true
info "zapret etkinleştiriliyor ve başlatılıyor..."
sudo systemctl enable zapret.service
sudo systemctl restart zapret.service

sleep 2
if systemctl is-active --quiet zapret.service; then
  info "zapret çalışıyor."
else
  warn "Servis aktif değil. Log:"
  sudo systemctl status zapret.service --no-pager -l | tail -20
  exit 1
fi

echo
info "Çalışan nfqws süreçleri:"; pgrep -a nfqws || warn "nfqws süreci görünmüyor!"
echo
info "Kurulum bitti. Test: ./verify.sh"
