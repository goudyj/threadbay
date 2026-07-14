# ThreadBay — app macOS

Petite app native (menu-bar + fenêtre) pour créer, lister et ouvrir les « espaces »
d'`threadbay`. 100 % Swift, elle lit et écrit **les mêmes fichiers** que la CLI Rust :

- `~/Library/Application Support/com.jlex.threadbay/settings.yaml`
- `~/.threadbay/spaces.yaml`

Un espace créé dans l'app apparaît donc dans `threadbay space list`, et inversement.

## Fonctionnalités

- **Lister** les espaces, groupés par projet (menu-bar et fenêtre).
- **Créer** un espace depuis une nouvelle branche, une branche locale ou distante existante,
  ou une pull request GitHub. Les branches sont recherchables et peuvent être actualisées
  avec un `fetch`. Les pull requests ouvertes sont listées avec leur titre et leur branche ;
  un numéro exact permet aussi de retrouver une PR absente de la liste. Les noms créés par
  l'app n'ajoutent pas de préfixe de type (`feature`/`review`).
- **Choisir la langue** de l'interface dans les Réglages : langue de macOS (par défaut),
  anglais, français, espagnol ou chinois simplifié.
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
  `~/Library/Application Support/com.jlex.threadbay/agents.yaml` (fichier **app-only**,
  jamais réécrit par la CLI Rust). Défauts : Claude, Codex, Shell.
- **Détection de fin** par trois canaux : fin de process (SwiftTerm), hooks **Claude Code**
  (`Stop`, `Notification` — injectés dans `.claude/settings.local.json` *de l'espace*, la
  config globale n'est pas touchée) et **Codex** (`-c notify=…` par process). Les hooks
  appellent le helper compilé `ThreadBay.app/Contents/Resources/bin/threadbay-notify`,
  qui pousse `{session_id, kind, payload}` sur un
  **socket Unix** (`…/com.jlex.threadbay/threadbay.sock`) ouvert par l'app — et devient
  un no-op si l'app ne tourne pas.
- À la fermeture de l'app avec des agents actifs : avertissement, puis arrêt propre
  (SIGTERM/SIGHUP, SIGKILL après 3 s).

## Prérequis

- macOS 14+
- `git` dans le PATH (résolu via un login shell, comme dans un terminal)
- GitHub CLI (`gh`) dans le PATH pour créer un espace depuis une pull request
- `code` / `zed` / `cursor` pour les actions d'ouverture correspondantes

## Développement

```bash
swift build          # compile
swift test           # tests unitaires + test d'intégration git (hors-ligne)
swift run ThreadBay # lance l'app depuis le terminal
```

Le paquet est aussi ouvrable directement dans Xcode (`File ▸ Open` → `Package.swift`).

## Construire l'app double-cliquable

```bash
./scripts/build-app.sh   # produit ThreadBay.app (menu-bar, sans icône Dock)
open ThreadBay.app
```

## Architecture

- **`ThreadBayCore`** (librairie testable) : modèles + IO YAML (`Settings`, `SpaceStore`,
  `AgentLibrary`), `Naming`, `Shell` (résolution du PATH), `GitService`, `SpaceService`,
  `OpenService`, `HookInjection` + `AgentEvent` + `EventSocketServer` (notifications agents).
- **`ThreadBay`** (exécutable) : `@main`, UI SwiftUI (`MenuBarView`, `MainWindow`,
  `TerminalPane`, `NewSpaceView`, `SettingsView`), `AppState`, et la couche terminal
  (`AgentSession`, `SessionManager`, `TerminalHostView`, `NotificationService`) sur SwiftTerm.

Au lancement, l'app **affiche sa fenêtre**. Elle vit ensuite dans la barre de menus (sans icône
Dock) et rouvre la fenêtre au double-clic sur l'app ou via « Ouvrir la fenêtre » du menu. La fenêtre
principale est une `NSWindow` pilotée par l'`AppDelegate` (affichage fiable sous `LSUIElement`).
