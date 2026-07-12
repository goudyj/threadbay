import OrchestrateCore
import SwiftUI

/// Create form: pick a project, name the new branch, pick the base branch it is
/// created from. Under the hood this is the CLI's feature flow.
struct NewSpaceView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var projectName = ""
    @State private var branchName = ""
    @State private var baseBranch = ""
    @State private var branches: [String] = []
    @State private var loadingBranches = false

    private var selectedProject: Project? {
        app.settings.projects.first { $0.name == projectName }
    }

    private var baseOptions: [String] {
        var options = branches
        if !baseBranch.isEmpty, !options.contains(baseBranch) {
            options.insert(baseBranch, at: 0)
        }
        return options
    }

    private var canCreate: Bool {
        selectedProject != nil
            && !branchName.trimmingCharacters(in: .whitespaces).isEmpty
            && !baseBranch.isEmpty
            && !app.isBusy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nouvel espace").font(.title2).bold()

            if app.settings.projects.isEmpty {
                Text("Aucun projet configuré. Ajoute un projet dans les Réglages.")
                    .foregroundStyle(.secondary)
            } else {
                Form {
                    Picker("Projet", selection: $projectName) {
                        ForEach(app.settings.projects) { Text($0.name).tag($0.name) }
                    }

                    TextField("Nom de la branche", text: $branchName, prompt: Text("feat/ma-fonctionnalite"))

                    HStack {
                        Picker("Branche de base", selection: $baseBranch) {
                            ForEach(baseOptions, id: \.self) { Text($0).tag($0) }
                        }
                        if loadingBranches {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
            }

            HStack {
                if app.isBusy {
                    ProgressView().controlSize(.small)
                    Text("Création en cours…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Créer") { Task { await create() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
        }
        .padding(20)
        .frame(width: 480)
        .task { await setup() }
        .onChange(of: projectName) { _, _ in Task { await loadBranches() } }
    }

    private func setup() async {
        if projectName.isEmpty {
            projectName = app.settings.defaultProject ?? app.settings.projects.first?.name ?? ""
        }
        await loadBranches()
    }

    private func loadBranches() async {
        guard let project = selectedProject else {
            branches = []
            baseBranch = ""
            return
        }
        loadingBranches = true
        let listed = await app.listBranches(project: project)
        let current = await app.currentBranch(project: project)
        branches = listed
        baseBranch = current ?? listed.first ?? ""
        loadingBranches = false
    }

    private func create() async {
        guard let project = selectedProject else { return }
        let ok = await app.createSpace(
            project: project, branchName: branchName, baseBranch: baseBranch)
        if ok { dismiss() }
    }
}
