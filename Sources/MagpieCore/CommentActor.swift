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
    let parts = url.pathComponents.filter { $0 != "/" }
    guard parts.count >= 4, parts[2] == "pull" || parts[2] == "issues",
          Int(parts[3]) != nil else { return nil }
    return "repos/\(parts[0])/\(parts[1])/issues/\(parts[3])/comments"
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
