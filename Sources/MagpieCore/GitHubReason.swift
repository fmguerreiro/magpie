// Pure presentation logic for GitHub notification captions. Kept free of any
// process/network dependency so it can be unit tested.

import Foundation

public func friendlyGitHubReason(_ raw: String) -> String {
    switch raw {
    case "review_requested": return "review requested"
    case "mention": return "mentioned you"
    case "team_mention": return "team mentioned"
    case "assign": return "assigned to you"
    case "author": return "your thread"
    case "comment": return "new comment"
    case "state_change": return "state changed"
    case "subscribed", "manual": return "subscribed"
    case "ci_activity": return "CI activity"
    case "security_alert": return "security alert"
    default: return raw.replacingOccurrences(of: "_", with: " ")
    }
}

// GitHub reasons that say less than the thread's own state. "author",
// "subscribed", and "manual" are standing relationships that recur on every such
// row; "state_change" only says something changed. "mention"/"team_mention"/
// "comment" are sticky: GitHub keeps them on the thread long after the comment
// that set them, so pairing the friendly "mentioned you" with the thread's
// "5h ago" reads as "mentioned you just now" on an unrelated bump. A genuinely
// fresh mention or comment still surfaces, because enrichment resolves it into an
// eventCaption ("octocat mentioned you") that outranks the state; only the stale
// label loses to it. For all of these the concrete state (open/closed/merged) is
// the safer news, so the caption prefers it when known.
public let reasonsSupersededByState: Set<String> = [
    "author", "subscribed", "manual", "state_change", "mention", "team_mention", "comment",
]

// The leading text of a notification's caption, before the "5h ago" suffix.
//
// A concrete latest event ("Sjlver approved", "DrH97 reviewed") is what actually
// pinged you, so it always wins: enrichment resolves it from the thread's newest
// review/comment and it must not be masked by the thread's standing state.
// Without one, an actionable event reason (review requested) is itself the news
// and wins; reasons vaguer or staler than the thread state lose to a known state,
// with the friendly reason as the fallback before enrichment has fetched that state.
// rawReason is nil for non-GitHub sources, keeping the plain "reason, else state"
// precedence.
public func captionBase(eventCaption: String? = nil, rawReason: String?,
                        statusLabel: String?, reason: String?) -> String? {
    if let eventCaption { return eventCaption }
    if let rawReason, reasonsSupersededByState.contains(rawReason) {
        return statusLabel ?? reason
    }
    return reason ?? statusLabel
}

public struct MentionAttribution: Equatable {
    public let reason: String
    // Login whose avatar should be shown, or nil to keep the existing avatar
    // (the PR/issue author's).
    public let avatarLogin: String?

    public init(reason: String, avatarLogin: String?) {
        self.reason = reason
        self.avatarLogin = avatarLogin
    }
}
