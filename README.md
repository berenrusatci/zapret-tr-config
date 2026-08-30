# zapret-tr-config

Türkiye (Türk Telekom) için çalışan **zapret** yapılandırmam — Discord ses/görüntü dahil.
Arch tabanlı sistemlerde (Arch, CachyOS, EndeavourOS, Manjaro) tek komutla kurulur.

```bash
git clone https://github.com/berenrusatci/zapret-tr-config.git
cd zapret-tr-config
./install.sh
```

Script sudo'yu kendisi ister; root olarak çalıştırma.

## Ne yapıyor

1. `zapret-git` kurulu değilse AUR'dan kurar (paru/yay varsa onunla, yoksa `makepkg`).
2. `nftables`, `ipset`, `curl` bağımlılıklarını kontrol eder.
3. `files/config` → `/opt/zapret/config` (mevcut config `config.bak-<tarih>` olarak yedeklenir).
4. `files/zapret-hosts-user-exclude.txt` → `/opt/zapret/ipset/` (aynı şekilde yedeklenir).
5. `nftables.service` ve `zapret.service`'i enable eder, zapret'i başlatır.
6. Süreçleri ve nftables kurallarını ekrana basar.

Doğrulama: `./verify.sh` · Kapatma: `./uninstall.sh`

## Strateji

`files/config` içindeki `NFQWS_OPT` üç bloktan oluşuyor:

| Trafik | Strateji |
| --- | --- |
| TCP 443 | `fakeddisorder`, split-pos=1, `autottl=-5` |
| UDP 443 (QUIC) | `fake` × 6, sahte QUIC initial: `quic_initial_www_google_com.bin` |
| UDP 50000-65535 | `fake` × 6, L7 filtresi `discord,stun` — Discord ses |

`MODE_FILTER=none`: hostlist yok, tüm TLS/QUIC trafiğine uygulanır. Daha güvenilir ama
daha geniş — bu yüzden bozulan siteler exclude listesine giriyor.

`INIT_APPLY_FW=1` kritik: bu satır olmadan servis çalışır ama nftables kuralları
yüklenmez, yani hiçbir şey olmaz. (Sessiz hata, uzun sürmüştü.)

## Exclude listesi

`fakeddisorder` bazı servislerin ClientHello'sunu bozuyor. Dışarıda tutulanlar:

- **Steam / Valve** — indirmeler ve arkadaş listesi bozuluyordu.
- **WhatsApp / Meta (`fbcdn.net` dahil)** — sunucu TLS `decode error 562` dönüyordu.

Yeni bir site zapret açıkken bozuluyorsa: alan adını
`files/zapret-hosts-user-exclude.txt` dosyasına ekle, `./install.sh` tekrar çalıştır.

## Sorun giderme

```bash
sudo systemctl status zapret.service    # servis durumu
journalctl -u zapret.service -b         # bu açılıştaki loglar
pgrep -a nfqws                          # süreç ve argümanları
sudo nft list table inet zapret         # aktif kurallar
sudo /opt/zapret/blockcheck.sh          # yeni strateji ara (ISP değiştiyse)
```

**Her şey yavaşladı / bağlantı koptu:** `./uninstall.sh` çalıştır, düzeliyorsa strateji
suçlu. **Sadece belirli site bozuk:** exclude listesine ekle. **Discord sesi yok:**
UDP 50000-65535 bloğunun durduğunu ve `NFQWS_PORTS_UDP` içinde bu aralığın olduğunu
doğrula.

ISP veya DPI değişirse strateji ölür — `blockcheck.sh` ile yenisini bulup
`files/config` içine yazmak gerekir.

## Kaynak

zapret: https://github.com/bol-van/zapret · AUR: `zapret-git`
