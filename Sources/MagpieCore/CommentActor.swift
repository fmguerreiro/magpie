// Pure logic for naming a notification's actor when GitHub omits
// latest_comment_url (e.g. a thread bumped by a non-comment event). Kept free
// of any process/network dependency so it can be unit tested.

import Foundation

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
    public let mentionsViewer: Bool

    public init(author: String, createdAt: Date, mentionsViewer: Bool = false) {
        self.author = author
        self.createdAt = createdAt
        self.mentionsViewer = mentionsViewer
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

// The newest comment as the thread's latest event, or nil to keep the state
// caption. Only a recent comment by someone other than the viewer counts;
// "mentioned you" only when the comment actually @-mentions the viewer.
public func commentEventAttribution(viewerLogin: String?, comment: DatedComment?,
                                    threadUpdatedAt: Date?) -> MentionAttribution? {
    guard let viewerLogin, let comment, let threadUpdatedAt,
          comment.author != viewerLogin,
          abs(threadUpdatedAt.timeIntervalSince(comment.createdAt)) <= commentTriggerWindow else { return nil }
    let name = displayLogin(comment.author)
    let verb = comment.mentionsViewer ? "mentioned you" : "commented"
    return MentionAttribution(reason: "\(name) \(verb)", avatarLogin: name)
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

// The author and time of the more recent of a thread's latest comment and review.
public func mostRecentActor(comment: DatedComment?, review: DatedReview?) -> (author: String, at: Date)? {
    let commentActor = comment.map { (author: $0.author, at: $0.createdAt) }
    let reviewActor = review.map { (author: $0.author, at: $0.createdAt) }
    switch (commentActor, reviewActor) {
    case let (commentActor?, reviewActor?): return commentActor.at >= reviewActor.at ? commentActor : reviewActor
    case let (commentActor?, nil): return commentActor
    case let (nil, reviewActor?): return reviewActor
    case (nil, nil): return nil
    }
}

// Suppression marks the thread read on GitHub, so it uses a tighter window than
// the caption: only the viewer's action essentially at the thread's last change
// counts as having caused it. We cannot see non-comment bumps (CI, labels,
// assignments), so a wider window would risk clearing a real notification that a
// later non-comment event raised after the viewer's own comment.
public let selfActivityWindow: TimeInterval = 120

// True when the thread's most recent action is the viewer's own, so they have
// already seen it and need no notification: they merged their own PR, or their
// comment/review is the latest action right at the thread's last change. Someone
// else's action, even if older than the viewer's latest comment, keeps the
// thread (they may not have seen it).
public func isOwnLatestActivity(viewerLogin: String?, latestComment: DatedComment?,
                                latestReview: DatedReview?, threadUpdatedAt: Date?,
                                mergedByViewer: Bool) -> Bool {
    guard let viewerLogin else { return false }
    if mergedByViewer { return true }
    guard let threadUpdatedAt, let actor = mostRecentActor(comment: latestComment, review: latestReview),
          actor.author == viewerLogin,
          abs(threadUpdatedAt.timeIntervalSince(actor.at)) <= selfActivityWindow else { return false }
    return true
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
