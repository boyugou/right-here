## What and why

<!-- What does this change, and what problem does it solve? -->

## Checklist

- [ ] `./script/verify_all.sh` passes (it needs a full Xcode and `uv`; if you cannot run it, say so and a maintainer will)
- [ ] A bug fix comes with a test that fails on the old code
- [ ] User-visible strings are in `Localization/Localizable.xcstrings` in all thirty languages (a correction to one language's wording
      changes only that language), and `script/verify_localizations.py` passes
- [ ] Docs are updated (and `script/compile_docs.py` run if an embedded guide changed)
- [ ] Each commit is signed off (`git commit -s`, see CONTRIBUTING.md)
- [ ] No GPL-licensed code is copied or paraphrased
- [ ] No email addresses, machine-specific paths or credentials are committed
