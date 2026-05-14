# Patch `ath/regd.c` — canaux 12-13 et pleine puissance sur AR9271

Ce patch retire le verrou regdomain « custom-reg » posé par le driver `ath`
(commun à `ath9k_htc`, `ath9k`, `ath10k`, etc.) à partir de la regdom inscrite
dans l'EEPROM. Sans patch, **cfg80211 calcule les channel limits effectifs
comme l'intersection de cette regdom EEPROM et de la regdom globale**, ce qui
bloque les canaux 12-13 et plafonne la puissance dès qu'une des deux est
restrictive.

## Symptôme sans patch

AR9271 (Alfa AWUS036NHA ou clone AR9271 AliExpress) sous kernel récent :

- EEPROM regdom (Alfa `0x8348`, clone `0x0` → default driver) → alpha2 `US`
  → `2400-2472 @ 30 dBm` posé en custom-reg sur le wiphy.
- Regdom globale `FR` (poussée par un Country IE reçu d'un AP local, ou
  par `iw reg set FR`) → `2400-2483 @ 20 dBm`.
- Intersection appliquée par cfg80211 sur la phy :
  - Puissance = min(20, 30) = **20 dBm**
  - Bande = 2400-2483 ∩ 2400-2472 = **2400-2472** → canaux 12 (2467) et 13
    (2472) débordent en HT20 (±10 MHz) → marqués `(disabled)`.

`iw phy phyN info | grep '24[67]'` montre alors :

```
* 2467.0 MHz [12] (disabled)
* 2472.0 MHz [13] (disabled)
```

## Ce que le patch modifie

Dans `drivers/net/wireless/ath/regd.c::ath_regd_init_wiphy()` :

| Flag / appel supprimé             | Effet supprimé                                                                 |
|-----------------------------------|--------------------------------------------------------------------------------|
| `REGULATORY_STRICT_REG`           | cfg80211 ne force plus le wiphy à respecter strictement la regdom custom.      |
| `REGULATORY_CUSTOM_REG`           | Plus de marquage « custom-reg » → plus d'intersection appliquée à la phy.      |
| `REGULATORY_COUNTRY_IE_FOLLOW_POWER` | La phy ne reçoit plus la puissance d'un Country IE comme plafond local.    |
| `wiphy_apply_custom_regulatory()` | La regdom EEPROM (US ici) n'est plus posée sur la phy au probe.                |
| `ath_reg_apply_radar_flags()`     | Flags radar du driver ath (5 GHz DFS) plus appliqués — irrelevant en 2.4 GHz.  |
| `ath_reg_apply_world_flags()`     | Idem, scan passif/no-IR sur world regd plus forcé.                             |

Résultat : la phy AR9271 hérite directement de la **regdom globale cfg80211**.
Plus d'intersection. C'est la regdom globale qui décide seule ce qui est
autorisé.

Le diff complet est dans [`patches/0001-ath-no-custom-regd.patch`](../patches/0001-ath-no-custom-regd.patch).

## Quel regdom global utiliser

Cherché dans `wireless-regdb 2026.02.04` (db.txt). Entrées 2.4 GHz couvrant
canaux 1-13 à ≥30 dBm :

| Code | Plage 2.4 GHz       | Puissance | Note                       |
|------|---------------------|-----------|----------------------------|
| `GY` | 2402-2482 @ 40 MHz  | 30 dBm    | **Recommandé** — pas de DFS|
| `BZ` | 2402-2482 @ 40 MHz  | 30 dBm    |                            |
| `IN` | 2402-2482 @ 40 MHz  | 30 dBm    |                            |
| `VE` | 2402-2482 @ 40 MHz  | 30 dBm    |                            |
| `BR` | 2400-2483.5 @ 40    | 30 dBm    |                            |
| `PK` | 2400-2500 @ 40 MHz  | 30 dBm    | couvre aussi canal 14      |
| `CR` | 2402-2482 @ 40 MHz  | 36 dBm    |                            |
| `NZ` | 2400-2483.5 @ 40    | 36 dBm    |                            |
| `HK` | 2400-2483.5 @ 40    | 36 dBm    |                            |
| `PA` | 2400-2483.5 @ 40    | 36 dBm    |                            |
| `AU` | 2400-2483.5 @ 40    | 4000 mW (36 dBm) |                     |
| `CA` | 2400-2483.5 @ 40    | 4000 mW (36 dBm) |                     |

> **Note hardware** : le AR9271 plafonne typiquement bien en dessous de 30 dBm
> en pratique (~20-23 dBm). Une regdom plus permissive **autorise** plus, mais
> la radio ne suit pas forcément. Mesurer au spectre-analyseur si critique.

## Build et installation

