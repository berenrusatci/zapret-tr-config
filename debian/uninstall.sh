#!/usr/bin/env bash
# zapret'i durdurur, otomatik başlatmayı kapatır. /opt/zapret dizinini SİLMEZ.
set -euo pipefail
echo "==> zapret durduruluyor..."
sudo systemctl disable --now zapret.service || true
echo "==> Kalan firewall kuralları temizleniyor..."
sudo nft delete table inet zapret 2>/dev/null || true
sudo /opt/zapret/init.d/sysv/zapret stop 2>/dev/null || true
echo "==> Bitti. Tamamen silmek için: sudo rm -rf /opt/zapret /etc/systemd/system/zapret.service && sudo systemctl daemon-reload"
