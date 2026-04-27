import Foundation
import Combine
import UIKit
import LlamaSwift

// ============================================================
// MARK: - AI Manager
// ============================================================
//
// On-device LLM inference powered by Gemma 4 via llama.cpp.
//
// Runs entirely on-device — no data leaves the phone.
// Uses the GGUF quantized model stored in Application Support.
//
// Usage:
//   let ai = AIManager.shared
//   ai.loadModel(from: url)
//   for await token in ai.stream("Analyze my spending") {
//       print(token, terminator: "")
//   }
//
// ============================================================

/// Status of the AI model lifecycle.
enum AIModelStatus: Equatable {
    case notLoaded
    case loading
    case ready
    case error(String)
    case generating
    case downloading(progress: Double, downloadedBytes: Int64)   // progress 0.0…1.0
}

@MainActor
class AIManager: ObservableObject {
    static let shared = AIManager()

    // MARK: - Published State

    @Published var status: AIModelStatus = .notLoaded
    @Published var isGenerating: Bool = false

    // MARK: - Private State

    private var model: OpaquePointer?                         // llama_model *
    private var context: OpaquePointer?                       // llama_context *
    private var sampler: UnsafeMutablePointer<llama_sampler>? // llama_sampler *

    /// Thread-safe cancellation token shared between main thread and inference queue.
    private final class CancelToken: @unchecked Sendable {
        private(set) var isCancelled = false
        func cancel() { isCancelled = true }
    }

    /// Active cancellation token for the current generation.
    private var cancelToken: CancelToken?

    // ── Idle auto-unload ──────────────────────────────────────
    // Gemma 4 holds ~2-4 GB resident once loaded. After a generation
    // finishes (or the user leaves an AI view, or the app backgrounds)
    // we schedule an idle timer; if no new generation arrives within
    // the timeout, the model is unloaded and RAM is reclaimed. The
    // next inference re-loads it transparently.
    private var idleTask: Task<Void, Never>?
    private static let idleTimeoutSeconds: UInt64 = 60          // 1 min after generation finishes
    private static let backgroundTimeoutSeconds: UInt64 = 15    // 15 s when app is backgrounded
    private static let leftViewTimeoutSeconds: UInt64 = 20      // 20 s after user leaves an AI view

    /// Dedicated serial queue for LLM inference — keeps main thread free.
    /// GCD queue instead of Swift concurrency because llama_decode() blocks
    /// for hundreds of ms and would starve the cooperative thread pool.
    private static let inferenceQueue = DispatchQueue(
        label: "com.centmond.ai.inference",
        qos: .userInitiated
    )

    // MARK: - Constants

    /// Max tokens to generate per response.
    private let maxTokens: Int32 = 512

