import Testing
@testable import MagpieCore

@Test func namesTheCommenterForAMentionByAnotherUser() {
    let attribution = attributeActor(rawReason: "mention", commentLogin: "octocat", viewerLogin: "fmguerreiro")
    #expect(attribution == MentionAttribution(reason: "octocat mentioned you", avatarLogin: "octocat"))
}

@Test func doesNotClaimTheViewerMentionedThemselves() {
    let attribution = attributeActor(rawReason: "mention", commentLogin: "fmguerreiro", viewerLogin: "fmguerreiro")
    #expect(attribution == MentionAttribution(reason: "mentioned you", avatarLogin: nil))
}

@Test func namesTheCommenterWhenViewerIsUnknown() {
    let attribution = attributeActor(rawReason: "mention", commentLogin: "fmguerreiro", viewerLogin: nil)
    #expect(attribution == MentionAttribution(reason: "fmguerreiro mentioned you", avatarLogin: "fmguerreiro"))
}

@Test func attributesPlainCommentsToTheCommenter() {
    let attribution = attributeActor(rawReason: "comment", commentLogin: "octocat", viewerLogin: "fmguerreiro")
    #expect(attribution == MentionAttribution(reason: "octocat commented", avatarLogin: "octocat"))
}

@Test func fallsBackToGenericReasonForSelfAuthoredComment() {
    let attribution = attributeActor(rawReason: "comment", commentLogin: "fmguerreiro", viewerLogin: "fmguerreiro")
    #expect(attribution == MentionAttribution(reason: "new comment", avatarLogin: nil))
}

@Test func attributesTeamMentionToTheCommenter() {
    let attribution = attributeActor(rawReason: "team_mention", commentLogin: "octocat", viewerLogin: "fmguerreiro")
    #expect(attribution == MentionAttribution(reason: "octocat mentioned your team", avatarLogin: "octocat"))
}

@Test func keepsExistingAvatarForReasonsItDoesNotAttribute() {
    let attribution = attributeActor(rawReason: "review_requested", commentLogin: "octocat", viewerLogin: "fmguerreiro")
    #expect(attribution == MentionAttribution(reason: "review requested", avatarLogin: nil))
}

@Test func mapsKnownRawReasonsToFriendlyText() {
    #expect(friendlyGitHubReason("review_requested") == "review requested")
    #expect(friendlyGitHubReason("mention") == "mentioned you")
    #expect(friendlyGitHubReason("security_alert") == "security alert")
    #expect(friendlyGitHubReason("some_unknown_reason") == "some unknown reason")
}

// These reasons say less than the thread's own state: "author"/"subscribed"/
// "manual" recur on every such row, and "state_change" only says something
// changed. The concrete state (closed/merged/...) is the news in each case.
@Test func prefersThreadStateOverAReasonThatSaysLess() {
    #expect(captionBase(rawReason: "author", statusLabel: "closed", reason: "your thread") == "closed")
    #expect(captionBase(rawReason: "subscribed", statusLabel: "approved", reason: "subscribed") == "approved")
    #expect(captionBase(rawReason: "manual", statusLabel: "merged", reason: "subscribed") == "merged")
    #expect(captionBase(rawReason: "state_change", statusLabel: "closed", reason: "state changed") == "closed")
}

// State is fetched during enrichment; until it arrives the friendly reason stands.
@Test func fallsBackToTheReasonWhenNoStateYet() {
    #expect(captionBase(rawReason: "author", statusLabel: nil, reason: "your thread") == "your thread")
}

// An event reason is itself what to surface, so a known state does not displace it.
@Test func keepsAnEventReasonEvenWhenTheStateIsKnown() {
    #expect(captionBase(rawReason: "mention", statusLabel: "open", reason: "octocat mentioned you") == "octocat mentioned you")
}

// Non-GitHub sources have no raw reason, so the reason leads and state is the fallback.
@Test func leadsWithTheReasonWhenThereIsNoRawReason() {
    #expect(captionBase(rawReason: nil, statusLabel: "In Progress", reason: "Yuki commented") == "Yuki commented")
    #expect(captionBase(rawReason: nil, statusLabel: "In Progress", reason: nil) == "In Progress")
}
