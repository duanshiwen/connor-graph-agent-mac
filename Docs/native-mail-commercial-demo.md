# Native Mail Commercial Demo Runbook

> Last updated: 2026-07-04

This runbook demonstrates the end-to-end Native Mail commercial path without requiring a real external mailbox.

## Demo Goal

Show that Connor can:

1. Search local mail.
2. Read mail body without mutating read state.
3. Capture read evidence into Memory OS.
4. Create a governed draft.
5. Request human approval before SMTP send.
6. Lock approval to an envelope hash.
7. Send through a fake SMTP adapter.
8. Persist sent cache, send history and outbound Memory OS evidence.

## Fixture Mode

Use `MailRuntime.fixture()` or equivalent app factory fixture wiring.

Fixture contains:

- Account: `fixture-account`
- Identity: `fixture-identity`
- Message: `fixture-message-1`
- Attachment descriptor: `fixture-attachment-1`
- Fake SMTP provider message id: `fixture-smtp-message-id`

## Manual Flow

### 1. Search Mail

Ask Connor:

```text
Search my mail for native mail system.
```

Expected tool path:

- `mail_search_messages`

Expected result:

- Candidate summary is returned.
- Read state is unchanged.
- Memory OS is not written by search alone.

### 2. Read Mail Detail

Ask Connor:

```text
Read the body of fixture-message-1.
```

Expected tool path:

- `mail_get_message` with `includeBody: true`

Expected result:

- Body is returned.
- Memory OS L0/L1 captures detail-read evidence.

### 3. Create Draft

Ask Connor:

```text
Create a reply draft to bob@example.com saying: Thanks, I reviewed the native mail system.
```

Expected tool path:

- `mail_create_draft`

Expected result:

- A draft is created.
- No SMTP send occurs.

### 4. Send Draft Approval

Ask Connor:

```text
Send that draft.
```

Expected tool path:

- `mail_send_draft`
- permission request for `.sendMail`

Expected UI:

- Title: `确认发送邮件`
- Recipients visible.
- Subject visible.
- Envelope hash visible.
- BCC redacted to count only.
- Always Allow unavailable.
- Warning says the approval will send real mail in real SMTP mode.

### 5. Approve Send

Click Allow.

Expected runtime path:

- Approval payload stores `approvedEnvelopeHash`.
- Send recomposes the message.
- Current envelope hash must match approved hash.
- SMTP client is called only after hash match.

### 6. Verify Sent Closure

Expected artifacts:

- Draft status becomes `sent`.
- Send attempts include `.sending` and `.sent`.
- Send history contains provider message id and envelope hash.
- Sent mailbox/cache contains the sent message.
- Optional Memory OS facade captures outbound evidence with direction `outbound`.

## Negative Demo

### Draft Changed After Approval

1. Generate approval payload.
2. Mutate draft subject/body/recipient.
3. Attempt approved send.

Expected result:

- SMTP is not called.
- Error: envelope hash mismatch.
- Draft remains not sent.

## Verification Commands

```bash
swift test --filter 'Mail|Approval'
swift test
```
