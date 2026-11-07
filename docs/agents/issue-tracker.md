# Issue tracker: jait (MCP)

Issues and specs for this repo live in jait, team **make it meme** (`MEME`, `team_id: 49`). Use the `mcp__jait__*` MCP tools for all operations; there is no CLI. If the tools are deferred, load them via ToolSearch first.

## Team reference

- **team_id**: `49`. Identifier prefix: `MEME` (e.g. `MEME-12`).
- **Lanes**: Backlog `218` (default on create) · In Progress `219` · Done `220` · Cancelled `221`.
- **Labels**: needs-triage `313` · needs-info `314` · ready-for-agent `315` · ready-for-human `316` · wontfix `317`. For any others, look up IDs with `list_labels(team_id: 49)`. Tools take label **IDs**, not names. Map triage roles to label names via `docs/agents/triage-labels.md`.

## Projects are epics

A jait **project** is an epic (as in Jira): one feature or body of work. **Every issue belongs to a project**; always pass `project_id` when creating an issue.

- **List projects**: `list_projects(team_id: 49)`; details via `get_project(team_id: 49, project_id)`.
- **Create a project (epic)**: `create_project(team_id: 49, name, description)`. The description holds the epic's summary/spec.
- When a skill breaks a spec or plan into tickets (e.g. `/to-tickets`), create a project for that feature/epic if one doesn't already exist, then create the tickets as issues inside it.
- **Update project status**: `update_project(team_id: 49, project_id, status: backlog|started|paused|completed|cancelled)`.

## Conventions

- **Create an issue**: `create_issue(team_id: 49, project_id, title, description, label_ids?, lane_id?, parent_issue_id?)`.
- **Read an issue**: `get_issue_by_identifier("MEME-<n>")` (or `get_issue(team_id: 49, issue_id)`); comments via `list_comments`.
- **List issues**: `list_issues(team_id: 49, project_id?, lane_id?, assignee_id?, priority?)`.
- **Sub-issue**: pass `parent_issue_id` on create (same project as the parent).
- **Comment on an issue**: `create_comment`.
- **Apply / remove labels**: `update_issue(team_id: 49, issue_id, label_ids: [...])` **replaces** the full label set, so read the issue's current labels first and send the merged list.
- **Close**: comment with the reason, then move to Done (`lane_id: 220`); for wontfix move to Cancelled (`221`).

## When a skill says "publish to the issue tracker"

Create a jait issue in team 49, inside the relevant project (creating the project first if the work is a new feature/epic).

## When a skill says "fetch the relevant ticket"

Read it as in **Read an issue** above.

## Wayfinding operations

Used by `/wayfinder`. The **map** is its own **project**; its **child tickets** are issues in that project. Feature/epic work that falls out of the map goes into **separate follow-up projects**, one per feature/epic.

- **Map**: a project (e.g. `Wayfinder: <topic>`) created with `create_project`, its description holding the Notes / Decisions-so-far / Fog body. Update it with `update_project(description: ...)`.
- **Child ticket**: an issue created with `project_id: <map project>`, labelled `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`). Create missing `wayfinder:*` labels with `create_label(team_id: 49, name)` on first use. Once claimed, the ticket is assigned to the driving dev.
- **Blocking**: `create_issue_dependency(team_id: 49, issue_id: <child>, target_issue_id: <blocker>, direction: "blocked_by")`; read with `list_issue_dependencies`. A ticket is unblocked when every blocker is in Done or Cancelled.
- **Frontier query**: `list_issues(team_id: 49, project_id: <map>)`, keep those not in Done/Cancelled, drop any with an open blocker or an assignee; first in map order wins.
- **Claim**: `update_issue(team_id: 49, issue_id, assignee_id: <me>)` (find your user ID via `list_members`), the session's first write.
- **Resolve**: `create_comment` with the answer, move the issue to Done (`220`), then append a context pointer (gist + `MEME-<n>`) to the map project's Decisions-so-far.
- **Follow-up epics**: when the map settles a feature/epic to build, create a new project for it (description links back to the map project) and put its tickets there, not in the map project.
