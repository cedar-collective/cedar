# CEDAR — Claude Code instructions

The complete development reference is maintained in a single canonical file and
imported here:

@AGENTS.md

Follow it: architecture layers, data tables, coding standards (no silent
fallbacks), module patterns and test infrastructure. Do not add project
documentation to this file. `AGENTS.md` holds rules only and is loaded into
every session, so keep it short: reasoning, measurements and history go on the
`docs/developers/` page it links, and a PR's details go in git.

`ISSUES.md` holds known problems and improvements in CEDAR as it exists:
**defects** (`I` numbers; wrong output or breakage, with evidence and a
reproduction) and **improvements** (`M` numbers; debt, inconsistency, missing
tests, interface standards). Read it before trusting a surprising number, and
add a defect the moment you discover one — with the evidence and a
reproduction, so it never has to be diagnosed twice. `ROADMAP.md` holds
strategy, new functionality and enhancements, one line per item, with an Inbox
for untriaged ideas; it links to issues rather than repeating them.
