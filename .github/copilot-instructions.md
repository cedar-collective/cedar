# CEDAR — Copilot instructions

The canonical development reference for this repository is **`AGENTS.md`** at the
repo root. Read it before making changes — it covers the architecture layers
(lists → trunk → branches → cones → reports → modules), the CEDAR data tables,
coding standards (no silent fallbacks), Shiny module patterns, and the test
infrastructure.

The standing how-to-work rules (layer placement, reuse, no fallbacks, complexity
budget, ships-with-a-test) live in `AGENTS.md`'s Coding Standards. Known unfixed
defects in code or data are in `ISSUES.md` — read it before trusting a surprising
number, and add an entry when you find a new one. Longer-term vision and
potential features are in `ROADMAP.md`.

Do not add project documentation to this file; update `AGENTS.md` so every tool
sees the same instructions.
