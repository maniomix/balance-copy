import Foundation
import Supabase

// ============================================================
// MARK: - AIStateSync (Phase 5.9)
// ============================================================
// Generic UserDefaults ↔ Supabase kv mirror for the AI subsystem.
//
// All AI domains (action history, memory entries, merchant profiles,
// few-shot examples, user prefs, proactive dismissals) persist
// complex Codable blobs to UserDefaults. This layer mirrors them to
// `public.ai_memory(owner_id, key, value jsonb)` so they sync across
// devices.
//
// UserDefaults stays the synchronous fast path. Cloud is best-effort:
// `pushBlob(key:_:)` fires-and-forgets; `pull()` on sign-in does a
// single SELECT and overwrites the matching UserDefaults keys.
// ============================================================

@MainActor
enum AIStateSync {

    // MARK: - Registry of sync keys
    //
    // Add a new entry here whenever an AI domain wants cross-device sync.
    // The `userDefaultsKey` is the key the existing manager uses; the
    // `cloudKey` is what we write into `ai_memory.key`.
    struct Domain {
        let cloudKey: String
        let userDefaultsKey: String
    }

    static let domains: [Domain] = [
        .init(cloudKey: "ai.action_history",       userDefaultsKey: "ai.actionHistory.v2"),
        .init(cloudKey: "ai.memory_entries",       userDefaultsKey: "ai.memoryStore"),
        .init(cloudKey: "ai.merchant_profiles",    userDefaultsKey: "ai.merchantMemory"),
        .init(cloudKey: "ai.fewshot_examples",     userDefaultsKey: "ai.fewShotExamples"),
        .init(cloudKey: "ai.user_preferences",     userDefaultsKey: "ai.userPreferences"),
        .init(cloudKey: "ai.proactive_dismissals", userDefaultsKey: "ai.proactive.dismissedKeys"),
    ]

    private static var client: SupabaseClient { SupabaseManager.shared.client }

    // MARK: - Pull (sign-in)

    private struct Row: Codable { let key: String; let value: AnyJSONValue }

    /// Fetch all AI rows for the current user and overwrite the matching
    /// UserDefaults keys. Idempotent — safe to call on every cold start.
    static func pull() async {
        do {
            let rows: [Row] = try await client
                .from("ai_memory")
                .select("key, value")
                .in("key", values: domains.map(\.cloudKey))
                .execute()
                .value
            let byKey = Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0.value) })
            for d in domains {
                guard let v = byKey[d.cloudKey],
                      let data = try? JSONEncoder().encode(v) else { continue }
                UserDefaults.standard.set(data, forKey: d.userDefaultsKey)
            }
            SecureLogger.info("AI state pulled: \(rows.count) domains")
        } catch {
            SecureLogger.warning("AI state pull failed")
        }
    }

    // MARK: - Push

    /// Mirror a single domain's encoded JSON blob to `ai_memory`.
    /// Call from the manager's persist() right after the UserDefaults set.
    static func pushBlob(cloudKey: String, encoded: Data) {
        Task.detached(priority: .background) {
            await pushBlocking(cloudKey: cloudKey, encoded: encoded)
        }
    }

    static func pushBlocking(cloudKey: String, encoded: Data) async {
        // Decode the blob to a JSON value so PostgREST stores it as native jsonb,
        // not as a quoted string. Falls back to wrapping if decode fails.
        let value: AnyJSONValue
        if let parsed = try? JSONDecoder().decode(AnyJSONValue.self, from: encoded) {
            value = parsed
        } else if let str = String(data: encoded, encoding: .utf8) {
            value = .string(str)
        } else {
            return
        }

        struct UpsertRow: Encodable {
            let key: String
            let value: AnyJSONValue
        }
        do {
            try await client
                .from("ai_memory")
                .upsert(UpsertRow(key: cloudKey, value: value),
                        onConflict: "owner_id,key")
                .execute()
        } catch {
            SecureLogger.warning("AI state push failed: \(cloudKey)")
        }
    }
}

// MARK: - AnyJSONValue
//
// A type-erased JSON container so `ai_memory.value` round-trips as native
// jsonb regardless of the underlying Swift type. Replaces the need for a
// dedicated DTO per AI domain.

enum AnyJSONValue: Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AnyJSONValue])
    case object([String: AnyJSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([AnyJSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: AnyJSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unknown JSON shape")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:        try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v):  try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}
