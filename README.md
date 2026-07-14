# ThreadBay

ThreadBay est une app macOS qui permet de travailler sur plusieurs branches Git en parallèle et de lancer des agents de développement dans des terminaux intégrés.

## Comment fonctionne l'app

1. Ajoutez un projet depuis les réglages en sélectionnant son dépôt Git local.
2. Créez un **espace** depuis une nouvelle branche, une branche existante ou une pull request GitHub.
3. ThreadBay crée un clone indépendant à côté du dépôt source, puis y ouvre la branche choisie. Chaque tâche dispose ainsi de son propre dossier et n'affecte pas les autres espaces.
4. Depuis cet espace, lancez Claude Code, Codex, un shell ou une commande personnalisée dans le terminal intégré. Plusieurs sessions peuvent tourner en même temps.
5. Ouvrez le dossier dans VS Code, Zed, Cursor ou le Finder. La suppression d'un espace arrête ses sessions, supprime son dossier et le retire de ThreadBay.

L'app reste accessible depuis la barre des menus et peut envoyer une notification lorsqu'un agent termine un tour ou attend une action. Les projets, espaces et agents sont conservés dans des fichiers YAML locaux :

- `~/Library/Application Support/com.jlex.threadbay/settings.yaml`
- `~/.threadbay/spaces.yaml`
- `~/Library/Application Support/com.jlex.threadbay/agents.yaml`

## Prérequis

- macOS 14 ou plus récent ;
- Swift 6, fourni par Xcode ou les Command Line Tools ;
- Git ;
- `gh` pour créer un espace depuis une pull request ;
- les commandes des agents ou éditeurs que vous souhaitez utiliser (`claude`, `codex`, `code`, `zed`, `cursor`, etc.).

## Construire depuis le code source

```bash
git clone https://github.com/goudyj/threadbay.git
cd threadbay
swift build
swift test
./scripts/run-app.sh
```

Swift Package Manager télécharge automatiquement les dépendances au premier build. Le lanceur construit en mode debug puis ouvre le bundle macOS, nécessaire pour tester les notifications. Pour créer l'app en mode release sans la lancer :

```bash
./scripts/build-app.sh
```

Le script compile en mode release, assemble `ThreadBay.app` à la racine du projet et la signe localement. Vous pouvez ensuite la déplacer dans le dossier `Applications`.
