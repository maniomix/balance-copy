import SwiftUI
import SwiftData
import SkeletonUI
import UniformTypeIdentifiers

// ============================================================
// MARK: - AI Chat View
// ============================================================
//
// Full-screen chat interface with the AI assistant.
// Supports streaming responses, action cards, and suggested prompts.
//
// ============================================================

struct AIChatView: View {
    @Binding var store: Store
    var initialInput: String? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var didSeedInput: Bool = false

    @StateObject private var conversation = AIConversation()
    @Environment(\.modelContext) private var modelContext
    @State private var currentSession: ChatSession?
    @State private var persistedMessageIDs: Set<UUID> = []
    @State private var input: String = ""
    @State private var isStreaming: Bool = false
    @State private var streamingText: String = ""
    @State private var streamingPhase: StreamingPhase = .thinking
    @State private var showReceiptScanner: Bool = false

    @StateObject private var aiManager = AIManager.shared
    private let trustManager = AITrustManager.shared
    @StateObject private var actionHistory = AIActionHistory.shared
    @State private var showDownloadConfirm = false
    @State private var showModelImporter = false
    @FocusState private var isInputFocused: Bool
    @State private var showAIMenu: Bool = false
    @State private var showActivityDashboard: Bool = false
    @State private var showWorkflow: Bool = false
    @State private var showIngestion: Bool = false
    @State private var showProactiveFeed: Bool = false
    @State private var showMemory: Bool = false
    @State private var showOptimizer: Bool = false
    @State private var showModeSettings: Bool = false
    @State private var showChatHistory: Bool = false
    @State private var sessionToRename: ChatSession?
    @State private var renameText: String = ""
    @State private var historyRefreshToken: UUID = UUID()

    /// Trust context preserved between classify and confirmAndExecute.
    @State private var pendingTrustContext: PendingTrustContext? = nil

    private var isModelLoading: Bool {
        if case .loading = aiManager.status { return true }
        return false
    }

    /// True when the model is fully loaded and ready to accept messages.
    private var isModelReady: Bool {
        aiManager.status == .ready || aiManager.status == .generating
    }

