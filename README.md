# wfb-ath9k-lab

Banc d'essai wfb-ng avec deux dongles Atheros AR9271 (2.4 GHz, HT20).  
Firmware custom pour figer le MCS (0, 1, 2, 3).

## Matériel

- 2x dongles USB AR9271 (Alpha AWUS036NHA + générique AliExpress)
- Debian 12/13 ou Ubuntu 24.04+ (x86_64)

## Firmware custom (MCS fixe)

Le firmware stock ignore les demandes de rate du driver `ath9k_htc`. Ce fork permet de figer le MCS à la compilation.

```bash
git clone https://github.com/alixpat/open-ath9k-htc-firmware.git
cd open-ath9k-htc-firmware

# Compiler (première fois ~30-60min pour le toolchain, ensuite ~30s)
# Les dépendances de build sont documentées dans le README du dépôt
make MCS=0    # 6.5 Mbit/s — portée max
# make MCS=1  # 13 Mbit/s — compromis
# make MCS=2  # 19.5 Mbit/s — équilibré
# make MCS=3  # 26 Mbit/s — vidéo HD

# Sauvegarder le firmware stock
# Debian : le stock est en .fw non compressé
sudo cp /lib/firmware/ath9k_htc/htc_9271-1.4.0.fw /lib/firmware/ath9k_htc/htc_9271-1.4.0.fw.bak
# Ubuntu 24.04+ : le stock est en .fw.zst, pas besoin de backup (il reste en place)

# Installer
sudo cp firmware/htc_9271-MCS0.fw /lib/firmware/ath9k_htc/htc_9271-1.4.0.fw

# Recharger le driver
sudo modprobe -r ath9k_htc && sudo modprobe ath9k_htc
```

Retour au firmware stock :
- **Debian** : `sudo cp /lib/firmware/ath9k_htc/htc_9271-1.4.0.fw.bak /lib/firmware/ath9k_htc/htc_9271-1.4.0.fw`
- **Ubuntu** : `sudo rm /lib/firmware/ath9k_htc/htc_9271-1.4.0.fw` (le noyau reprend le `.fw.zst` stock)

Puis recharger le driver : `sudo modprobe -r ath9k_htc && sudo modprobe ath9k_htc`

### MCS — AR9271 HT20 1SS

| MCS | Modulation | Débit théo. | Sensibilité |
|-----|------------|-------------|-------------|
| 0   | BPSK 1/2   | 6.5 Mbit/s  | -82 dBm     |
| 1   | QPSK 1/2   | 13.0 Mbit/s | -79 dBm     |
| 2   | QPSK 3/4   | 19.5 Mbit/s | -77 dBm     |
| 3   | 16-QAM 1/2 | 26.0 Mbit/s | -72 dBm     |
| 4   | 16-QAM 3/4 | 39.0 Mbit/s | -68 dBm     |
| 5   | 64-QAM 2/3 | 52.0 Mbit/s | -65 dBm     |
| 6   | 64-QAM 3/4 | 58.5 Mbit/s | -64 dBm     |
| 7   | 64-QAM 5/6 | 65.0 Mbit/s | -63 dBm     |

> Les tests de ce lab se concentrent sur MCS 0-3 (longue portée). MCS 4-7 sont supportés par le firmware mais non testés ici.

## Installation wfb-ng

```bash
sudo apt install -y gnupg curl iw jq \
  gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
  gstreamer1.0-plugins-bad gstreamer1.0-libav gstreamer1.0-x

# Dépôt wfb-ng
curl -fsSL https://apt.wfb-ng.org/public.asc | sudo gpg --dearmor --yes -o /usr/share/keyrings/wfb-ng.gpg

# Debian 12/13 (forcer bookworm)
echo "deb [signed-by=/usr/share/keyrings/wfb-ng.gpg] https://apt.wfb-ng.org/ bookworm release-25.01" \
  | sudo tee /etc/apt/sources.list.d/wfb-ng.list

# Ubuntu 24.04 (noble supporté nativement)
# echo "deb [signed-by=/usr/share/keyrings/wfb-ng.gpg] https://apt.wfb-ng.org/ noble release-25.01" \
#   | sudo tee /etc/apt/sources.list.d/wfb-ng.list

sudo apt update && sudo apt install -y wfb-ng
```

### Clés de chiffrement

wfb-ng chiffre le lien radio. Il faut générer une paire de clés et les distribuer :

