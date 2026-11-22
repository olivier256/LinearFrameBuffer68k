# Linear Frame Buffer sur Mega Drive : fiche récapitulative

*État au 22 novembre 2026. ROM de test vérifiée sous Genesis Plus GX ; pas encore testée sur vraie console.*

---

## 1. Enjeux

Le VDP de la Mega Drive ne connaît que des **tiles** (8×8, 4bpp, 32 octets). Dans un tile, une rangée de 8 pixels occupe 4 octets, et les rangées se suivent verticalement. Pour dessiner au pixel (rendu 3D, raycasting, effets, ports de code « bitmap »), on utilise d'ordinaire un buffer organisé **par tiles** (souvent en colonnes). Cela complique toutes les routines de tracé : l'adresse d'un pixel n'est pas une simple fonction linéaire de (x, y).

**Objectif :** que le 68k dessine dans un buffer **linéaire** classique :

```
offset = y * 64 + x / 2      ; 128 px de large, 4bpp, 2 pixels par octet
```

Ce buffer doit être copié **tel quel** en VRAM par DMA, sans réorganisation, et le VDP doit l'afficher correctement.

**Pourquoi c'est intéressant :**
- les routines de tracé deviennent triviales (lignes, remplissage, sprites logiciels, rendu colonne par colonne) ;
- le transfert reste un DMA brut de 7168 octets par image ;
- tout le travail d'adressage est reporté sur le VDP (VScroll et H_INT), qui le fait « gratuitement ».

**Le prix :** une H_INT à chaque ligne affichée, qui consomme du temps 68k et de la bande passante VDP.

---

## 2. Principe

### Disposition en VRAM
- Buffer de **128×112** pixels en 4bpp, soit **7168 octets**, placé à partir du tile 400 (VRAM `0x3200`).
- Une ligne du buffer fait 64 octets, c'est-à-dire exactement **2 tiles**. La ligne `y` occupe les tiles `400+2y` et `401+2y`.
- Le groupe de 8 pixels `k` (0..15) de la ligne `y` correspond à la **rangée `k & 7`** du tile `400 + 2y + (k >> 3)`.

Les 8 premiers groupes de la ligne correspondent donc aux rangées 0 à 7 du premier tile, et les 8 suivants aux rangées 0 à 7 du second.

### Affichage
- **Deux plans entrelacés.** Le plan A affiche les groupes pairs et le plan B les groupes impairs. Sur chaque plan, l'autre cellule contient le tile 0, transparent.
- **Tilemap.** La rangée `y` du tilemap correspond à la ligne `y` du buffer. Il faut donc 112 rangées, d'où des plans de **32×128 cellules**.
- **VScroll par colonne (mode 2-cell).** Chaque colonne de 16 px a sa propre valeur pour A et pour B :
  - plan A : rangées 0, 2, 4, 6, 0, 2… ;
  - plan B : rangées 1, 3, 5, 7, 1, 3…
- **À chaque ligne écran, la base de toutes les colonnes avance de +7.** Il faut +8 pour passer à la rangée suivante du tilemap, mais l'écran a lui-même avancé d'une ligne, d'où −1.

Formule (ligne écran `L = 56 + y`, rangée de tile `r`) :

```
v = 7y + r − 56   (mod 1024)
```

### Cycle d'une image

| Lignes écran | Affichage | Ce qui se passe |
|---|---|---|
| 0 – 55 | ON | VScroll pointé sur les rangées vides du plan (112..127) ; l'H_INT ne fait que compter |
| 56 – 167 | ON | une H_INT par ligne : écriture des valeurs VSRAM de la ligne suivante |
| 168 – 223 | **OFF** | DMA RAM → VRAM des 7168 octets, à pleine vitesse |
| VBlank | — | V_INT : réinitialisation, le 68k dessine l'image suivante |

---

## 3. Décisions (et pourquoi)

| Décision | Raison |
|---|---|
| **Rester en VScroll 2-cell**, ne jamais passer en plein écran | En plein écran, seuls VSRAM[0] et VSRAM[1] sont utilisés : les décalages par colonne disparaissent. Il n'existe pas de « base commune + deltas ». |
| **Base +7 par ligne** (et non +8) | +8 décale d'une rangée de tile par ligne, ce qui donne une image fausse. |
| **Table VSRAM précalculée** (112 lignes × N mots) | Aucun calcul dans l'H_INT : chaque cycle compte (voir §4). |
| **Vecteur H_INT → `jmp` en RAM**, organisé en machine à états | Pas de test de ligne ni de `mulu` dans le chemin critique. Les étapes sont : attente, buffer, dernière ligne, fin, inactif. |
| **Affichage coupé après la dernière ligne, DMA à ce moment-là** | Le VBlank seul donne environ 6 Ko de DMA en H32 et environ 7,8 Ko en H40 (NTSC) : trop juste pour 7 Ko. Avec l'affichage coupé, le bas de l'écran et le VBlank donnent environ 94 lignes de DMA rapide. Le 68k est gelé environ 35 lignes. |
| **Affichage ON en haut**, VScroll vers des rangées vides | Le bit VB du statut VDP vaut aussi 1 quand l'affichage est coupé. Il faut l'affichage allumé pour pouvoir filtrer l'H_INT parasite de la ligne 224. |
| **Mode H40** | Il offre plus de créneaux d'accès VDP par ligne et plus de débit DMA que le H32. |
| **Coupure de l'affichage une H_INT plus tard** que la dernière écriture VSRAM | Mesuré sous Genesis Plus GX : le registre 1 prend effet une ligne plus tôt que la VSRAM. |
| **Buffer RAM toujours de 128×112**, largeur visible paramétrable | Le stride reste de 64 octets, donc l'adressage reste linéaire quelle que soit la fenêtre affichée. |

