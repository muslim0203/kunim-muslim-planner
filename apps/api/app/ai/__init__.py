"""The LLM half of KUNIM (`docs/plan.md` section 5).

Three invariants shape every file in here, and they are the reason the
package is laid out the way it is rather than as one `llm.py`:

* **The model is never a source for religion.** Nothing below may quote the
  Qur'an, a hadith or a ruling; `safety.religious_guard` enforces it on the
  way out, not just in the prompt.
* **The model never writes the user's data.** An agent produces a *proposal*
  (`app.modules.ai.models.AiProposal`); the phone shows it, the user accepts
  it, and the ordinary offline write path creates the row. The server has no
  code path from a model's answer to a user's table.
* **The feature is optional.** Without a key the whole package reports itself
  unavailable and the endpoints say so; the app falls back to the rule-based
  analysis in `features/insights`, which needs no network at all.
"""
