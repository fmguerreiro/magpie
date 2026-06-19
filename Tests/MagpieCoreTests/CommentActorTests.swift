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

@Test func buildsReviewCommentsEndpointForAPullRequestURL() {
    let url = URL(string: "https://github.com/octo/repo/pull/115")!
    #expect(reviewCommentsEndpoint(forWebURL: url) == "repos/octo/repo/pulls/115/comments")
}

@Test func hasNoReviewCommentsEndpointForAnIssue() {
    #expect(reviewCommentsEndpoint(forWebURL: URL(string: "https://github.com/octo/repo/issues/7")!) == nil)
}

@Test func dropsTheBotSuffixFromADisplayLogin() {
    #expect(displayLogin("cubic-dev-ai[bot]") == "cubic-dev-ai")
    #expect(displayLogin("octocat") == "octocat")
}

private let threadUpdated = Date(timeIntervalSince1970: 1_000_000)

@Test func namesARecentCommenterOnAnAuthoredThread() {
    let comment = DatedComment(author: "cubic-dev-ai[bot]", createdAt: threadUpdated.addingTimeInterval(-21))
    #expect(recentCommenterAttribution(rawReason: "author", viewerLogin: "fmguerreiro",
                                       latest: comment, threadUpdatedAt: threadUpdated)
            == MentionAttribution(reason: "cubic-dev-ai commented", avatarLogin: "cubic-dev-ai"))
}

@Test func picksTheMoreRecentOfTwoComments() {
    let older = DatedComment(author: "alice", createdAt: threadUpdated.addingTimeInterval(-100))
    let newest = DatedComment(author: "bob", createdAt: threadUpdated.addingTimeInterval(-10))
    #expect(newer(older, newest) == newest)
    #expect(newer(newest, older) == newest)
    #expect(newer(older, nil) == older)
    #expect(newer(nil, newest) == newest)
    #expect(newer(nil, nil) == nil)
    let tieFirst = DatedComment(author: "alice", createdAt: threadUpdated)
    let tieSecond = DatedComment(author: "bob", createdAt: threadUpdated)
    #expect(newer(tieFirst, tieSecond) == tieFirst)
}

@Test func picksTheLatestCommentRegardlessOfBatchOrder() {
    let comments = [
        DatedComment(author: "alice", createdAt: threadUpdated.addingTimeInterval(-300)),
        DatedComment(author: "bob", createdAt: threadUpdated.addingTimeInterval(-10)),
        DatedComment(author: "carol", createdAt: threadUpdated.addingTimeInterval(-120)),
    ]
    #expect(newestComment(in: comments) == comments[1])
}

@Test func returnsNilForAnEmptyCommentBatch() {
    #expect(newestComment(in: []) == nil)
}

@Test func doesNotSurfaceTheViewersOwnComment() {
    let comment = DatedComment(author: "fmguerreiro", createdAt: threadUpdated.addingTimeInterval(-21))
    #expect(recentCommenterAttribution(rawReason: "author", viewerLogin: "fmguerreiro",
                                       latest: comment, threadUpdatedAt: threadUpdated) == nil)
}

// A comment far from the thread's last change was not the trigger (a CI run or
// push bumped the thread); keep the state caption rather than blame the comment.
@Test func ignoresACommentFarFromTheThreadsLastChange() {
    let comment = DatedComment(author: "octocat", createdAt: threadUpdated.addingTimeInterval(-3600))
    #expect(recentCommenterAttribution(rawReason: "author", viewerLogin: "fmguerreiro",
                                       latest: comment, threadUpdatedAt: threadUpdated) == nil)
}

@Test func leavesEventReasonsToTheirOwnActorNaming() {
    let comment = DatedComment(author: "octocat", createdAt: threadUpdated.addingTimeInterval(-21))
    #expect(recentCommenterAttribution(rawReason: "mention", viewerLogin: "fmguerreiro",
                                       latest: comment, threadUpdatedAt: threadUpdated) == nil)
}

