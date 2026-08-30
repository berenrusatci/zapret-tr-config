#!/usr/bin/env bash
# zapret'i durdurur ve otomatik başlatmayı kapatır. Paketi KALDIRMAZ, config'i SİLMEZ.
set -euo pipefail
echo "==> zapret durduruluyor..."
sudo systemctl disable --now zapret.service || true
echo "==> Kalan nftables kuralları temizleniyor..."
sudo nft delete table inet zapret 2>/dev/null || true
echo "==> Bitti. Paket duruyor; tamamen silmek için: sudo pacman -Rns zapret-git"