    var body: some View {
        NavigationStack {
            messageList
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        if !conversation.pendingActions.isEmpty {
                            actionBar
                        }
                        inputBar
                    }
                }
            .background(
                ZStack {
                    DS.Colors.bg
                    if isStreaming {
                        AIGeneratingGradient(cornerRadius: 0)
                            .transition(.asymmetric(
                                insertion: .opacity.animation(.easeIn(duration: 0.4)),
                                removal:   .opacity.animation(.easeOut(duration: 1.6))
                            ))
                    }
                }
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: isStreaming)
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(DS.Colors.subtext)
                        }
                        Button {
                            showChatHistory = true
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(DS.Colors.subtext)
                        }
                        .accessibilityLabel("Chat history")
                        SectionHelpButton(screen: .aiChat)
                    }
                }
                ToolbarItem(placement: .principal) {
                    aiNavigationTitle
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        if actionHistory.canUndo {
                            Button {
                                undoLastAction()
                            } label: {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                    .foregroundStyle(DS.Colors.accent)
                            }
                            .accessibilityLabel("Undo last AI action")
                        }
                        Button {
                            startNewChat()
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 17))
                                .foregroundStyle(DS.Colors.accent)
                        }
                        .accessibilityLabel("New chat")
                        Button {
                            showAIMenu = true
                        } label: {
                            Image(systemName: "line.3.horizontal.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(DS.Colors.subtext)
                        }
                    }
                }
            }
            .overlay {
                if isModelLoading {
                    modelLoadingOverlay
                }
            }
            .onAppear {
                loadModelIfNeeded()
                loadPersistedSessionIfNeeded()
                if !didSeedInput, let seed = initialInput, !seed.isEmpty {
                    input = seed
                    didSeedInput = true
                }
                // Phase 5: keep the AI subsystems aware of user-defined categories
                CategoryRegistry.shared.update(from: store)
            }
            .onChange(of: store.customCategoriesWithIcons) { _, _ in
                CategoryRegistry.shared.update(from: store)
            }
            .onDisappear {
                // User left the chat — schedule an aggressive unload so the
                // model frees its RAM if they don't come back soon.
                aiManager.requestUnloadSoon()
            }
            .onChange(of: conversation.messages.count) { _, _ in
                persistNewMessages()
            }
            .sheet(isPresented: $showReceiptScanner) {
                AIReceiptScannerView(store: $store)
            }
            .sheet(isPresented: $showAIMenu) {
                aiMenuSheet
            }
            .sheet(isPresented: $showActivityDashboard) {
                AIActivityDashboard(store: $store)
            }
            .sheet(isPresented: $showWorkflow) {
                AIWorkflowView(store: $store)
            }
            .sheet(isPresented: $showIngestion) {
                AIIngestionView(store: $store)
            }
            .sheet(isPresented: $showProactiveFeed) {
                AIProactiveView(store: $store)
            }
            .sheet(isPresented: $showMemory) {
                AIMemoryView()
            }
            .sheet(isPresented: $showOptimizer) {
                AIOptimizerView(store: $store)
            }
            .sheet(isPresented: $showModeSettings) {
                AIModeSettingsView()
            }
            .sheet(isPresented: $showChatHistory) {
                chatHistorySheet
            }
            .alert("Download AI Model?", isPresented: $showDownloadConfirm) {
                Button("Download (\(AIManager.modelDownloadSizeLabel))", role: .none) {
                    aiManager.downloadModel()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will download the AI model (\(AIManager.modelDownloadSizeLabel)). Make sure you're on Wi-Fi.")
            }
            .fileImporter(
                isPresented: $showModelImporter,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    guard url.lastPathComponent.hasSuffix(".gguf") else { return }
                    Task {
                        let accessing = url.startAccessingSecurityScopedResource()
                        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                        do {
                            try aiManager.importModel(from: url)
                            aiManager.loadModel()
                        } catch {
                            SecureLogger.error("Model import failed: \(error)")
                        }
                    }
                case .failure: break
                }
            }
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if conversation.messages.isEmpty && !isStreaming {
                        welcomeCard

                        if isModelReady {
                            AISuggestedPrompts { prompt in
                                sendMessage(prompt)
                            }
                        }
                    }

                    ForEach(conversation.messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }

                    if isStreaming {
                        streamingBubble
                            .id("streaming")
                    }

                    // Invisible anchor at the very bottom
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: conversation.messages.count) { _, _ in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: isStreaming) { _, streaming in
                if streaming {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    // scrollToBottom is now inlined with withAnimation in onChange handlers

    // MARK: - Welcome Card

    private var welcomeCard: some View {
        Group {
            if case .downloading(let progress, let bytes) = aiManager.status {
                downloadingCard(progress: progress, downloadedBytes: bytes)
            } else if case .error(let msg) = aiManager.status {
                modelErrorCard(message: msg)
            } else if !aiManager.isModelDownloaded && aiManager.status != .ready {
                modelNotAvailableCard
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundStyle(DS.Colors.accent)
                    Text("Centmond AI")
                        .font(DS.Typography.title)
                        .foregroundStyle(DS.Colors.text)
                    Text("Ask me anything about your finances, or tell me to add transactions, set budgets, and more.")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.subtext)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }
        }
    }

    private var modelNotAvailableCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "cpu")
                .font(.system(size: 44))
                .foregroundStyle(DS.Colors.accent)

            Text("Setup AI Assistant")
                .font(DS.Typography.title)
                .foregroundStyle(DS.Colors.text)

            Text("Centmond AI runs entirely on your device for maximum privacy. Download or import the language model to get started.")
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.subtext)
                .multilineTextAlignment(.center)

            // Primary: Download
            Button {
                showDownloadConfirm = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 18))
                    Text("Download Model (\(AIManager.modelDownloadSizeLabel))")
                        .font(DS.Typography.body)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(DS.Colors.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            // Secondary: Import from Files
            Button {
                showModelImporter = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 16))
                    Text("Import from Files")
                        .font(DS.Typography.body)
                        .fontWeight(.medium)
                }
                .foregroundStyle(DS.Colors.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(DS.Colors.accent.opacity(0.3), lineWidth: 1.5)
                )
            }

            Text("Requires Wi-Fi · One-time download\nOr AirDrop the .gguf file and tap Import")
                .font(.system(size: 11))
                .foregroundStyle(DS.Colors.subtext)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }

    private func downloadingCard(progress: Double, downloadedBytes: Int64) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(DS.Colors.surface2, lineWidth: 6)
                    .frame(width: 80, height: 80)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(DS.Colors.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: progress)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)
                    .contentTransition(.numericText())
            }

            Text("Downloading AI Model…")
                .font(DS.Typography.title)
                .foregroundStyle(DS.Colors.text)

            // Show downloaded size
            Text("\(ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)) / \(AIManager.modelDownloadSizeLabel)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(DS.Colors.subtext)

            ProgressView(value: progress)
                .tint(DS.Colors.accent)
                .padding(.horizontal, 20)

            Button {
                aiManager.cancelDownload()
            } label: {
                Text("Cancel")
                    .font(DS.Typography.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(DS.Colors.danger)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(DS.Colors.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(24)
    }

    private func modelErrorCard(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(DS.Colors.warning)

            Text("Model Error")
                .font(DS.Typography.title)
                .foregroundStyle(DS.Colors.text)

            Text(message)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.subtext)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                if aiManager.isModelDownloaded {
                    Button {
                        aiManager.loadModel()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry Loading")
                                .fontWeight(.semibold)
                        }
                        .font(DS.Typography.body)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(DS.Colors.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                Button {
                    aiManager.deleteModel()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Re-download")
                            .fontWeight(.semibold)
                    }
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(DS.Colors.accent, lineWidth: 1.5)
                    )
                }

                Button {
                    showModelImporter = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                        Text("Import from Files")
                            .fontWeight(.medium)
                    }
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.subtext)
                }
            }
        }
        .padding(24)
    }

    // MARK: - Message Bubbles

    private func messageBubble(_ message: AIMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                AIMarkdownText(text: message.content, role: message.role)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(message.role == .user
                                  ? DS.Colors.accent
                                  : (colorScheme == .dark ? DS.Colors.surfaceElevated : DS.Colors.surface))
                    )
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = message.content
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        if message.role == .user {
                            Button {
                                input = message.content
                                isInputFocused = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                        }
                    }

                // Action cards for assistant messages
                if let actions = message.actions, !actions.isEmpty {
                    let analysisTypes: Set<AIAction.ActionType> = [.analyze, .compare, .forecast, .advice]

                    // Rich saving tips card for advice/analysis actions
                    if let adviceAction = actions.first(where: { analysisTypes.contains($0.type) }),
                       let tipsCard = AISavingTipsCard.build(
                           store: store,
                           title: adviceAction.type == .advice ? "Saving Tips" : "Spending Analysis",
                           tipsText: adviceAction.params.analysisText
                       ) {
                        tipsCard
                    }

                    // Mutation action cards (non-analysis)
                    let grouped = Self.groupActions(actions)
                    ForEach(grouped, id: \.id) { group in
                        // Skip analysis-only groups (already shown as rich card above)
                        if group.actions.contains(where: { !analysisTypes.contains($0.type) }) {
                            if group.count > 1 {
                                GroupedActionCard(
                                    actions: group.actions,
                                    onConfirmAll: {
                                        for a in group.actions where a.status == .pending {
                                            confirmAndExecute(a.id)
                                        }
                                    },
                                    onRejectAll: {
                                        for a in group.actions {
                                            // Phase 7: Record rejection pattern
                                            AIMemoryStore.shared.recordApproval(actionType: a.type.rawValue, approved: false)
                                            conversation.rejectAction(a.id)
                                        }
                                    }
                                )
                            } else if let action = group.actions.first {
                                AIActionCard(action: action) { id in
                                    confirmAndExecute(id)
                                } onReject: { id in
                                    // Phase 7: Record rejection pattern
                                    if let a = conversation.pendingActions.first(where: { $0.id == id }) {
                                        AIMemoryStore.shared.recordApproval(actionType: a.type.rawValue, approved: false)
                                    }
                                    conversation.rejectAction(id)
                                }
                            }
                        }
                    }
                }
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }

    private var streamingBubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                if streamingText.isEmpty {
                    // Skeleton shimmer with dynamic phase label
                    AIThinkingShimmer(label: streamingPhase.label, icon: streamingPhase.icon)
                } else {
                    // Show streaming text with rich formatting
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 6) {
                            TypingDotsView()
                                .padding(.top, 4)
                            AIMarkdownText(text: streamingText, role: .assistant)
                        }

                        // Phase indicator below streaming text
                        if streamingPhase != .composing {
                            HStack(spacing: 4) {
                                Image(systemName: streamingPhase.icon)
                                    .font(.system(size: 10))
                                Text(streamingPhase.label)
                                    .font(.system(size: 11))
                            }
                            .foregroundStyle(DS.Colors.accent.opacity(0.7))
                            .padding(.leading, 4)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(colorScheme == .dark ? DS.Colors.surfaceElevated : DS.Colors.surface)
                    )
                    .animation(.easeInOut(duration: 0.25), value: streamingPhase.label)
                }
            }
            Spacer(minLength: 60)
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        let pending = conversation.pendingActions.filter { $0.status == .pending }
        return Group {
            if !pending.isEmpty {
                HStack {
                    Text("\(pending.count) action(s) pending")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                    Spacer()
                    Button("Confirm All (\(pending.count))") {
                        executeAllPending()
                    }
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Colors.accent)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(colorScheme == .dark ? DS.Colors.surfaceElevated : DS.Colors.surface)
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            // Receipt scan button
            Button {
                showReceiptScanner = true
            } label: {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 18))
                    .foregroundStyle(DS.Colors.accent)
            }
            .disabled(!isModelReady || isStreaming)

            TextField(isModelReady ? "Ask Centmond AI..." : "Model is loading...",
                      text: $input, axis: .vertical)
                .font(DS.Typography.body)
                .lineLimit(1...4)
                .focused($isInputFocused)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(colorScheme == .dark ? DS.Colors.surfaceElevated : DS.Colors.surface)
                )
                .disabled(!isModelReady || isStreaming)
                .submitLabel(.send)
                .onSubmit { sendMessage(input) }

            Button {
                sendMessage(input)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(!isModelReady || input.trimmingCharacters(in: .whitespaces).isEmpty || isStreaming
                                    ? DS.Colors.subtext.opacity(0.3)
                                    : DS.Colors.accent)
            }
            .disabled(!isModelReady || input.trimmingCharacters(in: .whitespaces).isEmpty || isStreaming)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Model Loading Overlay

    private var modelLoadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            AIModelLoadingView()
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.25)))
    }

    // MARK: - Navigation Title with Status

    private var aiNavigationTitle: some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Text("Centmond AI")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DS.Colors.text)
                DS.BetaBadge()
            }

            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(navStatusColor)
                        .frame(width: 6, height: 6)
                        .shadow(color: navStatusColor.opacity(0.6), radius: isModelReady ? 4 : 0)
                        .animation(.easeInOut(duration: 0.5), value: navStatusColor)

                    Text(navStatusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.Colors.subtext)
                        .contentTransition(.interpolate)
                }
                .animation(.easeInOut(duration: 0.4), value: navStatusText)

                // Phase 9: Mode indicator pill
                AIModeIndicator {
                    showModeSettings = true
                }
            }
        }
    }

    private var navStatusColor: Color {
        switch aiManager.status {
        case .ready, .generating: return DS.Colors.positive
        case .loading, .downloading: return DS.Colors.warning
        case .error: return DS.Colors.danger
        case .notLoaded: return DS.Colors.subtext.opacity(0.4)
        }
    }

    private var navStatusText: String {
        switch aiManager.status {
        case .ready: return "Ready"
        case .generating: return isStreaming ? streamingPhase.label : "Generating…"
        case .loading: return "Loading model..."
        case .downloading(let p, _): return "Downloading \(Int(p * 100))%"
        case .error: return "Error"
        case .notLoaded: return aiManager.isModelDownloaded ? "Tap to load" : "No model"
        }
    }

    // MARK: - AI Menu Sheet (placeholder)

    private var aiMenuSheet: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showAIMenu = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showProactiveFeed = true
                        }
                    } label: {
                        Label {
                            HStack {
                                Text("Proactive Feed")
                                if AIProactiveEngine.shared.activeCount > 0 {
                                    Text("\(AIProactiveEngine.shared.activeCount)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(DS.Colors.accent, in: Capsule())
                                }
                            }
                        } icon: {
                            Image(systemName: "bell.badge.fill")
                        }
                    }

                    Button {
                        showAIMenu = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showOptimizer = true
                        }
                    } label: {
                        Label("Optimizer", systemImage: "chart.line.text.clipboard")
                    }

                    Button {
                        showAIMenu = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showWorkflow = true
                        }
                    } label: {
                        Label("Workflows", systemImage: "gearshape.2.fill")
                    }

                    Button {
                        showAIMenu = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showIngestion = true
                        }
                    } label: {
                        Label("Import Data", systemImage: "text.page.badge.magnifyingglass")
                    }

                    Button {
                        showAIMenu = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showActivityDashboard = true
                        }
                    } label: {
                        Label("AI Activity", systemImage: "clock.arrow.circlepath")
                    }

                    Button {
                        showAIMenu = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showMemory = true
                        }
                    } label: {
                        Label {
                            HStack {
                                Text("AI Memory")
                                if AIMemoryStore.shared.totalCount > 0 {
                                    Text("\(AIMemoryStore.shared.totalCount)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(DS.Colors.positive, in: Capsule())
                                }
                            }
                        } icon: {
                            Image(systemName: "brain.head.profile.fill")
                        }
                    }

                    Button {
                        showAIMenu = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showModeSettings = true
                        }
                    } label: {
                        Label {
                            HStack {
                                Text("AI Mode")
                                Text(AIAssistantModeManager.shared.currentMode.title)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(DS.Colors.accent, in: Capsule())
                            }
                        } icon: {
                            Image(systemName: "dial.medium.fill")
                        }
                    }
                }

                if actionHistory.canUndo {
                    Section {
                        Button {
                            showAIMenu = false
                            undoLastAction()
                        } label: {
                            Label("Undo Last Action", systemImage: "arrow.uturn.backward")
                        }
                    }
                }
            }
            .navigationTitle("Centmond AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showAIMenu = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Actions

    private func loadModelIfNeeded() {
        switch aiManager.status {
        case .ready, .generating, .loading, .downloading:
            return  // Already loaded, loading, or downloading — nothing to do
        case .notLoaded, .error:
            guard aiManager.isModelDownloaded else { return }
            aiManager.loadModel()
        }
    }

    // MARK: - Chat Persistence

    /// On first chat open per app launch, start a fresh empty session.
    /// Subsequent opens within the same launch resume the current session so
    /// closing/reopening the sheet doesn't wipe an in-progress conversation.
    /// Previous sessions remain available via the history button.
    private static var hasStartedChatThisLaunch = false
    private static var hasPulledChatHistory = false

    private func loadPersistedSessionIfNeeded() {
        // One-shot cloud pull on first chat open per launch (Phase 5.9b).
        // Reconciles cloud sessions/messages into SwiftData by id; idempotent.
        if !Self.hasPulledChatHistory {
            Self.hasPulledChatHistory = true
            Task { await ChatSync.pull(into: modelContext) }
        }
        guard currentSession == nil else { return }
        if !Self.hasStartedChatThisLaunch {
            // First open since app launch → new blank chat.
            let session = ChatPersistenceManager.shared.createSession(context: modelContext)
            currentSession = session
            persistedMessageIDs = []
            Self.hasStartedChatThisLaunch = true
        } else {
            // Subsequent opens → resume the most recent session.
            let session = ChatPersistenceManager.shared.currentSession(context: modelContext)
            currentSession = session
            ChatPersistenceManager.shared.populate(conversation, from: session)
            persistedMessageIDs = Set(conversation.messages.map { $0.id })
        }
    }

    /// Save any messages appended to the conversation that haven't been
    /// persisted yet. Fired by .onChange on messages.count, so it runs after
    /// both user and assistant message additions.
    private func persistNewMessages() {
        guard let session = currentSession else { return }
        for msg in conversation.messages where !persistedMessageIDs.contains(msg.id) {
            switch msg.role {
            case .user:
                ChatPersistenceManager.shared.saveUserMessage(
                    msg.content, session: session, context: modelContext
                )
            case .assistant:
                ChatPersistenceManager.shared.saveAssistantMessage(
                    msg.content, actions: msg.actions,
                    session: session, context: modelContext
                )
            case .system:
                break
            }
            persistedMessageIDs.insert(msg.id)
        }
    }

    /// Create a new empty ChatSession and reset the in-memory conversation.
    private func startNewChat() {
        let session = ChatPersistenceManager.shared.createSession(context: modelContext)
        currentSession = session
        conversation.messages.removeAll()
        conversation.pendingActions.removeAll()
        persistedMessageIDs = []
        input = ""
        isInputFocused = false
    }

    /// Switch the current view to an existing ChatSession, replaying its messages.
    private func switchToSession(_ session: ChatSession) {
        currentSession = session
        ChatPersistenceManager.shared.populate(conversation, from: session)
        persistedMessageIDs = Set(conversation.messages.map { $0.id })
        showChatHistory = false
    }

    // MARK: - Chat History Sheet

    private var chatHistorySheet: some View {
        NavigationStack {
            let sessions = ChatPersistenceManager.shared.fetchSessions(context: modelContext)
            let _ = historyRefreshToken  // subscribe to refresh
            List {
                if sessions.isEmpty {
                    Text("No chats yet")
                        .foregroundStyle(DS.Colors.subtext)
                        .font(.system(size: 14))
                } else {
                    ForEach(sessions, id: \.id) { session in
                        Button {
                            switchToSession(session)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(session.title)
                                        .font(.system(size: 15, weight: session.id == currentSession?.id ? .semibold : .regular))
                                        .foregroundStyle(DS.Colors.text)
                                        .lineLimit(1)
                                    Spacer()
                                    if session.id == currentSession?.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(DS.Colors.accent)
                                    }
                                }
                                Text(session.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 11))
                                    .foregroundStyle(DS.Colors.subtext)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteHistorySession(session)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                beginRename(session)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(DS.Colors.accent)
                        }
                        .contextMenu {
                            Button {
                                beginRename(session)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deleteHistorySession(session)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Chat History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showChatHistory = false
                        startNewChat()
                    } label: {
                        Label("New", systemImage: "square.and.pencil")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showChatHistory = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .alert("Rename Chat", isPresented: Binding(
            get: { sessionToRename != nil },
            set: { if !$0 { sessionToRename = nil } }
        )) {
            TextField("Chat title", text: $renameText)
            Button("Cancel", role: .cancel) { sessionToRename = nil }
            Button("Save") {
                if let session = sessionToRename {
                    ChatPersistenceManager.shared.renameSession(
                        session, to: renameText, context: modelContext
                    )
                    historyRefreshToken = UUID()
                }
                sessionToRename = nil
            }
        }
    }

    private func beginRename(_ session: ChatSession) {
        renameText = session.title
        sessionToRename = session
    }

    private func deleteHistorySession(_ session: ChatSession) {
        let wasCurrent = session.id == currentSession?.id
        ChatPersistenceManager.shared.deleteSession(session, context: modelContext)
        if wasCurrent {
            currentSession = nil
            conversation.messages.removeAll()
            conversation.pendingActions.removeAll()
            persistedMessageIDs = []
        }
        historyRefreshToken = UUID()
    }

    // MARK: - Pending Action Patching

    /// Try to interpret `text` as an inline edit to the most recent pending
    /// action (not-yet-confirmed). Returns true if it patched something.
    /// Covers: date, amount, category, note, transaction type.
    private func tryPatchPendingAction(from text: String) -> Bool {
        guard let pending = conversation.pendingActions.last(where: { $0.status == .pending }),
              pending.type == .addTransaction || pending.type == .editTransaction else {
            return false
        }
        let lower = text.lowercased()

        var patched = pending
        var changed: [String] = []

        // ── Date ──
        if let newDate = extractDate(lower: lower, original: text) {
            patched.params.date = newDate
            changed.append("date to \(newDate)")
        }

        // ── Amount ──
        if let newAmountCents = extractAmountCents(text) {
            patched.params.amount = newAmountCents
            let dollars = Double(newAmountCents) / 100
            changed.append(String(format: "amount to %.2f", dollars))
        }

        // ── Category ──
        if let cat = extractCategory(lower) {
            patched.params.category = cat.storageKey
            changed.append("category to \(cat.title)")
        }

        // ── Note ──
        if let newNote = extractNote(text) {
            patched.params.note = newNote
            changed.append("note to \"\(newNote)\"")
        }

        // ── Type ──
        if lower.contains("make it income") || lower.contains("change to income") || lower.contains("set to income") {
            patched.params.transactionType = "income"
            changed.append("type to income")
        } else if lower.contains("make it expense") || lower.contains("change to expense") || lower.contains("set to expense") {
            patched.params.transactionType = "expense"
            changed.append("type to expense")
        }

        guard !changed.isEmpty else { return false }

        // Apply the patch to the conversation — update both pendingActions
        // and the message.actions blob so the card re-renders.
        if let pIdx = conversation.pendingActions.firstIndex(where: { $0.id == pending.id }) {
            conversation.pendingActions[pIdx] = patched
        }
        for mIdx in conversation.messages.indices {
            if var actions = conversation.messages[mIdx].actions,
               let aIdx = actions.firstIndex(where: { $0.id == pending.id }) {
                actions[aIdx] = patched
                conversation.messages[mIdx].actions = actions
            }
        }

        conversation.addAssistantMessage(
            "Updated " + changed.joined(separator: ", ") + ". Tap Confirm to save.",
            actions: nil
        )
        return true
    }

    private func extractDate(lower: String, original: String) -> String? {
        if lower.contains("yesterday") { return "yesterday" }
        if lower.contains("today") { return "today" }
        if lower.contains("tomorrow") { return "tomorrow" }
        // "N days ago"
        if let m = lower.range(of: #"(\d+)\s+days?\s+ago"#, options: .regularExpression) {
            let match = String(lower[m])
            let digits = match.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if let n = Int(digits) {
                let date = Calendar.current.date(byAdding: .day, value: -n, to: Date()) ?? Date()
                let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
                return df.string(from: date)
            }
        }
        // ISO date
        if let m = lower.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
            return String(lower[m])
        }
        // Natural-language fallback via NSDataDetector
        // Handles "02. April", "April 2", "2 Apr", "Apr 2nd", "02/04", etc.
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let range = NSRange(original.startIndex..., in: original)
            if let match = detector.matches(in: original, options: [], range: range).first,
               let parsed = match.date {
                // Default year: current, since the user rarely specifies it.
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: parsed)
                if comps.year == nil || comps.year == 0 {
                    comps.year = Calendar.current.component(.year, from: Date())
                }
                if let final = Calendar.current.date(from: comps) {
                    let df = DateFormatter()
                    df.dateFormat = "yyyy-MM-dd"
                    return df.string(from: final)
                }
            }
        }
        return nil
    }

    private func extractAmountCents(_ text: String) -> Int? {
        let lower = text.lowercased()
        let hasCurrency = lower.contains("$") || lower.contains("€") || lower.contains("£")
        let hasAmountWord = lower.contains("amount")
        let editVerbs = ["change", "make it", "update", "set "]
        let hasEditVerb = editVerbs.contains(where: { lower.contains($0) })
        // Require either an explicit currency OR (edit-verb + "amount")
        guard hasCurrency || (hasEditVerb && hasAmountWord) else { return nil }
        let pattern = #"(\d+(?:[.,]\d{1,2})?)"#
        guard let m = text.range(of: pattern, options: .regularExpression) else { return nil }
        let raw = String(text[m]).replacingOccurrences(of: ",", with: ".")
        guard let val = Double(raw), val > 0 else { return nil }
        return Int((val * 100).rounded())
    }

    private func extractCategory(_ lower: String) -> Category? {
        // Require an edit verb + "category" keyword OR plain mention
        let hasVerb = ["change", "make", "update", "set", "to "].contains(where: { lower.contains($0) })
        guard hasVerb else { return nil }
        // Phase 5: try custom names first (longest first so multi-word wins)
        let customs = CategoryRegistry.shared.customNames
            .sorted { $0.count > $1.count }
        for name in customs {
            if lower.contains(name.lowercased()) { return .custom(name) }
        }
        for cat in Category.allCases {
            if case .other = cat { continue }
            if lower.contains(cat.title.lowercased()) || lower.contains(cat.storageKey.lowercased()) {
                return cat
            }
        }
        return nil
    }

    private func extractNote(_ text: String) -> String? {
        let lower = text.lowercased()
        // Patterns: "note to X", "call it X", "label X", "note: X"
        let patterns = [
            #"note\s+to\s+(.+)$"#,
            #"note\s*[:=]\s*(.+)$"#,
            #"call\s+it\s+(.+)$"#,
            #"label\s+(?:it\s+)?(.+)$"#,
            #"change\s+(?:the\s+)?note\s+to\s+(.+)$"#
        ]
        for p in patterns {
            if let m = lower.range(of: p, options: .regularExpression) {
                let matched = String(text[m])
                if let capture = matched.range(of: #"(?<=to |: |= |it |label )[^\n]+$"#, options: .regularExpression) {
                    let note = String(matched[capture])
                        .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
                    if !note.isEmpty { return note }
                }
            }
        }
        return nil
    }

    private func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        conversation.addUserMessage(trimmed)
        input = ""

        // Dismiss keyboard immediately
        isInputFocused = false

        // Short-circuit: if the user is patching a pending (not-yet-confirmed)
        // action inline (e.g. "change the date to yesterday"), apply the patch
        // directly instead of hallucinating an edit_transaction on a row that
        // doesn't exist in the store yet.
        if tryPatchPendingAction(from: trimmed) { return }

        // Learn from user message
        AIUserPreferences.shared.learnFromMessage(trimmed)

        // ── Intent Layer (Phase 1) ──
        // Classify the message into high-level intent with ambiguity detection
        let classification = AIIntentRouter.classify(trimmed)

        // Check model health — use fallback if unavailable
        let versionManager = AIPromptVersionManager.shared
        versionManager.updateHealth(from: aiManager.status)
        if let fallback = versionManager.fallbackResponse(intentType: classification.intentType) {
            conversation.addAssistantMessage(fallback, actions: nil)
            return
        }

        // Apply mode-specific clarification threshold
        let modeManager = AIAssistantModeManager.shared

        // Run clarification engine (ambiguity + missing fields)
        let clarification = AIClarificationEngine.check(
            classification: classification, rawInput: trimmed
        )

        // Start audit trail
        let auditId = AIAuditLog.shared.beginEntry(
            userMessage: trimmed,
            classification: classification,
            clarification: clarification
        )

        // Short-circuit for simple intents (greeting, thanks, help, undo)
        if let shortCircuit = AIIntentRouter.shortCircuitResponse(for: classification) {
            conversation.addAssistantMessage(shortCircuit, actions: nil)
            AIAuditLog.shared.recordResponse(entryId: auditId, responseText: shortCircuit, actions: [])
            return
        }

        // Clarification: if we need more info and confidence is below mode threshold,
        // short-circuit with clarification question (saves LLM call)
        let clarificationThreshold = modeManager.currentMode.clarificationThreshold
        if let clarification, classification.confidence < clarificationThreshold {
            conversation.addAssistantMessage(clarification.question, actions: nil)
            AIAuditLog.shared.recordResponse(
                entryId: auditId, responseText: clarification.question, actions: []
            )
            versionManager.recordClarification()
            return
        }

        // Check model availability before streaming
        if aiManager.isDownloading {
            conversation.addAssistantMessage(
                "The AI model is still downloading. Please wait for it to finish.",
                actions: nil
            )
            return
        }
        if !aiManager.isModelDownloaded {
            conversation.addAssistantMessage(
                "The AI model needs to be downloaded first. Scroll up and tap the download button to get started!",
                actions: nil
            )
            return
        }
        if case .error(let msg) = aiManager.status {
            conversation.addAssistantMessage(
                "Model error: \(msg). Scroll up to retry or re-download.",
                actions: nil
            )
            return
        }

        isStreaming = true
        streamingText = ""
        streamingPhase = .thinking

        Task { @MainActor in
            defer {
                isStreaming = false
                streamingText = ""
                streamingPhase = .thinking
            }
            // Build context based on intent hint — focused context saves tokens
            streamingPhase = .analyzing
            let context: String
            switch classification.contextHint {
            case .budgetOnly:
                context = await AIContextBuilder.buildBudgetOnly(store: store)
            case .transactionsOnly:
                context = await AIContextBuilder.buildTransactionsOnly(store: store)
            case .goalsOnly:
                context = await AIContextBuilder.buildGoalsOnly(store: store)
            case .subscriptionsOnly:
                context = await AIContextBuilder.buildSubscriptionsOnly(store: store)
            case .accountsOnly:
                context = await AIContextBuilder.build(store: store)
            case .minimal:
                context = await AIContextBuilder.buildMinimal(store: store)
            case .none:
                context = ""
            case .full:
                context = await AIContextBuilder.build(store: store)
            }
            // Use compact prompt for follow-up messages (saves ~2000 tokens for history).
            // Full prompt only for first 2 messages when conversation history is short.
            let messageCount = conversation.messages.count
            var systemPrompt: String
            if messageCount <= 2 {
                systemPrompt = AISystemPrompt.build(context: context.isEmpty ? nil : context)
            } else {
                systemPrompt = AISystemPrompt.buildCompact(context: context.isEmpty ? nil : context)
            }

            // Inject merchant memory context (only for full prompt — compact already has memory)
            let merchantContext = messageCount <= 2 ? AIMerchantMemory.shared.contextSummary() : ""
            if !merchantContext.isEmpty {
                systemPrompt += "\n\n" + merchantContext
            }

            // Extra context injections — only for first messages (saves tokens for follow-ups)
            if messageCount <= 2 {
                // Inject safe-to-spend data for richer context
                if classification.contextHint == .full || classification.contextHint == .budgetOnly {
                    let sts = AISafeToSpend.shared.calculate(store: store)
                    systemPrompt += "\n\nSAFE-TO-SPEND\n=============\n\(sts.summary())"
                }

                // Inject recurring detection summary
                let recurringContext = AIRecurringDetector.shared.summary(
                    transactions: store.transactions,
                    existingRecurring: store.recurringTransactions
                )
                if !recurringContext.isEmpty {
                    systemPrompt += "\n\n" + recurringContext
                }
            }

            // Inject clarification hint if needed (guides LLM to ask the right question)
            if let clarification {
                let hint = clarification.missingFields.joined(separator: ", ")
                systemPrompt += "\n\nCLARIFICATION HINT: The user's message may be ambiguous. Missing: \(hint). Ask a short clarifying question if needed."
            }

            // Build multi-turn history — compact prompt leaves more room for history.
            // Strip actions from assistant messages to save tokens.
            let historyCount: Int
            if messageCount <= 2 {
                historyCount = classification.contextHint == .full ? 6 : 4
            } else {
                // Compact prompt saves ~2000 tokens — use them for more history
                historyCount = 12
            }
            let history = conversation.messages.suffix(historyCount).map { msg -> AIMessage in
                if msg.role == .assistant {
                    // Send only the text part (before ---ACTIONS---) to save tokens
                    let textOnly: String
                    if let range = msg.content.range(of: "---ACTIONS---") {
                        textOnly = String(msg.content[msg.content.startIndex..<range.lowerBound])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        textOnly = msg.content
                    }
                    return AIMessage(role: .assistant, content: textOnly)
                }
                return msg
            }

            var fullResponse = ""
            var hasDetectedActions = false
            var firstTokenReceived = false

            streamingPhase = .thinking

            for await token in aiManager.stream(messages: history, systemPrompt: systemPrompt) {
                fullResponse += token

                // Transition to composing on first token
                if !firstTokenReceived {
                    firstTokenReceived = true
                    streamingPhase = .composing
                }

                // Show text portion only (before ---ACTIONS---)
                let display: String
                if let range = fullResponse.range(of: "---ACTIONS---") {
                    display = String(fullResponse[fullResponse.startIndex..<range.lowerBound])
                    if !hasDetectedActions {
                        hasDetectedActions = true
                        streamingPhase = .buildingActions
                    }
                } else {
                    display = fullResponse
                }
                // Clean leaked tokens, echoed question, separator lines
                streamingText = Self.cleanModelResponse(display, userMessage: trimmed)
            }

            // Reviewing phase — parsing and validating
            streamingPhase = .reviewing

            // Strip leaked Gemma tokens from final response
            fullResponse = Self.cleanModelResponse(fullResponse, userMessage: trimmed)

            // Auto-retry once if the response was fully scrubbed away
            // (Gemma occasionally regurgitates the system prompt and the
            // leak-marker scrub leaves nothing). A silent second attempt
            // usually succeeds because sampler entropy is fresh.
            if fullResponse.isEmpty {
                streamingPhase = .thinking
                streamingText = ""
                var retryResponse = ""
                var retryFirstToken = false
                for await token in aiManager.stream(messages: history, systemPrompt: systemPrompt) {
                    retryResponse += token
                    if !retryFirstToken {
                        retryFirstToken = true
                        streamingPhase = .composing
                    }
                    let display: String
                    if let range = retryResponse.range(of: "---ACTIONS---") {
                        display = String(retryResponse[retryResponse.startIndex..<range.lowerBound])
                    } else {
                        display = retryResponse
                    }
                    streamingText = Self.cleanModelResponse(display, userMessage: trimmed)
                }
                fullResponse = Self.cleanModelResponse(retryResponse, userMessage: trimmed)
                streamingPhase = .reviewing
            }

            // If still empty after retry, show a helpful nudge instead of
            // a generic "something went wrong" message.
            if fullResponse.isEmpty {
                conversation.addAssistantMessage(
                    "I couldn't put together an answer for that. Try rephrasing — for example, ask about a specific category or month (\"how much did I spend on dining last month?\").",
                    actions: nil
                )
                AIAuditLog.shared.recordError(entryId: auditId, error: "empty_response_after_retry")
                return
            }

            let parsed = AIActionParser.parse(fullResponse)

            // Phase 8: Track prompt performance
            if parsed.actions.isEmpty && parsed.text.contains("---ACTIONS---") == false {
                versionManager.recordParseFailure()
            } else {
                versionManager.recordSuccess(responseLength: fullResponse.count)
            }

            // Record AI response in audit log
            AIAuditLog.shared.recordResponse(
                entryId: auditId, responseText: parsed.text, actions: parsed.actions
            )

            // Validate parsed actions
            if let failure = AIClarificationEngine.validateActions(parsed.actions) {
                let errorMsg = failure.userMessage
                conversation.addAssistantMessage(errorMsg, actions: nil)
                AIAuditLog.shared.recordError(entryId: auditId, error: errorMsg)
                return
            }

            // Detect multiplier: "add 5 expenses of $10" → model may only
            // return 1 action, so we duplicate it N times.
            var finalActions = Self.applyMultiplier(parsed.actions, userMessage: trimmed)

            // Conflict detection: check for duplicates, missing IDs, budget overruns
            if !finalActions.isEmpty {
                let conflicts = AIConflictDetector.detect(actions: finalActions, store: store)

                // Hard blocks: remove blocked actions
                if conflicts.isBlocked {
                    for block in conflicts.blocks {
                        if let idx = block.actionIndex, idx < finalActions.count {
                            finalActions[idx].status = .rejected
                        }
                    }
                }

                // Warnings: include in the text response
                if !conflicts.warnings.isEmpty {
                    let warningText = conflicts.warnings
                        .map { "⚠️ \($0.message)" }
                        .joined(separator: "\n")
                    // Prepend warnings to parsed text
                    let augmentedText = parsed.text + "\n\n" + warningText
                    // Use augmented text below
                    _ = augmentedText
                }
            }

            streamingPhase = .almostDone

            if !finalActions.isEmpty {
                let analysisTypes: Set<AIAction.ActionType> = [.analyze, .compare, .forecast, .advice]

                // Auto-mark analysis actions as executed (no confirmation needed)
                for i in finalActions.indices {
                    if analysisTypes.contains(finalActions[i].type) {
                        finalActions[i].status = .executed
                    }
                }

                // Separate mutation actions from analysis
                let mutationActions = finalActions.filter { !analysisTypes.contains($0.type) }

                if !mutationActions.isEmpty {
                    // Phase 2: Trust & Approval — evaluate through central policy engine
                    var classified = trustManager.classify(
                        mutationActions,
                        classification: classification,
                        mode: modeManager.currentMode
                    )

                    // HARD RULE belt-and-suspenders: every mutation must show a
                    // Confirm/Reject card, regardless of mode/preferences. If
                    // anything ever leaks into `auto`, downgrade it to confirm.
                    if !classified.auto.isEmpty {
                        let reroute = classified.auto.map { (action, decision) -> (AIAction, TrustDecision) in
                            let forced = TrustDecision(
                                id: decision.id,
                                actionType: decision.actionType,
                                level: .confirm,
                                reason: decision.reason + " · downgraded by Confirm-Every-Action policy",
                                riskScore: decision.riskScore,
                                confidenceUsed: decision.confidenceUsed,
                                preferenceInfluenced: decision.preferenceInfluenced,
                                blockMessage: decision.blockMessage
                            )
                            return (action, forced)
                        }
                        classified = TrustClassifiedActions(
                            auto: [],
                            confirm: classified.confirm + reroute,
                            blocked: classified.blocked
                        )
                    }

                    // Phase 3: Action grouping — link all actions from this request
                    let groupId = mutationActions.count > 1 ? UUID() : nil
                    let groupLabel = mutationActions.count > 1 ? String(trimmed.prefix(60)) : nil

                    // Auto-reject blocked actions and show block message
                    var blockMessages: [String] = []
                    for (action, decision) in classified.blocked {
                        if let idx = finalActions.firstIndex(where: { $0.id == decision.id }) {
                            finalActions[idx].status = .rejected
                        }
                        if let msg = decision.blockMessage {
                            blockMessages.append("🛑 \(msg)")
                        }
                        // Phase 3: Record blocked actions in history
                        actionHistory.recordBlocked(
                            action: action,
                            trustDecision: decision,
                            classification: classification,
                            groupId: groupId,
                            groupLabel: groupLabel
                        )
                    }

                    // Build accurate summary from the actual action params
                    var displayText = Self.buildActionSummary(mutationActions) ?? parsed.text
                    if !blockMessages.isEmpty {
                        displayText += "\n\n" + blockMessages.joined(separator: "\n")
                    }
                    conversation.addAssistantMessage(displayText, actions: finalActions)

                    // Record trust decisions in audit (rich format)
                    let trustDecisions = classified.allDecisions.map { decision in
                        AuditTrustDecision(
                            actionType: decision.actionType.rawValue,
                            trustLevel: decision.level.rawValue,
                            riskScore: decision.riskScore.value,
                            riskLevel: decision.riskScore.level.rawValue,
                            reason: decision.reason,
                            confidenceUsed: decision.confidenceUsed,
                            preferenceInfluenced: decision.preferenceInfluenced,
                            userDecision: nil
                        )
                    }
                    AIAuditLog.shared.recordTrustDecisions(entryId: auditId, decisions: trustDecisions)

                    // Build a lookup of trust decisions by action ID
                    let decisionsByActionId: [UUID: TrustDecision] = {
                        var map: [UUID: TrustDecision] = [:]
                        for (action, decision) in classified.auto { map[action.id] = decision }
                        for (action, decision) in classified.confirm { map[action.id] = decision }
                        return map
                    }()

                    // Store context for confirm-path actions (used by confirmAndExecute)
                    self.pendingTrustContext = PendingTrustContext(
                        decisionsByActionId: decisionsByActionId,
                        classification: classification,
                        groupId: groupId,
                        groupLabel: groupLabel,
                        userMessage: trimmed
                    )

                    // Auto-execute trusted actions
                    if !classified.auto.isEmpty {
                        var copy = store
                        var execResults: [AuditExecutionResult] = []
                        for (action, decision) in classified.auto {
                            conversation.confirmAction(action.id)
                            let result = await AIActionExecutor.execute(action, store: &copy)
                            execResults.append(AuditExecutionResult(
                                actionType: action.type.rawValue,
                                success: result.success,
                                summary: result.summary,
                                undoable: AIConflictDetector.isReversible(action.type)
                            ))
                            if result.success {
                                if let idx = conversation.pendingActions.firstIndex(where: { $0.id == action.id }) {
                                    conversation.pendingActions[idx].status = .executed
                                }

                                // Phase 3: Record with full audit context
                                actionHistory.record(
                                    action: action,
                                    result: result,
                                    trustDecision: decision,
                                    classification: classification,
                                    groupId: groupId,
                                    groupLabel: groupLabel,
                                    isAutoExecuted: true
                                )

                                // Phase 5: Post event for executed action
                                if action.type == .addTransaction {
                                    AIEventBus.shared.postTransactionAdded(
                                        amount: action.params.amount ?? 0,
                                        category: action.params.category ?? "other",
                                        note: action.params.note ?? "",
                                        type: action.params.transactionType ?? "expense"
                                    )
                                }

                                // Phase 6: Learn merchant from executed transaction
                                if action.type == .addTransaction,
                                   let note = action.params.note, !note.isEmpty {
                                    AIMerchantMemory.shared.learnFromTransaction(
                                        note: note,
                                        category: action.params.category ?? "other",
                                        amount: action.params.amount ?? 0
                                    )
                                }

                                // Few-shot learning: record successful auto-executed action
                                AIFewShotLearning.shared.recordSuccess(
                                    userMessage: trimmed,
                                    action: action,
                                    wasAutoExecuted: true
                                )
                            }
                        }
                        store = copy
                        AIAuditLog.shared.recordExecution(entryId: auditId, results: execResults)
                    }
                } else {
                    // Analysis-only: show text + action cards pre-marked as Done
                    conversation.addAssistantMessage(parsed.text, actions: finalActions)
                }
            } else {
                // Safety net: the model may announce a mutation in text
                // ("I'll add…", "I will delete…") without emitting a parseable
                // action block. Per the hard rule "every mutation needs a
                // confirm card", we must NOT let that text stand — there is
                // nothing to confirm and nothing actually happened.
                if Self.textClaimsMutation(parsed.text) {
                    conversation.addAssistantMessage(
                        "I couldn't turn that into a confirmable action. Could you rephrase it — for example: \"add a 12€ dining expense yesterday\"?",
                        actions: nil
                    )
                } else {
                    conversation.addAssistantMessage(parsed.text, actions: nil)
                }
            }
        }
    }

    /// Detect text where the model is announcing it will mutate state
    /// without having emitted an action. We never want such text to land
    /// in the chat without a Confirm/Reject card.
    private static func textClaimsMutation(_ text: String) -> Bool {
        let lower = text.lowercased()
        let phrases = [
            "i'll add", "i will add", "i added", "i've added",
            "i'll delete", "i will delete", "i deleted",
            "i'll remove", "i will remove", "i removed",
            "i'll update", "i will update", "i updated",
            "i'll edit", "i will edit", "i edited",
            "i'll set", "i will set", "i set your",
            "i'll create", "i will create", "i created",
            "i'll cancel", "i will cancel", "i cancelled", "i canceled",
            "i'll transfer", "i will transfer", "i transferred",
            "i'll split", "i will split", "i split",
            "i'll log", "i will log", "i logged",
            "i'll record", "i will record", "i recorded",
            "i'll save", "i will save", "i saved",
            "expenses:", "two expenses", "both dated", "both for"
        ]
        return phrases.contains(where: { lower.contains($0) })
    }

    /// Confirm + execute in one step to avoid race conditions between
    /// status update and execution check.
    private func confirmAndExecute(_ id: UUID) {
        // Find the action in pending list (must be .pending)
        guard let action = conversation.pendingActions.first(where: { $0.id == id && $0.status == .pending }) else { return }

        // Mark confirmed immediately
        conversation.confirmAction(id)

        // Phase 7: Record approval pattern
        AIMemoryStore.shared.recordApproval(actionType: action.type.rawValue, approved: true)

        Task { @MainActor in
            var copy = store
            let result = await AIActionExecutor.execute(action, store: &copy)

            if result.success {
                store = copy
                conversation.markExecuted(id)

                // Phase 3: Record with trust context from pending state
                let ctx = pendingTrustContext
                actionHistory.record(
                    action: action,
                    result: result,
                    trustDecision: ctx?.decisionsByActionId[action.id],
                    classification: ctx?.classification,
                    groupId: ctx?.groupId,
                    groupLabel: ctx?.groupLabel,
                    isAutoExecuted: false
                )

                conversation.addAssistantMessage("✅ \(result.summary)", actions: nil)

                // Phase 5: Post event
                if action.type == .addTransaction {
                    AIEventBus.shared.postTransactionAdded(
                        amount: action.params.amount ?? 0,
                        category: action.params.category ?? "other",
                        note: action.params.note ?? "",
                        type: action.params.transactionType ?? "expense"
                    )
                }
                // Phase 6: Learn merchant
                if action.type == .addTransaction,
                   let note = action.params.note, !note.isEmpty {
                    AIMerchantMemory.shared.learnFromTransaction(
                        note: note,
                        category: action.params.category ?? "other",
                        amount: action.params.amount ?? 0
                    )
                }

                // Few-shot learning: record confirmed+executed action
                if let userMsg = pendingTrustContext?.userMessage {
                    AIFewShotLearning.shared.recordSuccess(
                        userMessage: userMsg,
                        action: action,
                        wasAutoExecuted: false
                    )
                }

                // Satisfaction signal: user confirmed = positive
                AIPromptVersionManager.shared.recordSatisfaction()
            } else {
                conversation.addAssistantMessage("❌ \(result.summary)", actions: nil)
            }
        }
    }

    private func executeAllPending() {
        // Grab pending actions and confirm them all first
        let pending = conversation.pendingActions.filter { $0.status == .pending }
        guard !pending.isEmpty else { return }
        conversation.confirmAll()

        Task { @MainActor in
            let ctx = pendingTrustContext
            var copy = store
            let results = await AIActionExecutor.executeAll(pending, store: &copy)
            store = copy
            var summaries: [String] = []
            for result in results where result.success {
                conversation.markExecuted(result.action.id)
                // Phase 3: Record with trust context
                actionHistory.record(
                    action: result.action,
                    result: result,
                    trustDecision: ctx?.decisionsByActionId[result.action.id],
                    classification: ctx?.classification,
                    groupId: ctx?.groupId,
                    groupLabel: ctx?.groupLabel,
                    isAutoExecuted: false
                )
                summaries.append("✅ \(result.summary)")

                // Few-shot learning: batch-confirmed actions
                if let userMsg = ctx?.userMessage {
                    AIFewShotLearning.shared.recordSuccess(
                        userMessage: userMsg,
                        action: result.action,
                        wasAutoExecuted: false
                    )
                }
            }
            // Satisfaction signal: user confirmed all = positive
            if !summaries.isEmpty {
                AIPromptVersionManager.shared.recordSatisfaction()
            }
            if !summaries.isEmpty {
                conversation.addAssistantMessage(summaries.joined(separator: "\n"), actions: nil)
            }
        }
    }

    // MARK: - Pending Trust Context

    /// Preserves trust + intent context between trust classification and user confirmation.
    struct PendingTrustContext {
        let decisionsByActionId: [UUID: TrustDecision]
        let classification: IntentClassification?
        let groupId: UUID?
        let groupLabel: String?
        let userMessage: String  // original user input — used for few-shot learning
    }

    // MARK: - Action Grouping

    struct ActionGroup: Identifiable {
        let id: String  // type + key params as identifier
        let actions: [AIAction]
        var count: Int { actions.count }
    }

    /// Group identical actions (same type + same params) into one group.
    static func groupActions(_ actions: [AIAction]) -> [ActionGroup] {
        var groups: [(key: String, actions: [AIAction])] = []

        for action in actions {
            let key = "\(action.type.rawValue)|\(action.params.amount ?? 0)|\(action.params.category ?? "")|\(action.params.budgetAmount ?? 0)"
            if let idx = groups.firstIndex(where: { $0.key == key }) {
                groups[idx].actions.append(action)
            } else {
                groups.append((key: key, actions: [action]))
            }
        }

        return groups.map { ActionGroup(id: $0.key, actions: $0.actions) }
    }

    /// Detect multiplier in user message and duplicate actions.
    /// Supports date ranges: "from 1.Feb to 3.Feb" → each action gets a different date.
    private static func applyMultiplier(_ actions: [AIAction], userMessage: String) -> [AIAction] {
        let msg = normalizePersianDigits(userMessage.lowercased())

        // Extract multiplier (count)
        let count = extractCount(from: msg)
        guard let n = count, n > 1 else { return actions }

        // Extract date range if present
        let dates = extractDateRange(from: msg, count: n)

        // If model returned 1 action, duplicate with date spread
        if actions.count == 1, let template = actions.first, template.type == .addTransaction {
            return (0..<n).map { i in
                var params = template.params
                if i < dates.count { params.date = dates[i] }
                return AIAction(type: template.type, params: params)
            }
        }

        // If model returned correct count but all same date, spread dates
        if actions.count == n, let firstDate = actions.first?.params.date,
           actions.allSatisfy({ $0.params.date == firstDate }), !dates.isEmpty {
            return actions.enumerated().map { i, action in
                var params = action.params
                if i < dates.count { params.date = dates[i] }
                return AIAction(type: action.type, params: params)
            }
        }

        // If model returned 0 actions, build from user message
        if actions.isEmpty {
            if let amt = extractAmount(from: msg) {
                let cents = Int((amt * 100).rounded())
                return (0..<n).map { i in
                    let params = AIAction.ActionParams(
                        amount: cents,
                        category: "other",
                        date: i < dates.count ? dates[i] : "today",
                        transactionType: "expense"
                    )
                    return AIAction(type: .addTransaction, params: params)
                }
            }
        }

        return actions
    }

    // MARK: - Multiplier Helpers

    private static func normalizePersianDigits(_ text: String) -> String {
        text.replacingOccurrences(of: "۰", with: "0")
            .replacingOccurrences(of: "۱", with: "1")
            .replacingOccurrences(of: "۲", with: "2")
            .replacingOccurrences(of: "۳", with: "3")
            .replacingOccurrences(of: "۴", with: "4")
            .replacingOccurrences(of: "۵", with: "5")
            .replacingOccurrences(of: "۶", with: "6")
            .replacingOccurrences(of: "۷", with: "7")
            .replacingOccurrences(of: "۸", with: "8")
            .replacingOccurrences(of: "۹", with: "9")
    }

    private static func extractCount(from msg: String) -> Int? {
        let patterns: [String] = [
            #"(\d+)\s*[x×]\s*(?:expense|expence|transaction|payment|item)"#,
            #"(\d+)\s*(?:expense|expence|transaction|payment|item)"#,
            #"(?:add|create)\s+(\d+)\s*(?:expense|expence|transaction|payment|item)"#,
            #"(\d+)\s*(?:تا|عدد|دونه|بار)"#,
        ]
        for pattern in patterns {
            if let n = firstCaptureInt(pattern: pattern, in: msg), n > 1, n <= 50 {
                return n
            }
        }
        return nil
    }

    private static func extractAmount(from msg: String) -> Double? {
        let patterns: [String] = [
            #"[\$€£¥₹]\s*(\d+(?:\.\d+)?)"#,
            #"(\d+(?:\.\d+)?)\s*[\$€£¥₹]"#,
            #"(\d+(?:\.\d+)?)\s*(?:dollar|euro|pound)"#,
            #"هر\s*(?:کدوم|کدام)?\s*(\d+)"#,
            #"each\s+(?:for\s+)?[\$€£¥₹]?\s*(\d+)"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: msg, range: NSRange(msg.startIndex..., in: msg)) {
                for i in 1..<match.numberOfRanges {
                    if let range = Range(match.range(at: i), in: msg),
                       let a = Double(String(msg[range])), a > 0 {
                        return a
                    }
                }
            }
        }
        return nil
    }

    /// Parse date range from user message.
    /// "from 1.feb to 3.feb" → ["2026-02-01", "2026-02-02", "2026-02-03"]
    /// "starting from 5 jan" with count=3 → ["2026-01-05", "2026-01-06", "2026-01-07"]
    private static func extractDateRange(from msg: String, count: Int) -> [String] {
        let monthMap: [String: Int] = [
            "jan": 1, "january": 1, "feb": 2, "february": 2,
            "mar": 3, "march": 3, "apr": 4, "april": 4,
            "may": 5, "jun": 6, "june": 6,
            "jul": 7, "july": 7, "aug": 8, "august": 8,
            "sep": 9, "september": 9, "oct": 10, "october": 10,
            "nov": 11, "november": 11, "dec": 12, "december": 12,
            // Farsi
            "فروردین": 1, "اردیبهشت": 2, "خرداد": 3,
            "تیر": 4, "مرداد": 5, "شهریور": 6,
            "مهر": 7, "آبان": 8, "آذر": 9,
            "دی": 10, "بهمن": 11, "اسفند": 12,
        ]

        // Pattern: "from D.month to D.month" or "from D month to D month"
        let rangePatterns: [String] = [
            #"from\s+(\d{1,2})[\.\s]*([a-z]+)\s+to\s+(\d{1,2})[\.\s]*([a-z]+)"#,
            #"از\s+(\d{1,2})\s*([^\s]+)\s+تا\s+(\d{1,2})\s*([^\s]+)"#,
        ]

        for pattern in rangePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: msg, range: NSRange(msg.startIndex..., in: msg)) {
                guard match.numberOfRanges >= 5,
                      let r1 = Range(match.range(at: 1), in: msg),
                      let r2 = Range(match.range(at: 2), in: msg),
                      let r3 = Range(match.range(at: 3), in: msg),
                      let r4 = Range(match.range(at: 4), in: msg),
                      let startDay = Int(String(msg[r1])),
                      let endDay = Int(String(msg[r3])) else { continue }

                let startMonthStr = String(msg[r2]).lowercased().trimmingCharacters(in: .punctuationCharacters)
                let endMonthStr = String(msg[r4]).lowercased().trimmingCharacters(in: .punctuationCharacters)

                guard let startMonth = monthMap[startMonthStr],
                      let endMonth = monthMap[endMonthStr] else { continue }

                let year = Calendar.current.component(.year, from: Date())
                return generateDateList(
                    startDay: startDay, startMonth: startMonth,
                    endDay: endDay, endMonth: endMonth,
                    year: year, maxCount: count
                )
            }
        }

        // Pattern: "starting from D.month" or "from D.month" (no end date — spread consecutive days)
        let startPatterns: [String] = [
            #"(?:starting\s+)?from\s+(\d{1,2})[\.\s]*([a-z]+)"#,
            #"از\s+(\d{1,2})\s*([^\s]+)"#,
        ]

        for pattern in startPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: msg, range: NSRange(msg.startIndex..., in: msg)) {
                guard match.numberOfRanges >= 3,
                      let r1 = Range(match.range(at: 1), in: msg),
                      let r2 = Range(match.range(at: 2), in: msg),
                      let startDay = Int(String(msg[r1])) else { continue }

                let monthStr = String(msg[r2]).lowercased().trimmingCharacters(in: .punctuationCharacters)
                guard let month = monthMap[monthStr] else { continue }

                let year = Calendar.current.component(.year, from: Date())
                return generateConsecutiveDates(startDay: startDay, month: month, year: year, count: count)
            }
        }

        return []
    }

    private static func generateDateList(startDay: Int, startMonth: Int, endDay: Int, endMonth: Int, year: Int, maxCount: Int) -> [String] {
        let cal = Calendar.current
        guard let startDate = cal.date(from: DateComponents(year: year, month: startMonth, day: startDay)),
              let endDate = cal.date(from: DateComponents(year: year, month: endMonth, day: endDay)),
              endDate >= startDate else { return [] }

        var dates: [String] = []
        var current = startDate
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        while current <= endDate && dates.count < maxCount {
            dates.append(formatter.string(from: current))
            guard let next = cal.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return dates
    }

    private static func generateConsecutiveDates(startDay: Int, month: Int, year: Int, count: Int) -> [String] {
        let cal = Calendar.current
        guard let startDate = cal.date(from: DateComponents(year: year, month: month, day: startDay)) else { return [] }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        return (0..<count).compactMap { i in
            guard let date = cal.date(byAdding: .day, value: i, to: startDate) else { return nil }
            return formatter.string(from: date)
        }
    }

    private static func firstCaptureInt(pattern: String, in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        for i in 1..<match.numberOfRanges {
            if let range = Range(match.range(at: i), in: text), let n = Int(String(text[range])) {
                return n
            }
        }
        return nil
    }

    /// Clean raw model output: strip Gemma tokens, echoed user question,
    /// and separator lines (=== or ---).
    private static func cleanModelResponse(_ raw: String, userMessage: String) -> String {
        var text = raw
            // Gemma chat template tokens
            .replacingOccurrences(of: "<end_of_turn>", with: "")
            .replacingOccurrences(of: "<start_of_turn>model", with: "")
            .replacingOccurrences(of: "<start_of_turn>user", with: "")
            .replacingOccurrences(of: "<start_of_turn>system", with: "")
            .replacingOccurrences(of: "<start_of_turn>", with: "")

        // System-prompt leakage: when the model echoes the system prompt
        // back to the user, cut everything from the first known leak marker.
        // These are phrases that ONLY appear in the system prompt — they
        // never legitimately occur in a real assistant reply.
        let leakMarkers = [
            "You are Centmond AI",
            "You are Centmond",
            "RESPONSE FORMAT",
            "HISTORICAL SUMMARY",
            "ACTIONS BLOCK",
            "JSON actions block",
            "---ACTIONS---",      // raw separator if it leaks before any text
            "FULL financial history",
            "bilingual (English + Farsi)",
            "privacy-first: you run entirely on-device"
        ]
        for marker in leakMarkers {
            if let range = text.range(of: marker) {
                text = String(text[text.startIndex..<range.lowerBound])
                break
            }
        }

        // Remove echoed user question (model sometimes repeats it at the top)
        // Check if response starts with the user's message (case-insensitive)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerText = trimmedText.lowercased()
        let lowerUser = userMessage.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if !lowerUser.isEmpty && lowerText.hasPrefix(lowerUser) {
            text = String(trimmedText.dropFirst(userMessage.trimmingCharacters(in: .whitespacesAndNewlines).count))
        }

        // Remove separator lines (===, ---, ***) and stray dashes/bullets
        let lines = text.components(separatedBy: .newlines)
        let filtered = lines.filter { line in
            let stripped = line.trimmingCharacters(in: .whitespaces)
            // Remove empty lines that are just a single dash or bullet
            if stripped == "-" || stripped == "–" || stripped == "—" || stripped == "•" || stripped == "*" {
                return false
            }
            // Remove lines that are only = - or * repeated (separators)
            if stripped.count >= 2 {
                let unique = Set(stripped)
                if unique.count == 1 && ["=", "-", "*", "─", "━", "·"].contains(stripped.first!) {
                    return false
                }
            }
            return true
        }
        text = filtered.joined(separator: "\n")

        // Collapse multiple blank lines into one
        while text.contains("\n\n\n") {
            text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Build a human-readable summary from actual action params so the
    /// displayed text always matches the action card — the model's own text
    /// is sometimes inaccurate (wrong date, wrong amount, etc.).
    private static func buildActionSummary(_ actions: [AIAction]) -> String? {
        guard !actions.isEmpty else { return nil }

        // Group identical actions for cleaner summary
        let groups = groupActions(actions)
        let lines: [String] = groups.compactMap { group in
            let action = group.actions[0]
            let count = group.count
            let p = action.params
            switch action.type {
            case .addTransaction:
                let type = p.transactionType == "income" ? "income" : "expense"
                let amt = fmtCentsStatic(p.amount)
                if count > 1 {
                    let total = fmtCentsStatic((p.amount ?? 0) * count)
                    var s = "I'll add \(count)× \(amt) \(type) (total: \(total))"
                    if let cat = p.category { s += " in \(cat)" }
                    return s + "."
                }
                var s = "I'll add a \(amt) \(type)"
                if let cat = p.category { s += " in \(cat)" }
                if let note = p.note { s += " (\(note))" }
                if let date = p.date, date != "today" { s += " on \(date)" }
                return s + "."
            case .editTransaction:
                return "I'll update that transaction for you."
            case .deleteTransaction:
                return "I'll delete that transaction."
            case .splitTransaction:
                let amt = fmtCentsStatic(p.amount)
                return "I'll split \(amt) with \(p.splitWith ?? "your partner")."
            case .setBudget, .adjustBudget:
                let amt = fmtCentsStatic(p.budgetAmount)
                var s = "I'll set your monthly budget to \(amt)"
                if let m = p.budgetMonth { s += " for \(m)" }
                return s + "."
            case .setCategoryBudget:
                let amt = fmtCentsStatic(p.budgetAmount)
                return "I'll set the \(p.budgetCategory ?? "category") budget to \(amt)."
            case .createGoal:
                let target = fmtCentsStatic(p.goalTarget)
                return "I'll create a goal \"\(p.goalName ?? "Goal")\" with target \(target)."
            case .addContribution:
                let amt = fmtCentsStatic(p.contributionAmount)
                return "I'll add \(amt) to \"\(p.goalName ?? "goal")\"."
            case .updateGoal:
                return "I'll update the goal \"\(p.goalName ?? "Goal")\"."
            case .pauseGoal:
                let verb = (p.goalPause ?? true) ? "pause" : "resume"
                return "I'll \(verb) the goal \"\(p.goalName ?? "Goal")\"."
            case .archiveGoal:
                let verb = (p.goalArchive ?? true) ? "archive" : "unarchive"
                return "I'll \(verb) the goal \"\(p.goalName ?? "Goal")\"."
            case .withdrawFromGoal:
                let amt = fmtCentsStatic(p.contributionAmount)
                return "I'll withdraw \(amt) from \"\(p.goalName ?? "goal")\"."
            case .addSubscription:
                let amt = fmtCentsStatic(p.subscriptionAmount)
                return "I'll add subscription \"\(p.subscriptionName ?? "")\" at \(amt)."
            case .cancelSubscription:
                return "I'll cancel the subscription \"\(p.subscriptionName ?? "")\"."
            case .pauseSubscription:
                return "I'll pause the subscription \"\(p.subscriptionName ?? "")\"."
            case .transfer:
                let amt = fmtCentsStatic(p.amount)
                return "I'll transfer \(amt) from \(p.fromAccount ?? "?") to \(p.toAccount ?? "?")."
            case .addRecurring:
                let amt = fmtCentsStatic(p.amount)
                return "I'll add recurring \"\(p.recurringName ?? "")\" at \(amt)/\(p.recurringFrequency ?? "month")."
            case .editRecurring:
                return "I'll update recurring \"\(p.recurringName ?? p.subscriptionName ?? "")\"."
            case .cancelRecurring:
                return "I'll cancel recurring \"\(p.recurringName ?? p.subscriptionName ?? "")\"."
            case .updateBalance:
                return "I'll update \(p.accountName ?? "account") balance."
            case .analyze, .compare, .forecast, .advice:
                return nil  // Use model's text for analysis responses
            default:
                // Goal lifecycle ops (.pauseGoal/.archiveGoal/.withdrawFromGoal)
                // and any future action types fall through to the model's text.
                return nil
            }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func fmtCentsStatic(_ cents: Int?) -> String {
        guard let cents else { return "$0.00" }
        let dollars = Double(cents) / 100.0
        return String(format: "$%.2f", dollars)
    }

    private func undoLastAction() {
        Task { @MainActor in
            var copy = store
            if let summary = await actionHistory.undoLast(store: &copy) {
                store = copy
                conversation.addAssistantMessage(summary, actions: nil)

                // Few-shot learning: record that the last action was bad
                if let lastUserMsg = conversation.messages.last(where: { $0.role == .user })?.content {
                    AIFewShotLearning.shared.recordUndo(userMessage: lastUserMsg)
                }
            }
        }
    }

    // MARK: - Streaming Phase

    /// Dynamic status phases shown while the AI is working.
    enum StreamingPhase {
        case thinking           // Initial — model starts processing
        case analyzing          // Building context / reading financial data
        case composing          // First tokens arriving — writing response
        case buildingActions    // Detected ---ACTIONS--- in output
        case reviewing          // Parsing & validating actions
        case almostDone         // Final cleanup

        var label: String {
            switch self {
            case .thinking:        return "Thinking…"
            case .analyzing:       return "Analyzing your finances…"
            case .composing:       return "Writing response…"
            case .buildingActions: return "Building actions…"
            case .reviewing:       return "Reviewing actions…"
            case .almostDone:      return "Almost done…"
            }
        }

        var icon: String {
            switch self {
            case .thinking:        return "brain"
            case .analyzing:       return "chart.bar.doc.horizontal"
            case .composing:       return "text.cursor"
            case .buildingActions: return "hammer"
            case .reviewing:       return "checkmark.shield"
            case .almostDone:      return "sparkles"
            }
        }
    }
}
