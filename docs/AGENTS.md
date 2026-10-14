# docs: lightspark-client API notes

`api-notes.md` records how the two APIs behave as observed: request shapes, error bodies, the
sandbox quirks seen in live runs, and which fields the client decodes.

Rules:

- Mark each claim as documented or observed, with the date of the observation.
- Keep account ids, customer names and any personal data out of this file.
- When a live run changes what the client does, update the note in the same commit.
