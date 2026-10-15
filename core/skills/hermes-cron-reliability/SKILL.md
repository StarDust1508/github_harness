---
name: hermes-cron-reliability
description: "Диагностика и укрепление cron-задач Hermes, особенно напоминаний с дедлайном и одноразовых. Используй, когда запланированное напоминание не пришло, пришло не вовремя или сработало дважды."
version: 1.0.0
metadata:
  hermes:
    tags: [cron, reminders, reliability, hermes, diagnostics]
---

# Hermes Cron Reliability

Use when:
- a scheduled reminder allegedly did not arrive;
- a one-shot cron job is deadline-sensitive;
- `cronjob(action='list')` looks healthy but the user says delivery failed;
- you need to distinguish `agent ran` vs `message was delivered on time`.

## Key findings

1. **One-shot jobs are weak for critical reminders.** They can run late and then disappear from `jobs.json` after execution, which makes them hard to audit later.
2. **`last_status: ok` is not enough.** A cron can complete successfully while delivery still failed. Always inspect `last_delivery_error`.
3. **Output artifacts matter.** If the job vanished from `jobs.json`, check `~/.hermes/cron/output/<job_id>/`. An output file there proves the agent ran, and its timestamp reveals lateness.
4. **For reminder jobs, timing is part of correctness.** A reminder that arrives 5+ minutes late may be functionally equivalent to a failure.
5. In this environment, a missed reminder investigation found a real output artifact under `~/.hermes/cron/output/<job_id>/...` with the expected reminder text, but it was timestamped about 5 minutes late and the one-shot job had already disappeared from the scheduler state. This confirms the failure mode is often scheduler/delivery observability, not prompt generation.

## Reliable pattern for deadline-sensitive reminders

Do **not** rely on a bare one-shot cron alone.

Preferred pattern:
1. Create the primary reminder job.
2. Also create a short watchdog job scheduled a few minutes after the reminder deadline.
3. The watchdog checks whether the reminder produced an output artifact and whether delivery succeeded.
4. If missing, late, or failed, the watchdog sends a fallback message or raises an explicit alert.

## Debugging workflow for a missed reminder

### 1. List active jobs
Use:
- `cronjob(action='list')`

Check:
- is the job still present?
- if present, what are `next_run_at`, `last_run_at`, `last_status`, `last_delivery_error`?

### 2. Inspect scheduler state
Read:
- `~/.hermes/cron/jobs.json`

Important:
- recurring jobs remain visible here;
- one-shot jobs may disappear after execution, so absence does **not** prove they never ran.

### 3. Inspect cron output artifacts
Search/read under:
- `~/.hermes/cron/output/<job_id>/`

Interpretation:
- output file exists + final response present = agent executed;
- output timestamp later than scheduled time = scheduler lateness / delayed execution;
- no artifact = likely never ran or failed before output write.

### 4. Distinguish run success from delivery success
Use both:
- output artifact contents;
- `last_delivery_error` in `jobs.json` when available.

Examples:
- `last_status: ok` + `last_delivery_error: Telegram send failed ...` = agent succeeded, delivery failed.
- output exists but user saw nothing = likely delivery-layer issue or wrong destination.

## Hard rules

1. For personal reminders like “ask me in 15 minutes”, treat **timely delivery** as the success condition.
2. If a reminder is important and time-bound, add a watchdog/fallback.
3. When investigating a missed cron, check both `jobs.json` and `cron/output/` — not just one.
4. Never conclude “job didn’t run” only because it is absent from `cronjob(action='list')`.
5. Repeated `ok` statuses do not mean the cron is healthy if `last_delivery_error` is non-null.

## Practical examples

### Symptom: user says reminder never arrived
Check:
1. `cronjob(action='list')`
2. `~/.hermes/cron/jobs.json`
3. `~/.hermes/cron/output/<job_id>/...`

If output file exists and says the reminder text was generated, but delivery evidence is missing, report: the agent ran, but the delivery/timing layer failed.

### Symptom: group report appears healthy in list
If `last_status` is `ok` but `last_delivery_error` says the bot was kicked from Telegram group, treat the cron as broken and either retarget or disable it.

## Recommended future improvement

For critical reminders, build a reusable pair:
- main reminder job;
- watchdog job that verifies on-time output + delivery and emits fallback if needed.

This has already been implemented locally as the preferred path for important personal reminders, so future reminder features should use this pattern by default rather than a bare one-shot cron.

## Proven implementation in this environment

In this setup, a working pattern was implemented as a local helper script:
- `~/.hermes/scripts/reliable_reminder.py`
- state files under `~/.hermes/state/reliable_reminders/<reminder_id>.json`

The helper does two things:
1. creates the **main** one-shot reminder cron;
2. creates a **watchdog** one-shot cron a few minutes later.

The watchdog runs local verification logic:
- inspect `jobs.json` when the main job is still present;
- if the one-shot disappeared, inspect `~/.hermes/cron/output/<job_id>/`;
- if delivery looks missing or unclear after the grace window, send a fallback Telegram message directly.

Suggested state fields:
- `main_job_id`
- `watchdog_job_id`
- `remind_at`
- `check_at`
- `status`
- `fallback_sent`
- `main_output_file`
- `observed_last_run_at`
- `observed_delivery_error`

Useful statuses:
- `scheduled`
- `waiting`
- `delivered`
- `fallback_sent`
- `delivery_failed`
- `unclear`

## Hermes CLI gotcha

When using the local Hermes CLI directly, `hermes cron create` expects:
- **positional** `schedule`
- optional **positional** `prompt`

Not flags like `--schedule` / `--prompt`.

Correct pattern:
```bash
hermes cron create --name my-job --deliver telegram:2079133102 '2026-05-12T11:15:00+04:00' 'Напиши короткое напоминание'
```

This matters because the first implementation attempt failed only due to CLI argument shape.

## One more one-shot pitfall

A one-shot created for a time already in the past may appear in odd intermediate state, for example:
- `enabled: true`
- `state: scheduled`
- `next_run_at: null`

Do not trust such jobs for reminders. Treat them as invalid and recreate them with a future timestamp.

## Verification checklist for reliable reminders

After creating a reliable reminder pair, verify all four layers:
1. state file exists in `~/.hermes/state/reliable_reminders/`
2. main job exists in `cronjob(action='list')`
3. watchdog job exists in `cronjob(action='list')`
4. running the verifier before deadline returns `waiting`

After deadline, verify outcome becomes one of:
- `delivered`
- `fallback_sent`

If it stays `unclear`, inspect both `jobs.json` and `cron/output/` immediately.
