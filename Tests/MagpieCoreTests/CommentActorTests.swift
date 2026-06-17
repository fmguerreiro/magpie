import Foundation
import Testing
@testable import MagpieCore

@Test func buildsIssueCommentsEndpointForAPullRequestURL() {
    let url = URL(string: "https://github.com/SakanaAIBusiness/komb-enterprise/pull/115")!
    #expect(issueCommentsEndpoint(forWebURL: url) == "repos/SakanaAIBusiness/komb-enterprise/issues/115/comments")
}

@Test func buildsIssueCommentsEndpointForAnIssueURL() {
    let url = URL(string: "https://github.com/octo/repo/issues/7")!
    #expect(issueCommentsEndpoint(forWebURL: url) == "repos/octo/repo/issues/7/comments")
}

@Test func rejectsNonPullOrIssueURLs() {
    #expect(issueCommentsEndpoint(forWebURL: URL(string: "https://github.com/octo/repo/commit/abc123")!) == nil)
    #expect(issueCommentsEndpoint(forWebURL: URL(string: "https://github.com/octo/repo")!) == nil)
    #expect(issueCommentsEndpoint(forWebURL: URL(string: "https://github.com/octo/repo/pull/notanumber")!) == nil)
}

@Test func picksTheMostRecentCommentMentioningTheViewer() {
    let comments = [
        CommentSummary(author: "alice", body: "kicking off"),
        CommentSummary(author: "claude[bot]", body: "Claude finished @fmguerreiro's task"),
        CommentSummary(author: "bob", body: "unrelated follow-up"),
    ]
    #expect(mentioner(in: comments, rawReason: "mention", viewerLogin: "fmguerreiro") == "claude[bot]")
}

@Test func prefersTheLatestMentionWhenSeveralMentionTheViewer() {
    let comments = [
        CommentSummary(author: "alice", body: "@fmguerreiro ping"),
        CommentSummary(author: "carol", body: "@fmguerreiro again"),
    ]
    #expect(mentioner(in: comments, rawReason: "mention", viewerLogin: "fmguerreiro") == "carol")
}

@Test func fallsBackToLatestCommenterWhenNoCommentStillMentionsTheViewer() {
    let comments = [
        CommentSummary(author: "alice", body: "no mention here"),
        CommentSummary(author: "claude[bot]", body: "### Reviewing PR (mention edited out)"),
    ]
    #expect(mentioner(in: comments, rawReason: "mention", viewerLogin: "fmguerreiro") == "claude[bot]")
}

@Test func prefersAnExactMentionOverALaterNonMentioningComment() {
    let comments = [
        CommentSummary(author: "claude[bot]", body: "@fmguerreiro your task is done"),
        CommentSummary(author: "bob", body: "thanks"),
    ]
    #expect(mentioner(in: comments, rawReason: "mention", viewerLogin: "fmguerreiro") == "claude[bot]")
}

@Test func doesNotTreatALongerHandleAsAnExactMention() {
    #expect(bodyMentions("hey @octocat, look", login: "octocat"))
    #expect(bodyMentions("@octocat", login: "octocat"))
    #expect(!bodyMentions("@octocat-bot shipped", login: "octocat"))
    #expect(!bodyMentions("email user@octocat here", login: "octocat"))
    #expect(!bodyMentions("nope@octocat2", login: "octocat"))
}

@Test func fallsBackToLatestCommenterWhenTheViewerIsUnknown() {
    let comments = [CommentSummary(author: "alice", body: "@someone else")]
    #expect(mentioner(in: comments, rawReason: "mention", viewerLogin: nil) == "alice")
}

@Test func usesLatestCommenterForAPlainCommentReason() {
    let comments = [
        CommentSummary(author: "alice", body: "first"),
        CommentSummary(author: "bob", body: "second"),
    ]
    #expect(mentioner(in: comments, rawReason: "comment", viewerLogin: "fmguerreiro") == "bob")
}

@Test func returnsNilForReasonsThatAreNotActorWorthy() {
    let comments = [CommentSummary(author: "alice", body: "x")]
    #expect(mentioner(in: comments, rawReason: "state_change", viewerLogin: "fmguerreiro") == nil)
}