@Test func surfacesNothingWhenThereIsNoComment() {
    #expect(recentCommenterAttribution(rawReason: "author", viewerLogin: "fmguerreiro",
                                       latest: nil, threadUpdatedAt: threadUpdated) == nil)
}

@Test func surfacesAReviewAsTheLatestEvent() {
    let approval = DatedReview(author: "ryukez", state: "APPROVED", createdAt: threadUpdated.addingTimeInterval(-30))
    #expect(reviewEventAttribution(viewerLogin: "fmguerreiro", latestComment: nil,
                                   latestReview: approval, threadUpdatedAt: threadUpdated)
            == MentionAttribution(reason: "ryukez approved", avatarLogin: "ryukez"))
}

@Test func mapsEachSurfacedReviewState() {
    func caption(_ state: String) -> String? {
        let review = DatedReview(author: "ryukez", state: state, createdAt: threadUpdated)
        return reviewEventAttribution(viewerLogin: "me", latestComment: nil,
                                      latestReview: review, threadUpdatedAt: threadUpdated)?.reason
    }
    #expect(caption("APPROVED") == "ryukez approved")
    #expect(caption("CHANGES_REQUESTED") == "ryukez requested changes")
    #expect(caption("COMMENTED") == "ryukez reviewed")
    #expect(caption("DISMISSED") == nil)
    #expect(caption("PENDING") == nil)
}

// A comment newer than the review is the actual latest event, so the review yields.
@Test func defersToACommentNewerThanTheReview() {
    let review = DatedReview(author: "ryukez", state: "APPROVED", createdAt: threadUpdated.addingTimeInterval(-120))
    let comment = DatedComment(author: "octocat", createdAt: threadUpdated.addingTimeInterval(-10))
    #expect(reviewEventAttribution(viewerLogin: "me", latestComment: comment,
                                   latestReview: review, threadUpdatedAt: threadUpdated) == nil)
}

// On a tie the review is the more specific action, so it wins over the comment.
@Test func keepsTheReviewWhenACommentTiesItsTimestamp() {
    let review = DatedReview(author: "ryukez", state: "APPROVED", createdAt: threadUpdated)
    let comment = DatedComment(author: "octocat", createdAt: threadUpdated)
    #expect(reviewEventAttribution(viewerLogin: "me", latestComment: comment,
                                   latestReview: review, threadUpdatedAt: threadUpdated)
            == MentionAttribution(reason: "ryukez approved", avatarLogin: "ryukez"))
}

@Test func doesNotSurfaceTheViewersOwnReview() {
    let review = DatedReview(author: "me", state: "APPROVED", createdAt: threadUpdated.addingTimeInterval(-30))
    #expect(reviewEventAttribution(viewerLogin: "me", latestComment: nil,
                                   latestReview: review, threadUpdatedAt: threadUpdated) == nil)
}

@Test func ignoresAReviewFarFromTheThreadsLastChange() {
    let review = DatedReview(author: "ryukez", state: "APPROVED", createdAt: threadUpdated.addingTimeInterval(-3600))
    #expect(reviewEventAttribution(viewerLogin: "me", latestComment: nil,
                                   latestReview: review, threadUpdatedAt: threadUpdated) == nil)
}

@Test func stripsABotSuffixFromAReviewerName() {
    let review = DatedReview(author: "cubic-dev-ai[bot]", state: "APPROVED", createdAt: threadUpdated)
    #expect(reviewEventAttribution(viewerLogin: "me", latestComment: nil,
                                   latestReview: review, threadUpdatedAt: threadUpdated)
            == MentionAttribution(reason: "cubic-dev-ai approved", avatarLogin: "cubic-dev-ai"))
}

@Test func buildsTheReviewsEndpointForAPullRequest() {
    #expect(reviewsEndpoint(forWebURL: URL(string: "https://github.com/octo/repo/pull/42")!) == "repos/octo/repo/pulls/42/reviews")
    #expect(reviewsEndpoint(forWebURL: URL(string: "https://github.com/octo/repo/issues/42")!) == nil)
}
