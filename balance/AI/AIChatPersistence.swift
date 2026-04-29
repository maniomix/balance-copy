import Foundation
import SwiftData

// ============================================================
// MARK: - Chat Persistence Models
// ============================================================
//
// SwiftData models for persisting AI chat history to disk on iOS.
// Ported from macOS Centmond (2026-04-22). Uses the app's shared
// ModelContainer (see balanceApp.swift).
//
// ChatSession groups messages into named conversations.
// ChatMessageRecord stores individual messages with role, content,
// timestamp, and (for assistant) serialized AIAction blobs.
//
// ============================================================

@Model
final class ChatSession {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ChatMessageRecord.session)
    var messages: [ChatMessageRecord]

    init(title: String = "New Chat") {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.messages = []
    }

    var sortedMessages: [ChatMessageRecord] {
        messages.sorted { $0.timestamp < $1.timestamp }
    }
}

@Model
final class ChatMessageRecord {
    var id: UUID
    var roleRaw: String
    var content: String
    var timestamp: Date
    var actionsJSON: Data?

    var session: ChatSession?

    var role: AIMessage.Role {
        AIMessage.Role(rawValue: roleRaw) ?? .user
    }

    init(role: AIMessage.Role, content: String, actions: [AIAction]? = nil) {
        self.id = UUID()
        self.roleRaw = role.rawValue
        self.content = content
        self.timestamp = Date()

        if let actions, !actions.isEmpty {
            self.actionsJSON = try? JSONEncoder().encode(actions)
        }
    }

    func toAIMessage() -> AIMessage {
        var decoded: [AIAction]?
        if let data = actionsJSON {
            decoded = try? JSONDecoder().decode([AIAction].self, from: data)
        }
        return AIMessage(role: role, content: content, actions: decoded)
    }
}

// ============================================================
// MARK: - Chat Persistence Manager
// ============================================================

@MainActor
final class ChatPersistenceManager {

    static let shared = ChatPersistenceManager()

    private init() {}

    // MARK: - Sessions

    func createSession(context: ModelContext, title: String = "New Chat") -> ChatSession {
        let session = ChatSession(title: title)
        context.insert(session)
        try? context.save()
        ChatSync.pushSession(session)
        return session
    }

    func fetchSessions(context: ModelContext) -> [ChatSession] {
        let descriptor = FetchDescriptor<ChatSession>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func currentSession(context: ModelContext) -> ChatSession {
        if let latest = fetchSessions(context: context).first {
            return latest
        }
        return createSession(context: context)
    }

    // MARK: - Messages

    func saveUserMessage(_ text: String, session: ChatSession, context: ModelContext) {
        let record = ChatMessageRecord(role: .user, content: text)
        record.session = session
        session.messages.append(record)
        session.updatedAt = Date()
        try? context.save()
        ChatSync.pushMessage(record, sessionId: session.id)
        ChatSync.pushSession(session)
    }

    func saveAssistantMessage(_ text: String, actions: [AIAction]?, session: ChatSession, context: ModelContext) {
        let record = ChatMessageRecord(role: .assistant, content: text, actions: actions)
        record.session = session
        session.messages.append(record)
        session.updatedAt = Date()

        // Auto-title: first user message becomes the session title
        if session.title == "New Chat",
           let firstUser = session.sortedMessages.first(where: { $0.role == .user }) {
            let preview = String(firstUser.content.prefix(50))
            session.title = preview.count < firstUser.content.count ? preview + "..." : preview
        }

        try? context.save()
        ChatSync.pushMessage(record, sessionId: session.id)
        ChatSync.pushSession(session)
    }

    // MARK: - Loading into AIConversation

    /// Populate an existing AIConversation in-place with the session's history.
    /// Clears current messages first. Safe to call on the @StateObject instance
    /// held by AIChatView — SwiftUI keeps observing the same object.
    func populate(_ conversation: AIConversation, from session: ChatSession) {
        conversation.messages.removeAll()
        conversation.pendingActions.removeAll()
        for record in session.sortedMessages {
            let msg = record.toAIMessage()
            if msg.role == .user {
                conversation.addUserMessage(msg.content)
            } else if msg.role == .assistant {
                conversation.addAssistantMessage(msg.content, actions: msg.actions)
            }
        }
    }

    // MARK: - Rename

    func renameSession(_ session: ChatSession, to newTitle: String, context: ModelContext) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        session.title = trimmed
        session.updatedAt = Date()
        try? context.save()
        ChatSync.pushSession(session)
    }

    // MARK: - Deletion

    func deleteSession(_ session: ChatSession, context: ModelContext) {
        let id = session.id
        context.delete(session)
        try? context.save()
        ChatSync.deleteSession(id: id)
    }

    func clearAll(context: ModelContext) {
        for session in fetchSessions(context: context) {
            context.delete(session)
        }
        try? context.save()
        ChatSync.deleteAllSessions()
    }
}
