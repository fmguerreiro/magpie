// Pure logic for naming a notification's actor when GitHub omits
// latest_comment_url (e.g. a thread bumped by a non-comment event). Kept free
// of any process/network dependency so it can be unit tested.

import Foundation

public struct CommentSummary: Equatable {
    public let author: String
    public let body: String

    public init(author: String, body: String) {
        self.author = author
        self.body = body
    }
}

// PR conversation comments live under the issues endpoint, which is where an
// @-mention in the timeline lands. nil when the URL is not a PR/issue.
public func issueCommentsEndpoint(forWebURL url: URL) -> String? {
    apiEndpoint(forWebURL: url, webKinds: ["pull", "issues"], apiSegment: "issues", suffix: "comments")
}

// Inline PR review comments live under the pulls endpoint, separate from the
// conversation comments above. nil for issues and non-PR/issue URLs.
public func reviewCommentsEndpoint(forWebURL url: URL) -> String? {
    apiEndpoint(forWebURL: url, webKinds: ["pull"], apiSegment: "pulls", suffix: "comments")
}

// PR reviews (approve / request changes / comment) live under the pulls
// endpoint. nil for issues and non-PR URLs.
public func reviewsEndpoint(forWebURL url: URL) -> String? {
    apiEndpoint(forWebURL: url, webKinds: ["pull"], apiSegment: "pulls", suffix: "reviews")
}

private func apiEndpoint(forWebURL url: URL, webKinds: Set<String>, apiSegment: String, suffix: String) -> String? {
    let parts = url.pathComponents.filter { $0 != "/" }
    guard parts.count >= 4, webKinds.contains(parts[2]), Int(parts[3]) != nil else { return nil }
    return "repos/\(parts[0])/\(parts[1])/\(apiSegment)/\(parts[3])/\(suffix)"
}

public struct DatedComment: Equatable {
    public let author: String
    public let createdAt: Date

    public init(author: String, createdAt: Date) {
        self.author = author
        self.createdAt = createdAt
    }
}

// A comment counts as the trigger only if it sits within this window of the
// thread's last-changed time. GitHub omits latest_comment_url for authored
// threads and bumps the thread at or shortly after the comment (lags of tens of
// seconds are real), so we match on recency rather than an exact key.
public let commentTriggerWindow: TimeInterval = 5 * 60

// GitHub bot logins carry a "[bot]" suffix ("cubic-dev-ai[bot]"); drop it for
// display so the caption reads "cubic-dev-ai commented".
public func displayLogin(_ login: String) -> String {
    login.hasSuffix("[bot]") ? String(login.dropLast("[bot]".count)) : login
}

// For a thread that arrived under a reason vaguer than its state (author,
// subscribed, ...), a recent comment by someone other than the viewer is the
// real news. Returns the actor to surface ("octocat commented", avatar octocat),
// or nil to keep the state caption: not such a reason, no comment, the viewer's
// own comment, or a comment too far from the thread's last change to be its cause.
public func recentCommenterAttribution(rawReason: String?, viewerLogin: String?,
                                       latest: DatedComment?, threadUpdatedAt: Date?) -> MentionAttribution? {
    guard let rawReason, reasonsSupersededByState.contains(rawReason),
          let latest, let threadUpdatedAt,
          latest.author != viewerLogin,
          abs(threadUpdatedAt.timeIntervalSince(latest.createdAt)) <= commentTriggerWindow else { return nil }
    // GitHub serves a bot's avatar at its stripped login, not the "[bot]" form,
    // so use the display name for both the caption and the avatar.
    let name = displayLogin(latest.author)
    return MentionAttribution(reason: "\(name) commented", avatarLogin: name)
}

// The more recent of two optional comments, or whichever one is present.
public func newer(_ first: DatedComment?, _ second: DatedComment?) -> DatedComment? {
    switch (first, second) {
    case let (first?, second?): return first.createdAt >= second.createdAt ? first : second
    case let (first?, nil): return first
    case let (nil, second?): return second
    case (nil, nil): return nil
    }
}

// The most recent comment in a batch, or nil if empty. The per-issue comments
// endpoint ignores sort/direction and returns oldest-first, so the caller pages
// through all of them and picks the latest here rather than trusting the server.
public func newestComment(in comments: [DatedComment]) -> DatedComment? {
    comments.max { $0.createdAt < $1.createdAt }
}

public struct DatedReview: Equatable {
    public let author: String
    public let state: String
    public let createdAt: Date

    public init(author: String, state: String, createdAt: Date) {
        self.author = author
        self.state = state
        self.createdAt = createdAt
    }
}

// nil for PENDING (unsubmitted) and DISMISSED (retraction).
func reviewVerb(_ state: String) -> String? {
    switch state.uppercased() {
    case "APPROVED": return "approved"
    case "CHANGES_REQUESTED": return "requested changes"
    case "COMMENTED": return "reviewed"
    default: return nil
    }
}

// A review surfaced as the latest event ("ryukez approved"), or nil to leave the
// caption alone. A review wins only when it is the most recent actor action on
// the thread: a captionable state, within the trigger window, not the viewer's
// own, and no comment newer than it (a later comment is the actual latest event).
public func reviewEventAttribution(viewerLogin: String?, latestComment: DatedComment?,
                                   latestReview: DatedReview?, threadUpdatedAt: Date?) -> MentionAttribution? {
    guard let review = latestReview, let threadUpdatedAt,
          let verb = reviewVerb(review.state),
          review.author != viewerLogin,
          abs(threadUpdatedAt.timeIntervalSince(review.createdAt)) <= commentTriggerWindow else { return nil }
    if let comment = latestComment, comment.createdAt > review.createdAt { return nil }
    let name = displayLogin(review.author)
    return MentionAttribution(reason: "\(name) \(verb)", avatarLogin: name)
}

// Comments must be in chronological (oldest-first) order. For a mention, prefer
// the latest comment that still @-mentions the viewer; the triggering mention
// is often gone (bots edit their comments, or it lived in the PR body), so fall
// back to the most recent commenter as a best-effort actor. nil only when there
// are no comments or the reason is not actor-worthy.
public func mentioner(in comments: [CommentSummary], rawReason: String, viewerLogin: String?) -> String? {
    switch rawReason {
    case "mention":
        if let viewer = viewerLogin,
           let mentioned = comments.last(where: { bodyMentions($0.body, login: viewer) }) {
            return mentioned.author
        }
        return comments.last?.author
    case "team_mention", "comment":
        return comments.last?.author
    default:
        return nil
    }
}

// True when body contains "@login" as a whole handle, not as a prefix of a
// longer one ("@octocat" must not match "@octocat-bot").
public func bodyMentions(_ body: String, login: String) -> Bool {
    let haystack = body.lowercased()
    let needle = "@\(login.lowercased())"
    var searchStart = haystack.startIndex
    while let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
        let precededByLoginChar = range.lowerBound > haystack.startIndex
            && isLoginCharacter(haystack[haystack.index(before: range.lowerBound)])
        let followedByLoginChar = range.upperBound < haystack.endIndex
            && isLoginCharacter(haystack[range.upperBound])
        if !precededByLoginChar && !followedByLoginChar {
            return true
        }
        searchStart = range.upperBound
    }
    return false
}

private func isLoginCharacter(_ character: Character) -> Bool {
    character.isASCII && (character.isLetter || character.isNumber || character == "-")
}