### Pré-requis
```bash
sudo apt install build-essential linux-headers-$(uname -r) dpkg-dev
```

### Récupération de la source kernel et application du patch

```bash
mkdir -p ~/wfb-ath9k-lab-build && cd ~/wfb-ath9k-lab-build
apt source linux=$(uname -r | sed 's/+.*//')-1   # version Debian, adapter
cd linux-*/
patch -p1 < /path/to/wfb-ath9k-lab/patches/0001-ath-no-custom-regd.patch
```

### Compilation out-of-tree de `ath.ko` seul

Créer `~/wfb-ath9k-lab-build/ath-patched/` avec les fichiers du dossier
`drivers/net/wireless/ath/` (sans `ath5k`, `ath6kl`, `ath9k`, `ath10k`, etc.,
qui sont des sous-modules — on ne touche qu'à la lib `ath`) :

```bash
mkdir -p ath-patched
cp linux-*/drivers/net/wireless/ath/{regd.c,regd.h,regd_common.h,reg.h,ath.h,debug.c,dfs_pattern_detector.c,dfs_pattern_detector.h,dfs_pri_detector.c,dfs_pri_detector.h,hw.c,key.c,main.c,spectral_common.h,trace.c,trace.h} ath-patched/
cat > ath-patched/Kbuild <<'EOF'
obj-m += ath.o
ath-objs := main.o regd.o hw.o key.o dfs_pattern_detector.o dfs_pri_detector.o debug.o trace.o
ccflags-y := -DCONFIG_ATH_DEBUG
EOF
cat > ath-patched/Makefile <<'EOF'
all:
	$(MAKE) -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules
clean:
	$(MAKE) -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean
EOF
make -C ath-patched
```

### Installation

```bash
sudo install -D -m 644 ath-patched/ath.ko /lib/modules/$(uname -r)/updates/ath.ko
sudo depmod -a
```

Le module dans `updates/` prime sur celui dans `kernel/` sans l'écraser.
Rollback : `sudo rm /lib/modules/$(uname -r)/updates/ath.ko && sudo depmod -a`.

### Configuration du regdom global persistant

```bash
echo 'options cfg80211 ieee80211_regdom=GY' | \
  sudo tee /etc/modprobe.d/cfg80211-wfb.conf
```

⚠️ Un Country IE reçu d'un AP associé peut écraser ce hint au runtime. Pour
les tests wfb-ng, déconnecter la carte wifi interne avant :
`sudo nmcli radio wifi off`.

### Reboot ou rechargement à chaud

Reboot recommandé. Rechargement à chaud théorique :

```bash
# Décharger tous les modules dépendants de cfg80211 (ath9k_htc, mac80211, etc.)
# … puis recharger. En pratique très souvent un reboot est plus propre.
```

## Vérification

Module patché bien chargé :

```bash
sudo modinfo ath | grep filename
# → /lib/modules/.../updates/ath.ko
sudo cat /sys/module/ath/srcversion
sudo modinfo /lib/modules/$(uname -r)/updates/ath.ko | grep srcversion
# Les deux doivent être identiques.
```

Modparam appliqué :

```bash
cat /sys/module/cfg80211/parameters/ieee80211_regdom
# → GY
```

Channel limits effectifs sur la phy AR9271 :

```bash
sudo /usr/sbin/iw reg get | head -5
# global / country GY (ou autre si Country IE reçu)
sudo /usr/sbin/iw phy phy1 info | grep -E '2412|2467|2472'
# canaux 1, 12, 13 enabled à la puissance du regdom
```

Si 12-13 sont `(disabled)` : voir `docs/patch-ath-regd-troubleshoot.md` (à
créer au besoin) — vérifier que le bon `ath.ko` est en mémoire, que le
modparam n'a pas été écrasé par un Country IE, et qu'aucune autre regdom
n'a été posée via `iw reg set` après coup.

## Limites connues

- **Sécurité réglementaire** : ce patch retire des limites volontairement
  posées par le driver. L'utiliser hors-bande (canaux 12-13 en EU, 30+ dBm
  partout) **n'est pas légal** dans la plupart des juridictions. Usage en
  banc d'essai isolé / cage de Faraday / champ ouvert peu peuplé recommandé.
- **Pas un self-managed wiphy** : on n'a pas marqué la phy comme
  self-managed (`REGULATORY_WIPHY_SELF_MANAGED`). Si un Country IE arrive,
  cfg80211 va l'appliquer globalement. C'est pour ça qu'on coupe la wifi
  interne pendant les tests.
- **Impact sur autres cartes ath** : ce `ath.ko` patché est commun à toutes
  les cartes ath présentes (ath9k, ath10k, ath11k, …). Si tu as une autre
  carte ath PCIe / USB en parallèle, elle hérite aussi du patch.
