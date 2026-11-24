# Commands: one per call

Applies always, and is mandatory in unattended runs.

Run **one command per shell call**: no `&&`, `;`, `|`, `&`, `$(...)`, here-documents or redirection to a
file. A compound command passes permission checks only if every part is allowed, and in an unattended
run nobody is there to approve the rest.

- Write files with the editor tools (Write/Edit), not with shell redirection.
- Change directory by passing a path or a directory flag to the tool
  (for example `npm --prefix <dir> run test`), not with `cd <dir> && ...`.
- Before committing, run the project's formatter on the files you touched. A pre-commit hook may
  reject files that are not formatted.
