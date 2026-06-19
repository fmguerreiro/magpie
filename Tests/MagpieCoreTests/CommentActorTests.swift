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

@Test func doesNotTreatALongerHandleAsAnExactMention() {
    #expect(bodyMentions("hey @octocat, look", login: "octocat"))
    #expect(bodyMentions("@octocat", login: "octocat"))
    #expect(!bodyMentions("@octocat-bot shipped", login: "octocat"))
    #expect(!bodyMentions("email user@octocat here", login: "octocat"))
    #expect(!bodyMentions("nope@octocat2", login: "octocat"))
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

@Test func suppressesAThreadTheViewerMerged() {
    #expect(isOwnLatestActivity(viewerLogin: "me", latestComment: nil, latestReview: nil,
                                threadUpdatedAt: threadUpdated, mergedByViewer: true) == true)
}

@Test func suppressesAThreadWhoseLatestActionIsTheViewersComment() {
    let mine = DatedComment(author: "me", createdAt: threadUpdated.addingTimeInterval(-10))
    #expect(isOwnLatestActivity(viewerLogin: "me", latestComment: mine, latestReview: nil,
                                threadUpdatedAt: threadUpdated, mergedByViewer: false) == true)
}

@Test func suppressesAThreadWhoseLatestActionIsTheViewersReview() {
    let myReview = DatedReview(author: "me", state: "APPROVED", createdAt: threadUpdated.addingTimeInterval(-10))
    let older = DatedComment(author: "ryukez", createdAt: threadUpdated.addingTimeInterval(-200))
    #expect(isOwnLatestActivity(viewerLogin: "me", latestComment: older, latestReview: myReview,
                                threadUpdatedAt: threadUpdated, mergedByViewer: false) == true)
}

// Someone else's action, even if older than the viewer's latest comment, keeps
// the thread: they replied after a mention the viewer hasn't acted on.
@Test func keepsAThreadWhoseLatestActionIsSomeoneElse() {
    let theirs = DatedComment(author: "ryukez", createdAt: threadUpdated.addingTimeInterval(-10))
    let mine = DatedComment(author: "me", createdAt: threadUpdated.addingTimeInterval(-200))
    #expect(isOwnLatestActivity(viewerLogin: "me", latestComment: newer(theirs, mine), latestReview: nil,
                                threadUpdatedAt: threadUpdated, mergedByViewer: false) == false)
}

// The viewer's comment from long ago was not what bumped the thread (a CI run or
// someone else's non-comment action was), so keep it visible.
@Test func keepsAThreadWhenTheViewersCommentIsOutsideTheWindow() {
    let mine = DatedComment(author: "me", createdAt: threadUpdated.addingTimeInterval(-3600))
    #expect(isOwnLatestActivity(viewerLogin: "me", latestComment: mine, latestReview: nil,
                                threadUpdatedAt: threadUpdated, mergedByViewer: false) == false)
}

@Test func keepsAThreadWithNoActorActivityAndNoSelfMerge() {
    #expect(isOwnLatestActivity(viewerLogin: "me", latestComment: nil, latestReview: nil,
                                threadUpdatedAt: threadUpdated, mergedByViewer: false) == false)
}

// A bump well after the viewer's comment was a non-comment event (CI, label) we
// cannot see, so suppression's tight window keeps the thread rather than clear it.
@Test func keepsAThreadBumpedWellAfterTheViewersComment() {
    let mine = DatedComment(author: "me", createdAt: threadUpdated.addingTimeInterval(-180))
    #expect(isOwnLatestActivity(viewerLogin: "me", latestComment: mine, latestReview: nil,
                                threadUpdatedAt: threadUpdated, mergedByViewer: false) == false)
}

// Without a known viewer we cannot claim an action is theirs, even a merge.
@Test func neverSuppressesWhenTheViewerIsUnknown() {
    #expect(isOwnLatestActivity(viewerLogin: nil, latestComment: nil, latestReview: nil,
                                threadUpdatedAt: threadUpdated, mergedByViewer: true) == false)
}

@Test func breaksATieBetweenCommentAndReviewTowardTheComment() {
    let comment = DatedComment(author: "alice", createdAt: threadUpdated)
    let review = DatedReview(author: "bob", state: "APPROVED", createdAt: threadUpdated)
    #expect(mostRecentActor(comment: comment, review: review)?.author == "alice")
}

@Test func picksTheMoreRecentOfACommentAndReview() {
    let comment = DatedComment(author: "alice", createdAt: threadUpdated.addingTimeInterval(-10))
    let review = DatedReview(author: "bob", state: "APPROVED", createdAt: threadUpdated.addingTimeInterval(-100))
    #expect(mostRecentActor(comment: comment, review: review)?.author == "alice")
    #expect(mostRecentActor(comment: nil, review: review)?.author == "bob")
    #expect(mostRecentActor(comment: nil, review: nil) == nil)
}

// commentEventAttribution tests

@Test func attributesARecentMentioningCommentAsMentionedYou() {
    let comment = DatedComment(author: "octocat", createdAt: threadUpdated.addingTimeInterval(-30),
                               mentionsViewer: true)
    #expect(commentEventAttribution(viewerLogin: "fmguerreiro", comment: comment,
                                    threadUpdatedAt: threadUpdated)
            == MentionAttribution(reason: "octocat mentioned you", avatarLogin: "octocat"))
}

@Test func attributesARecentNonMentioningCommentAsCommented() {
    let comment = DatedComment(author: "octocat", createdAt: threadUpdated.addingTimeInterval(-30),
                               mentionsViewer: false)
    #expect(commentEventAttribution(viewerLogin: "fmguerreiro", comment: comment,
                                    threadUpdatedAt: threadUpdated)
            == MentionAttribution(reason: "octocat commented", avatarLogin: "octocat"))
}

@Test func stripsTheBotSuffixFromACommentingBot() {
    let comment = DatedComment(author: "cubic-dev-ai[bot]", createdAt: threadUpdated.addingTimeInterval(-10),
                               mentionsViewer: true)
    #expect(commentEventAttribution(viewerLogin: "fmguerreiro", comment: comment,
                                    threadUpdatedAt: threadUpdated)
            == MentionAttribution(reason: "cubic-dev-ai mentioned you", avatarLogin: "cubic-dev-ai"))
}

@Test func returnsNilWhenTheCommentIsAuthoredByTheViewer() {
    let comment = DatedComment(author: "fmguerreiro", createdAt: threadUpdated.addingTimeInterval(-10),
                               mentionsViewer: true)
    #expect(commentEventAttribution(viewerLogin: "fmguerreiro", comment: comment,
                                    threadUpdatedAt: threadUpdated) == nil)
}

@Test func returnsNilWhenTheCommentIsOutsideTheTriggerWindow() {
    let comment = DatedComment(author: "octocat", createdAt: threadUpdated.addingTimeInterval(-3600),
                               mentionsViewer: true)
    #expect(commentEventAttribution(viewerLogin: "fmguerreiro", comment: comment,
                                    threadUpdatedAt: threadUpdated) == nil)
}

@Test func returnsNilWhenThereIsNoComment() {
    #expect(commentEventAttribution(viewerLogin: "fmguerreiro", comment: nil,
                                    threadUpdatedAt: threadUpdated) == nil)
}
