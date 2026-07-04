# Native Mail Commercial Release Checklist

> Last updated: 2026-07-04

This checklist freezes the commercial Native Mail surface for Connor Graph Agent Mac.

## 1. Credential Boundary

- Mail account records store credential bindings only.
- Passwords, app passwords, access tokens and refresh tokens must stay inside the credential store abstraction.
- Credential-like values must not appear in:
  - LLM context
  - Memory OS L0/L1 payloads
  - mail audit summaries
  - connection test summaries
  - demo documentation

Verification:

```bash
swift test --filter 'MailConnectionTestService|MailMemoryOS|MailOutboundMemoryOS|MailRuntimeSMTP'
```

## 2. Read Path

- `mail_search_messages` returns candidate summaries only.
- Search must not write Memory OS observations.
- `mail_get_message` with detail/body read writes Native Source evidence into Memory OS L0/L1.
- Plain and HTML bodies are preserved as safe evidence text.

Verification:

```bash
swift test --filter 'MailMemoryOSEndToEndTests|NativeSourceReferenceToolHookTests'
```

## 3. Send Path

- `mail_create_draft` creates a draft and never sends.
- `mail_send_draft` always requires `.sendMail` human approval.
- Model-supplied `approved` arguments are ignored.
- SMTP send is blocked unless the current tool execution context contains `.sendMail`.

Verification:

```bash
swift test --filter 'MailAgentTools|MailRuntimeSendPipeline'
```

## 4. Approval Integrity

- Approval payload includes the draft envelope hash.
- Generating the approval payload stores the approved envelope hash on the draft.
- Sending recomposes the message and compares the current envelope hash against the approved hash.
- If the draft changes after approval, SMTP is not called.

Verification:

```bash
swift test --filter 'sendApprovalPayloadStoresEnvelopeHashForLaterApprovedSend|approvedSendBlocksWhenDraftEnvelopeHashChangedAfterApproval'
```

## 5. Outbound Evidence

- Successful sends write the message to sent cache.
- Successful sends can write outbound Mail evidence into Memory OS L0/L1 when a Memory OS facade is attached.
- Outbound evidence links draft, receipt, provider message id and envelope hash.

Verification:

```bash
swift test --filter 'MailOutboundMemoryOSEndToEndTests|MailRuntimeSentCacheTests'
```

## 6. Attachment Policy

- Composer supports governed `multipart/mixed` messages.
- Attachment filenames and MIME types are header-injection checked.
- BCC is never emitted as an RFC5322 header.
- Sent cache preserves attachment descriptors, not raw attachment content.

Verification:

```bash
swift test --filter 'MailMessageComposer|MailRuntimeSentCache'
```

## 7. UI / Demo Surface

- Mail send approval is presented as a structured mail card/detail, not only raw JSON.
- BCC recipients are redacted to count only.
- Envelope hash is visible for auditability.
- Always Allow is disabled for mail sending.

Verification:

```bash
swift test --filter 'AppAgentPendingApprovalPresentation|AppMailSendApprovalPresentation|MailSettings|NativeMailReadiness'
```

## 8. Full Release Gate

Before claiming release readiness:

```bash
swift test
```

Expected result: all tests pass.

## Known Limitations

- Gmail API / Microsoft Graph direct OAuth mail APIs are intentionally not part of this release path.
- Native Mail is IMAP/SMTP local-first.
- Attachment payload resolution is governed and descriptor-first; full attachment binary source-of-truth is intentionally outside LLM/Memory payloads.
- Full rich mail client UX such as conversation threading and rich-text editing remains backlog.
