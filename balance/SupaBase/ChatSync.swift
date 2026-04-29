import Foundation
import Supabase
import SwiftData

// ============================================================
// MARK: - ChatSync (Phase 5.9b)
// ============================================================
// Mirrors SwiftData ChatSession / ChatMessageRecord to
// public.ai_chat_sessions / public.ai_chat_messages.
//
// SwiftData stays the local source of truth. Push happens
// per-save (small messages, cheap upsert). Pull on sign-in
// reconciles by id: cloud rows missing locally get inserted
// into SwiftData; local rows missing in cloud stay (will be
// pushed on next save).
//
// Conflict policy: per-row last-write-wins on updated_at /
// created_at. Same as everywhere else in the rebuild.
// ============================================================

@MainActor
enum ChatSync {

    private static var client: SupabaseClient { SupabaseManager.shared.client }

    // MARK: - DTOs

    private struct SessionRow: Codable {
        let id: String
        let title: String?
        let created_at: String
        let updated_at: String
    }

    private struct MessageRow: Codable {
        let id: String
        let session_id: String
        let role: String
        let content: String
        let actions: AnyJSONValue?    // matches new column name
        let created_at: String
    }

    private static let isoOut: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    // MARK: - Push

    /// Upsert a session row (after rename, new chat, etc.). Fire-and-forget.
    static func pushSession(_ session: ChatSession) {
        let row = SessionRow(
            id: session.id.uuidString,
            title: session.title,
            created_at: isoOut.string(from: session.createdAt),
            updated_at: isoOut.string(from: session.updatedAt)
        )
        Task.detached(priority: .background) {
            do {
                try await client
                    .from("ai_chat_sessions")
                    .upsert(row, onConflict: "id")
                    .execute()
            } catch {
                SecureLogger.warning("Chat session push failed")
            }
        }
    }

    /// Upsert a single message after it's saved locally. Fire-and-forget.
    static func pushMessage(_ record: ChatMessageRecord, sessionId: UUID) {
        let actionsValue: AnyJSONValue? = {
            guard let data = record.actionsJSON else { return nil }
            return try? JSONDecoder().decode(AnyJSONValue.self, from: data)
        }()
        let row = MessageRow(
            id: record.id.uuidString,
            session_id: sessionId.uuidString,
            role: record.roleRaw,
            content: record.content,
            actions: actionsValue,
            created_at: isoOut.string(from: record.timestamp)
        )
        Task.detached(priority: .background) {
            do {
                try await client
                    .from("ai_chat_messages")
                    .upsert(row, onConflict: "id")
                    .execute()
            } catch {
                SecureLogger.warning("Chat message push failed")
            }
        }
    }

    // MARK: - Delete

    /// Cascades to messages via FK on delete cascade.
    static func deleteSession(id: UUID) {
        Task.detached(priority: .background) {
            do {
                try await client
                    .from("ai_chat_sessions")
                    .delete()
                    .eq("id", value: id.uuidString)
                    .execute()
            } catch {
                SecureLogger.warning("Chat session delete failed")
            }
        }
    }

    static func deleteAllSessions() {
        Task.detached(priority: .background) {
            do {
                guard let userId = await AuthManager.shared.currentUser?.id.uuidString else { return }
                try await client
                    .from("ai_chat_sessions")
                    .delete()
                    .eq("owner_id", value: userId)
                    .execute()
            } catch {
                SecureLogger.warning("Chat clear-all failed")
            }
        }
    }

    // MARK: - Pull (sign-in)

    /// Reconciles cloud sessions+messages into the SwiftData store. Cloud
    /// rows missing locally get inserted; local-only rows (not yet pushed)
    /// are left alone and will sync on next save.
    static func pull(into context: ModelContext) async {
        do {
            let sessions: [SessionRow] = try await client
                .from("ai_chat_sessions")
                .select()
                .order("updated_at", ascending: false)
                .execute()
                .value
            let messages: [MessageRow] = try await client
                .from("ai_chat_messages")
                .select()
                .order("created_at", ascending: true)
                .execute()
                .value

            // Local snapshots for fast lookup
            let local = (try? context.fetch(FetchDescriptor<ChatSession>())) ?? []
            var localSessionsById = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })

            // Insert missing sessions
            for row in sessions {
                guard let uuid = UUID(uuidString: row.id) else { continue }
                if localSessionsById[uuid] == nil {
                    let newSession = ChatSession(title: row.title ?? "New Chat")
                    // Override the auto-generated ID to keep cloud + local aligned
                    newSession.id = uuid
                    newSession.createdAt = parseDate(row.created_at) ?? Date()
                    newSession.updatedAt = parseDate(row.updated_at) ?? Date()
                    context.insert(newSession)
                    localSessionsById[uuid] = newSession
                }
            }

            // Build a set of local message IDs to skip duplicates
            let localMessageIds: Set<UUID> = Set(local.flatMap { $0.messages.map(\.id) })

            for m in messages {
                guard let mid = UUID(uuidString: m.id),
                      let sid = UUID(uuidString: m.session_id),
                      let parent = localSessionsById[sid] else { continue }
                if localMessageIds.contains(mid) { continue }
                let role = AIMessage.Role(rawValue: m.role) ?? .user
                let actions: [AIAction]? = {
                    guard let v = m.actions, case .array = v,
                          let raw = try? JSONEncoder().encode(v) else { return nil }
                    return try? JSONDecoder().decode([AIAction].self, from: raw)
                }()
                let record = ChatMessageRecord(role: role, content: m.content, actions: actions)
                record.id = mid
                record.timestamp = parseDate(m.created_at) ?? Date()
                record.session = parent
                parent.messages.append(record)
            }

            try? context.save()
            SecureLogger.info("Chat pulled: \(sessions.count) sessions, \(messages.count) messages")
        } catch {
            SecureLogger.warning("Chat pull failed")
        }
    }
}
