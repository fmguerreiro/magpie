import AppKit
import SwiftUI

let securityPath = "/usr/bin/security"

// Approximation of "assigned + mentions + watched": Jira has no currentUser()
// mention operator, so this covers assigned-and-open, watched, and reported.
// No trailing ORDER BY — jira-cli appends its own ordering and a second one 400s.
let defaultJiraJQL = "(assignee = currentUser() AND statusCategory != Done) OR (watcher = currentUser() AND updated >= -7d) OR (reporter = currentUser() AND statusCategory != Done)"

// Personal paths and Jira identity live in a config file outside the repo so the
// source can be shared. See config.example.json. Absent Jira block => GitHub only.
struct AppConfig {
    let ghPath: String
    let jiraPath: String
    let jira: JiraConfig?
    let github: GitHubFilter

    struct JiraConfig {
        let site: String
        let email: String
        let keychainService: String
        let jql: String
    }

    // Repo/org filter for GitHub notifications. Patterns match "owner",
    // "owner/*", or "owner/repo" (case-insensitive). With an include list, only
    // matching repos show; exclude hides repos. On conflict, include wins.
    struct GitHubFilter {
        let include: [String]
        let exclude: [String]

        func allows(_ fullName: String) -> Bool {
            let included = Self.matches(include, fullName)
            if !include.isEmpty && !included { return false }
            if Self.matches(exclude, fullName) && !included { return false }
            return true
        }

        private static func matches(_ patterns: [String], _ fullName: String) -> Bool {
            let name = fullName.lowercased()
            let parts = name.split(separator: "/", maxSplits: 1)
            let owner = parts.count == 2 ? String(parts[0]) : nil
            return patterns.contains { pattern in
                let pattern = pattern.lowercased()
                if pattern == name { return true }
                guard let owner else { return false }
                return pattern == owner || pattern == "\(owner)/*"
            }
        }
    }

    private struct Raw: Decodable {
        var ghPath: String?
        var jiraPath: String?
        var jira: RawJira?
        var github: RawGitHub?
        struct RawJira: Decodable {
            var site: String
            var email: String
            var keychainService: String?
            var jql: String?
        }
        struct RawGitHub: Decodable {
            var include: [String]?
            var exclude: [String]?
        }
    }

    static func load() -> AppConfig {
        let path = NSString(string: "~/.config/magpie/config.json").expandingTildeInPath
        let raw = (try? Data(contentsOf: URL(fileURLWithPath: path)))
            .flatMap { try? JSONDecoder().decode(Raw.self, from: $0) }

        let jira = raw?.jira.map {
            JiraConfig(site: $0.site, email: $0.email,
                       keychainService: $0.keychainService ?? "magpie-jira",
                       jql: $0.jql ?? defaultJiraJQL)
        }
        return AppConfig(
            ghPath: raw?.ghPath ?? resolveBinary("gh") ?? "/usr/local/bin/gh",
            jiraPath: raw?.jiraPath ?? resolveBinary("jira") ?? "/opt/homebrew/bin/jira",
            jira: jira,
            github: GitHubFilter(include: raw?.github?.include ?? [],
                                 exclude: raw?.github?.exclude ?? [])
        )
    }