### Erreurs corrigées par rapport au document d'origine
- « +8 par ligne » → **+7**.
- Table VScroll `0,0,1,1,2,2…` → **`0,1,2,3,4,5,6,7,0,1…`** (A/B entrelacés par colonne).
- « Les deltas sont gardés en VScroll plein écran » → **faux**.
- « DMA de 7168 octets pendant le VBlank » → **pas assez de temps** en H32, et à la limite en H40.

---

## 4. État des lieux

### Ce qui marche (Genesis Plus GX)
- Une ROM de test complète :
  - des diagonales et un cercle calculés à la construction ;
  - un carré de 16×16 dessiné à chaque image par le 68k en adressage linéaire ;
  - un DMA par image.
- La comparaison pixel par pixel avec le buffer attendu ne relève **aucune erreur**, sur plusieurs images, hormis le carré mobile, attendu.

### La limite mesurée : la bande passante VDP par ligne

Pendant l'affichage, le VDP n'accepte qu'une écriture du 68k par créneau d'accès, et il y en a peu par ligne. Il faut 2 mots VSRAM par colonne de 16 px.

| Largeur visible | Mots VSRAM par ligne | Résultat |
|---|---|---|
| 96 px | 12 | OK, avec de la marge |
| **112 px** | **14** | **OK, à la limite** (ROM par défaut) |
| 128 px | 16 | **Décroche** : l'H_INT dure plus d'une ligne, des interruptions sont perdues et l'image s'étire jusqu'à la ligne ~181 |

Le seuil est très serré : avec 12 mots, l'ajout d'un `mulu` (70 cycles) dans l'H_INT suffisait à tout faire décrocher.

### Ce qui reste incertain
- **Sur vraie console**, la limite (14 mots), le décalage d'une ligne du registre 1 et les éventuelles déchirures quand les écritures débordent sur la ligne active restent à vérifier.
- **Temps 68k disponible** : il n'a pas été mesuré. L'H_INT tourne sur 112 lignes ; il faut savoir ce qu'il reste pour le rendu.
- **Couleur 0** : elle est transparente, donc un pixel de valeur 0 affiche la couleur de fond (registre 7). C'est sans conséquence si le fond vaut la couleur 0 de la palette 0.

### Livrables (ce dépôt)
- `src/lfb.s` : source GNU as (binutils m68k).
- `tools/gen_data.py` : génère la table VSRAM, les tilemaps, l'image de fond, la palette et `config.inc`.
- `build.sh` : construit `roms/lfb.bin` (`VIS_COLS=6|7|8` choisit la largeur).
- `tools/test_emu.py` : lance la ROM sous Genesis Plus GX et compare l'écran au buffer attendu.
- `roms/lfb_96px.bin`, `roms/lfb_112px.bin` et `roms/lfb_128px.bin`.

---

## 5. Directions possibles

### A. Valider sur matériel (priorité)
- Passer les trois ROMs sur une vraie Mega Drive (flashcart), en NTSC et en PAL.
- Ajouter un repère visuel de timing, par exemple changer la couleur de fond dans l'H_INT, pour voir où tombent les écritures dans la ligne.
- Comparer avec BlastEm et Exodus, réputés plus précis sur les créneaux d'accès VDP.

### B. Récupérer les 128 px
- **Écrire à l'avance.** Commencer l'écriture des colonnes de gauche dès que possible, voire préparer la ligne L+1 pendant la ligne L, en jouant sur l'ordre d'écriture pour suivre le faisceau. C'est risqué, mais c'est la seule piste qui garde 128 px à pleine résolution verticale.
- **Moins de mots par ligne.** Aucune variante strictement linéaire avec un stride de 64 octets ne l'évite : la réécriture complète à chaque ligne est inhérente au principe.
- **Accepter 112 px**, ou une fenêtre de 112×112 dans un buffer de 128 de large. C'est la solution pragmatique.

### C. Libérer du temps et de la bande passante
- **Moins de lignes** : 128×96 ou 112×96 réduisent le nombre d'H_INT et la taille du DMA.
- **Doublement vertical** (128×56 affiché sur 112 lignes) : sur la 2ᵉ ligne de chaque paire, il faut une base de −1. On réécrit donc toujours à chaque ligne : aucun gain en bande passante, mais deux fois moins de pixels à dessiner.
- **Mesurer le temps 68k libre** (compteur dans la boucle principale) pour savoir ce que coûte réellement l'astuce.

### D. Exploiter le principe
- Un **double buffer** en RAM : dessiner l'image N+1 pendant que N est transférée.
- Une **démo de rendu** qui profite de l'adressage linéaire : raycaster, tracé de lignes, polygones pleins. Le projet Fog of War pourrait en bénéficier.
- Combiner avec des **sprites matériels** par-dessus le buffer pour un HUD ou des objets.
- **Comparer** avec un buffer en tiles organisé en colonnes (méthode classique) : temps de dessin, temps 68k libre et complexité du code.

### E. Outillage
- Un portage vers **vasm** (syntaxe mot), si c'est votre assembleur habituel.
- Intégrer `tools/test_emu.py` dans un test automatique (ROM → émulateur → comparaison) pour valider chaque modification.
