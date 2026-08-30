# zapret-tr-config — Debian / Ubuntu

Türkiye (Türk Telekom) için çalışan **zapret** yapılandırması — Discord ses/görüntü dahil.
Debian ve Ubuntu türevlerinde tek komutla kurulur.

```bash
unzip zapret-tr-config-debian.zip
cd zapret-tr-config-debian
./install.sh
```

Script sudo'yu kendisi ister; **root olarak çalıştırma.**

## Ne yapıyor

1. `curl git nftables ipset iptables` kurar.
2. zapret yoksa getirir:
   - önce GitHub'daki son sürüm arşivini indirip `install_bin.sh` ile mimarine uygun
     **hazır ikiliyi** seçer (derleyici gerekmez);
   - o çalışmazsa derleme bağımlılıklarını kurup **kaynaktan derler** (`make systemd`).
   İkisi de `/opt/zapret` altına kurar.
3. `files/config` → `/opt/zapret/config`, `files/zapret-hosts-user-exclude.txt` →
   `/opt/zapret/ipset/`. Mevcut dosyalar `*.bak-<tarih>` olarak yedeklenir.
4. `nft` yoksa config'i otomatik `FWTYPE=iptables`'a çevirir.
5. systemd unit'ini `/etc/systemd/system/` altına kurar, enable eder, başlatır.

Doğrulama: `./verify.sh` · Kapatma: `./uninstall.sh`

## Strateji

`files/config` içindeki `NFQWS_OPT` üç bloktan oluşuyor:

| Trafik | Strateji |
| --- | --- |
| TCP 443 | `fakeddisorder`, split-pos=1, `autottl=-5` |
| UDP 443 (QUIC) | `fake` × 6, sahte QUIC initial: `quic_initial_www_google_com.bin` |
| UDP 50000-65535 | `fake` × 6, L7 filtresi `discord,stun` — Discord ses |

`MODE_FILTER=none`: hostlist yok, tüm TLS/QUIC trafiğine uygulanır. Daha güvenilir ama
daha geniş — bozulan siteler exclude listesine giriyor.

`INIT_APPLY_FW=1` kritik: bu satır olmadan servis çalışır ama firewall kuralları
yüklenmez, yani hiçbir şey olmaz. Sessiz hata.

## Exclude listesi

`fakeddisorder` bazı servislerin ClientHello'sunu bozuyor. Dışarıda tutulanlar:

- **Steam / Valve** — indirmeler ve arkadaş listesi bozuluyordu.
- **WhatsApp / Meta (`fbcdn.net` dahil)** — sunucu TLS `decode error 562` dönüyordu.

Yeni bir site zapret açıkken bozuluyorsa: alan adını
`files/zapret-hosts-user-exclude.txt` dosyasına ekle, `./install.sh` tekrar çalıştır.

## Bu strateji sende çalışmayabilir

Bu config **Türk Telekom'un DPI'ına karşı** ayarlandı. Başka bir ISP'de (veya TT
davranışını değiştirdiğinde) hiçbir şey yapmayabilir. O durumda kendi stratejini bul:

```bash
sudo /opt/zapret/blockcheck.sh
```

Çıktıda çalışan `--dpi-desync=...` kombinasyonunu `files/config` içindeki `NFQWS_OPT`
bloklarına yazıp `./install.sh` tekrar çalıştır.

## Sorun giderme

```bash
sudo systemctl status zapret.service    # servis durumu
journalctl -u zapret.service -b         # bu açılıştaki loglar
pgrep -a nfqws                          # süreç ve argümanları
sudo nft list table inet zapret         # aktif kurallar (nftables modunda)
```

**Her şey yavaşladı / bağlantı koptu:** `./uninstall.sh` çalıştır; düzeliyorsa strateji
suçlu. **Sadece belirli site bozuk:** exclude listesine ekle. **Discord sesi yok:**
UDP 50000-65535 bloğunun ayakta olduğunu ve `NFQWS_PORTS_UDP` içinde bu aralığın
bulunduğunu doğrula.

**Debian 10 ve öncesi** iptables-legacy kullanıyor olabilir; script bunu algılayıp
`FWTYPE=iptables`'a düşer ama nftables modu daha iyi test edilmiştir.

## Kaynak

zapret: https://github.com/bol-van/zapret
