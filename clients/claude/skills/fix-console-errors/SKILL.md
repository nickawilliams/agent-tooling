---
name: fix-console-errors
description: Systematically assess, fix, and commit browser console errors one at a time. Use when the user wants to work through console errors/warnings.
disable-model-invocation: true
user-invocable: true
argument-hint: ""
---

Systematically assess, fix, and commit browser console errors using the workflow below.

## 1. Initial Error Assessment

Ask the user to open the browser console and share the current errors. From the list, create a todo list with each error as a separate item. Include a proposed commit message for each.

### Todo Item Structure

Each todo item should contain:
- Error description and location
- Proposed commit message
- Mark exactly one item as `in_progress` at a time

### Commit Message Format

Use [conventional commits](https://www.conventionalcommits.org/en/v1.0.0/) format.

Some latitude with the commit message contents is allowed on a case-by-case basis as long as it aligns with conventional commits and clearly describes the fix. In these cases, prompt the user for confirmation first.

For simple self-explanatory fixes, use a single line. For more complex fixes, use the multi-line format.

#### Single Line

```
fix(<logging_level>): <error_message>
```

#### Multi Line

```
fix(<logging_level>): <error_message>

<optional body>
```

#### Values

- **`<logging_level>`** — the logging level from the console, in lowercase
- **`<error_message>`** — a literal copy of the error message from the console; start with a lowercase character (exceptions for acronyms, case-sensitive types, or other words that would appear strange lowercased); do not end with a period
- **`<truncated_error_message>`** — enough of the original error to be identifiable in the console
- **`<optional body>`** — for complex fixes, include a description of the fix

#### Exceptions

**PropType change:**
```
fix(error): changed PropType `{prop_name}` from `{original_type}` to `{new_type}`
```

**Excessively long error messages:**
```
fix(<logging_level>): <truncated_error_message>
```

## 2. Process Each Error

For each error/todo item:

1. Ask the user to reload the page and wait for confirmation before proceeding
2. Confirm the error is still present in the console (skip if resolved by a previous commit)
3. Apply the fix
4. Ask the user to reload the page and wait for confirmation before proceeding
5. Verify the error is gone in the console (repeat steps 3-4 if it persists)
6. Commit changes using the proposed message
7. Mark the todo as completed and move to the next `in_progress` item

## 3. Key Rules

- One error = one commit
- Console verification before and after each fix prevents wasted effort on stale errors
- User confirmation at reload steps prevents accidental commits
