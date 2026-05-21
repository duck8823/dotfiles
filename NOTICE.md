# Notices and third-party knowledge attributions

## `theoden9014/ai-knowledge-base` — Structure-Behavior Design

The following files include guidance adapted from the `structure-behavior-design` knowledge pack in `theoden9014/ai-knowledge-base`:

- `codex/skills/structure-behavior-design/SKILL.md`
- `codex/skills/structure-behavior-design/agents/openai.yaml`
- `claude/skills/structure-behavior-design/SKILL.md`
- `codex/agents/structure-reviewer.toml`
- `claude/agents/structure-reviewer.md`
- `gemini/agents/structure-reviewer.md`

Source repository: <https://github.com/theoden9014/ai-knowledge-base>  
Source pack: `knowledge/structure-behavior-design`  
Upstream license for knowledge packs: CC BY-SA 4.0  
License URL: <https://creativecommons.org/licenses/by-sa/4.0/>
Local license pointer: `LICENSES/CC-BY-SA-4.0.md`

Changes made in this repository:

- translated and condensed the workflow into Japanese
- merged separate upstream skills/agents into dotfiles-oriented skill and reviewer agents
- aligned the workflow with the dotfiles Claude foreground / Codex worker-verifier / Gemini read-only scout model
- added External AI delegation policy gate considerations
- adjusted high-risk handling to prefer small Draft PRs / design notes / migration-safe steps rather than blocking autonomous progress indefinitely

The files listed above are licensed under CC BY-SA 4.0. Other repository content remains under the repository default license unless otherwise noted.
