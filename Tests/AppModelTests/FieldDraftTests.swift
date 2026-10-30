import Testing
@testable import AppModel

@Suite("FieldDraft: what a field does with the config that changes under it")
struct FieldDraftTests {
    @Test func aFieldThatWasNotTypedInTakesWhatTheConfigSaysNow() {
        var field = FieldDraft()
        field.appear(saved: "one")
        #expect(field.draft == "one" && field.baseline == "one")
        field.configChanged(to: "two")
        #expect(field.draft == "two" && field.baseline == "two", "an Undo, or something else that changed the setting")
        #expect(field.beginCommit() == nil, "leaving it changes nothing")
    }

    @Test func aFieldThatWasTypedInKeepsWhatWasTypedWhateverTheConfigSaysMeanwhile() {
        var field = FieldDraft()
        field.appear(saved: "one")
        field.draft = "mine"
        field.configChanged(to: "other")
        #expect(field.draft == "mine" && field.baseline == "one", "the text based on the old one stays, and says which text that was")
        #expect(field.beginCommit()?.typed == "mine")
    }

    @Test func aChangeThatWasHeldAndThenMadeAndUndoneLeavesTheFieldShowingTheFileAndAsksNothingMore() {
        // The person types a flag; the change is held for their yes (the commit says no); they say yes (the config says the flag); they press Undo (the config says nothing).
        var field = FieldDraft()
        field.appear(saved: "")
        field.draft = "--yolo"
        let held = field.beginCommit()
        #expect(held?.typed == "--yolo" && held?.shown == "")
        field.endCommit(typed: "--yolo", done: false, now: "")
        #expect(field.draft == "--yolo" && field.baseline == "" && !field.committing, "what was typed stays for the person")
        field.configChanged(to: "--yolo")
        #expect(field.baseline == "--yolo", "the config says what was typed: the field follows the file again")
        #expect(field.beginCommit() == nil, "nothing is left to make")
        field.configChanged(to: "")
        #expect(field.draft == "" && field.baseline == "", "the Undo is shown")
        #expect(field.beginCommit() == nil, "and leaving the field asks the question that was answered no more")
    }

    @Test func aChangeThatIsBeingMadeIsMadeOnceAndTypingThatWentOnStays() {
        var field = FieldDraft()
        field.appear(saved: "a")
        field.draft = "ab"
        let first = field.beginCommit()
        #expect(first?.typed == "ab" && field.beginCommit() == nil, "a second Return, or a Return and then a Tab, is the same change")
        field.draft = "abc"
        field.endCommit(typed: "ab", done: true, now: "ab")
        #expect(field.draft == "abc" && field.baseline == "ab" && !field.committing)
        field.draft = "ab"
        field.endCommit(typed: "ab", done: true, now: "AB")
        #expect(field.draft == "AB" && field.baseline == "AB", "the field shows what the config says now")
    }

    @Test func givingUpShowsWhatTheConfigSaysNowAndAChangeIsMadeFromThat() {
        var field = FieldDraft()
        field.appear(saved: "one")
        field.draft = "typed"
        field.giveUp(now: "one")
        #expect(field.draft == "one" && field.beginCommit() == nil)
        // Something else changed the setting while the field was typed in: the field kept what was typed (`configChanged`), and Escape shows the file, not the text the field started from
        // (it showed "one", which the file no longer said, and the next change was built on it).
        field.draft = "typed again"
        field.configChanged(to: "two")
        #expect(field.draft == "typed again" && field.baseline == "one")
        field.giveUp(now: "two")
        #expect(field.draft == "two" && field.baseline == "two" && field.beginCommit() == nil, "nothing is left to write over the other change")
        field.draft = "two and more"
        #expect(field.beginCommit()?.shown == "two", "a change is made from what the file says")
    }

    @Test func aFieldWhoseChangeIsHeldTakesTheConfigsTextWhenTheQuestionIsAnsweredAndNoOtherFieldDoes() {
        // The field at the end of a list of arguments: what it shows is always "", so the config never says what was typed there.
        var add = FieldDraft()
        add.appear(saved: "")
        add.draft = "--yolo"
        #expect(add.beginCommit()?.typed == "--yolo")
        add.endCommit(typed: "--yolo", done: false, held: true, now: "")
        #expect(add.held && add.draft == "--yolo", "what was typed stays while the question is up")
        add.answered(now: "")
        #expect(add.draft == "" && add.baseline == "" && !add.held && add.beginCommit() == nil, "the yes was made: leaving the field does not add the argument a second time")
        // A field whose change was refused is not the one the question was about: its text stays for the person to put right.
        var refused = FieldDraft()
        refused.appear(saved: "")
        refused.draft = "--dir C:\\x"
        _ = refused.beginCommit()
        refused.endCommit(typed: "--dir C:\\x", done: false, held: false, now: "")
        refused.answered(now: "")
        #expect(refused.draft == "--dir C:\\x" && !refused.held, "an answer to another field's question does not take its text")
        // A field that was typed in and not left is no one's question either.
        var typing = FieldDraft()
        typing.appear(saved: "claude")
        typing.draft = "claude --model opus"
        typing.answered(now: "claude")
        #expect(typing.draft == "claude --model opus")
    }

    @Test func aNoShowsTheFileToTheFieldThatAskedAndAFieldThatFollowsTheFileDropsTheWait() {
        var field = FieldDraft()
        field.appear(saved: "claude")
        field.draft = "claude --dangerously-skip-permissions"
        _ = field.beginCommit()
        field.endCommit(typed: "claude --dangerously-skip-permissions", done: false, held: true, now: "claude")
        field.answered(now: "claude")
        #expect(field.draft == "claude" && field.baseline == "claude", "a no: the field shows the file")
        // The wait ends too when the config says what was typed (the change was made some other way).
        field.draft = "claude --x"
        _ = field.beginCommit()
        field.endCommit(typed: "claude --x", done: false, held: true, now: "claude")
        field.configChanged(to: "claude --x")
        #expect(!field.held && field.draft == "claude --x" && field.baseline == "claude --x")
        field.answered(now: "elsewhere")
        #expect(field.draft == "claude --x", "nothing was waiting any more")
    }

    @Test func aChangeThatWasMadeIsNotWaitingAndANewChangeEndsTheOldWait() {
        var field = FieldDraft()
        field.appear(saved: "a")
        field.draft = "ab"
        _ = field.beginCommit()
        field.endCommit(typed: "ab", done: true, held: true, now: "ab")
        #expect(!field.held, "a change that was made has nothing to wait for")
        // A held change, and the person types on and asks again before answering: the wait is the new change's.
        field.draft = "abc"
        _ = field.beginCommit()
        field.endCommit(typed: "abc", done: false, held: true, now: "ab")
        #expect(field.held)
        field.draft = "abcd"
        _ = field.beginCommit()
        #expect(!field.held, "while the new change is written, the answer to the old question is not waited for")
    }

    @Test func theAnswerMakesTheFieldBuiltOnTheFileAsItIsNowWhateverItSaidWhenTheQuestionWasAsked() {
        var field = FieldDraft()
        field.appear(saved: "claude")
        field.draft = "claude --dangerously-skip-permissions"
        _ = field.beginCommit()
        field.endCommit(typed: "claude --dangerously-skip-permissions", done: false, held: true, now: "claude")
        // Something else changed the setting while the question was up; the field keeps what was typed (`configChanged`), and the answer is a no.
        field.configChanged(to: "claude-beta")
        field.answered(now: "claude-beta")
        #expect(field.draft == "claude-beta" && field.baseline == "claude-beta" && field.beginCommit() == nil, "nothing is left to write over the other change")
    }
}
