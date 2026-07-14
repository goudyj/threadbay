# Terminal embarqué & agents — avancement

Suivi d'implémentation du plan `docs/plan-terminal-embarque.html` (décisions 1→9 closes).

## Phase 0 — Spike SwiftTerm ✅ (plomberie validée, go/no-go visuel à faire à la main)
- Dépendance SPM `SwiftTerm` (v1.14.0) ajoutée au target `Orchestrate`.
- API vérifiée sur les sources : `startProcess(executable:args:environment:execName:currentDirectory:)`,
  `process.shellPid` public, `terminate()`, délégué rappelé sur la main queue,
  `Terminal.getEnvironmentVariables` fournit `TERM`/`COLORTERM`/`LANG` (UTF-8 OK pour les TUI).
- ⚠ Le rendu interactif réel de Claude/Codex (écran alternatif, souris, redraw) reste à
  valider à l'œil en lançant l'app — non automatisable ici.

## Phase 1 — Modèle de sessions ✅
- `AgentDefinition` (+ `Kind` claude/codex/shell/custom) — `OrchestrateCore/AgentLibrary.swift`.
- `AgentSession` (start/stop/restart/clear, état `.starting/.running/.exited` via délégué,
  `attention` pour les badges) — `Orchestrate/AgentSession.swift`.
- `SessionManager` observable (launch/close/select, N sessions par espace) — `Orchestrate/SessionManager.swift`.
- Wrapper `NSViewRepresentable` (`TerminalHostView`) : la vue terminal appartient à la
  session et survit aux changements de sélection.
- Arrêt : SIGTERM + SIGHUP (shells interactifs), SIGKILL après 3 s si ignoré.

## Phase 2 — Intégration UI ✅
- Sidebar = espaces groupés par projet, **badge** nombre d'agents actifs (orange si « a
  besoin de toi ») ; « Tous les espaces » = vue d'ensemble.
- Détail d'espace : en-tête (branche, chemin, Ouvrir dans…/Finder/Supprimer) +
  `TerminalPane` : onglets de sessions, barre relancer/arrêter/effacer, bouton « + ».
- « Lancer un agent » : ligne d'espace (vue d'ensemble), détail, état vide, et menu-bar.

## Phase 3 — Config des agents ✅
- `agents.yaml` **app-only** dans `~/Library/Application Support/com.jlex.orchestrate/`
  (décision n°3 : zéro risque interop avec la CLI Rust). Défauts : Claude, Codex, Shell.
- Placeholders `{space_path} {branch} {task_value} {name} {project}` (`CommandTemplate`).
- Éditeur d'agents dans les Réglages (nom, commande, type, ajout/retrait).

## Phase 4 — Notifications & détection de fin ✅
- **Canal 1** (fin de process) : `processTerminated` → badge + notification « session terminée ».
- **Canal 3** (hooks) :
  - Claude : hooks `UserPromptSubmit`/`Stop`/`Notification` fusionnés dans
    `.claude/settings.local.json` **de l'espace** (les autres clés du fichier sont
    préservées). `UserPromptSubmit`→`Stop` encadre le tour : état « réfléchit » (indigo)
    visible depuis la sidebar et les onglets de session.
  - Codex : `-c notify=["…orchestrate-notify.sh","codex-notify"]` par process.
  - Identité par env : `ORCHESTRATE_SESSION_ID` + `ORCHESTRATE_SOCK`.
  - Notifieur `orchestrate-notify.sh` → **socket Unix** `orchestrate.sock` (décision n°8) ;
    no-op silencieux si l'app ne tourne pas. Testé de bout en bout (nc -U).
- Notifications macOS (`UserNotifications`, inertes hors bundle) ; clic → fenêtre + session.
- **Canal 2** (OSC 9/777/99) : non fait — optionnel dans le plan (« si le spike le permet
  facilement ») ; SwiftTerm ne les expose pas tel quel, à traiter plus tard si besoin.

## Phase 5 — Finitions ✅
- Quitter avec agents actifs : avertissement puis arrêt propre (décision n°4).
- Suppression d'espace : ses sessions sont fermées d'abord (risque « espace supprimé »).
- Police mono système 13, fond sombre ; ⌘C/⌘V câblés dans la vue terminal.
- États vides (`ContentUnavailableView`), erreurs remontées via l'alerte existante.
- `build-app.sh` OK (release + bundle signé ad-hoc) ; README mis à jour.

## Vérifications effectuées
- `swift build` + `swift test` : 24/24 tests verts (dont nouveaux : AgentLibrary,
  CommandTemplate, HookInjection, AgentEvent, EventSocketServer).
- Smoke test app : lancement → socket + notifieur + `agents.yaml` créés, arrêt propre.
- Script notifieur : envoi réel sur socket vérifié, et no-op exit 0 sans app.

## Reste à valider à la main (non automatisable)
- Phase 0 go/no-go visuel : lancer Claude/Codex dans l'app et vérifier rendu TUI,
  saisie, souris, resize.
- Notifications macOS réelles (autorisation système) depuis le bundle `.app`.