    // Finder-launched apps get a minimal PATH, so probe the usual install dirs.
    private static func resolveBinary(_ name: String) -> String? {
        let home = NSHomeDirectory()
        let candidates = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        return candidates
            .map { "\($0)/\(name)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

let config = AppConfig.load()
let ghPath = config.ghPath
let jiraPath = config.jiraPath

enum Source {
    case github
    case jira
}

enum SubjectKind {
    case pullRequest, issue, discussion, commit, release, other

    init(_ raw: String) {
        switch raw {
        case "PullRequest": self = .pullRequest
        case "Issue": self = .issue
        case "Discussion": self = .discussion
        case "Commit": self = .commit
        case "Release": self = .release
        default: self = .other
        }
    }

    var symbol: String {
        switch self {
        case .pullRequest: return "arrow.triangle.pull"
        case .issue: return "smallcircle.filled.circle"
        case .discussion: return "bubble.left.and.bubble.right"
        case .commit: return "arrow.triangle.branch"
        case .release: return "tag"
        case .other: return "bell"
        }
    }
}

struct ThreadStatus {
    let label: String
    let symbol: String
    let tint: Color
}

// Normalized notification item shared across adapters.
struct Item: Identifiable {
    let id: String
    let source: Source
    let group: String
    let title: String
    let url: URL?
    let actionId: String
    let kind: SubjectKind
    let canMarkRead: Bool
    // "#34" for GitHub PRs/issues, "PF-117" for Jira.
    var reference: String? = nil
    // Why this notification reached you (GitHub: review_requested/mention/...).
    var reason: String? = nil
    var status: ThreadStatus?
    var avatarURL: URL?
    // Jira issues have no server "read" state, so "seen" is local and keyed on
    // the issue's updated timestamp: dismissing hides it until the issue changes.
    var version: String? = nil
    // When the notification last changed, used to show "5h ago" in the caption.
    var updatedAt: Date? = nil
    // GitHub's raw reason ("mention", "comment", ...), kept so enrich can decide
    // whether to resolve the actor behind the latest comment.
    var rawReason: String? = nil
    // GitHub API URL of the comment that triggered this notification, if any.
    var latestCommentURL: String? = nil

    var displaySymbol: String {
        if let status { return status.symbol }
        return source == .github ? kind.symbol : "smallcircle.filled.circle"
    }

    var displayTint: Color {
        status?.tint ?? .secondary
    }

    // Small context line under the title: GitHub's reason, else the status words,
    // suffixed with how long ago the notification last changed ("review requested 5h ago").
    var caption: String? {
        let base = reason ?? status?.label
        guard let base else { return updatedAt.map(relativeAge) }
        guard let updatedAt else { return base }
        return "\(base) \(relativeAge(updatedAt))"
    }
}

// Compact "time ago" suffix: "just now", "5m ago", "5h ago", "3d ago", "2w ago".
func relativeAge(_ date: Date) -> String {
    let elapsed = max(0, Date().timeIntervalSince(date))
    let minute = 60.0, hour = 3600.0, day = 86400.0, week = 604800.0
    if elapsed < minute { return "just now" }
    if elapsed < hour { return "\(Int(elapsed / minute))m ago" }
    if elapsed < day { return "\(Int(elapsed / hour))h ago" }
    if elapsed < week { return "\(Int(elapsed / day))d ago" }
    return "\(Int(elapsed / week))w ago"
}

func friendlyGitHubReason(_ raw: String) -> String {
    switch raw {
    case "review_requested": return "review requested"
    case "mention": return "mentioned you"
    case "team_mention": return "team mentioned"
    case "assign": return "assigned to you"
    case "author": return "you opened this"
    case "comment": return "new comment"
    case "state_change": return "state changed"
    case "subscribed", "manual": return "subscribed"
    case "ci_activity": return "CI activity"
    case "security_alert": return "security alert"
    default: return raw.replacingOccurrences(of: "_", with: " ")
    }
}

// MARK: - Subprocess helper

func runCommand(_ executable: String, _ arguments: [String], env: [String: String]? = nil,
                completion: @escaping (Result<Data, Error>) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let env {
            var merged = ProcessInfo.processInfo.environment
            for (key, value) in env { merged[key] = value }
            process.environment = merged
        }
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                DispatchQueue.main.async { completion(.success(data)) }
            } else {
                let message = String(data: errorData, encoding: .utf8) ?? "exit \(process.terminationStatus)"
                let error = NSError(domain: executable, code: Int(process.terminationStatus),
                                    userInfo: [NSLocalizedDescriptionKey: message])
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
        }
    }
}

func runCommandSync(_ executable: String, _ arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = Pipe()
    do {
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    } catch {
        return nil
    }
}

// MARK: - Adapter protocol

protocol NotificationAdapter {
    var source: Source { get }
    func load(completion: @escaping (Result<[Item], Error>) -> Void)
    func enrich(_ item: Item, completion: @escaping (Item) -> Void)
    func markRead(_ item: Item)
}

// MARK: - GitHub

struct GHThread: Identifiable, Decodable {
    let id: String
    let subject: Subject
    let repository: Repository
    let reason: String
    let updated_at: String?

    var updatedAt: Date? {
        updated_at.flatMap { GHThread.timestampFormatter.date(from: $0) }
    }

    static let timestampFormatter = ISO8601DateFormatter()

    struct Subject: Decodable {
        let title: String
        let url: String?
        let type: String
        let latest_comment_url: String?
    }

    struct Repository: Decodable {
        let full_name: String
        let html_url: String
    }

    var kind: SubjectKind { SubjectKind(subject.type) }

