# The Room row is the state machine

Every Room's live state (`phase`, `phase_seq`, `phase_deadline_at`, current Game, current Round number, the Meme being voted on) lives on the Room row. Every transition goes through a single `advance!` that runs under that row's lock. Each phase with a deadline (`captioning`, `vote`, `standings`) enqueues one Solid Queue job for its deadline, carrying the `phase_seq` it was scheduled for. If the phase has already moved on, the job finds a different `phase_seq` and does nothing. Early finishes (everyone submitted, every present voter voted) call the same `advance!`. Each Meme's vote is its own phase (scores are held back until the Round's `standings`; a per-Meme `reveal` phase was dropped), and captioning's ~5s upload grace extends that phase's deadline instead of adding a phase. We chose the database row over in-process timers or Redis because a single box with Postgres and Solid Queue already survives restarts, needs no extra infrastructure, and makes racing advances impossible. See `docs/research/realtime-engine.md` (MEME-2).

## Consequences

- A recurring sweep is the crash backstop: it advances any Room whose deadline passed without a transition.
- Jobs and broadcasts are sent after commit, so no job ever sees uncommitted state, and the phase change always reaches phones before the next phase's content.
