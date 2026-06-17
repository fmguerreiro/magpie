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
