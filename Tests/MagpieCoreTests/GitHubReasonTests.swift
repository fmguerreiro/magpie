import Testing
@testable import MagpieCore

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

// An actionable event reason is itself what to surface, so a known state does not
// displace it ("review requested" tells you to act; "open" alone would not).
@Test func keepsAnActionableEventReasonEvenWhenTheStateIsKnown() {
    #expect(captionBase(rawReason: "review_requested", statusLabel: "open", reason: "review requested") == "review requested")
}

// GitHub keeps "mention"/"comment" on a thread long after the comment that set
// them, so the sticky friendly label loses to a known state rather than claiming
// a fresh "mentioned you" on an unrelated bump.
@Test func prefersThreadStateOverAStaleMentionOrCommentReason() {
    #expect(captionBase(rawReason: "mention", statusLabel: "open", reason: "mentioned you") == "open")
    #expect(captionBase(rawReason: "team_mention", statusLabel: "closed", reason: "team mentioned") == "closed")
    #expect(captionBase(rawReason: "comment", statusLabel: "merged", reason: "new comment") == "merged")
}

// A genuinely fresh mention still wins: enrichment resolves it into an eventCaption
// naming the actor, which outranks both the sticky reason and the state.
@Test func surfacesAFreshMentionThroughTheEventCaption() {
    #expect(captionBase(eventCaption: "octocat mentioned you", rawReason: "mention",
                        statusLabel: "open", reason: "mentioned you") == "octocat mentioned you")
}

// Non-GitHub sources have no raw reason, so the reason leads and state is the fallback.
@Test func leadsWithTheReasonWhenThereIsNoRawReason() {
    #expect(captionBase(rawReason: nil, statusLabel: "In Progress", reason: "Yuki commented") == "Yuki commented")
    #expect(captionBase(rawReason: nil, statusLabel: "In Progress", reason: nil) == "In Progress")
}

// The resolved latest event is what pinged you, so it leads the caption even for a
// reason that would otherwise lose to the state (an authored PR a reviewer touched).
@Test func leadsWithTheResolvedEventOverStateAndReason() {
    #expect(captionBase(eventCaption: "DrH97 reviewed", rawReason: "author",
                        statusLabel: "open", reason: "your thread") == "DrH97 reviewed")
    #expect(captionBase(eventCaption: "Sjlver approved", rawReason: "subscribed",
                        statusLabel: "merged", reason: "subscribed") == "Sjlver approved")
}
