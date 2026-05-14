# wfb-ath9k-lab

Banc d'essai wfb-ng avec deux dongles Atheros AR9271 (2.4 GHz, HT20).  
Firmware custom pour figer le MCS (0, 1, 2, 3).

## Matériel

- 2x dongles USB AR9271 (Alpha AWUS036NHA + générique AliExpress)
- Debian 12/13 ou Ubuntu 24.04+ (x86_64)

## Convention de notation

Dans tout ce document, `<WIFI_IFACE>` désigne le nom de l'interface wifi du dongle AR9271. Récupère-le **avant** de commencer, sur chaque machine :

```bash
iw dev
# Exemple : Interface wlx00c0cab4fb55
```

Le format `wlxXXXXXXXXXXXX` (12 hex après `wlx`) est dérivé de l'adresse MAC du dongle. Substitue `<WIFI_IFACE>` par ta valeur dans toutes les commandes ci-dessous.

## Reproduire l'environnement de manip

Les sections ci-dessous référencent plusieurs dépôts externes (firmware AR9271 patché, source amont wfb-ng, driver RTL8812AU). Pour les cloner d'un coup au même endroit que ce repo :

```bash
./setup.sh
```

Le script est idempotent : il vérifie chaque dépôt avant de cloner et n'écrase rien.

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
unmanaged-devices=interface-name:<WIFI_IFACE>
```

Puis `sudo systemctl restart NetworkManager`.

### /etc/default/wifibroadcast

```
WFB_NICS="<WIFI_IFACE>"
```

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

Les mesures sont à consigner dans `results/` (voir `results/README.md` pour le format).

## Bande étroite (5/10 MHz) — pousser le link budget

> **⚠️ Section non validée expérimentalement.** Les chiffres ci-dessous sont théoriques. À confirmer / corriger après les premiers tests terrain. Tableau de résultats vierge en fin de section.

L'AR9271 + `ath9k_htc` mainline supportent nativement les bandes 5 MHz et 10 MHz, en plus du 20 MHz par défaut. wfb-ng les expose explicitement via `bandwidth = 5` ou `10` dans `/etc/wifibroadcast.cfg`. Côté RTL8812AU/EU, ces modes sont **inaccessibles** (verrou silicium/firmware). C'est donc un avantage spécifique au lab AR9271.

### Principe

Le bruit thermique d'un récepteur est proportionnel à la largeur de bande : `N = kTB`. Diviser B par 2 abaisse le noise floor de 3 dB, donc améliore la sensibilité d'autant à modulation égale. En espace libre (atténuation en 1/r²), **+6 dB ≈ doublement de la portée utile**.

### Gain théorique (à vérifier)

À MCS0 fixé (BPSK 1/2, le mode le plus sensible) :

| Bandwidth | Noise floor théo. | Sensibilité MCS0 théo. | Gain vs 20 MHz | Débit utile théo. |
|-----------|-------------------|------------------------|----------------|-------------------|
| 20 MHz    | -101 dBm          | ~-82 dBm               | référence      | 6.5 Mbit/s        |
| 10 MHz    | -104 dBm          | ~-85 dBm               | **+3 dB**      | 3.25 Mbit/s       |
| 5 MHz     | -107 dBm          | ~-88 dBm               | **+6 dB**      | 1.6 Mbit/s        |

Le débit utile reste largement suffisant pour du tunnel IP, télémétrie mavlink et même H.265 à très bas bitrate.

### Configuration

Côté TX et RX, `/etc/wifibroadcast.cfg` :

```ini
[common]
wifi_channel = 2412     # spécifier en MHz, pas en numéro de canal
wifi_region  = 'BO'     # région permissive (régulatoire — à tes risques)

[base]
bandwidth = 5           # ou 10 — commencer par 10, descendre à 5 si stable
mcs_index = 0
ldpc      = 1           # vérifier que l'AR9271 l'accepte à 5/10 MHz
stbc      = 1

