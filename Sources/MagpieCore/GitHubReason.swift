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

// Names the person behind a notification's latest comment ("octocat mentioned
// you") and points the avatar at them. When that commenter is the viewer, we
// cannot honestly name the mentioner: GitHub's notifications API exposes only
// the latest comment, not the comment that triggered the mention, so a
// viewer-authored latest comment would otherwise read as "you mentioned you".
// In that case fall back to the generic reason and keep the existing avatar.
public func attributeActor(rawReason: String, commentLogin: String, viewerLogin: String?) -> MentionAttribution {
    if commentLogin == viewerLogin {
        return MentionAttribution(reason: friendlyGitHubReason(rawReason), avatarLogin: nil)
    }
    switch rawReason {
    case "mention": return MentionAttribution(reason: "\(commentLogin) mentioned you", avatarLogin: commentLogin)
    case "team_mention": return MentionAttribution(reason: "\(commentLogin) mentioned your team", avatarLogin: commentLogin)
    case "comment": return MentionAttribution(reason: "\(commentLogin) commented", avatarLogin: commentLogin)
    default: return MentionAttribution(reason: friendlyGitHubReason(rawReason), avatarLogin: nil)
    }
}
