# Contributing to NCM Online

Thanks for looking. NCM is developed by one person on a live server, so the most useful contributions are often the
smallest: a clear bug report, a correction to the docs, a test for something that broke.

## Ways to help

- **Report a bug:** from inside the game (F6 → HELP → report a problem), or with the
  [bug template](https://github.com/evengineer1ng/ncm-online/issues/new/choose). Steps to reproduce and log lines
  matter more than anything else.
- **Fix the docs:** the website lives in `site/content/` as Markdown. A pull request that makes a page match what the
  game actually does is always welcome.
- **Suggest an idea:** use the feature template. Every idea raised is recorded in `docs/ncm-online/BACKLOG.md`, but
  not every idea gets built.
- **Code:** open an issue first for anything larger than a fix, so we can agree it fits before you spend time on it.

## Before you send a pull request

1. Read [Architecture](https://evengineer1ng.github.io/ncm-online/developers/architecture.html) and
   [Extending NCM](https://evengineer1ng.github.io/ncm-online/developers/extending.html).
2. **Edit `ncm/core/`, never the vendored `shared/core/` copies** inside resources. Run `tools/ncm-build.ps1`
   afterwards.
3. Run the gate. It must end `ALL GREEN`:
   `powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\ncm-test.ps1`
4. If you changed the website: `python site/build.py --check`.
5. Match the surrounding code. Server Lua has no `os`. Core must run under Lua 5.4 and LuaJIT. Redscript natives carry
   no `module` line.
6. New native capabilities go in a **new** native mod, never inside Carrier or Rig Bridge.
7. No chat commands as gameplay and no modal UI layers. Features are reached through play and docked panels.

## Never commit

Credentials, licence keys, `server.jsonc`, `*.env`, `*.pem`, database dumps, save files, logs with other players'
details, or screenshots showing other players' names. `.gitignore` covers the common cases. Check `git status`
before you commit anyway.

## Licence

By contributing you agree that your contribution is licensed under the repository's [MIT License](LICENSE). Only
contribute work you have the right to license that way. Third-party code needs its licence recorded in
`THIRD_PARTY_NOTICES.md`.