```bash
# Générer les clés (sur une des deux machines)
sudo wfb_keygen

# Les clés sont créées dans /etc/
# /etc/gs.key    → à copier sur la machine RX (ground station)
# /etc/drone.key → à copier sur la machine TX (drone/émetteur)

# Copier la clé vers l'autre machine (exemple)
scp /etc/drone.key user@machine-tx:/tmp/
ssh user@machine-tx "sudo cp /tmp/drone.key /etc/drone.key && sudo chmod 600 /etc/drone.key"
```

Chaque machine n'a besoin que de sa propre clé : `gs.key` sur le RX, `drone.key` sur le TX.

## Configuration

### Exclure l'interface de NetworkManager

NetworkManager va tenter de gérer l'interface AR9271. Il faut l'exclure (remplacer le nom d'interface par le vôtre, visible avec `iw dev`) :

```bash
# /etc/NetworkManager/conf.d/wfb.conf
[keyfile]
unmanaged-devices=interface-name:wlx00c0cab4fb55  # adapter à votre interface
```

Puis `sudo systemctl restart NetworkManager`.

### /etc/default/wifibroadcast

```
WFB_NICS="wlx00c0cab4fb55"  # adapter à votre interface
```

Le nom de l'interface est visible avec `iw dev`.

### /etc/wifibroadcast.cfg

Ce fichier n'existe pas par défaut, il faut le créer. Il surcharge la configuration par défaut de wfb-ng (`/usr/lib/python3/dist-packages/wfb_ng/conf/master.cfg`).

**Machine TX (drone/émetteur)** :

```bash
sudo tee /etc/wifibroadcast.cfg << 'EOF'
[common]
wifi_channel = 11

[drone_tunnel]
fec_k = 1
fec_n = 4
EOF
```

**Machine RX (ground station)** :

```bash
sudo tee /etc/wifibroadcast.cfg << 'EOF'
[common]
wifi_channel = 11

[gs_tunnel]
fec_k = 1
fec_n = 4
EOF
```

### Optimisation FEC pour la portée

Le FEC (Forward Error Correction) ajoute de la redondance aux paquets radio. Plus le ratio `fec_n / fec_k` est élevé, plus le lien tolère de pertes, au prix du débit utile.

| fec_k | fec_n | Perte tolérée | Débit utile (MCS 0) | Usage |
|-------|-------|---------------|---------------------|-------|
| 1     | 2     | 50%           | ~3 Mbit/s           | Défaut tunnel |
| 1     | 4     | 75%           | ~1.5 Mbit/s         | Portée élevée |
| 1     | 6     | 83%           | ~1 Mbit/s           | Portée maximale |

Pour du tunnel IP (SSH, ping), `fec_k=1 fec_n=4` est un bon point de départ. Monter à `fec_n=6` si les pertes sont trop élevées en limite de portée.

### Démarrer

```bash
sudo systemctl start wifibroadcast@drone   # TX
sudo systemctl start wifibroadcast@gs      # RX
wfb-cli gs                                 # vérifier le lien côté RX
wfb-cli drone                              # vérifier le lien côté TX

# Debug
sudo journalctl -xu wifibroadcast@gs -f    # logs RX
sudo journalctl -xu wifibroadcast@drone -f # logs TX
```

## Vidéo H.265

**TX** — vers le port 5602 (écouté par wfb-ng) :
```bash
gst-launch-1.0 v4l2src device=/dev/video0 \
  ! image/jpeg,width=640,height=480,framerate=15/1 ! jpegdec ! videoconvert \
  ! x265enc bitrate=250 tune=zerolatency speed-preset=ultrafast \
  ! rtph265pay config-interval=1 ! udpsink host=127.0.0.1 port=5602 sync=false
```

**RX** — port 5600 :
```bash
gst-launch-1.0 udpsrc port=5600 \
  ! application/x-rtp,encoding-name=H265,payload=96 ! rtph265depay \
  ! avdec_h265 ! videoconvert ! xvimagesink sync=false
```

## Tunnel IP

Géré automatiquement par les services (GS = 10.5.0.1, drone = 10.5.0.2).

```bash
ping 10.5.0.2        # depuis RX
ssh user@10.5.0.2    # depuis RX
```

## Test de portée par MCS

Flasher le firmware pour le MCS voulu, relancer les services, puis :

1. Fixer un MCS (`make MCS=X`, flasher, recharger)
2. S'éloigner par paliers (50m, 100m, 200m, 500m…)
3. À chaque palier :

```bash
# Vérifier le RSSI et les stats du lien
wfb-cli gs

# Test de perte de paquets
ping -c 100 10.5.0.2
```

4. Noter le RSSI, la latence moyenne et le taux de perte
5. Recommencer avec un autre MCS

## Licence

MIT
