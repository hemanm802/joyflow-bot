# Project layout

Joyflow stores knowledge on disk. The files *are* the product. Swift code is an index and an editor.

This layout follows [Eve](https://eve.dev/docs) conventions so a Project is recognizable as an agent directory, then adds the pieces Eve does not require: a SOUL, living knowledge, Commons, and first-class resources.

## Application Support

```
~/Library/Application Support/Joyflow/
  Commons/
    SOUL.md
    instructions.md
    knowledge/
    resources/links.json
    resources/folders.json
    resources/documents/
    index.json
  Projects/<uuid>/
    project.json
    SOUL.md
    instructions.md
    knowledge/memories.md
    knowledge/<slug>.md
    resources/links.json
    resources/folders.json
    resources/documents/
    skills/
    workspace/
    threads/<thread-id>.jsonl
    commons.json
```

## Eve → Joyflow

| Eve slot | Joyflow path | Notes |
| --- | --- | --- |
| `agent/instructions.md` | `instructions.md` | Standing project instructions |
| `agent/skills/` | `skills/` | Markdown procedures |
| `agent/sandbox/workspace` | `workspace/` | Local computer jail; cloud seed |
| `agent/tools/` | (in the app) | Swift tools, not TypeScript |
| — | `SOUL.md` | Personality, voice, boundaries |
| — | `knowledge/` | AI-maintained notes + memories |
| — | `resources/` | Links, documents, folders |
| — | `Commons/` | Shared library any project can link |

Joyflow does not import the `eve` npm package. A Project folder can still be read, edited, and copied without the app.
