# Proxyn

Client iOS natif pour **Proxmox VE** — supervision temps réel et administration complète
d'un nœud isolé ou d'un cluster, sans passer par un navigateur.

Écrit en SwiftUI (iOS 18+), sans dépendance externe : tout passe par l'API REST
`api2/json` de vos serveurs. Aucune donnée ne transite par un service tiers.

---

## Ce que l'application sait faire

### Supervision
- **Vue d'ensemble** : CPU / RAM / stockage agrégés du cluster (pondérés par le nombre
  de cœurs et dédupliqués pour les stockages partagés), débit réseau instantané calculé
  à partir des compteurs cumulés, nœuds, instances actives, tâches en cours.
- **Alertes** dérivées de l'état réel : perte de quorum, nœud hors ligne, stockage > 90 %,
  RAM saturée, instance verrouillée, tâches en échec.
- **Graphes RRD interactifs** (Swift Charts) sur 1 h / 24 h / 7 j / 1 mois / 1 an, avec
  scrubbing horizontal : CPU + I/O wait, mémoire + swap, réseau, E/S disque, charge système.
- **Micro-graphes temps réel** : entre deux écritures RRD (Proxmox n'écrit qu'à la minute),
  l'app maintient son propre tampon glissant à l'intervalle de polling.

### Nœuds
Statut détaillé (modèle CPU, noyau, version PVE, uptime, load average, I/O wait),
mémoire et swap, disques physiques avec état SMART et usure, interfaces réseau,
services systemd (démarrer / arrêter / redémarrer), paquets en attente de mise à jour,
journal des tâches, démarrage et arrêt groupés, redémarrage et extinction du nœud,
terminal (xterm.js) intégré.

### VM et conteneurs
- Démarrer, arrêter, arrêt forcé, redémarrer, suspendre, reprendre, réinitialiser.
- **Snapshots** : création (avec état mémoire pour les VM), restauration, suppression.
- **Sauvegardes** : vzdump à la demande (mode, compression, note, protection),
  restauration, protection / déprotection, suppression.
- **Clonage** (lié ou complet, vers un autre nœud / stockage) et **migration**
  (à chaud, disques locaux inclus).
- Modification des vCPU et de la mémoire, agrandissement d'un disque virtuel,
  conversion en modèle, suppression.
- Configuration complète : disques, interfaces, type d'OS, ordre de boot, protection,
  démarrage automatique.
- **Pare-feu** par instance : activation et liste des règles.
- **Agent invité QEMU** : système détecté et adresses IP réelles.
- **Console** noVNC (VM) et xterm.js (LXC) intégrée via WKWebView.

### Stockage
Liste consolidée avec taux d'occupation, navigateur de contenu (sauvegardes, ISO,
modèles LXC, images disque) avec recherche et filtres, suppression, protection,
et téléchargement direct d'une ISO ou d'un modèle depuis une URL — le fichier est
récupéré par le serveur, rien ne transite par l'iPhone.

### Activité
Flux des tâches du cluster groupées par jour, filtres (en cours / échecs / planifié),
journal de tâche en direct avec coloration et interruption possible, jobs de sauvegarde
planifiés et jobs de réplication.

### Widgets
Extension WidgetKit : écran d'accueil (petit / moyen / grand) et écran verrouillé
(circulaire / rectangulaire / en ligne). Les widgets interrogent Proxmox directement
grâce au profil partagé via l'App Group, et affichent le dernier instantané connu
en attendant.

---

## Sécurité

| Aspect | Traitement |
|---|---|
| Mots de passe, secrets de jeton | Trousseau iOS (`kSecAttrAccessibleAfterFirstUnlock`), jamais dans les préférences |
| Authentification | Ticket `PVEAuthCookie` + `CSRFPreventionToken`, ou `PVEAPIToken` |
| Double authentification | TOTP pris en charge (défi `tfa-challenge`), à la connexion et au renouvellement du ticket |
| TLS auto-signé | Acceptation explicite par serveur, ou **épinglage** de l'empreinte SHA-256 affichée lors du test de connexion |
| Renouvellement | Le ticket est renouvelé automatiquement avant expiration ; un 401 déclenche une seule ré-authentification puis rejoue la requête |

Un jeton d'API donne accès à tout sauf à la console (limitation de Proxmox, pas de l'app).

---

## Mode démonstration

L'écran d'accueil propose **« Explorer un cluster de démonstration »**. Il branche un
faux backend (`Shared/Networking/DemoBackend.swift`) au niveau du transport du client
HTTP : 3 nœuds, 15 instances, 7 stockages, tâches, snapshots et sauvegardes, avec des
valeurs qui évoluent dans le temps. Toutes les actions fonctionnent (démarrer, cloner,
migrer, snapshoter…) et modifient l'état simulé. Aucun écran ne contient de code
spécifique au mode démo.

