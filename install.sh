#!/usr/bin/env bash
# zapret-tr-config — tak çalıştır kurulum (Arch / CachyOS)
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
[[ $EUID -eq 0 ]] && die "Bunu root olarak çalıştırma. Normal kullanıcı olarak çalıştır, sudo gerektiğinde kendisi soracak."
command -v pacman >/dev/null || die "pacman yok — bu script Arch tabanlı sistemler için (Arch, CachyOS, EndeavourOS, Manjaro)."
command -v systemctl >/dev/null || die "systemd yok."

info "sudo yetkisi isteniyor..."
sudo -v

# --- 1. zapret paketi -------------------------------------------------------
if pacman -Qq zapret-git &>/dev/null || pacman -Qq zapret &>/dev/null; then
  info "zapret zaten kurulu: $(pacman -Qq zapret-git zapret 2>/dev/null | tr '\n' ' ')"
else
  info "zapret kurulu değil, AUR'dan kuruluyor (zapret-git)..."
  AUR=""
  for h in paru yay pikaur trizen; do command -v "$h" >/dev/null && { AUR="$h"; break; }; done
  if [[ -n "$AUR" ]]; then
    "$AUR" -S --needed --noconfirm zapret-git
  else
    warn "AUR helper (paru/yay) bulunamadı — makepkg ile elle kuruluyor."
    sudo pacman -S --needed --noconfirm base-devel git
    tmp="$(mktemp -d)"
    git clone --depth=1 https://aur.archlinux.org/zapret-git.git "$tmp/zapret-git"
    ( cd "$tmp/zapret-git" && makepkg -si --noconfirm )
    rm -rf "$tmp"
  fi
fi

[[ -d "$ZAPRET_BASE" ]] || die "$ZAPRET_BASE yok — zapret kurulumu başarısız görünüyor."

# --- 2. bağımlılıklar -------------------------------------------------------
info "Gerekli paketler kontrol ediliyor (nftables, ipset, curl)..."
sudo pacman -S --needed --noconfirm nftables ipset curl

# --- 3. config'i yerleştir --------------------------------------------------
if [[ -f "$ZAPRET_BASE/config" ]]; then
  if cmp -s "$REPO_DIR/files/config" "$ZAPRET_BASE/config"; then
    info "config zaten güncel."
  else
    info "Mevcut config yedekleniyor: config.bak-$STAMP"
    sudo cp -a "$ZAPRET_BASE/config" "$ZAPRET_BASE/config.bak-$STAMP"
  fi
fi
sudo install -m 644 "$REPO_DIR/files/config" "$ZAPRET_BASE/config"
info "config yerleştirildi."

# --- 4. exclude listesi -----------------------------------------------------
EXC="$ZAPRET_BASE/ipset/zapret-hosts-user-exclude.txt"
if [[ -f "$EXC" ]] && ! cmp -s "$REPO_DIR/files/zapret-hosts-user-exclude.txt" "$EXC"; then
  info "Mevcut exclude listesi yedekleniyor."
  sudo cp -a "$EXC" "$EXC.bak-$STAMP"
fi
sudo install -m 644 "$REPO_DIR/files/zapret-hosts-user-exclude.txt" "$EXC"
info "exclude listesi yerleştirildi."

# --- 5. servis --------------------------------------------------------------
info "nftables servisi etkinleştiriliyor..."
sudo systemctl enable --now nftables.service >/dev/null 2>&1 || warn "nftables servisi başlatılamadı (zapret kendi kurallarını yine de yükleyebilir)."

info "zapret servisi etkinleştiriliyor ve yeniden başlatılıyor..."
sudo systemctl enable zapret.service
sudo systemctl restart zapret.service

sleep 2
if systemctl is-active --quiet zapret.service; then
  info "zapret çalışıyor."
else
  warn "zapret servisi aktif değil. Log:"
  sudo systemctl status zapret.service --no-pager -l | tail -20
  exit 1
fi

# --- 6. doğrulama -----------------------------------------------------------
echo
info "Çalışan nfqws süreçleri:"
pgrep -a nfqws || warn "nfqws süreci görünmüyor!"
echo
info "nftables zapret kuralları:"
sudo nft list table inet zapret 2>/dev/null | head -30 || warn "inet zapret tablosu bulunamadı."
echo
info "Kurulum bitti. Test: ./verify.sh"
