# Résultats de mesures

Chaque session de mesures terrain est consignée dans un fichier daté.

## Convention de nommage

```
results/YYYY-MM-DD_<lieu>_<MCS>.md
```

Exemples :
- `2025-06-12_chemin-de-saint-jacques_MCS0.md`
- `2025-07-03_parking-leclerc_MCS1-vs-MCS3.md`

## Template d'une session

À copier dans un nouveau fichier au début de chaque session :

```markdown
# Session : <lieu> — <date>

## Matériel
- TX : <machine, dongle (modèle + adresse MAC partielle), antenne>
- RX : <idem>
- Distance maximale visée : <m>

## Configuration
- Firmware : MCS <X> (sortie de `htc_9271-MCSX.fw`)
- wfb-ng version : `dpkg -l wfb-ng | tail -1`
- Canal : <N> (<MHz>)
- FEC : `fec_k=<K> fec_n=<N>`
- txpower : <dBm ou "driver default">

## Conditions
- Météo : <temp, humidité, vent>
- Visibilité : <ligne de vue / obstacles>
- Interférences observées : <wifi voisins, microondes…>

## Mesures

| Distance (m) | RSSI (dBm) | Perte ping (%) | Latence moy. (ms) | Notes |
|---|---|---|---|---|
| 50 | -55 | 0 | 3.2 | RAS |
| 100 | -62 | 0 | 4.1 | |
| 200 | -71 | 2 | 6.8 | |
| ... | | | | |

Source des valeurs :
- RSSI : `wfb-cli gs` colonne RSSI moyenne sur 5s
- Perte : `ping -c 100 10.5.0.2`
- Latence : `ping -c 100 10.5.0.2` moy. arrondie

## Observations
<text libre : décrochage, retour de lien, comportements bizarres>

## Conclusion
- Portée utile (perte < 5%) : <m>
- Portée limite (perte < 50%) : <m>
- Comparaison avec session précédente : <gain/perte par rapport à un autre MCS>
```

## Vue d'ensemble

À mesure que les sessions s'accumulent, agréger les conclusions dans un tableau résumé au fond de ce README :

| Date | Lieu | MCS | FEC | Portée utile | Portée limite |
|---|---|---|---|---|---|
| _vide_ | | | | | |