---

## Compiler

Prérequis : Xcode 26+. Le projet est versionné, il suffit de l'ouvrir :

```bash
open Proxyn.xcodeproj
```

Il est décrit par `project.yml` et régénéré avec
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
après tout ajout ou déplacement de fichier :

```bash
xcodegen generate
```

Pour un déploiement sur appareil, dans Xcode :

1. Sélectionner votre équipe de signature sur les cibles `Proxyn` et `ProxynWidgets`.
2. Remplacer `com.proxyn.app` par un identifiant qui vous appartient
   (dans `project.yml`, puis régénérer).
3. L'App Group `group.com.proxyn.app` n'est nécessaire que pour les widgets ;
   sans lui l'application fonctionne, les widgets affichent simplement l'état par défaut.

Compilation en ligne de commande :

```bash
xcodebuild -project Proxyn.xcodeproj -scheme Proxyn -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

---

## Architecture

```
Shared/                      compilé dans l'app ET dans l'extension widget
  Core/        Theme, Format, Keychain, décodage tolérant, stockage partagé
  Models/      ressources PVE, métriques, snapshot de cluster, profil serveur
  Networking/  client acteur, surface d'API typée, délégué TLS, backend de démo
Proxyn/
  App/         point d'entrée, splash, shell + barre d'onglets
  Design/      palette, mouvement, composants (jauges, graphes, cartes, champs)
  Features/    Dashboard, Nodes, Guests, Storage, Tasks, Console, Settings, Onboarding
  Store/       AppModel (@Observable), moteur de polling, toasts
ProxynWidgets/ extension WidgetKit
```

Points structurants :

- `ProxmoxClient` est un **acteur** : une instance par serveur, sérialise l'accès au
  ticket et gère le renouvellement.
- Toutes les vues lisent un `ClusterSnapshot` immuable produit par un seul appel à
  `/cluster/resources`. En cas d'erreur, le dernier instantané reste affiché et un
  bandeau explique la panne — jamais d'écran vide.
- Le décodage est volontairement permissif (`looseInt`, `looseString`…) : l'API Proxmox
  renvoie le même champ tantôt en nombre, tantôt en chaîne, selon la version et
  l'endpoint.
- Les actions mutantes passent toutes par `AppModel.perform`, qui gère le toast
  optimiste, le suivi de l'UPID jusqu'à la fin de la tâche, et le rafraîchissement.

---

## Design

Un instrument, pas un tableau de bord. Sombre par choix — on lit cet écran la
nuit, ou à côté d'une baie.

**Une seule couleur d'accent.** L'orange descend de celui de Proxmox, désaturé
pour ne pas vibrer sur du noir. Il n'apparaît que là où il veut dire quelque
chose : l'onglet actif, la série principale d'un graphe, l'action primaire, un
lien. Tout le reste est en niveaux de gris. Les états (vert / ambre / rouge) sont
volontairement ternes : une pastille ambre dans une colonne grise se voit ;
quinze barres colorées ne disent rien.

**Deux élévations, zéro contour.** Le fond, et la surface des cartes. Une carte
se détache par son ton, pas par une bordure — encadrer chaque bloc est
exactement ce qui fait qu'une interface a l'air assemblée plutôt que dessinée.
Les séparations à l'intérieur d'une carte sont des filets d'un pixel, alignés sur
le texte. Aucune ombre, aucun halo, aucun dégradé décoratif.

**Les chiffres portent la page.** Pas d'anneaux : une barre exprime un ratio plus
précisément qu'un arc et laisse la place aux valeurs réelles à côté. Chiffres à
chasse fixe, unité plus petite et plus discrète, transition `numericText` pour
que les compteurs s'interpolent au lieu de sauter. Libellés en casse de phrase —
pas de micro-capitales espacées.

**La fluidité vient du mouvement, pas des effets.** Un seul ressort
(`.smooth(0.34)`) pour les changements d'état, un plus lent pour les jauges, un
plus vif pour le toucher. Le grand titre se replie en barre compacte de façon
continue, pilotée par le décalage de défilement plutôt que par un seuil. Les
cartes se posent en entrant dans le champ (`scrollTransition`). Les surfaces
tactiles se compriment de 1,5 %.

**Densité assumée.** Les lignes de liste n'ont ni chevron ni icône encadrée : une
pastille d'état, le nom, une ligne d'identité, et à droite les deux nombres qui
comptent. Sur une VM, une seule action primaire contextuelle (démarrer / arrêter)
plutôt que sept boutons équivalents à relire à chaque fois.