    var webURL: URL? {
        let raw = subject.url ?? repository.html_url
        let web = raw
            .replacingOccurrences(of: "https://api.github.com/repos", with: "https://github.com")
            .replacingOccurrences(of: "/pulls/", with: "/pull/")
            .replacingOccurrences(of: "/commits/", with: "/commit/")
        return URL(string: web)
    }
}

struct GHAuthor: Decodable {
    let login: String
}

struct GHComment: Decodable {
    let user: GHAuthor
}

struct GHPullRequestInfo: Decodable {
    let state: String
    let isDraft: Bool
    let reviewDecision: String?
    let author: GHAuthor?
}

struct GHIssueInfo: Decodable {
    let state: String
    let stateReason: String?
    let author: GHAuthor?
}

final class GitHubAdapter: NotificationAdapter {
    let source = Source.github

    func load(completion: @escaping (Result<[Item], Error>) -> Void) {
        runCommand(ghPath, ["api", "notifications"]) { result in
            switch result {
            case .success(let data):
                do {
                    let threads = try JSONDecoder().decode([GHThread].self, from: data)
                    let items = threads
                        .filter { config.github.allows($0.repository.full_name) }
                        .map { thread in
                        Item(id: "gh:\(thread.id)", source: .github,
                             group: thread.repository.full_name, title: thread.subject.title,
                             url: thread.webURL, actionId: thread.id, kind: thread.kind,
                             canMarkRead: true,
                             reference: thread.webURL.flatMap { Int($0.lastPathComponent) }.map { "#\($0)" },
                             reason: friendlyGitHubReason(thread.reason),
                             status: nil, avatarURL: nil, updatedAt: thread.updatedAt,
                             rawReason: thread.reason,
                             latestCommentURL: thread.subject.latest_comment_url)
                    }
                    completion(.success(items))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func enrich(_ item: Item, completion: @escaping (Item) -> Void) {
        guard let url = item.url?.absoluteString else { return }
        switch item.kind {
        case .pullRequest:
            runCommand(ghPath, ["pr", "view", url, "--json", "state,isDraft,reviewDecision,author"]) { result in
                guard case .success(let data) = result,
                      let info = try? JSONDecoder().decode(GHPullRequestInfo.self, from: data) else {
                    // State fetch failed; still try to name the mentioner.
                    self.resolveActor(item, completion: completion)
                    return
                }
                var updated = item
                updated.status = Self.status(forPullRequest: info)
                if let login = info.author?.login { updated.avatarURL = Self.avatarURL(login) }
                self.resolveActor(updated, completion: completion)
            }
        case .issue:
            runCommand(ghPath, ["issue", "view", url, "--json", "state,stateReason,author"]) { result in
                guard case .success(let data) = result,
                      let info = try? JSONDecoder().decode(GHIssueInfo.self, from: data) else {
                    self.resolveActor(item, completion: completion)
                    return
                }
                var updated = item
                updated.status = Self.status(forIssue: info)
                if let login = info.author?.login { updated.avatarURL = Self.avatarURL(login) }
                self.resolveActor(updated, completion: completion)
            }
        default:
            // Commits, releases, discussions etc. carry no PR/issue state to enrich.
            break
        }
    }

    // For mention/comment notifications, name the person behind the triggering
    // comment ("octocat mentioned you") and show their avatar instead of the
    // PR/issue author's. Other reasons pass through untouched.
    private static let actorReasons: Set<String> = ["mention", "team_mention", "comment"]

    private func resolveActor(_ item: Item, completion: @escaping (Item) -> Void) {
        guard let raw = item.rawReason, Self.actorReasons.contains(raw),
              let commentURL = item.latestCommentURL else {
            completion(item)
            return
        }
        // gh api accepts a full https://api.github.com/... URL as the path arg.
        runCommand(ghPath, ["api", commentURL]) { result in
            guard case .success(let data) = result,
                  let comment = try? JSONDecoder().decode(GHComment.self, from: data) else {
                completion(item)
                return
            }
            var updated = item
            updated.reason = Self.actorReason(raw, login: comment.user.login)
            updated.avatarURL = Self.avatarURL(comment.user.login)
            completion(updated)
        }
    }

    private static func actorReason(_ raw: String, login: String) -> String {
        switch raw {
        case "mention": return "\(login) mentioned you"
        case "team_mention": return "\(login) mentioned your team"
        case "comment": return "\(login) commented"
        default: return friendlyGitHubReason(raw)
        }
    }

    func markRead(_ item: Item) {
        runCommand(ghPath, ["api", "--method", "PATCH", "/notifications/threads/\(item.actionId)"]) { _ in }
    }

    private static func avatarURL(_ login: String) -> URL? {
        URL(string: "https://github.com/\(login).png?size=48")
    }

    private static func status(forPullRequest info: GHPullRequestInfo) -> ThreadStatus {
        switch info.state.uppercased() {
        case "MERGED":
            return ThreadStatus(label: "merged", symbol: "arrow.triangle.merge", tint: .purple)
        case "CLOSED":
            return ThreadStatus(label: "closed", symbol: "xmark.circle.fill", tint: .red)
        default:
            if info.isDraft {
                return ThreadStatus(label: "draft", symbol: "circle.dashed", tint: .gray)
            }
            switch (info.reviewDecision ?? "").uppercased() {
            case "CHANGES_REQUESTED":
                return ThreadStatus(label: "changes requested", symbol: "exclamationmark.bubble.fill", tint: .orange)
            case "APPROVED":
                return ThreadStatus(label: "approved", symbol: "checkmark.seal.fill", tint: .green)
            default:
                return ThreadStatus(label: "open", symbol: "arrow.triangle.pull", tint: .green)
            }
        }
    }

    private static func status(forIssue info: GHIssueInfo) -> ThreadStatus {
        if info.state.uppercased() == "OPEN" {
            return ThreadStatus(label: "open", symbol: "smallcircle.filled.circle", tint: .green)
        }
        if (info.stateReason ?? "").uppercased() == "NOT_PLANNED" {
            return ThreadStatus(label: "closed", symbol: "slash.circle.fill", tint: .gray)
        }
        return ThreadStatus(label: "closed", symbol: "checkmark.circle.fill", tint: .purple)
    }
}

// MARK: - Jira

struct JiraListIssue: Decodable {
    let key: String
    let fields: Fields

    struct Fields: Decodable {
        let summary: String
        let updated: String?
    }
}

struct JiraIssueDetail: Decodable {
    let fields: Fields
    let changelog: Changelog?

    struct Fields: Decodable {
        let status: Status?
        let assignee: User?
        let comment: CommentBlock?

        struct Status: Decodable {
            let name: String?
            let statusCategory: Category?
            struct Category: Decodable { let key: String? }
        }

        struct User: Decodable {
            let displayName: String?
            let avatarUrls: [String: String]?
        }

        struct CommentBlock: Decodable {
            let comments: [Comment]
            struct Comment: Decodable {
                let created: String?
                let updated: String?
                let author: User?
            }
        }
    }

    struct Changelog: Decodable {
        let histories: [History]
        struct History: Decodable {
            let created: String?
            let items: [ChangeItem]
            let author: JiraIssueDetail.Fields.User?
            struct ChangeItem: Decodable {
                let field: String?
                let toString: String?
            }
        }
    }
}

final class JiraAdapter: NotificationAdapter {
    let source = Source.jira
    private let jira: AppConfig.JiraConfig
    private let token: String?
    private let seenKey = "jiraSeen"
    private var seen: [String: String]

    init(_ jira: AppConfig.JiraConfig) {
        self.jira = jira
        token = runCommandSync(securityPath,
                               ["find-generic-password", "-a", jira.email, "-s", jira.keychainService, "-w"])
        seen = (UserDefaults.standard.dictionary(forKey: seenKey) as? [String: String]) ?? [:]
    }

    private var tokenEnv: [String: String]? {
        guard let token else { return nil }
        return ["JIRA_API_TOKEN": token]
    }

    func load(completion: @escaping (Result<[Item], Error>) -> Void) {
        guard let env = tokenEnv else {
            completion(.failure(NSError(domain: "jira", code: 1,
                                        userInfo: [NSLocalizedDescriptionKey: "no Jira token in Keychain"])))
            return
        }
        runCommand(jiraPath, ["issue", "list", "-q", jira.jql, "--raw"], env: env) { result in
            switch result {
            case .success(let data):
                do {
                    let issues = try JSONDecoder().decode([JiraListIssue].self, from: data)
                    let items = issues
                        .filter { self.seen[$0.key] != ($0.fields.updated ?? "") }
                        .map { issue in
                            Item(id: "jira:\(issue.key)", source: .jira,
                                 group: "\(issue.key.split(separator: "-").first.map(String.init) ?? "Jira") · Jira",
                                 title: issue.fields.summary,
                                 url: URL(string: "https://\(self.jira.site)/browse/\(issue.key)"),
                                 actionId: issue.key, kind: .other, canMarkRead: true,
                                 reference: issue.key,
                                 status: nil, avatarURL: nil, version: issue.fields.updated,
                                 updatedAt: Self.parse(issue.fields.updated))
                        }
                    completion(.success(items))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // jira-cli's --raw can't expand the changelog, so enrich goes straight to the
    // REST API (same Keychain token, basic auth) to also learn what last happened.
    func enrich(_ item: Item, completion: @escaping (Item) -> Void) {
        guard let token,
              let url = URL(string: "https://\(jira.site)/rest/api/3/issue/\(item.actionId)?expand=changelog&fields=status,assignee,comment")
        else { return }

        var request = URLRequest(url: url)
        let credentials = Data("\(jira.email):\(token)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let detail = try? JSONDecoder().decode(JiraIssueDetail.self, from: data) else { return }
            var updated = item
            updated.status = Self.status(categoryKey: detail.fields.status?.statusCategory?.key,
                                         name: detail.fields.status?.name)
            let activity = Self.activity(from: detail)
            updated.reason = activity?.text
            // Prefer the avatar of whoever last acted; fall back to the assignee.
            if let actorAvatar = activity?.avatar {
                updated.avatarURL = URL(string: actorAvatar)
            } else if let avatar = detail.fields.assignee?.avatarUrls?["48x48"] {
                updated.avatarURL = URL(string: avatar)
            }
            DispatchQueue.main.async { completion(updated) }
        }.resume()
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return formatter
    }()

    private static func parse(_ value: String?) -> Date? {
        value.flatMap { timestampFormatter.date(from: $0) }
    }

    // Most recent of (last comment, last changelog entry) wins; describe it and
    // name who did it ("Jane Doe commented"), with that person's avatar.
    private static func activity(from detail: JiraIssueDetail) -> (text: String, avatar: String?)? {
        let lastComment = detail.fields.comment?.comments.last
        let commentDate = parse(lastComment?.updated ?? lastComment?.created)
        let lastHistory = detail.changelog?.histories.last
        let historyDate = parse(lastHistory?.created)

        let commentWins: Bool
        if let commentDate {
            commentWins = historyDate.map { commentDate >= $0 } ?? true
        } else {
            commentWins = false
        }

        if commentWins {
            let author = lastComment?.author
            return (actorPhrase(author?.displayName, "commented"), author?.avatarUrls?["48x48"])
        }
        if let lastHistory {
            let name = lastHistory.author?.displayName
            let avatar = lastHistory.author?.avatarUrls?["48x48"]
            if let status = lastHistory.items.first(where: { $0.field == "status" }) {
                return (actorPhrase(name, "moved to \(status.toString ?? "new status")"), avatar)
            }
            if lastHistory.items.contains(where: { $0.field == "assignee" }) {
                return (actorPhrase(name, "reassigned"), avatar)
            }
            if let field = lastHistory.items.first?.field {
                return (actorPhrase(name, "\(field) updated"), avatar)
            }
        }
        if commentDate != nil {
            let author = lastComment?.author
            return (actorPhrase(author?.displayName, "commented"), author?.avatarUrls?["48x48"])
        }
        return nil
    }

    private static func actorPhrase(_ name: String?, _ verb: String) -> String {
        if let name, !name.isEmpty { return "\(name) \(verb)" }
        return verb
    }

    func markRead(_ item: Item) {
        seen[item.actionId] = item.version ?? ""
        UserDefaults.standard.set(seen, forKey: seenKey)
    }

    private static func status(categoryKey: String?, name: String?) -> ThreadStatus {
        let label = name ?? "—"
        switch categoryKey {
        case "done":
            return ThreadStatus(label: label, symbol: "checkmark.circle.fill", tint: .green)
        case "indeterminate":
            return ThreadStatus(label: label, symbol: "circle.lefthalf.filled", tint: .blue)
        default:
            return ThreadStatus(label: label, symbol: "circle", tint: .gray)
        }
    }
}

// MARK: - Store

final class Store: ObservableObject {
    @Published var items: [Item] = []
    @Published var errorMessage: String?
    @Published var loading = false

    private let adapters: [NotificationAdapter]
    private var timer: Timer?

    init(adapters: [NotificationAdapter]) {
        self.adapters = adapters
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    // GitHub groups first, then Jira; alphabetical within each.
    var grouped: [(group: String, items: [Item])] {
        let groups = Dictionary(grouping: items, by: { $0.group })
        return groups.keys.sorted { left, right in
            let leftJira = groups[left]?.first?.source == .jira
            let rightJira = groups[right]?.first?.source == .jira
            if leftJira != rightJira { return !leftJira }
            return left < right
        }.map { (group: $0, items: groups[$0] ?? []) }
    }

    private func adapter(for source: Source) -> NotificationAdapter? {
        adapters.first { $0.source == source }
    }

    func refresh() {
        loading = true
        let group = DispatchGroup()
        var collected: [Item] = []
        var firstError: Error?
        for adapter in adapters {
            group.enter()
            adapter.load { result in
                switch result {
                case .success(let items):
                    collected.append(contentsOf: items)
                case .failure(let error):
                    if firstError == nil { firstError = error }
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            self.items = collected
            self.errorMessage = firstError?.localizedDescription
            self.loading = false
            self.enrichAll()
        }
    }

    private func enrichAll() {
        for item in items {
            adapter(for: item.source)?.enrich(item) { [weak self] updated in
                guard let self, let index = self.items.firstIndex(where: { $0.id == updated.id }) else { return }
                self.items[index] = updated
            }
        }
    }

    func markRead(_ item: Item) {
        guard item.canMarkRead else { return }
        items.removeAll { $0.id == item.id }
        adapter(for: item.source)?.markRead(item)
    }

    func markGroupRead(_ group: String) {
        let toMark = items.filter { $0.group == group && $0.canMarkRead }
        items.removeAll { $0.group == group && $0.canMarkRead }
        for item in toMark { adapter(for: item.source)?.markRead(item) }
    }

    func markAllRead() {
        let toMark = items.filter { $0.canMarkRead }
        items.removeAll { $0.canMarkRead }
        for item in toMark { adapter(for: item.source)?.markRead(item) }
    }

    var hasReadableItems: Bool {
        items.contains { $0.canMarkRead }
    }

    func open(_ item: Item) {
        guard let url = item.url else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Views

// Leading glyph for a group header: the GitHub org's avatar (derived from the
// "<org>/<repo>" group name), or a neutral mark for Jira (no org avatar).
struct GroupIcon: View {
    let group: String
    let source: Source

    static func orgAvatarURL(for group: String, source: Source) -> URL? {
        guard source == .github else { return nil }
        let parts = group.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return URL(string: "https://github.com/\(parts[0]).png?size=48")
    }

    @ViewBuilder private var content: some View {
        if let url = Self.orgAvatarURL(for: group, source: source) {
            if let cached = demoAvatarCache[url] {
                Image(nsImage: cached).resizable().scaledToFill()
            } else {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.2))
                }
            }
        } else {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.15))
                .overlay(
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                )
        }
    }

    var body: some View {
        content
            .frame(width: 14, height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

struct ItemRow: View {
    let item: Item
    @ObservedObject var store: Store
    @State private var hovering = false

    private var titleText: Text {
        guard let reference = item.reference else { return Text(item.title) }
        return Text(reference).foregroundColor(.secondary) + Text("  ") + Text(item.title)
    }

    // Prefetched avatars (demo/snapshot only) render synchronously; everything
    // else streams over the network via AsyncImage.
    @ViewBuilder private var avatarImage: some View {
        if let url = item.avatarURL, let cached = demoAvatarCache[url] {
            Image(nsImage: cached).resizable().scaledToFill()
        } else {
            AsyncImage(url: item.avatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(Color.secondary.opacity(0.2))
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                avatarImage
                    .frame(width: 22, height: 22)
                    .clipShape(Circle())

                Image(systemName: item.displaySymbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(item.displayTint)
                    .padding(2)
                    .background(Circle().fill(Color(NSColor.windowBackgroundColor)))
                    .offset(x: 3, y: 3)
            }
            .frame(width: 22, height: 22)
            .padding(.top, 1)
            .help(item.status?.label ?? "")

            Button {
                store.open(item)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    titleText
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let caption = item.caption {
                        Text(caption)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if item.canMarkRead {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        store.markRead(item)
                    }
                } label: {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Mark as read")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(hovering ? Color.primary.opacity(0.06) : Color.clear)
        .onHover { hovering = $0 }
    }
}

struct ContentView: View {
    @ObservedObject var store: Store

    @State private var measuredHeight: CGFloat = 0
    private let maxListHeight: CGFloat = 460

    private var listHeight: CGFloat {
        let height = measuredHeight > 0 ? measuredHeight : 120
        return min(height, maxListHeight)
    }

    private func groupHasReadable(_ items: [Item]) -> Bool {
        items.contains { $0.canMarkRead }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Notifications").font(.headline)
                Spacer()
                if store.loading {
                    ProgressView().controlSize(.small)
                }
                Button {
                    store.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
            .padding(10)

            Divider()

            if let errorMessage = store.errorMessage, store.items.isEmpty {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(10)
            }

            if store.items.isEmpty {
                Text(store.loading ? "Loading…" : "Nothing to show")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(20)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(store.grouped, id: \.group) { group in
                            HStack(spacing: 5) {
                                GroupIcon(group: group.group,
                                          source: group.items.first?.source ?? .github)
                                Text(group.group)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if groupHasReadable(group.items) {
                                    Button("clear") {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            store.markGroupRead(group.group)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                            .padding(.bottom, 2)

                            ForEach(group.items) { item in
                                ItemRow(item: item, store: store)
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                            }
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { newHeight in
                        measuredHeight = newHeight
                    }
                }
                .frame(height: listHeight)
            }

            Divider()

            HStack {
                Button("Mark all as read") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        store.markAllRead()
                    }
                }
                .disabled(!store.hasReadableItems)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(10)
        }
        .frame(width: 380)
    }
}

// MARK: - Demo

// Avatars decoded ahead of a synchronous snapshot render, keyed by source URL.
// Empty in normal operation, so ItemRow falls back to AsyncImage.
var demoAvatarCache: [URL: NSImage] = [:]

// Static, non-scrolling mirror of ContentView for ImageRenderer. ContentView's
// ScrollView clamps its own height, which would clip an off-screen render, so
// the snapshot lays every row out at natural height instead.
struct SnapshotView: View {
    @ObservedObject var store: Store

    private func groupHasReadable(_ items: [Item]) -> Bool {
        items.contains { $0.canMarkRead }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Notifications").font(.headline)
                Spacer()
                Image(systemName: "arrow.clockwise").foregroundStyle(.secondary)
            }
            .padding(10)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                ForEach(store.grouped, id: \.group) { group in
                    HStack(spacing: 5) {
                        GroupIcon(group: group.group,
                                  source: group.items.first?.source ?? .github)
                        Text(group.group)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if groupHasReadable(group.items) {
                            Text("clear")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 2)

                    ForEach(group.items) { item in
                        ItemRow(item: item, store: store)
                    }
                }
            }

            Divider()

            HStack {
                Text("Mark all as read")
                Spacer()
                Text("Quit")
            }
            .padding(10)
        }
        .frame(width: 380)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

@MainActor
func renderSnapshot(to path: String) {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    application.appearance = NSAppearance(named: .aqua)

    var avatarURLs = Set<URL>()
    for item in DemoAdapter.items {
        if let url = item.avatarURL { avatarURLs.insert(url) }
        if let orgURL = GroupIcon.orgAvatarURL(for: item.group, source: item.source) {
            avatarURLs.insert(orgURL)
        }
    }
    for url in avatarURLs {
        if let data = try? Data(contentsOf: url), let image = NSImage(data: data) {
            demoAvatarCache[url] = image
        }
    }

    let store = Store(adapters: [DemoAdapter()])
    let deadline = Date().addingTimeInterval(3)
    while store.items.isEmpty && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    let card = SnapshotView(store: store)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
        .padding(24)

    let renderer = ImageRenderer(content: card)
    renderer.scale = 2

    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("snapshot render failed\n".utf8))
        exit(1)
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("snapshot write failed: \(error)\n".utf8))
        exit(1)
    }
}

// Canned, already-enriched items used for screenshots. Enabled with
// MAGPIE_DEMO=1 so the popover renders every state without touching real
// GitHub/Jira accounts. enrich/markRead are no-ops: the items arrive complete.
struct DemoAdapter: NotificationAdapter {
    let source = Source.github

    func load(completion: @escaping (Result<[Item], Error>) -> Void) {
        completion(.success(DemoAdapter.items))
    }

    func enrich(_ item: Item, completion: @escaping (Item) -> Void) {}
    func markRead(_ item: Item) {}

    private static func ago(_ seconds: TimeInterval) -> Date {
        Date().addingTimeInterval(-seconds)
    }

    private static func avatar(_ login: String) -> URL? {
        URL(string: "https://github.com/\(login).png")
    }

    private static func gh(_ ref: String, _ group: String, _ title: String,
                           kind: SubjectKind, reason: String, status: ThreadStatus,
                           login: String, age: TimeInterval) -> Item {
        Item(id: "demo:\(group)\(ref)", source: .github, group: group, title: title,
             url: URL(string: "https://github.com"), actionId: "demo:\(group)\(ref)",
             kind: kind, canMarkRead: true, reference: ref, reason: reason,
             status: status, avatarURL: avatar(login), updatedAt: ago(age))
    }

    private static func jira(_ key: String, _ title: String, reason: String,
                             status: ThreadStatus, login: String, age: TimeInterval) -> Item {
        let prefix = key.split(separator: "-").first.map(String.init) ?? "Jira"
        return Item(id: "demo:\(key)", source: .jira, group: "\(prefix) · Jira",
                    title: title, url: URL(string: "https://example.atlassian.net"),
                    actionId: key, kind: .other, canMarkRead: true, reference: key,
                    reason: reason, status: status, avatarURL: avatar(login),
                    updatedAt: ago(age))
    }

    static let items: [Item] = [
        gh("#128", "vercel/webapp", "Add OAuth login flow", kind: .pullRequest,
           reason: "review requested",
           status: ThreadStatus(label: "open", symbol: "arrow.triangle.pull", tint: .green),
           login: "octocat", age: 5 * 3600),
        gh("#131", "vercel/webapp", "Fix flaky checkout test", kind: .pullRequest,
           reason: "you opened this",
           status: ThreadStatus(label: "changes requested", symbol: "exclamationmark.bubble.fill", tint: .orange),
           login: "torvalds", age: 2 * 3600),
        gh("#119", "vercel/webapp", "Bump dependencies to latest", kind: .pullRequest,
           reason: "subscribed",
           status: ThreadStatus(label: "approved", symbol: "checkmark.seal.fill", tint: .green),
           login: "gaearon", age: 26 * 3600),
        gh("#98", "vercel/webapp", "Spike: websocket transport", kind: .pullRequest,
           reason: "you opened this",
           status: ThreadStatus(label: "draft", symbol: "circle.dashed", tint: .gray),
           login: "defunkt", age: 3 * 86400),
        gh("#117", "supabase/api", "Refactor cache invalidation", kind: .pullRequest,
           reason: "review requested",
           status: ThreadStatus(label: "merged", symbol: "arrow.triangle.merge", tint: .purple),
           login: "mojombo", age: 3 * 3600),
        gh("#51", "supabase/api", "Add per-route rate limiting", kind: .pullRequest,
           reason: "octocat mentioned you",
           status: ThreadStatus(label: "closed", symbol: "xmark.circle.fill", tint: .red),
           login: "octocat", age: 6 * 3600),
        gh("#44", "supabase/api", "Race condition in worker pool", kind: .issue,
           reason: "kelseyhightower mentioned you",
           status: ThreadStatus(label: "open", symbol: "smallcircle.filled.circle", tint: .green),
           login: "kelseyhightower", age: 35 * 60),
        gh("#40", "supabase/api", "Memory leak on reconnect", kind: .issue,
           reason: "state changed",
           status: ThreadStatus(label: "closed", symbol: "checkmark.circle.fill", tint: .purple),
           login: "torvalds", age: 4 * 3600),
        jira("PF-204", "Design new onboarding screens", reason: "Yuki Tanaka commented",
             status: ThreadStatus(label: "In Progress", symbol: "circle.lefthalf.filled", tint: .blue),
             login: "gaearon", age: 1 * 3600),
        jira("PF-198", "Migrate billing to Stripe", reason: "Sam Rivera reassigned",
             status: ThreadStatus(label: "To Do", symbol: "circle", tint: .gray),
             login: "octocat", age: 2 * 86400),
        jira("PF-187", "Ship Q2 analytics dashboard", reason: "Priya Nair moved to Done",
             status: ThreadStatus(label: "Done", symbol: "checkmark.circle.fill", tint: .green),
             login: "mojombo", age: 5 * 86400),
    ]
}

func makeAdapters() -> [NotificationAdapter] {
    if ProcessInfo.processInfo.environment["MAGPIE_DEMO"] == "1" {
        return [DemoAdapter()]
    }
    var adapters: [NotificationAdapter] = [GitHubAdapter()]
    if let jira = config.jira {
        adapters.append(JiraAdapter(jira))
    }
    return adapters
}

struct MagpieApp: App {
    @StateObject private var store = Store(adapters: makeAdapters())

    var body: some Scene {
        MenuBarExtra {
            ContentView(store: store)
        } label: {
            let count = store.items.count
            Image(systemName: count == 0 ? "bird" : "bird.fill")
            if count > 0 {
                Text("\(count)")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

if let snapshotPath = ProcessInfo.processInfo.environment["MAGPIE_SHOT"] {
    MainActor.assumeIsolated { renderSnapshot(to: snapshotPath) }
}

MagpieApp.main()
