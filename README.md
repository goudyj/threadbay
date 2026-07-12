# Orchestrate — app macOS

Petite app native (menu-bar + fenêtre) pour créer, lister et ouvrir les « espaces »
d'`orchestrate`. 100 % Swift, elle lit et écrit **les mêmes fichiers** que la CLI Rust :

- `~/Library/Application Support/com.jlex.orchestrate/settings.yaml`
- `~/.orchestrate/spaces.yaml`

Un espace créé dans l'app apparaît donc dans `orchestrate space list`, et inversement.

## Fonctionnalités

- **Lister** les espaces, groupés par projet (menu-bar et fenêtre).
- **Créer** un espace : choix du projet, nom de la nouvelle branche, et **branche de base**
  (choisie parmi les branches du dépôt). Sous le capot : clone local du dépôt source,
  remotes repointés vers les vrais upstreams, puis `checkout <base>` + `checkout -b <branche>`.
- **Ouvrir** un espace dans **VS Code**, **Zed**, **Cursor** ou le **Finder**.
- **Supprimer** un espace (dossier + entrée de suivi).
- **Réglages** : projet par défaut, ajout/retrait de projets, ouverture directe du `settings.yaml`.

## Prérequis

- macOS 14+
- `git` dans le PATH (résolu via un login shell, comme dans un terminal)
- `code` / `zed` / `cursor` pour les actions d'ouverture correspondantes

## Développement

```bash
cd macos
swift build          # compile
swift test           # tests unitaires + test d'intégration git (hors-ligne)
swift run Orchestrate # lance l'app depuis le terminal
```

Le paquet est aussi ouvrable directement dans Xcode (`File ▸ Open` → `macos/Package.swift`).

## Construire l'app double-cliquable

```bash
cd macos
./scripts/build-app.sh   # produit Orchestrate.app (menu-bar, sans icône Dock)
open Orchestrate.app
```

## Architecture

- **`OrchestrateCore`** (librairie testable) : modèles + IO YAML (`Settings`, `SpaceStore`),
  `Naming`, `Shell` (résolution du PATH), `GitService`, `SpaceService`, `OpenService`.
- **`Orchestrate`** (exécutable) : `@main`, UI SwiftUI (`MenuBarView`, `MainWindow`,
  `NewSpaceView`, `SettingsView`) et `AppState`.

Au lancement, l'app **affiche sa fenêtre**. Elle vit ensuite dans la barre de menus (sans icône
Dock) et rouvre la fenêtre au double-clic sur l'app ou via « Ouvrir la fenêtre » du menu. La fenêtre
principale est une `NSWindow` pilotée par l'`AppDelegate` (affichage fiable sous `LSUIElement`).
