# Agent roles

- Use GPT-6 Astra with medium reasoning as the primary agent for discussion,
  requirements, planning, coordination, and the final explanation.
- Delegate implementation, code changes, and implementation-related tests to
  GPT-6 Luna with medium reasoning. Do not create a separate user-facing task
  unless the user explicitly asks for one.
- Keep product and scope decisions with the primary agent. The delegated
  coding agent should implement and test its assigned work directly.
- If GPT-6 Luna is unavailable, do not silently substitute another model;
  explain the limitation and ask the user how to proceed.
