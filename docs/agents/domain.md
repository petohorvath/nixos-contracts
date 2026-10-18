# Domain docs

This repository uses a single-context layout.

## Before exploring the codebase

- Read the root `GLOSSARY.md` for domain terminology.
- Read relevant decisions under `docs/adr/`.

Missing domain documents are skipped silently. The `domain-modeling` skill creates them when terms or decisions are resolved.

## File structure

```text
/
├── GLOSSARY.md
└── docs/
    └── adr/
        └── 0001-<decision>.md
```

## Vocabulary

Issue titles, proposals, hypotheses, and test names use terms defined in `GLOSSARY.md`. New concepts are checked against existing terminology; unresolved gaps are recorded for `domain-modeling`.

## ADR conflicts

Proposals that contradict an existing ADR identify the conflict and explain why the decision merits reconsideration.

> Contradicts ADR-0001 (<decision>); proposed reconsideration: <reason>.
