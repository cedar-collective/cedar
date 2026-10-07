# CEDAR — Claude Code instructions

The complete development reference is maintained in a single canonical file and
imported here:

@AGENTS.md

Follow it — architecture layers, data tables, coding standards (no silent
fallbacks), module patterns, and test infrastructure all live there. Do not add
project documentation to this file; update `AGENTS.md` so every tool sees it.

`ISSUES.md` holds known problems and improvements in CEDAR as it exists:
**defects** (`I` numbers; wrong output or breakage, with evidence and a
reproduction) and **improvements** (`M` numbers; debt, inconsistency, missing
tests, interface standards). Read it before trusting a surprising number, and
add a defect the moment you discover one — with the evidence and a
reproduction, so it never has to be diagnosed twice. `ROADMAP.md` holds new
features and significant upgrades, and links to issues rather than repeating
them.
