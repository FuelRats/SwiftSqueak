# IRC end-to-end harness

`irc_e2e.py` drives a **running** MechaSqueak over IRC: it connects as a
throwaway client, joins a channel, sends commands, and asserts on the bot's
replies. It uses [jaraco's `irc`](https://pypi.org/project/irc/) library for the
protocol — it does not reimplement IRC.

This is the client half of the dev rig used for the groupsync / group-management
command work. The other halves:

- **Dev bot** — the dockerised SwiftSqueak dev instance:
  `docker compose -f docker-compose.dev.yml -f docker-compose.dev.override.yml up`
  (the override runs it as nick `MechaGSTest` in `#test`, pointed at a local API
  on `:8080`, with `GENERAL_DEBUG=true`). Kill any previous container first so
  two instances don't fight over the nick.
- **Local API** — `api.fuelrats.com`: `docker compose up` (serves `:8080` plus
  the `anope-tunnel` SSH forward to the dev Anope DB).
- **Dev IRC network** — `irc.fuelrats.dev:6697` (TLS, self-signed cert).

## Setup

```sh
python3 -m venv tools/.venv
tools/.venv/bin/pip install -r tools/requirements.txt
```

## Usage

```sh
# one command, assert the reply
tools/.venv/bin/python tools/irc_e2e.py --bot MechaGSTest "!landmark Sol" --expect "(?i)ly from"

# send and just print the bot's replies for 8s (no assertion)
tools/.venv/bin/python tools/irc_e2e.py --bot MechaGSTest "!version" --timeout 8

# multi-step scenario
tools/.venv/bin/python tools/irc_e2e.py --scenario tools/scenarios/groupsync.json
```

Exit status is `0` only if every expectation matched, so it slots into CI or a
shell `&&` chain.

### Options

Connection defaults target the dev network and can also be set via environment
variables (`IRC_E2E_SERVER`, `IRC_E2E_PORT`, `IRC_E2E_NICK`, `IRC_E2E_CHANNEL`,
`IRC_E2E_BOT`, `IRC_E2E_PASSWORD`):

| Flag | Default | Meaning |
|------|---------|---------|
| `--server` / `--port` | `irc.fuelrats.dev` / `6697` | dev IRCd |
| `--nick` | `E2ETester` | this client's nick (auto-suffixes `_` if taken) |
| `--channel` | `#test` | channel to join and send in |
| `--bot` | `MechaGSTest` | the nick whose replies are asserted on |
| `--password` | — | NickServ IDENTIFY password (prefer `IRC_E2E_PASSWORD`) |
| `--expect` | — | regex the reply must match; repeatable (all must match) |
| `--timeout` | `10` | per-step seconds to wait for the reply |
| `--no-tls` | off | plaintext connection |
| `--verify-tls` | off | enforce cert validation (dev cert is self-signed, so off by default) |
| `--no-join` | off | skip waiting for the JOIN confirmation |

Replies are matched against the bot's channel messages, notices, and PMs
(MechaSqueak replies to some commands via `CNOTICE`). mIRC colour/formatting
codes are stripped before matching.

### Scenario files

JSON with a `steps` list. Each step supports:

| Key | Meaning |
|-----|---------|
| `send` | line to send; `{bot}` is replaced with the bot's nick (for name-triggers) |
| `expect` | regexes the reply must all match |
| `expect_absent` | regexes the reply must NOT match (e.g. a leaked secret) |
| `silent` | pass only if the bot says nothing (gate / cooldown / non-trigger tests) |
| `pm` | send as a private message to the bot instead of to the channel |
| `timeout` | seconds to wait for the reply |
| `delay_before` | seconds to wait before sending (clear the 30s AI cooldown) |

See `scenarios/groupsync.json` and `scenarios/ai.json`.

## Testing the AI assistant

`scenarios/ai.json` exercises every facet of the always-listening AI assistant:
name-trigger vs silence, the prefilter and relevance gate, SOP vs ED-Knowledge
grounding, cite-or-refuse, data tools, `run_command`, channel scrollback,
prompt-injection resistance, locale, the 30s cooldown, and the PM surface. Two
steps are marked `(MANUAL)` — tone, and multi-turn memory (which needs an
identified NickServ account). Because the cooldown is 30s per (channel+user),
real triggers carry `delay_before: 33`, so a full run takes ~7-8 minutes and
makes ~15 paid Anthropic calls.

Bring the rig up (needs `.env.ai` with `AI_ANTHROPIC_TOKEN` + `AI_OUTLINE_TOKEN`):

```sh
cp .env.ai.example .env.ai   # fill the two tokens
docker compose -f docker-compose.dev.yml -f docker-compose.dev.ai.override.yml up --build -d
tools/.venv/bin/python tools/irc_e2e.py --scenario tools/scenarios/ai.json --bot MechaAITest
```