    /// Available device RAM in GB.
    private static var deviceRAM: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    }

    /// Context window size — needs to be large enough for system prompt + history + response.
    private var contextSize: UInt32 {
        if Self.deviceRAM >= 8 { return 4096 }
        if Self.deviceRAM >= 6 { return 3072 }
        return 2048
    }

    /// GPU layers — adaptive. The crash was from n_gpu_layers=99 overwhelming GPU.
    private var gpuLayers: Int32 {
        if Self.deviceRAM >= 8 { return 33 }
        if Self.deviceRAM >= 6 { return 24 }
        return 0
    }

    /// Batch size — adaptive.
    private var batchSize: UInt32 {
        if Self.deviceRAM >= 8 { return 256 }
        return 128
    }

    /// Where we store the downloaded model inside the app container.
    static var modelDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AIModels", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Expected filename of the model.
    static let modelFilename = "gemma-4-E2B-it-Q4_K_M.gguf"

    /// Full path to the model on disk.
    static var modelURL: URL {
        modelDirectory.appendingPathComponent(modelFilename)
    }

    #if DEBUG
    /// Development-only: path to model in project folder (avoids copying 3GB into simulator sandbox).
    static var devModelURL: URL? {
        // When running from Xcode the working dir varies, so use an absolute path.
        let path = "/Users/mani/Desktop/SwiftProjects/gemma-4-E2B-it-Q4_K_M.gguf"
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }
    #endif

    /// Best available model path — prefers dev path in DEBUG, falls back to App Support.
    static var resolvedModelURL: URL {
        #if DEBUG
        if let dev = devModelURL { return dev }
        #endif
        return modelURL
    }

    /// Whether the model file exists on disk.
    var isModelDownloaded: Bool {
        FileManager.default.fileExists(atPath: Self.resolvedModelURL.path)
    }

    // MARK: - Init / Deinit

    private init() {
        llama_backend_init()
        installLifecycleObservers()
    }

    // MARK: - Idle / Lifecycle Auto-Unload

    private func installLifecycleObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleIdleUnload(seconds: Self.backgroundTimeoutSeconds, reason: "app backgrounded")
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleIdleUnload(seconds: Self.backgroundTimeoutSeconds, reason: "app inactive")
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if case .ready = self.status {
                    self.scheduleIdleUnload(seconds: Self.idleTimeoutSeconds, reason: "app foregrounded")
                }
            }
        }
        // Reclaim aggressively when iOS warns memory is tight.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isGenerating { return }
                SecureLogger.info("AI: memory warning received → unloading model")
                self.unloadModel()
            }
        }
    }

    private func scheduleIdleUnload(seconds: UInt64, reason: String) {
        idleTask?.cancel()
        // Don't auto-unload while a generation is in flight.
        guard !isGenerating else { return }
        // No point scheduling if model isn't loaded.
        if case .notLoaded = status { return }
        if case .loading   = status { return }
        if case .error     = status { return }
        if case .downloading = status { return }
        // Skip if model pointer is already nil.
        guard model != nil else { return }

        SecureLogger.info("AI auto-unload scheduled in \(seconds)s (\(reason))")
        idleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if self.isGenerating { return }
                guard case .ready = self.status else { return }
                SecureLogger.info("AI model auto-unloaded after \(seconds)s idle (\(reason))")
                self.unloadModel()
            }
        }
    }

    private func cancelIdleUnload() {
        idleTask?.cancel()
        idleTask = nil
    }

    /// Public hook for views to request an aggressive unload — call from
    /// `.onDisappear` of any AI-using view so the model frees its RAM
    /// shortly after the user navigates away. Cancelled automatically if
    /// a new generation begins.
    func requestUnloadSoon() {
        scheduleIdleUnload(seconds: Self.leftViewTimeoutSeconds, reason: "left AI view")
    }

    deinit {
        // Signal cancellation to any running inference
        cancelToken?.cancel()
        if let sampler { llama_sampler_free(sampler) }
        if let context { llama_free(context) }
        if let model   { llama_model_free(model) }
        llama_backend_free()
    }

    // ============================================================
    // MARK: - Model Loading
    // ============================================================

    /// Load the GGUF model from a file URL.
    /// Call on a background thread — model loading takes a few seconds.
    func loadModel(from url: URL? = nil) {
        // Guard against double-loading or loading during other operations
        if case .loading = status { return }
        if case .downloading = status { return }

        let modelURL = url ?? Self.resolvedModelURL
        let modelPath = modelURL.path

        guard FileManager.default.fileExists(atPath: modelPath) else {
            status = .error("Model file not found")
            SecureLogger.error("AI model not found at \(modelPath)")
            return
        }

        // Check file is a valid GGUF
        guard Self.isValidGGUF(at: modelURL) else {
            let size = (try? FileManager.default.attributesOfItem(atPath: modelPath)[.size] as? Int64) ?? 0
            status = .error("Invalid model file (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))")
            SecureLogger.error("Not a valid GGUF file at \(modelPath), size: \(size)")
            // Auto-delete the corrupt file so user can re-download
            if modelPath == Self.modelURL.path {
                try? FileManager.default.removeItem(atPath: modelPath)
            }
            return
        }

        // Don't reload if already loaded
        if model != nil {
            status = .ready
            return
        }

        status = .loading
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: modelPath)[.size] as? Int64) ?? 0
        SecureLogger.info("Loading AI model (\(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)))…")

        let nGpuLayers = self.gpuLayers
        SecureLogger.info("Device RAM: \(String(format: "%.1f", Self.deviceRAM)) GB → gpu_layers=\(nGpuLayers), ctx=\(contextSize), batch=\(batchSize)")

        Task.detached(priority: .userInitiated) { [weak self] in
            var mparams = llama_model_default_params()
            mparams.n_gpu_layers = nGpuLayers

            let mdl = llama_model_load_from_file(modelPath, mparams)

            await MainActor.run {
                guard let self else { return }

                guard let mdl else {
                    self.status = .error("Failed to load model — not enough memory or incompatible format")
                    SecureLogger.error("llama_model_load_from_file returned nil for \(modelPath)")
                    return
                }

                self.model = mdl
                self.setupContext()
                self.setupSampler()
                self.status = .ready
                SecureLogger.info("AI model loaded successfully")
                // Start the idle timer immediately — if the user loads but
                // never generates, reclaim RAM after the timeout.
                self.scheduleIdleUnload(seconds: Self.idleTimeoutSeconds, reason: "loaded, awaiting use")
            }
        }
    }

    /// Release all resources.
    func unloadModel() {
        cancelGeneration()
        cancelIdleUnload()

        if let sampler { llama_sampler_free(sampler) }
        if let context { llama_free(context) }
        if let model   { llama_model_free(model) }

        sampler = nil
        context = nil
        model = nil
        status = .notLoaded
    }

    // MARK: - Context & Sampler Setup

    private func setupContext() {
        guard let model else { return }

        var cparams = llama_context_default_params()
        cparams.n_ctx = contextSize
        cparams.n_batch = batchSize
        cparams.n_threads = Int32(max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 1)))
        cparams.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO

        context = llama_init_from_model(model, cparams)

        if context == nil {
            SecureLogger.error("Failed to create context (n_ctx=\(contextSize), batch=\(batchSize))")
        }
    }

    private func setupSampler() {
        let sparams = llama_sampler_chain_default_params()
        let chain = llama_sampler_chain_init(sparams)

        // Sampling strategy: top-k → top-p → temperature → dist
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(0.9, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(0.7))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))

        sampler = chain
    }

    // ============================================================
    // MARK: - Text Generation (Streaming)
    // ============================================================

    /// Generate a streaming response for the given prompt.
    ///
    /// Returns an `AsyncStream<String>` that yields one token at a time.
    /// The caller can `for await` over it to build the response incrementally.
    func stream(_ userMessage: String, systemPrompt: String? = nil) -> AsyncStream<String> {
        stream(messages: [AIMessage(role: .user, content: userMessage)], systemPrompt: systemPrompt)
    }

    /// Multi-turn streaming — send full conversation history to the model.
    func stream(messages: [AIMessage], systemPrompt: String? = nil) -> AsyncStream<String> {
        // A new inference cancels any pending auto-unload — the model will
        // re-arm its idle timer when this generation completes.
        cancelIdleUnload()

        let (stream, continuation) = AsyncStream.makeStream(of: String.self)

        // Capture everything we need before entering the background queue
        let ctx = self.context
        let mdl = self.model
        let smp = self.sampler
        let maxTok = self.maxTokens

        guard let ctx, let mdl, let smp else {
            continuation.finish()
            return stream
        }

        self.isGenerating = true
        self.status = .generating

        // Cancel any previous generation
        cancelToken?.cancel()

        // Run inference on a dedicated serial queue — NOT the cooperative thread pool.
        // llama_decode() blocks for hundreds of ms per call; the cooperative pool
        // has very few threads and blocking one starves the entire async runtime.
        let token = CancelToken()
        self.cancelToken = token

        AIManager.inferenceQueue.async { [weak self] in
            AIManager.runGenerationSync(
                ctx: ctx, mdl: mdl, smp: smp,
                messages: messages, systemPrompt: systemPrompt,
                maxTokens: maxTok, continuation: continuation,
                token: token
            )
            DispatchQueue.main.async {
                self?.isGenerating = false
                self?.status = .ready
                // Generation done — arm the idle timer so the model frees
                // its KV cache + weights if the user walks away.
                self?.scheduleIdleUnload(seconds: AIManager.idleTimeoutSeconds, reason: "generation finished")
            }
        }

        continuation.onTermination = { _ in
            token.cancel()
        }

        return stream
    }

    /// Cancel any in-progress generation.
    func cancelGeneration() {
        cancelToken?.cancel()
        isGenerating = false
        if case .generating = status {
            status = .ready
            // Cancelled mid-stream still counts as "done using AI" — arm the
            // idle timer so an aborted generation doesn't leave the model
            // resident forever.
            scheduleIdleUnload(seconds: Self.idleTimeoutSeconds, reason: "generation cancelled")
        }
    }

    // ============================================================
    // MARK: - Non-streaming convenience
    // ============================================================

    /// Generate a complete response (non-streaming).
    func generate(_ userMessage: String, systemPrompt: String? = nil) async -> String {
        var result = ""
        for await token in stream(userMessage, systemPrompt: systemPrompt) {
            result += token
        }
        return result
    }

    /// Multi-turn non-streaming convenience.
    func generate(messages: [AIMessage], systemPrompt: String? = nil) async -> String {
        var result = ""
        for await token in stream(messages: messages, systemPrompt: systemPrompt) {
            result += token
        }
        return result
    }

    // ============================================================
    // MARK: - Chat Template & Tokenization
    // ============================================================

    /// Core generation loop — runs synchronously on the dedicated inference queue.
    /// Uses a `CancelToken` instead of Task.isCancelled since this runs on a
    /// plain GCD queue, not in the Swift concurrency runtime.
    private static func runGenerationSync(
        ctx: OpaquePointer,
        mdl: OpaquePointer,
        smp: UnsafeMutablePointer<llama_sampler>,
        messages: [AIMessage],
        systemPrompt: String?,
        maxTokens: Int32,
        continuation: AsyncStream<String>.Continuation,
        token: CancelToken
    ) {
        let fullPrompt = buildPromptStatic(
            model: mdl, messages: messages, systemPrompt: systemPrompt
        )

        let vocab = llama_model_get_vocab(mdl)
        var tokens = tokenizeStatic(vocab: vocab, text: fullPrompt, addSpecial: true)

        guard !tokens.isEmpty else {
            continuation.finish()
            return
        }

        // Truncate prompt to fit context window (leave room for generation)
        // Strategy: keep the FULL system prompt (formatting rules, persona, etc.)
        // and trim from conversation history middle if needed.
        let ctxSize = Int(llama_n_ctx(ctx))
        let maxPromptTokens = ctxSize - Int(maxTokens) - 16  // reserve for generation
        if tokens.count > maxPromptTokens {
            SecureLogger.info("Truncating prompt: \(tokens.count) → \(maxPromptTokens) tokens (ctx=\(ctxSize))")
            // Keep 45% from start (system prompt + early history) and 55% from end
            // (recent history + model turn). This preserves formatting instructions
            // which are at the start of the prompt.
            let keepStart = (maxPromptTokens * 45) / 100
            let keepEnd = maxPromptTokens - keepStart
            tokens = Array(tokens.prefix(keepStart)) + Array(tokens.suffix(keepEnd))
        }

        llama_memory_clear(llama_get_memory(ctx), true)

        // Decode prompt in batches to avoid memory spikes
        let batchLimit = Int(llama_n_batch(ctx))
        var offset = 0
        while offset < tokens.count {
            if token.isCancelled { continuation.finish(); return }
            let remaining = tokens.count - offset
            let chunkSize = min(remaining, batchLimit)
            let chunk = Array(tokens[offset..<(offset + chunkSize)])
            var batch = llama_batch_get_one(UnsafeMutablePointer(mutating: chunk), Int32(chunkSize))
            if llama_decode(ctx, batch) != 0 {
                SecureLogger.error("llama_decode failed at offset \(offset)/\(tokens.count)")
                continuation.finish()
                return
            }
            offset += chunkSize
        }

        let eosToken = llama_vocab_eos(vocab)

        for _ in 0..<maxTokens {
            if token.isCancelled { break }

            let tokenId = llama_sampler_sample(smp, ctx, -1)
            if tokenId == eosToken { break }

            let piece = tokenToPieceStatic(vocab: vocab, token: tokenId)
            if !piece.isEmpty {
                // Stop at Gemma end-of-turn marker
                if piece.contains("<end_of_turn>") || piece.contains("<start_of_turn>") {
                    break
                }
                continuation.yield(piece)
            }

            var nextToken = tokenId
            var batch = llama_batch_get_one(&nextToken, 1)
            if llama_decode(ctx, batch) != 0 {
                SecureLogger.error("llama_decode failed during generation")
                break
            }
        }

        continuation.finish()
    }

    /// Build a multi-turn formatted prompt using Gemma's chat template.
    static func buildPromptStatic(
        model: OpaquePointer,
        messages: [AIMessage],
        systemPrompt: String?
    ) -> String {
        // Gemma chat template format:
        // <start_of_turn>system\n{system}<end_of_turn>
        // <start_of_turn>user\n{user}<end_of_turn>
        // <start_of_turn>model\n{response}<end_of_turn>
        // ... repeat ...
        // <start_of_turn>model\n
        var prompt = ""
        if let sys = systemPrompt, !sys.isEmpty {
            prompt += "<start_of_turn>system\n\(sys)<end_of_turn>\n"
        }

        for message in messages {
            switch message.role {
            case .user:
                prompt += "<start_of_turn>user\n\(message.content)<end_of_turn>\n"
            case .assistant:
                prompt += "<start_of_turn>model\n\(message.content)<end_of_turn>\n"
            case .system:
                prompt += "<start_of_turn>system\n\(message.content)<end_of_turn>\n"
            }
        }

        // Open the model's turn for generation
        prompt += "<start_of_turn>model\n"
        return prompt
    }

    /// Tokenize a string into llama tokens.
    static func tokenizeStatic(
        vocab: OpaquePointer?,
        text: String,
        addSpecial: Bool
    ) -> [llama_token] {
        guard let vocab else { return [] }

        let utf8 = text.utf8CString
        let maxTokens = Int32(utf8.count) + 16

        var tokens = [llama_token](repeating: 0, count: Int(maxTokens))
        let nTokens = utf8.withUnsafeBufferPointer { buf in
            llama_tokenize(vocab, buf.baseAddress, Int32(text.utf8.count), &tokens, maxTokens, addSpecial, true)
        }

        if nTokens < 0 {
            // Buffer too small — retry with larger buffer
            tokens = [llama_token](repeating: 0, count: Int(-nTokens))
            let n2 = utf8.withUnsafeBufferPointer { buf in
                llama_tokenize(vocab, buf.baseAddress, Int32(text.utf8.count), &tokens, -nTokens, addSpecial, true)
            }
            if n2 < 0 { return [] }
            return Array(tokens.prefix(Int(n2)))
        }

        return Array(tokens.prefix(Int(nTokens)))
    }

    /// Convert a single token ID back to a string piece.
    static func tokenToPieceStatic(vocab: OpaquePointer?, token: llama_token) -> String {
        guard let vocab else { return "" }

        var buf = [CChar](repeating: 0, count: 128)
        let n = llama_token_to_piece(vocab, token, &buf, 128, 0, true)
        if n <= 0 { return "" }
        return String(cString: Array(buf.prefix(Int(n))) + [0])
    }

    // ============================================================
    // MARK: - Model File Management
    // ============================================================

    /// Copy a model from a source URL (e.g. Downloads) to the app's model directory.
    func importModel(from sourceURL: URL) throws {
        let dest = Self.modelURL
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: sourceURL, to: dest)
        SecureLogger.info("AI model imported to \(dest.lastPathComponent)")
    }

    /// Delete the stored model to free disk space.
    func deleteModel() {
        unloadModel()
        try? FileManager.default.removeItem(at: Self.modelURL)
        SecureLogger.info("AI model deleted")
    }

    /// Model file size in bytes (nil if not downloaded).
    var modelFileSize: Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: Self.modelURL.path),
              let size = attrs[.size] as? Int64 else { return nil }
        return size
    }

    // ============================================================
    // MARK: - Model Download
    // ============================================================

    /// Default download URL — change this to your own public hosting.
    nonisolated static let defaultDownloadURL = "https://huggingface.co/Dextermitur/Centmond-Ai/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf"

    /// Expected download size — used for progress estimation & confirmation dialog.
    nonisolated static let modelDownloadSizeLabel = "~3 GB"
    nonisolated static let estimatedModelBytes: Int64 = 3_300_000_000  // ~3.1 GB fallback

    /// UserDefaults key for custom download URL.
    private static let downloadURLKey = "ai.download_url"

    /// Configurable download URL — developer sets this once.
    var downloadURL: String {
        get { UserDefaults.standard.string(forKey: Self.downloadURLKey) ?? Self.defaultDownloadURL }
        set { UserDefaults.standard.set(newValue, forKey: Self.downloadURLKey); objectWillChange.send() }
    }

    /// Active download task (so we can cancel).
    private var downloadTask: URLSessionDownloadTask?

    /// Unique ID per download session — used to ignore callbacks from cancelled downloads.
    private var downloadID: UUID?

    /// Whether a download is in progress.
    var isDownloading: Bool {
        if case .downloading = status { return true }
        return false
    }

    /// GGUF files start with the magic bytes "GGUF" (0x47475546).
    private static func isValidGGUF(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 4) else { return false }
        return header.count == 4 && header == Data([0x47, 0x47, 0x55, 0x46]) // "GGUF"
    }

    /// Download the GGUF model. Progress is published via status.
    func downloadModel() {
        guard !isDownloading else { return }

        guard let url = URL(string: downloadURL) else {
            status = .error("Invalid download URL")
            return
        }

        let thisDownloadID = UUID()
        downloadID = thisDownloadID

        status = .downloading(progress: 0, downloadedBytes: 0)
        SecureLogger.info("Starting model download from \(url)")

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 3600

        let delegate = DownloadDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: url)

        delegate.onProgress = { [weak self] bytesWritten, totalExpected in
            Task { @MainActor in
                guard let self, self.downloadID == thisDownloadID else { return }
                let progress: Double
                if totalExpected > 0 {
                    progress = Double(bytesWritten) / Double(totalExpected)
                } else {
                    // Server didn't send Content-Length — estimate from known model size
                    progress = min(0.99, Double(bytesWritten) / Double(Self.estimatedModelBytes))
                }
                self.status = .downloading(progress: progress, downloadedBytes: bytesWritten)
            }
        }

        delegate.onComplete = { [weak self] tempURL, httpStatus, error in
            Task { @MainActor in
                guard let self, self.downloadID == thisDownloadID else {
                    if let tempURL { try? FileManager.default.removeItem(at: tempURL) }
                    return
                }
                self.downloadTask = nil
                self.downloadID = nil

                if let error {
                    self.status = .error("Download failed: \(error.localizedDescription)")
                    return
                }

                if let code = httpStatus, !(200...299).contains(code) {
                    self.status = .error("Download failed (HTTP \(code))")
                    if let tempURL { try? FileManager.default.removeItem(at: tempURL) }
                    return
                }

                guard let tempURL else {
                    self.status = .error("Download failed — no file")
                    return
                }

                let fileSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? 0

                guard Self.isValidGGUF(at: tempURL) else {
                    self.status = .error("Invalid file — not a GGUF model")
                    try? FileManager.default.removeItem(at: tempURL)
                    return
                }

                guard fileSize > 100_000_000 else {
                    self.status = .error("File too small (\(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)))")
                    try? FileManager.default.removeItem(at: tempURL)
                    return
                }

                do {
                    let dest = Self.modelURL
                    if FileManager.default.fileExists(atPath: dest.path) {
                        try FileManager.default.removeItem(at: dest)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: dest)
                    SecureLogger.info("Model saved (\(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)))")
                    self.loadModel()
                } catch {
                    self.status = .error("Save failed: \(error.localizedDescription)")
                }
            }
        }

        downloadTask = task
        task.resume()
    }

    /// Cancel an in-progress download.
    func cancelDownload() {
        downloadID = nil             // Invalidate — any pending callback will be ignored
        downloadTask?.cancel()
        downloadTask = nil
        status = .notLoaded
        SecureLogger.info("Model download cancelled")
    }
}

// ============================================================
// MARK: - URLSession Download Delegate
// ============================================================

/// Lightweight delegate that forwards progress & completion to closures.
/// Each download gets its own instance — no shared state issues.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    var onProgress: ((_ bytesWritten: Int64, _ totalExpected: Int64) -> Void)?
    var onComplete: ((URL?, Int?, Error?) -> Void)?

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let httpStatus = (downloadTask.response as? HTTPURLResponse)?.statusCode
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".gguf")
        do {
            try FileManager.default.moveItem(at: location, to: tmp)
            onComplete?(tmp, httpStatus, nil)
        } catch {
            onComplete?(nil, httpStatus, error)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error, (error as NSError).code != NSURLErrorCancelled {
            onComplete?(nil, nil, error)
        }
    }
}
