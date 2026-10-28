# Agent Guidelines

Instructions for AI coding agents working on this project.

## Adding content

`DESIGN.md` is the master plan; `README.md` describes the repo as it is.
Read `DESIGN.md` before adding or restructuring anything.

Give each new item the shape it actually needs now. If that departs from
`DESIGN.md`, either move the repo toward the plan or revise the plan, and
update its section status. Keep `README.md` matching reality.

Items marked *Open* in `DESIGN.md` are the user's decisions. When an
addition forces one (the marketplace name, for example), ask rather than
choosing, then record the answer in `DESIGN.md`.

## Commits

Commits follow Conventional Commits: `type(scope): summary`. The scope is
the item or area the change touches, such as `feat(pr-autoreview)` or
`build(ci)`.

Start the summary in lowercase and don't end it with a period:
`docs: add commit guidelines`, not `docs: Add commit guidelines.` This is
the commit subject only. PR and issue titles keep their own convention.

### Commit types

Pick the type for the effect on someone using the tooling, not for the
shape of the diff.

| Type       | Use for                                                        |
|------------|----------------------------------------------------------------|
| `feat`     | New or changed capability in a skill, plugin, hook, or other item |
| `fix`      | Corrected behavior                                             |
| `refactor` | Internal restructuring, behavior unchanged                     |
| `perf`     | Faster, behavior unchanged                                     |
| `build`    | Build script, tooling, dependencies, **and CI**                |
| `test`     | Tests and harness                                              |
| `docs`     | Documentation                                                  |
| `chore`    | Maintenance with no user-visible effect, incl. code formatting |

Two conventions here differ from the Angular defaults; both are
deliberate.

**No `style`.** Pure code formatting is `chore`. A visible change to
something the user sees, such as a status line or mod, is `feat` or `fix`.

**`build` covers CI.** Use one type with the area in the scope:
`build(ci)`, `build(dist)`. Don't use a separate `ci` type.

### The breaking-change bar

A `!` marker or `BREAKING CHANGE:` footer says that existing setups need
action after this change. Treat it as that signal, not as emphasis.

The public surface here is whatever other setups depend on by name or
path: marketplace, plugin, and skill names (install ids and slash
commands), hook behavior, and the locations of state and config files.

Reserve the marker for changes that break a working install or invocation
**with no diagnostic**: the user gets silence, wrong behavior, or a
failure that doesn't name the cause.

| Change                                                   | Marker |
|----------------------------------------------------------|--------|
| Plugin, skill, or command removed                        | Yes    |
| Plugin or marketplace renamed without a `renames` entry  | Yes    |
| State or config file moved; old location silently ignored | Yes   |
| Skill or command's meaning changes, same name            | Yes    |
| Plugin renamed with a `renames` entry migrating installs | No     |
| Default changes, with the new value reported             | No     |
| Output or wording changes                                | No     |

A change that **fails loudly and names the migration** is a warned
migration, not a break. Use `feat` and put the migration in the commit
body.
