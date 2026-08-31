# zapret-tr-config — Debian / Ubuntu

Türkiye (Türk Telekom) için çalışan **zapret** yapılandırması — Discord ses/görüntü dahil.
Debian ve Ubuntu türevlerinde tek komutla kurulur.

```bash
sudo apt install -y git
git clone https://github.com/berenrusatci/zapret-tr-config.git
cd zapret-tr-config/debian
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

zapret'i **yükseltmek** için: script `/opt/zapret/nfq/nfqws` varsa "zaten kurulu" deyip
indirmeyi atlar. Yeni sürüme geçmek istiyorsan önce `sudo rm -rf /opt/zapret`, sonra
`./install.sh`. (Config'in bu repoda duruyor, kaybolmaz.)

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

## Profiller

Aynı ISP'de bile DPI her yerde aynı davranmıyor. Üç hazır profil var,
sırayla dene:

| Komut | TCP 443 stratejisi | Ne zaman |
| --- | --- | --- |
| `./install.sh` | `fakeddisorder --split-pos=1 --autottl=-5` | varsayılan |
| `./install.sh alt` | `multidisorder --split-pos=1` | varsayılan kurulu, servis ayakta, kurallar yerinde ama Discord hâlâ açılmıyorsa |
| `./install.sh tt3` | `multidisorder --split-pos=1,sniext+1,host+1,midsld-2,midsld,midsld+2,endhost-1` | ilk ikisi de açmıyorsa; TCP 80'i de kapsar |

`alt` profili 30 Ağu 2026'da, `tt3` 31 Ağu 2026'da — ikisi de Linux Mint 22.3 /
Türk Telekom'da `blockcheck.sh` ile bulundu. İki makine aynı ISP'de olmasına
rağmen `tt3`'ün çıktığı hatta `alt`'ın stratejisi (`--split-pos=1`) UNAVAILABLE:
o DPI ancak ClientHello yedi yere bölünüp ters sırada gönderilince kaçırıyor.
`tt3` ayrıca düz HTTP'yi (TCP 80) da işliyor, o hatta 80 de kesiliyordu.

UDP blokları üçünde de aynı (curl'de HTTP/3 yok, blockcheck QUIC'i test edemiyor).

**Fooling/TTL tabanlı stratejileri seçmedik.** blockcheck'te `ttl=3`,
`autottl=-1..-5`, `ts`, `md5sig`, `badseq` de AVAILABLE çıkabiliyor; ama bunlar
hop sayısına, karşı sunucunun işletim sistemine ya da istemcinin TCP timestamp
ayarına bağlı. Ağ değişince sessizce bozulurlar. Saf split stratejileri böyle
bir bağımlılık taşımaz — eşit koşulda onları tercih et.

## DPI kararsızsa — `./strategy-test.sh`

Belirti: aynı komut arka arkaya bazen `200` bazen `000` veriyor. Bu bir kurulum
hatası değil, DPI'nın kararsız davranması (birden fazla DPI kutusu ya da yük
dengeleme). Böyle bir hatta **blockcheck yanıltır**, çünkü her stratejiyi
varsayılan olarak bir kez dener: çalışmayan strateji `AVAILABLE`, çalışan
strateji `UNAVAILABLE` çıkabilir.

```bash
sudo ./strategy-test.sh 10 discord.com
```

Adayları sırayla kurar, her birini 10 kez ölçer, yüzde verir. Başta bypass'ı
kapatıp bir taban ölçümü alır — taban zaten sıfır değilse engel kısmi demektir
ve skorları ona göre okumak gerekir. Çıkarken config'i geri yükler (Ctrl-C dahil).

TLS 1.2 zorlar, bilerek: blockcheck'in kuralı, **1.2'de geçen 1.3'te de geçer,
tersi geçerli değil.** TLS 1.3'ün şifreli ServerHello'su zayıf stratejileri de
bazen geçirdiği için 1.3'e bakıp "çalışıyor" demek yanıltıcıdır.

Alternatif: `blockcheck.sh`'yi tekrar sayısı sorusunda **3 veya 5** vererek koş.
Daha yavaş ama gürültüyü aynı şekilde eler.

## DNS ayrı bir engel — `./fix-dns.sh`

Bazı hatlarda DPI'ya **ek olarak** DNS de kaçırılıyor. Belirti:

```bash
dig +short discord.com          # -> 195.175.254.2  (TTNet blok sunucusu, gerçek IP değil)
dig +short discord.com @8.8.8.8 # -> connection refused (53/UDP dışarı kapalı)
```

**Zapret DNS'e hiç dokunmaz.** Bu ayrı bir iş ve zapret çalışsa bile bu düzelmeden
tarayıcıda Discord açılmaz — sistem hâlâ blok sunucusuna gider.

```bash
./fix-dns.sh          # 853 açıksa systemd-resolved+DoT, değilse dnscrypt-proxy (DoH/443)
./fix-dns.sh --undo   # geri al
```

DNS'i DPI'dan ayırmak için, sistem DNS'ini baypas edip doğrudan gerçek IP'ye git:

```bash
curl -s -o /dev/null -m 10 -w 'discord -> %{http_code}\n' \
  --resolve discord.com:443:162.159.137.232 https://discord.com/
