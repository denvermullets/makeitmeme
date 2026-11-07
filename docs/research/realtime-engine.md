# Realtime engine: phase timers and Solid Cable fitness (MEME-2)

Scope: a Room holds at most 10 Players, a handful of Rooms run at once, on one server. The server owns the Room state machine (waiting, captioning, voting, round results, ..., Scoreboard) and every phase except waiting and Scoreboard has a deadline.

Repo config checked: `config/cable.yml` (production: `solid_cable`, `polling_interval: 0.1.seconds`, `message_retention: 1.day`, `writer_batch_size: 4`; development uses `async`), `config/queue.yml` (dispatcher `polling_interval: 1`, `batch_size: 500`; worker `polling_interval: 1`, 3 threads).

Sources are marked [SQ] Solid Queue README / source, [SC] Solid Cable README, [AJ] Rails Active Job guide, [TR] turbo-rails README / source. Statements marked "design guidance" are my own recommendations, not claims from a source.

## 1. Firing phase deadlines

### What the sources say
- Active Job `set(wait_until: time).perform_later` is the supported way to run a job at a point in time [AJ].
- Solid Queue holds such jobs as scheduled executions; a Dispatcher moves due ones to ready, and a Worker then runs them. "Jobs ... will go into the scheduled queue and will wait there until they're due" [SQ].
- Defaults: the polling interval is 1 second for dispatchers and 0.1 seconds for workers; dispatcher `batch_size` is 500 [SQ].
- In `Dispatcher#poll`, a batch that dispatched anything returns a 0 wait (poll again at once); an empty batch waits `polling_interval` [SQ source, `lib/solid_queue/dispatcher.rb`].
- Retries are not automatic under Solid Queue; they need an explicit `retry_on`. A job without it goes to failed executions [AJ].
- Jobs discarded through `discard_on` count as completed, not failed [SQ].
- `enqueue_after_transaction_commit` defers enqueueing until the surrounding Active Record transaction commits, and a rolled-back transaction enqueues nothing [AJ].

### Precision
Worst-case latency from deadline to code running is roughly dispatcher interval + worker interval. With the shipped config (1 s + 1 s in `config/queue.yml`) that is up to about 2 s of slop; the stock Solid Queue defaults (1 s + 0.1 s) give about 1.1 s. Design guidance: lowering the dispatcher `polling_interval` to 0.1-0.25 s gives about 0.2-0.35 s. With a handful of Rooms the extra polling queries are negligible. Treat the job as "close the phase at or after the deadline", never "exactly at the deadline"; the client countdown (section 4) hides the slop.

### Idempotency when a phase ends early
The scheduled job cannot be cancelled cheaply, so make it harmless instead (design guidance):
1. Give each Room a `phase_token` (an integer `phase_seq` incremented on every transition) and enqueue `PhaseDeadlineJob.set(wait_until: room.phase_deadline_at).perform_later(room.id, room.phase_seq)`.
2. The job does `room.with_lock { return unless room.phase_seq == seq && room.phase_deadline_at <= Time.current; room.advance! }`. A stale job (everyone submitted early, the phase already advanced) is a no-op.
3. The "everyone submitted" path calls the same `advance!` under the same row lock. Two racing callers cannot both advance, because the second sees a new `phase_seq`.
4. `advance!` bumps `phase_seq`, sets the new deadline, and enqueues the next job. Enqueue after the transaction commits, so the job can never run against uncommitted state (`enqueue_after_transaction_commit` [AJ], or enqueue in `after_commit`).
5. Add `retry_on` for transient DB errors (retries are not automatic [AJ]). A stale job needs no `discard_on`; it just returns.
6. Leftover stale rows are cleared by the built-in hourly finished-job cleanup [SQ]; nothing to add.

Solid Queue's `limits_concurrency ... on_conflict: :discard` is an alternative guard, but the row lock plus token is stricter and independent of queue internals.

