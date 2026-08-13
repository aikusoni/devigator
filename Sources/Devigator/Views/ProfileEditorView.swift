import AppKit
import SwiftUI

struct ProfileEditorView: View {
    @ObservedObject var store: ProfileStore

    @State private var selectedID: String?
    @State private var draft = ""
    @State private var validationMessage = ""
    @State private var isDraftValid = false
    @State private var isNewProfile = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedID) {
                    ForEach(store.profiles) { loaded in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(loaded.profile.name)
                                .font(.body.weight(.medium))
                            HStack(spacing: 5) {
                                Text(loaded.source.rawValue)
                                Text("·")
                                Text(loaded.profile.metadata.version)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                        .tag(Optional(loaded.id))
                    }
                }

                HStack {
                    Button(action: createProfile) {
                        Image(systemName: "plus")
                    }
                    .help("새 프로필")
                    Button(action: importProfile) {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .help("프로필 가져오기")
                    Spacer()
                    Button(action: reload) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("다시 불러오기")
                }
                .buttonStyle(.borderless)
                .padding(10)
                .background(.bar)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 320)
        } detail: {
            VStack(spacing: 0) {
                editorHeader
                Divider()
                TextEditor(text: $draft)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor))
                    .onChange(of: draft) { _ in validateDraft() }
                Divider()
                editorFooter
            }
        }
        .onAppear {
            store.reload()
            if selectedID == nil { selectedID = store.profiles.first?.id }
            loadSelection()
        }
        .onChange(of: selectedID) { _ in loadSelection() }
        .onReceive(store.$profiles) { profiles in
            if !isNewProfile, let selectedID,
               !profiles.contains(where: { $0.id == selectedID }) {
                self.selectedID = profiles.first?.id
            }
        }
    }

    private var editorHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(currentProfile?.profile.name ?? (isNewProfile ? "새 프로필" : "프로필을 선택하세요"))
                    .font(.headline)
                Text("Devigator Profile Schema \(ProfileValidator.supportedSchemaVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("복제", action: duplicateProfile)
                .disabled(currentProfile == nil)
            Button("내보내기…", action: exportProfile)
                .disabled(currentProfile == nil)
            Button("저장", action: save)
                .keyboardShortcut("s")
                .disabled(!isDraftValid || draft.isEmpty)
        }
        .padding(14)
        .background(.bar)
    }

    private var editorFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: isDraftValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isDraftValid ? .green : .orange)
            Text(validationMessage)
                .lineLimit(2)
            Spacer()
            if let source = currentProfile?.source, source != .user {
                Text("저장하면 사용자 오버라이드가 생성됩니다")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(.bar)
    }

    private var currentProfile: LoadedProfile? {
        guard let selectedID else { return nil }
        return store.profiles.first(where: { $0.id == selectedID })
    }

    private func loadSelection() {
        guard !isNewProfile, let currentProfile else { return }
        do {
            draft = try store.json(for: currentProfile)
            validateDraft()
        } catch {
            validationMessage = error.localizedDescription
            isDraftValid = false
        }
    }

    private func validateDraft() {
        guard !draft.isEmpty else {
            isDraftValid = false
            validationMessage = "JSON 프로필을 입력하세요."
            return
        }
        do {
            let catalog = try store.validate(json: draft)
            isDraftValid = true
            validationMessage = "유효한 프로필 \(catalog.profiles.count)개"
        } catch {
            isDraftValid = false
            validationMessage = error.localizedDescription
        }
    }

    private func createProfile() {
        selectedID = nil
        isNewProfile = true
        draft = store.templateJSON()
        validateDraft()
    }

    private func duplicateProfile() {
        guard let currentProfile else { return }
        do {
            var catalog = try store.validate(json: store.json(for: currentProfile))
            guard !catalog.profiles.isEmpty else { return }
            catalog.profiles[0].id += ".custom"
            catalog.profiles[0].name += " Custom"
            let temporary = LoadedProfile(profile: catalog.profiles[0], source: .user, fileURL: nil)
            selectedID = nil
            isNewProfile = true
            draft = try store.json(for: temporary)
            validateDraft()
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func save() {
        do {
            let original = isNewProfile ? nil : currentProfile
            let url = try store.save(json: draft, replacing: original)
            let savedCatalog = try store.validate(json: draft)
            selectedID = savedCatalog.profiles.first?.id
            isNewProfile = false
            validationMessage = "저장됨: \(url.lastPathComponent)"
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func importProfile() {
        let panel = NSOpenPanel()
        panel.title = "Devigator 프로필 가져오기"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            selectedID = try store.importProfile(from: url)
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func exportProfile() {
        guard let currentProfile else { return }
        let panel = NSSavePanel()
        panel.title = "Devigator 프로필 내보내기"
        panel.nameFieldStringValue = "\(currentProfile.id).\(ProfileStore.profileExtension)"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.export(currentProfile, to: url)
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func reload() {
        isNewProfile = false
        store.reload()
        loadSelection()
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "프로필 오류"
        alert.informativeText = message
        alert.runModal()
    }
}