[radio_base]
fec_k = 1
fec_n = 8               # FEC très généreux : 87% pertes tolérées, ~200 kbit/s utile en 5 MHz
```

Le firmware AR9271 custom (MCS figé) doit rester en place. Il agit sur l'index MCS, pas sur la largeur de bande — donc en principe compatible avec 5/10 MHz, **à confirmer**.

### Caveats à valider avant de croire les chiffres

1. **Firmware custom à 5/10 MHz** : alixpat/open-ath9k-htc-firmware a été testé à HT20. Vérifier qu'aucun chemin codé en dur ne casse le mode étroit. Test rapide : flasher MCS0, configurer `bandwidth = 10`, lancer `wfb-cli` et observer que des paquets passent.
2. **Régulatoire** : les canaux 5/10 MHz hors standard 802.11. `wifi_region = 'BO'` lève les blocages CRDA mais ne te dispense pas du droit local. Test sur banc fermé d'abord.
3. **Drift de l'oscillateur** : le TCXO de l'AR9271 (~±20 ppm) reste OK à 5 MHz mais marge plus serrée. À surveiller en dérive thermique (dongle au soleil).
4. **Numérotation canal** : les channels entiers (1, 6, 11…) sont définis pour HT20. À 5/10 MHz, spécifier en MHz directement (`wifi_channel = 2412`). master.cfg confirme que c'est supporté.
5. **`iw` doit accepter la commande** : vérifier `iw list | grep -A20 "Supported channel width"` et `iw dev <WIFI_IFACE> set freq 2412 10MHz` doit retourner 0.

### Protocole de test

1. Sur banc fermé (atténuateur ou faraday), avec MCS0 firmware déjà flashé :
   - Test A : `bandwidth = 20` (référence)
   - Test B : `bandwidth = 10`
   - Test C : `bandwidth = 5`
2. À chaque palier, sur 5 minutes :
   - Démarrer `wifibroadcast@gs` / `@drone`, attendre la session
   - Lancer `ping -c 600 -i 0.5 10.5.0.2` (5 min de ping)
   - Capturer le RSSI moyen via `wfb-cli gs`
   - Capturer le débit utile effectif via `iperf3` (en parallèle, sur le tunnel)
3. Comparer : le gain de RSSI à perte égale doit suivre la table ci-dessus (±1 dB pour bruit de mesure).
4. Si A→B confirme ~+3 dB et B→C confirme ~+6 dB cumulé, descendre en extérieur avec antenne directive pour mesurer le gain en portée réel.

### Résultats (à remplir)

| Date | Bandwidth | MCS | FEC | RSSI moyen | Perte | Débit utile mesuré | Notes |
|------|-----------|-----|-----|------------|-------|--------------------|-------|
| _vide_ | | | | | | | |

Une fois ces lignes complétées, mettre à jour la table « gain théorique » avec les valeurs mesurées (et marquer celles qui restent théoriques).

## Dépannage

### Le dongle n'apparaît pas

```bash
lsusb | grep -i atheros          # USB ID 0cf3:9271 attendu
iw dev                           # liste les interfaces wifi
dmesg | grep -i ath9k_htc        # erreurs de chargement firmware/driver
```

Si `dmesg` montre `firmware loading failed`, vérifier que `/lib/firmware/ath9k_htc/htc_9271-1.4.0.fw` existe et n'est pas corrompu (`file` doit retourner `data`, pas `ASCII text`).

### Le firmware custom ne se charge pas

Symptôme : `dmesg` montre l'ancien firmware ou un mismatch de version.

- **Debian** : le driver lit `.fw` non compressé. Vérifier l'extension et le SHA du fichier installé.
- **Ubuntu 24.04+** : le driver lit `.fw.zst` en priorité. Si tu poses un `.fw` à côté, **il faut supprimer le `.fw.zst`** sinon il reprend le firmware stock.

```bash
sudo ls -l /lib/firmware/ath9k_htc/htc_9271-1.4.0.fw*
sudo modprobe -r ath9k_htc && sudo modprobe ath9k_htc
dmesg | tail -20
```

### NetworkManager reprend l'interface après reboot

La conf `unmanaged-devices` doit être dans `/etc/NetworkManager/conf.d/` (pas dans `NetworkManager.conf` directement) et NM doit être redémarré.

```bash
sudo cat /etc/NetworkManager/conf.d/wfb.conf
sudo nmcli device status              # <WIFI_IFACE> doit afficher "unmanaged"
sudo systemctl restart NetworkManager
```

### `wfb-cli` reste à 0 paquet RX

Dans l'ordre, vérifier :

1. **Service côté émetteur lancé** : `sudo systemctl status wifibroadcast@drone` côté TX.
2. **Même canal des deux côtés** : `wifi_channel` dans `/etc/wifibroadcast.cfg` doit matcher (et le canal doit être autorisé par le `wifi_region` du driver).
3. **Même `link_domain`** : sinon les paquets sont rejetés par hashage MAC.
4. **Clés cohérentes** : `drone.key` (TX) et `gs.key` (RX) doivent être issus du même `wfb_keygen`. Si tu as régénéré d'un côté, regénère partout.
5. **Carte en mode monitor** : `iw dev <WIFI_IFACE> info` doit indiquer `type monitor`. Sinon, le service wfb-ng n'a pas pris la main (NetworkManager ou autre).

### Ping `10.5.0.2` timeout mais `wfb-cli` montre des paquets

L'interface tunnel n'est pas montée ou non routée d'un côté :

```bash
ip link show wfb-tun          # doit être UP
ip addr show wfb-tun          # doit avoir 10.5.0.X/24
sudo journalctl -xu wifibroadcast@gs | grep -i tunnel
```

## Licence

MIT — voir `LICENSE`.
