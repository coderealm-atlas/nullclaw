# Email Channel

This page documents the current Email channel implementation in nullclaw.
It focuses on configuration format, runtime behavior, and practical limits.

## Page Guide

**Who this page is for**

- Operators configuring Email as a delivery channel
- Contributors verifying Email behavior against current implementation
- Integrators deciding whether Email is suitable for inbound, outbound, or both

**Read this next**

- Open [Configuration](./configuration.md) for global config context
- Open [Usage and Operations](./usage.md) for runtime and diagnostics commands
- Open [Commands](./commands.md) for channel-related command reference

**If you came from ...**

- [Configuration](./configuration.md): this page gives Email-specific details missing from the high-level config overview
- [Usage and Operations](./usage.md): come here when Email behavior differs from other channels
- source code review: this page maps the implementation in `src/channels/email.zig` to operational expectations

## Summary

The Email channel is currently implemented as an outbound-capable channel with helper logic for inbound parsing/allowlist checks.
In daemon/channel orchestration, Email is treated as `send_only`.

Practical meaning:

1. `start()` does not establish a persistent IMAP listener.
2. `send()` attempts direct SMTP delivery.
3. Inbound allowlist and parsing helpers exist, but full inbound service behavior is not the primary runtime path.

## Config Format

Email accounts use the standard multi-account channel layout under `channels.email.accounts`.

Example:

```json
{
  "channels": {
    "email": {
      "accounts": {
        "default": {
          "imap_host": "imap.gmail.com",
          "imap_port": 993,
          "imap_folder": "INBOX",
          "smtp_host": "smtp.gmail.com",
          "smtp_port": 587,
          "smtp_tls": true,
          "username": "bot@example.com",
          "password": "app-password",
          "from_address": "bot@example.com",
          "poll_interval_secs": 60,
          "allow_from": ["alice@example.com", "@example.com"],
          "consent_granted": true
        }
      }
    }
  }
}
```

## Field Reference

Schema source: `src/config_types.zig` (`EmailConfig`).

- `account_id`: logical account id (usually derived from account key such as `default`)
- `imap_host`: IMAP host
- `imap_port`: IMAP port (default `993`)
- `imap_folder`: IMAP folder (default `INBOX`)
- `smtp_host`: SMTP host
- `smtp_port`: SMTP port (default `587`)
- `smtp_tls`: TLS preference flag in config (see limitations below)
- `username`: configured username
- `password`: configured password
- `from_address`: sender address used in `MAIL FROM` and `From:`
- `poll_interval_secs`: polling interval hint (default `60`)
- `allow_from`: sender allowlist for inbound checks
- `consent_granted`: must be `true` to send mail

## How Sending Works

When `send(target, message)` is called:

1. Consent gate: returns `error.ConsentNotGranted` if `consent_granted = false`.
2. Subject parsing:
   - If message starts with `Subject: <line>`, that line becomes the Subject.
   - Otherwise Subject defaults to `nullclaw Message`.
3. SMTP connection opens to `smtp_host:smtp_port`.
4. SMTP command sequence:
   - greeting read
   - `EHLO nullclaw`
   - `MAIL FROM:<from_address>`
   - `RCPT TO:<target>`
   - `DATA`
   - headers/body write
   - `QUIT`
5. If a tracked Message-ID exists for the recipient, `In-Reply-To` and `References` headers are included.

## Reply/Thread Behavior

- `trackMessageId(sender, message_id)` stores the latest message id per sender.
- `sendReply(recipient, original_subject, message)` applies `Re:` prefix if needed.
- Subject prefix detection is case-insensitive (`Re:`, `re:`, `RE:`).

## Allowlist Behavior

`isSenderAllowed` supports:

1. Wildcard: `*`
2. Full address: `alice@example.com`
3. Domain with at-sign: `@example.com`
4. Bare domain: `example.com` (matches `user@example.com`)

Address comparisons are case-insensitive where applicable.

## Current Limitations

Important current constraints in implementation:

1. No SMTP AUTH handshake is performed in `sendMessage`.
2. No STARTTLS negotiation or TLS wrapping is performed in `sendMessage`.
3. `smtp_tls`, `username`, and `password` are present in config but not used by the current SMTP command path.
4. Channel start is effectively no-op for persistent inbound email transport.

Operational impact:

- Best fit today is environments where direct SMTP relay is available without auth/TLS requirements, or where a trusted local relay is used.
- If your SMTP provider requires AUTH/STARTTLS (common), current Email channel will likely fail without additional implementation work.

## Runtime Classification

Channel catalog currently classifies Email as `send_only`.
This means the daemon treats it as outbound lifecycle instead of long-lived inbound listener.

## Minimal Send-Only Example

```json
{
  "channels": {
    "email": {
      "accounts": {
        "default": {
          "smtp_host": "127.0.0.1",
          "smtp_port": 25,
          "from_address": "bot@example.com",
          "consent_granted": true
        }
      }
    }
  }
}
```

## Troubleshooting

Common failures:

1. `ConsentNotGranted`: set `consent_granted` to `true`.
2. `SmtpConnectError`: host/port unreachable or DNS issue.
3. `SmtpError`: SMTP server rejected a command or connection state invalid.

Suggested checks:

1. Verify SMTP reachability from host.
2. Test relay policy for unauthenticated local submissions.
3. Confirm `from_address` is accepted by relay policy.

## Related Pages

- [Configuration](./configuration.md)
- [Usage and Operations](./usage.md)
- [Commands](./commands.md)
