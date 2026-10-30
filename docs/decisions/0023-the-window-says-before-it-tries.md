# 0023: What the setup window says before it tries, and what it calls attention

Date: 2026-10-16. Status: decided.

## The problem

An independent review of the setup app read it as a person doing a first setup, and found what was wrong in the first minutes, which no earlier review had looked at:
the likeliest first failure (the app run from the disk image) showed nothing in the window; the header buttons were live before the first look had ended and skipped the choice the
first run asks for; a setup that failed was drawn as the same chooser and a footnote; the first-run card's third step was a button that could only fail; a setup that went well ended in
"some checks need your attention" for a command link that is not on PATH, which only a person who types `rh` needs; nothing the window did was said to VoiceOver; the model of the
window had no test at all, because it is in the app target.

## Decision

- **The window says where it runs from before anything is tried** (`InstallError.problem(runningFrom:)`, one function for the runner and the window): from a disk image, another
  volume or the temporary copy macOS makes of a download, a card at the top says to move the app into Applications, and Set Up and Install or Repair wait. `rh` that is not inside an
  app (a build folder, Homebrew's) is not asked about its volume.
- **Only the first run's Set Up makes a config, from the person's choices.** Install or Repair and Open Config never do (`SetupActions.repair`, `openConfig`), and the header does not
  show them until the first look has ended and found a config (`configIsThere`). A config that is a link to a file that is not there counts as a config (`LoadedConfig.hasConfig`): the
  runner leaves it alone, so the window must not offer a first run whose button could only fail.
- **The answer of a setup is shown where the person looks.** A setup that did not come out leaves the chooser, with its report (or, when nothing was tried, its notice) above it, and the
  page scrolls to it; the extension's mark in "What Right Here set up" says it is registered but switched off while it is.
- **A warning the person may leave is not "needs attention".** The command link whose folder is not on PATH, Claude Code's terminal link without its handler (made when Claude Code is
  started once) and a choice of no agents at all stay rows of the Checks page and are not counted in the state, the badge or the banner (`DoctorCheck.isOptional`). `rh doctor` still
  says `warn`: an AI agent reads that, and the person who types `rh` needs it.
- **Step 3 of the first-run card points to the test and does not run it.** The test goes through the extension, which is off while the card is shown; the card goes the moment it is on.
  The test button is on the Checks page and is off while the extension is.
- **The fixes on the Checks page name a button**, not a command, for the four that mention `rh setup`.
- **VoiceOver:** each action's result and the state after a setup are announced; the titles of the sections are headings; a step says whether it is done.
- **The model of the window is tested** (`Sources/AppModel` links `Apps/RightHere/SetupModel.swift` as it is into a package target; `Tests/AppModelTests`): everything it asks of the Mac is
  injected.

## Alternatives

- **A localized refusal in the notice for the disk image** (the old behaviour made it a sentence in English after the person pressed Set Up). The likeliest first failure should not
  need a button press and a sentence in the wrong language to be found.
- **Show optional rows as a third kind of status** (JSON `info`). It would change what an AI agent reads for a row it should still tell the person about; the window's own state is
  what was wrong.
- **Keep the test button in the first-run card, enabled.** Pressed in the order the card shows, it waits 75 seconds and says the extension did not answer.

## Evidence

`FirstRunWindowTests`, `SetupActionsTests`, `SetupSummaryTests`, `InstallerTests`, `ExtensionProbeTests` and `SetupModelTests` (the model, with a made-up Mac: before the first look nothing is
claimed, the buttons that would skip the choice do nothing and say why, a second press starts nothing, the buttons stay off until the state has been read again, the answer of a failed setup is there
for the window to show, the extension is looked at only while the window can be seen); pictures of each state in English, German, Arabic and Thai (`script/preview_setup.sh --location`,
`--failed-set-up`, `--onboarding`, `--tab checks`).
