# AGENTS.md

## Start here

Antes de cualquier cambio en este repositorio, leer en este orden:

1. `promptMaster.md`
2. `.agents/skills/swift-elite-coach/SKILL.md`
3. `backlog.md`
4. `plan.md`
5. `README.md`

## Product invariant

PR es un entrenador experto digital, no un chatbot fitness ni un simple tracker.

## Engineering invariant

```text
Develop → Test → Prove
```

Ninguna historia está DONE sin tests/build/validación aplicables.

## Architectural invariant

```text
LLM interprets/explains
Training Engine decides
Policy Validator protects
Local persistence protects workout data
```

## Before coding

```bash
git status
xcodebuild -list
```

Inspeccionar el repo real antes de asumir paths/schemes.

## Backlog selection

Elegir la primera historia `READY` de mayor prioridad con dependencies `DONE`.

No empezar una feature P2 si hay una dependencia P0 incompleta.

## Never

- invent Apple APIs;
- store secrets in client;
- put business rules in Views;
- rely on LLM for deterministic calculations;
- lose workout data because of network;
- double-count HealthKit energy;
- bypass restrictions;
- diagnose injuries;
- add random exercise variation;
- claim tests ran when they did not.