### Alternatives considered
| Option | Verdict |
|---|---|
| In-process timer (`Concurrent::ScheduledTask`, `Thread`) | Precise, but lost on restart or deploy (Kamal restarts), and not visible in the DB. Acceptable only as a supplement. |
| Recurring task polling for expired Rooms [SQ recurring tasks] | Good as a safety net: a sweep that advances any Room whose deadline has passed catches jobs lost to a crash. Recurring schedules are time-of-day granularity (cron-like), not sub-second, so keep it as the backstop, not the primary timer. (I did not verify the minimum interval in the source.) |
| Client-driven advance | Not authoritative; a Host leaving would stall the Room. Rejected. |
| Per-phase job (recommended) + sweep backstop | Durable, survives restarts, simple. |

Single-server note: Solid Queue's Puma plugin can run the supervisor with Puma, either forking processes or, alternatively, running workers and dispatchers inside the Puma process, in which case `processes` is ignored [SQ]. For one box either works; jobs and Cable then share the database.

## 2. Is Solid Cable's polling acceptable?

- Solid Cable "keeps messages in a table and continuously polls for updates" [SC].
- `polling_interval` defaults to 0.1 s [SC] and the repo already sets that. So a broadcast reaches subscribers up to about 0.1 s after the write, plus database round trips. The README says performance is "comparable to Redis in most situations" and that a 0.01 s interval makes it comparable to Redis, while the 0.1 s default has higher round-trip time [SC].
- Phase changes and countdown ticks are human-scale events (a phase lasts tens of seconds). 100-200 ms of delivery delay is imperceptible, especially because the client renders the countdown locally from a deadline (section 4). It is acceptable.
- Tuning [SC]:
  - `message_retention`: needs only to outlast the slowest subscriber's poll plus reconnect margin; the README says a few minutes is plenty. The repo's `1.day` is wasteful but harmless; suggest `5.minutes`.
  - `autotrim` is on by default and may cost some performance. At this volume, leave it on.
  - `silence_polling` defaults to true, which keeps logs quiet.
  - `writer_batch_size` (default 4) batches writes; irrelevant at this scale.
  - `polling_interval` could go to 0.05 s for snappier voting reveals; leave 0.1 s until a real need appears.
- Keep payloads small: do not push images through Cable. Send IDs, URLs, and deadlines. Solid Cable also avoids the 8 kB limit of the dedicated PostgreSQL adapter [SC].
- Cable needs its own database (`connects_to: database: writing: cable`) in production [SC]; confirm `config/database.yml` has a `cable` entry before deploy.
- When Redis would be warranted: multiple app servers with high fan-out, sub-50 ms delivery needs (twitch-style input), or thousands of concurrent subscribers causing polling load (each server process polls the table). None applies to a single server with at most a few dozen connections. Note that dev uses the single-process `async` adapter, so broadcasts from a separate job process do not reach browsers in dev unless jobs run inline in the web process [TR].

## 3. Per-Player private state versus Room-wide broadcasts

- `turbo_stream_from` subscribes the page to a stream. Stream names are signed: `signed_stream_name` generates the signed value, and `Turbo::StreamsChannel#subscribed` calls `verified_stream_name_from_params` and rejects the subscription if it fails to verify [TR source: `stream_name.rb`, `streams_channel.rb`]. The name in the HTML therefore cannot be tampered with; but anyone who is served the page can subscribe, so authorization is decided by what you render.
- Design guidance for this game, using two streams per page:
  - Room stream: `turbo_stream_from room` for everything shared (phase, Players, Memes on display, tallies, deadline).
  - Player stream: `turbo_stream_from room, player` (array streamables are joined with colons [TR source]) for the Player's own Hand and private Vote state. Only render this tag in the view for the current Player (identified by the Room-scoped session cookie, since there is no account), so only that Player is ever given the signed name. The signature is unguessable per Player and per Room.
