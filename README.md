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
- **Lancer des agents** (Claude Code, Codex, shell, commande custom) dans un **terminal
  embarqué** (SwiftTerm), plusieurs par espace : sélecteur de sessions, relancer/arrêter/
  effacer, badges d'agents actifs dans la sidebar et le menu-bar.
- **Être notifié** (notifications macOS) quand un agent a **fini son tour**, **a besoin de
  toi** (permission) ou quand la **session se termine**. Un clic ramène sur la session.
- **Ouvrir** un espace dans **VS Code**, **Zed**, **Cursor** ou le **Finder**.
- **Supprimer** un espace (dossier + entrée de suivi ; ses agents sont arrêtés).
- **Réglages** : projet par défaut, ajout/retrait de projets, **catalogue d'agents**
  (placeholders `{space_path}`, `{branch}`…), ouverture directe du `settings.yaml`.

## Terminal embarqué & agents

Voir le plan : `docs/plan-terminal-embarque.html`. En bref :

- Un **agent** = une commande lancée via un login shell (`zsh -lc "exec …"`, PATH identique
  à un vrai terminal) dans le dossier de l'espace, à l'intérieur d'un
  `LocalProcessTerminalView` SwiftTerm (PTY complet : TUI, souris, couleurs, resize).
- Le catalogue d'agents vit dans
  `~/Library/Application Support/com.jlex.orchestrate/agents.yaml` (fichier **app-only**,
  jamais réécrit par la CLI Rust). Défauts : Claude, Codex, Shell.
- **Détection de fin** par trois canaux : fin de process (SwiftTerm), hooks **Claude Code**
  (`Stop`, `Notification` — injectés dans `.claude/settings.local.json` *de l'espace*, la
  config globale n'est pas touchée) et **Codex** (`-c notify=…` par process). Les hooks
  appellent `orchestrate-notify.sh`, qui pousse `{session_id, kind, payload}` sur un
  **socket Unix** (`…/com.jlex.orchestrate/orchestrate.sock`) ouvert par l'app — et devient
  un no-op si l'app ne tourne pas.
- À la fermeture de l'app avec des agents actifs : avertissement, puis arrêt propre
  (SIGTERM/SIGHUP, SIGKILL après 3 s).

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

- **`OrchestrateCore`** (librairie testable) : modèles + IO YAML (`Settings`, `SpaceStore`,
  `AgentLibrary`), `Naming`, `Shell` (résolution du PATH), `GitService`, `SpaceService`,
  `OpenService`, `HookInjection` + `AgentEvent` + `EventSocketServer` (notifications agents).
- **`Orchestrate`** (exécutable) : `@main`, UI SwiftUI (`MenuBarView`, `MainWindow`,
  `TerminalPane`, `NewSpaceView`, `SettingsView`), `AppState`, et la couche terminal
  (`AgentSession`, `SessionManager`, `TerminalHostView`, `NotificationService`) sur SwiftTerm.

Au lancement, l'app **affiche sa fenêtre**. Elle vit ensuite dans la barre de menus (sans icône
Dock) et rouvre la fenêtre au double-clic sur l'app ou via « Ouvrir la fenêtre » du menu. La fenêtre
principale est une `NSWindow` pilotée par l'`AppDelegate` (affichage fiable sous `LSUIElement`).
