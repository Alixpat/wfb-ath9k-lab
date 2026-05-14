# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Nature du dépôt

`wfb-ath9k-lab` est un **dépôt de documentation de banc d'essai**, pas du code. Il décrit une procédure reproductible pour monter un lien radio [wfb-ng](https://github.com/svpcom/wfb-ng) longue portée entre deux dongles USB Atheros AR9271 (2.4 GHz, HT20, 1 stream spatial), en utilisant un firmware AR9271 patché pour figer le MCS à la compilation.

Contenu versionné :
- `README.md` — la procédure de bout en bout.
- `LICENSE` — MIT.
- `.gitignore` — exclut défensivement `*.key`, `*.fw*`, logs, captures, notes privées.
- `setup.sh` — clone idempotent des 3 dépôts liés dans le dossier parent.
- `results/` — journaux de mesures terrain (template dans `results/README.md`).

Tout le reste (code wfb-ng, firmware patché, driver, clés) est externe et référencé via URLs ou cloné par `setup.sh` dans des dossiers frères.

## Le README est la source canonique

Le `README.md` couvre la totalité de la procédure :
1. Compilation et installation du firmware AR9271 custom (MCS 0–7) — fork `alixpat/open-ath9k-htc-firmware`.
2. Installation de wfb-ng via le dépôt apt officiel `apt.wfb-ng.org` (Debian bookworm / Ubuntu noble).
3. Génération et distribution des clés libsodium (`wfb_keygen` → `gs.key` côté RX, `drone.key` côté TX).
4. Configuration : exclusion NetworkManager, `/etc/default/wifibroadcast`, `/etc/wifibroadcast.cfg` (override de `master.cfg`).
5. Tuning FEC pour la portée (table `fec_k/fec_n` → perte tolérée / débit utile).
6. Démarrage des services `wifibroadcast@drone` / `wifibroadcast@gs`, monitoring par `wfb-cli`.
7. Pipelines GStreamer H.265 (TX `v4l2src → x265enc → udpsink:5602`, RX `udpsrc:5600 → avdec_h265`).
8. Tunnel IP 10.5.0.0/24 automatique (GS = `.1`, drone = `.2`).
9. Protocole de test de portée par paliers (RSSI, perte, latence en fonction du MCS).

Avant toute modification, **relire le `README.md`** : il est dense, en français, et chaque commande a un contexte (Debian vs Ubuntu, ordre de chargement du driver, etc.).

## Choix techniques à connaître

- **MCS fixé en dur dans le firmware**, pas via le driver. Le firmware AR9271 stock ignore les requêtes de rate du driver `ath9k_htc` — le rate d'injection est dans le firmware. Conséquence : changer de MCS = recompiler + flasher + recharger `ath9k_htc`. Pas d'ajustement à chaud.
- **Cible portée maximale** : MCS 0 (BPSK 1/2, 6.5 Mbit/s, ~-82 dBm de sensibilité). Les tests du lab portent sur MCS 0–3 ; 4–7 sont supportés mais non testés.
- **Cartes wifi en mode monitor**, exclues de NetworkManager. Le nom d'interface (`wlxXXXXXX`) doit être adapté partout (`/etc/default/wifibroadcast`, conf NetworkManager).
- **wfb-ng s'installe via apt**, pas via build source — la procédure du lab ne couvre PAS le build. Pour le build source, voir le dépôt amont.
- **Linux x86_64 uniquement** dans ce lab. Pas de RPi, pas de cross-compilation.

## Dépôts liés (hors de ce repo)

Ce lab référence trois projets externes :

| Repo | Rôle |
|---|---|
| [svpcom/wfb-ng](https://github.com/svpcom/wfb-ng) | Code amont du lien radio (binaires C/C++ + superviseur Python Twisted). Installé via apt dans ce lab. |
| [alixpat/open-ath9k-htc-firmware](https://github.com/alixpat/open-ath9k-htc-firmware) | Fork firmware AR9271 avec `make MCS=0..7`. |
| [svpcom/rtl8812au](https://github.com/svpcom/rtl8812au) | Driver out-of-tree pour RTL8812AU. **Non utilisé par ce lab** (lab AR9271), mais cité pour la complétude. |

Si tu travailles dans une copie locale de ce workspace où ces dépôts sont clonés à côté (`../wfb-ng/`, `../open-ath9k-htc-firmware/`, etc.), ils sont indépendants — chacun a son propre cycle de commit, son propre remote.

## Édition du README

- Garder le **français** et le ton existant (factuel, commandes prêtes à coller).
- Préserver les **deux variantes Debian / Ubuntu 24.04+** quand elles diffèrent (extension `.fw` vs `.fw.zst`, backup nécessaire ou non).
- Ne pas inventer de chiffres pour la table MCS / FEC : les valeurs actuelles sont théoriques et explicitement marquées comme telles. Les colonnes « Perte tolérée » et « Débit utile (MCS 0) » sont des approximations — préciser à chaque modification si la valeur est mesurée ou estimée.
- Les commandes utilisent `sudo` explicite (pas de prompt root) — conserver la convention.
- Pour les noms d'interface : toujours `wlxXXXXXXXXXXXX` (format MAC) comme exemple, jamais `wlan0` qui prête à confusion sur les distros récentes.

## Quand ce lab sera utile à enrichir

Le README documente la *méthodologie* mais pas les *résultats*. Le dossier `results/` est prévu pour ça : un fichier par session de mesures (format dans `results/README.md`), avec en-tête matériel / configuration / conditions, puis le tableau RSSI / perte / latence par distance, et une conclusion sur la portée utile.

Au fil de l'accumulation, agréger dans le tableau final de `results/README.md` (date / lieu / MCS / FEC / portée utile / portée limite) pour avoir une vue d'ensemble exploitable.

Les pannes rencontrées et leur résolution peuvent être ajoutées à la section « Dépannage » du README principal si elles sont génériques, ou consignées dans le fichier de session si elles sont contextuelles.