- Broadcast with `Turbo::StreamsChannel.broadcast_replace_to(room, player, target: ..., partial: ...)` for private data and `broadcast_replace_to(room, ...)` for shared data. The `broadcast_*_to` helpers wrap `broadcast_action_to`, which ends in `ActionCable.server.broadcast` [TR source: `broadcasts.rb`].
- Do not put private data in room-wide partials. Do not rely on CSS or JS to hide a Hand (a Player must not see another's Hand).
- `_later` versus sync:
  - `broadcast_*_later_to` enqueues `Turbo::Streams::ActionBroadcastJob` and renders in the job [TR source]. The `_later` forms avoid rendering in the request or inside the phase-deadline job, and they run after commit if called from callbacks.
  - Sync is simpler and gives deterministic ordering, and with at most 10 Players rendering cost is trivial.
  - Recommendation: use sync broadcasts from the `advance!` path after the transaction commits (ordering matters: phase change must arrive before the next phase's content). Use `_later` only for noisy per-submission updates such as the "7 of 10 submitted" counter. A `_later` job competes with phase-deadline jobs in the same queue, so give broadcasts a separate higher-priority queue if used.
  - `broadcast_refresh_later_to` is debounced [TR source], which suits "something changed, re-fetch" but is too indirect for per-Player data; prefer explicit replaces.
- Reconnection: Turbo streams do not replay missed messages. After a reconnect or reload, the page must render full current state from the server (design guidance); broadcasts are only deltas.

## 4. Client countdown pattern and clock skew

Sources for the browser APIs were not fetched (this section is design guidance based on standard behavior of `Date.now()` and `performance.now()`; verify against MDN when implementing).

1. The server sends an absolute `deadline_at` (ISO8601 or epoch ms) with each phase change, and also `server_now` at send time. Render both as data attributes on the phase element, e.g. `data-countdown-deadline-value`, plus `data-countdown-server-now-value`, for a Stimulus controller.
2. On connect, the controller computes `offset = server_now - Date.now()` (it includes one-way latency, up to roughly 100-200 ms of error, which is fine for a seconds-resolution display). Remaining time = `deadline - (Date.now() + offset)`.
3. Tick with `requestAnimationFrame` or a 250 ms interval, recomputing from the deadline each tick; never decrement a counter, since timers drift and throttle in background tabs.
4. Re-sync `offset` on every phase-change broadcast and on page load, so skew corrections are free. Alternatively send only the remaining duration (`ends_in_ms`) and compute a local monotonic deadline with `performance.now()`, which is immune to the user changing their clock.
5. At zero, show "time's up" and wait for the server's phase broadcast; do not advance locally. The server accepts submissions until it processes the deadline (add a grace of about 1 s so a submission at 0:00 is not lost to dispatch latency, since server enforcement lags the display by the job slop).
6. Resync on `visibilitychange` and Turbo stream reconnect by fetching current Room state.

## Recommendation

1. Timers: one `PhaseDeadlineJob.set(wait_until: deadline)` per phase, guarded by `phase_seq` and a row lock in `advance!`; the "all submitted" path calls the same `advance!`. Enqueue and broadcast after commit. Add `retry_on` for transient errors, plus a recurring sweep that advances any Room whose deadline passed without a transition (crash backstop).
2. Tune `config/queue.yml`: dispatcher `polling_interval: 0.25` (or 0.1) and worker `polling_interval: 0.1`, giving roughly 0.35 s worst-case slop. Run Solid Queue in Puma (single server).
3. Keep Solid Cable at `polling_interval: 0.1`; set `message_retention: 5.minutes`; make sure a `cable` database exists. Do not add Redis; revisit only for multiple servers or measured latency problems.
4. Streams: a shared Room stream plus a per-Player signed stream (`turbo_stream_from room, player`) only rendered to that Player for Hand and private state. Sync broadcasts from state transitions; `_later` for high-frequency counters.
5. Client: deadline timestamps plus `server_now` offset in a Stimulus controller; recompute each tick; the server remains authoritative; always re-render full state on reconnect.

Open items (not verified from primary sources): minimum recurring-task granularity in Solid Queue; browser time APIs; Action Cable per-connection identification approach for Players without accounts.
