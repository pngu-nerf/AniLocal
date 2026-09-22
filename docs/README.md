# docs/

Which document to read, by question.

| Question | Read |
|---|---|
| Where does X live, what are the layers, what must I not touch? | [`ARCHITECTURE.md`](ARCHITECTURE.md) — the maintainer front door |
| How does feature X work, and why is it shaped that way? | [`feature-log.md`](feature-log.md) — one paragraph per shipped feature, with the measurements |
| What are the rules for every change? | [`../CLAUDE.md`](../CLAUDE.md) |
| What was built when, and what is next? | [`../ROADMAP.md`](../ROADMAP.md), [`../CHANGELOG.md`](../CHANGELOG.md) |
| Metadata and skip sources: what shipped, what is parked, how to un-park | [`multi-source-plan.md`](multi-source-plan.md) |
| Registering a MyAnimeList client ID (the parked source) | [`myanimelist-registration.md`](myanimelist-registration.md) |
| Changing the player: what to verify by hand | [`player-regression-checklist.md`](player-regression-checklist.md) |
| Runtime behaviour a test cannot settle — unplugging, quitting, offline, scale — to verify by hand | [`runtime-walkthrough.md`](runtime-walkthrough.md) |
| How fast is the read path, what does a scan cost, and what was it before | [`performance.md`](performance.md) |
| Which player behaviours are under test, which are manual-verify, and why | [`player-test-coverage.md`](player-test-coverage.md) |
| Why the player engine is app-lifetime and fullscreen is state | [`player-architecture-research.md`](player-architecture-research.md); the crash oracle it was measured against is archived: [`archive/player-crash-repro.md`](archive/player-crash-repro.md) |
| Why the header is hoisted above the Navigator | [`header-architecture-audit.md`](header-architecture-audit.md) |
| The duplication rules and where they came from | [`tech-debt-audit.md`](tech-debt-audit.md); the older assessment is archived: [`archive/maintainability-assessment.md`](archive/maintainability-assessment.md) |
| Historical documents — read for the why, not as a map | [`archive/`](archive/) |
| The app icon's source | [`brand/app-icon-source.png`](brand/app-icon-source.png) — the artwork as drawn, a full square, never cropped (Windows/Linux derive from it too); `tool/app_icon.py` derives the macOS rounded-square set |
