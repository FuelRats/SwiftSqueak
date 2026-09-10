#!/usr/bin/env python3
"""End-to-end IRC harness for driving a running MechaSqueak instance.

Connects to an IRC network as a throwaway client, joins a channel, sends one or
more commands, and asserts on the bot's replies (in-channel messages, notices,
and private messages from the bot's nick). Intended for the groupsync / command
dev rig: a dockerised dev bot (see docker-compose.dev.yml) joined to #test on
the dev network, talking to a local api.fuelrats.com.

Uses jaraco's `irc` library (https://pypi.org/project/irc/) for the protocol;
this script only adds the connect -> send -> await-reply -> assert loop.

Examples:
    # one command, assert the reply mentions a landmark distance
    ./irc_e2e.py --bot MechaGSTest "!landmark Sol" --expect "(?i)ly from"

    # just send and print whatever the bot says for 8s (no assertion)
    ./irc_e2e.py --bot MechaGSTest "!version" --timeout 8

    # a multi-step scenario from JSON
    ./irc_e2e.py --scenario scenarios/groupsync.json

Connection defaults target the dev network (irc.fuelrats.dev:6697, self-signed
TLS tolerated). Override via flags or the IRC_E2E_* environment variables.
Exit status is 0 only if every expectation was met.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import ssl
import sys
import time
from dataclasses import dataclass, field

try:
    import irc.client
    from irc.connection import Factory
except ImportError:
    sys.exit(
        "The 'irc' library is required: pip install -r tools/requirements.txt "
        "(or: pip install irc)"
    )

# IRC formatting control codes (bold, colour, italic, underline, reset, reverse).
_FORMATTING = re.compile(r"\x03(?:\d{1,2}(?:,\d{1,2})?)?|[\x00-\x08\x0b-\x1f]")


def strip_formatting(text: str) -> str:
    """Remove mIRC colour/formatting codes so expectations match on plain text."""
    return _FORMATTING.sub("", text)


@dataclass
class Step:
    send: str
    expect: list[str] = field(default_factory=list)
    expect_absent: list[str] = field(default_factory=list)
    silent: bool = False  # pass only if the bot says nothing at all
    timeout: float = 10.0
    delay_before: float = 0.0  # wait before sending (e.g. to clear the 30s AI cooldown)
    pm: bool = False  # send as a private message to the bot instead of to the channel


@dataclass
class StepResult:
    step: Step
    replies: list[str]
    unmatched: list[str]  # expect patterns that never appeared
    present_absent: list[str]  # expect_absent patterns that wrongly appeared
    spoke_when_silent: bool

    @property
    def passed(self) -> bool:
        return not self.unmatched and not self.present_absent and not self.spoke_when_silent


class Harness(irc.client.SimpleIRCClient):
    def __init__(self, channel: str, bot: str, password: str | None):
        super().__init__()
        self.channel = channel
        self.bot_nick = bot  # original case, for the {bot} name-trigger substitution
        self.bot = bot.lower()
        self.password = password
        self.welcomed = False
        self.joined = False
        # (source_nick, plain_text) for every message/notice we observe.
        self.inbox: list[tuple[str, str]] = []

    # -- irc event handlers -------------------------------------------------
    def on_welcome(self, connection, event):
        self.welcomed = True
        if self.password:
            connection.privmsg("NickServ", f"IDENTIFY {self.password}")
        connection.join(self.channel)

    def on_join(self, connection, event):
        if event.source.nick == connection.get_nickname():
            self.joined = True

    def on_nicknameinuse(self, connection, event):
        connection.nick(connection.get_nickname() + "_")

    def _record(self, connection, event):
        source = event.source.nick if event.source else ""
        text = strip_formatting(event.arguments[0]) if event.arguments else ""
        self.inbox.append((source, text))

    on_pubmsg = _record
    on_privmsg = _record
    on_pubnotice = _record
    on_privnotice = _record

    # -- driving ------------------------------------------------------------
    def pump_until(self, predicate, timeout: float) -> bool:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            self.reactor.process_once(0.2)
            if predicate():
                return True
        return predicate()

    def bot_lines_since(self, index: int) -> list[str]:
        return [text for nick, text in self.inbox[index:] if nick.lower() == self.bot]

    def run_step(self, step: Step) -> StepResult:
        if step.delay_before > 0:
            # Keep the connection pumped while we wait out (e.g.) the AI cooldown.
            self.pump_until(lambda: False, step.delay_before)

        start = len(self.inbox)
        text = step.send.replace("{bot}", self.bot_nick)
        self.connection.privmsg(self.bot if step.pm else self.channel, text)
        patterns = [re.compile(p) for p in step.expect]
        absent = [re.compile(p) for p in step.expect_absent]

        def satisfied() -> bool:
            # A silent step or one with absence checks must wait the full window to be sure
            # nothing (bad) arrives; a pure positive-expect step can early-exit once matched.
            if step.silent or absent or not patterns:
                return False
            lines = self.bot_lines_since(start)
            return all(any(p.search(line) for line in lines) for p in patterns)

        self.pump_until(satisfied, step.timeout)
        lines = self.bot_lines_since(start)
        unmatched = [p.pattern for p in patterns if not any(p.search(line) for line in lines)]
        present_absent = [p.pattern for p in absent if any(p.search(line) for line in lines)]
        spoke_when_silent = step.silent and bool(lines)
        return StepResult(
            step=step, replies=lines, unmatched=unmatched,
            present_absent=present_absent, spoke_when_silent=spoke_when_silent)


def load_steps(args) -> list[Step]:
    if args.scenario:
        with open(args.scenario, encoding="utf-8") as handle:
            data = json.load(handle)
        return [
            Step(
                send=entry["send"],
                expect=entry.get("expect", []),
                expect_absent=entry.get("expect_absent", []),
                silent=bool(entry.get("silent", False)),
                timeout=float(entry.get("timeout", args.timeout)),
                delay_before=float(entry.get("delay_before", 0.0)),
                pm=bool(entry.get("pm", False)),
            )
            for entry in data["steps"]
        ]
    if not args.command:
        sys.exit("provide a COMMAND to send, or --scenario FILE")
    return [Step(
        send=args.command, expect=args.expect, expect_absent=args.expect_absent,
        silent=args.silent, timeout=args.timeout)]


def build_factory(use_tls: bool, insecure: bool) -> Factory:
    if not use_tls:
        return Factory()
    context = ssl.create_default_context()
    if insecure:
        # The dev IRCd uses a self-signed cert (IRC_ALLOW_SELF_SIGNED_CERT).
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
    return Factory(wrapper=context.wrap_socket)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", nargs="?", help="the command/line to send, e.g. '!landmark Sol'")
    parser.add_argument("--expect", action="append", default=[],
                        help="regex the bot's reply must match (repeatable; all must match)")
    parser.add_argument("--expect-absent", action="append", default=[], dest="expect_absent",
                        help="regex the bot's reply must NOT match (repeatable)")
    parser.add_argument("--silent", action="store_true",
                        help="pass only if the bot says nothing within the timeout")
    parser.add_argument("--scenario", help="JSON file with a 'steps' list instead of a single command")
    parser.add_argument("--server", default=os.environ.get("IRC_E2E_SERVER", "irc.fuelrats.dev"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("IRC_E2E_PORT", "6697")))
    parser.add_argument("--nick", default=os.environ.get("IRC_E2E_NICK", "E2ETester"))
    parser.add_argument("--channel", default=os.environ.get("IRC_E2E_CHANNEL", "#test"))
    parser.add_argument("--bot", default=os.environ.get("IRC_E2E_BOT", "MechaGSTest"),
                        help="the bot nick whose replies are asserted on")
    parser.add_argument("--password", default=os.environ.get("IRC_E2E_PASSWORD"),
                        help="NickServ IDENTIFY password (or set IRC_E2E_PASSWORD)")
    parser.add_argument("--timeout", type=float, default=10.0, help="per-step reply timeout (seconds)")
    parser.add_argument("--connect-timeout", type=float, default=20.0)
    parser.add_argument("--no-tls", action="store_true", help="plaintext connection")
    parser.add_argument("--verify-tls", action="store_true", help="enforce TLS cert validation (default: off for dev)")
    parser.add_argument("--no-join", action="store_true", help="don't wait for the channel JOIN to confirm")
    args = parser.parse_args()

    steps = load_steps(args)
    client = Harness(channel=args.channel, bot=args.bot, password=args.password)
    factory = build_factory(use_tls=not args.no_tls, insecure=not args.verify_tls)

    print(f"[e2e] connecting to {args.server}:{args.port} as {args.nick} "
          f"(channel {args.channel}, bot {args.bot})")
    try:
        client.connect(args.server, args.port, args.nick, username=args.nick,
                       ircname=args.nick, connect_factory=factory)
    except irc.client.ServerConnectionError as error:
        print(f"[e2e] connection failed: {error}", file=sys.stderr)
        return 2

    if not client.pump_until(lambda: client.welcomed, args.connect_timeout):
        print("[e2e] never received welcome (001) from the server", file=sys.stderr)
        return 2
    if not args.no_join and not client.pump_until(lambda: client.joined, args.connect_timeout):
        print(f"[e2e] never confirmed JOIN to {args.channel}", file=sys.stderr)
        return 2

    results = [client.run_step(step) for step in steps]

    try:
        client.connection.quit("e2e done")
        client.reactor.process_once(0.5)
    except irc.client.ServerNotConnectedError:
        pass

    all_passed = True
    for index, result in enumerate(results, 1):
        status = "PASS" if result.passed else "FAIL"
        all_passed = all_passed and result.passed
        print(f"\n[e2e] step {index}: {status}  send={result.step.send!r}")
        for line in result.replies:
            print(f"        <{args.bot}> {line}")
        if not result.replies:
            print("        (no reply from the bot)")
        if result.spoke_when_silent:
            print("        VIOLATION: expected silence but the bot replied")
        for pattern in result.unmatched:
            print(f"        UNMATCHED expect: {pattern}")
        for pattern in result.present_absent:
            print(f"        FORBIDDEN match present: {pattern}")

    print(f"\n[e2e] {'ALL STEPS PASSED' if all_passed else 'FAILURES PRESENT'}")
    return 0 if all_passed else 1


if __name__ == "__main__":
    sys.exit(main())