```

`000` değilse DPI aşılmış, kalan tek sorun DNS'tir.

## Bu strateji sende çalışmayabilir

Bu config **Türk Telekom'un DPI'ına karşı** ayarlandı. Başka bir ISP'de (veya TT
davranışını değiştirdiğinde) hiçbir şey yapmayabilir. O durumda kendi stratejini bul:

```bash
sudo systemctl stop zapret          # ÖNEMLİ — aşağıya bak
sudo /opt/zapret/blockcheck.sh
sudo systemctl start zapret
```

> ⚠️ **blockcheck'i zapret KAPALIYKEN çalıştır.** Kendi `nfqws`'ini ve firewall kuralını
> geçici olarak kendisi kurar, servise ihtiyacı yok. Servis açık kalırsa iki nfqws aynı
> `qnum 200`'e biner; blockcheck'in "hiçbir strateji uygulanmadı" temel testi bile başarılı
> görünür ve çalışmayan stratejiler `AVAILABLE` çıkar (yanlış pozitif).
>
> Ayrıca **önce DNS'i düzelt** (`./fix-dns.sh`) — bozuk DNS'le blockcheck blok sunucusunun
> IP'sine karşı ölçüm yapar, sonuçlar çöp olur.

Sorulara: domain `discord.com` · mod `standard` · TLS `1.2` · IPv6 `no`. 10-20 dk sürer.

Çıktıda çalışan `--dpi-desync=...` kombinasyonunu `files/config` içindeki `NFQWS_OPT`
bloklarına yazıp `./install.sh` tekrar çalıştır.

## Sorun giderme

```bash
sudo systemctl status zapret.service    # servis durumu
journalctl -u zapret.service -b         # bu açılıştaki loglar
pgrep -a nfqws                          # süreç ve argümanları
sudo nft list table inet zapret         # aktif kurallar (nftables modunda)

# Kural gerçekten var mı — DOĞRU sayım:
sudo nft list table inet zapret | grep -cE 'queue (num|flags|to)'
```

> ⚠️ **İki yanlış negatif tuzağı** (31 Ağu 2026'da yaşandı, saatler yedi):
> 1. `chain postrouting` **boş** görünür — gerçek kurallar `chain postnat` ve `chain prenat`
>    içindedir. Sadece postrouting'e bakıp "kural yok" sanma.
> 2. Kural metni `queue flags bypass to 200` şeklindedir, **`queue num` değil.**
>    `grep "queue num"` sıfır döner ve kurulu sistemi bozuk sanırsın.

**Her şey yavaşladı / bağlantı koptu:** `./uninstall.sh` çalıştır; düzeliyorsa strateji
suçlu. **Sadece belirli site bozuk:** exclude listesine ekle. **Discord sesi yok:**
UDP 50000-65535 bloğunun ayakta olduğunu ve `NFQWS_PORTS_UDP` içinde bu aralığın
bulunduğunu doğrula.

**Debian 10 ve öncesi** iptables-legacy kullanıyor olabilir; script bunu algılayıp
`FWTYPE=iptables`'a düşer ama nftables modu daha iyi test edilmiştir.

## Kaynak

zapret: https://github.com/bol-van/zapret
