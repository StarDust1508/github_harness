---
name: apple-apps
description: "Apple data-layer apps on macOS: Notes (memo CLI), Reminders (remindctl), Messages/iMessage (imsg), FindMy (AppleScript + vision). Load when the user wants to interact with any of these native macOS/iCloud apps."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [macos]
metadata:
  hermes:
    tags: [Apple, macOS, Notes, Reminders, iMessage, SMS, FindMy, AirTag, iCloud]
    related_skills: [obsidian, macos-computer-use]
---

# Apple Apps — macOS Native Data Layer

Four Apple data-layer apps accessible from the terminal. All sync across Apple devices via iCloud.

**Decision table:**

| User wants | Skill section |
|---|---|
| Create / search / edit Apple Notes | § Notes |
| Add / list / complete Apple Reminders | § Reminders |
| Send / read iMessages or SMS | § iMessage |
| Find devices or AirTags (pet, keys, bag) | § Find My |
| Agent-internal scratchpad | → use the `memory` tool instead |
| Markdown-native knowledge base | → use the `obsidian` skill |

---

## § Notes — Apple Notes via `memo`

### Prerequisites
```bash
brew tap antoniorodr/memo && brew install antoniorodr/memo/memo
# Grant Automation access to Notes.app when prompted:
# System Settings → Privacy → Automation
```

### Quick Reference

```bash
memo notes                        # List all notes
memo notes -f "Folder Name"       # Filter by folder
memo notes -s "query"             # Search notes (fuzzy)
memo notes -a                     # Interactive editor (new note)
memo notes -a "Note Title"        # Quick add with title
memo notes -e                     # Interactive: select note to edit
memo notes -d                     # Interactive: select note to delete
memo notes -m                     # Move note to folder (interactive)
memo notes -ex                    # Export to HTML/Markdown
```

### Limitations
- Cannot edit notes containing images or attachments
- Interactive prompts require `pty=true` if needed
- macOS only

---

## § Reminders — Apple Reminders (AppleScript, `remindctl` НЕ установлен)

### ⚠️ Сначала прочитай это

`remindctl` **на этой машине не установлен** (проверено 11.10.2026), поэтому все
команды ниже не сработают. Рабочий способ — **AppleScript через `osascript`**;
доступ к Напоминаниям и Календарю уже выдан, ничего доустанавливать не нужно.

```bash
# СОЗДАТЬ напоминание (синхронизируется на iPhone через iCloud)
osascript -e 'tell application "Reminders" to make new reminder at end of first list with properties {name:"Сдать анализы", body:"Все документы при мне", due date:date "12.10.2026 09:16"}'

# СПИСОК напоминаний
osascript -e 'tell application "Reminders" to get name of every reminder of first list'

# СОЗДАТЬ событие в календаре
osascript -e 'tell application "Calendar" to tell (first calendar whose writable is true) to make new event at end of events with properties {summary:"Эндокринолог", start date:date "26.10.2026 14:00", end date:date "26.10.2026 15:00"}'
```

Проверено 11.10.2026: напоминание создаётся и удаляется, событие в календаре
«Домашний» создаётся. Правила «куда записывать» — в разделе Rules ниже.

### Если `remindctl` появится

```bash
brew install steipete/tap/remindctl
remindctl authorize               # Grant Reminders permission
remindctl status                  # Verify access
```

### Quick Reference

```bash
# View
remindctl                         # Today's reminders
remindctl today / tomorrow / week / overdue / all
remindctl 2026-01-04              # Specific date
remindctl list                    # All lists
remindctl list Work               # Specific list

# Create
remindctl add "Buy milk"
remindctl add --title "Call mom" --list Personal --due tomorrow
remindctl add --title "Meeting prep" --due "2026-02-15 09:00"

# Due time vs alarm — they are DIFFERENT fields
remindctl add --title "Hairdresser" --due "2026-05-15 14:00" --alarm "2026-05-15 13:30"
# Edit existing:
remindctl edit 87354 --due "2026-05-15 14:00" --alarm "2026-05-15 13:30"

# Complete / delete
remindctl complete 1 2 3
remindctl delete 4A83 --force

# Output formats
remindctl today --json            # JSON for scripting
remindctl today --plain           # TSV
remindctl today --quiet           # Counts only
```

### Date formats
`today`, `tomorrow`, `yesterday`, `YYYY-MM-DD`, `YYYY-MM-DD HH:mm`, ISO 8601.

### Rules
1. **По умолчанию «напомни» = Apple Reminders, а не внутренний cron.**
   Дмитрий смотрит напоминания с телефона, а Apple Reminders синхронизируется
   через iCloud — внутреннее напоминание агента видно только в чате Hermes.
   Поэтому: создавай через `remindctl` и **явно говори, куда записал**.
   Пример: «Записал в Apple Reminders: 12.10 в 9:16 — сдача анализов
   (придёт на телефон)».

   *Почему правило появилось:* 07.10.2026 агент на «записать и напомнить»
   молча создал внутренний cron-алерт. Напоминание сработало, но в календаре и
   в приложении «Напоминания» на телефоне его не было — Дмитрий решил, что
   задача потерялась.

   Внутренний алерт (`scripts/reliable_reminder.py`) — только если пользователь
   прямо просит «напомни в чате» или Apple Reminders недоступен.
2. Always confirm reminder content and due date before creating.
3. Verify with `--json`: check `dueDate` vs `alarmDate` fields separately.
4. Если дата в прошлом — не молчи, а спроси: «12 сентября уже прошло,
   ты имел в виду 12 октября?»

---

## § iMessage — Apple Messages via `imsg`

### Prerequisites
```bash
brew install steipete/tap/imsg
# Grant Full Disk Access for terminal: System Settings → Privacy → Full Disk Access
# Grant Automation for Messages.app when prompted
```

### Quick Reference

```bash
# List chats
imsg chats --limit 10 --json

# View history
imsg history --chat-id 1 --limit 20 --json
imsg history --chat-id 1 --limit 20 --attachments --json

# Send
imsg send --to "+14155551212" --text "Hello!"
imsg send --to "+14155551212" --text "Check this" --file /path/to/image.jpg
imsg send --to "+14155551212" --text "Hi" --service imessage   # force iMessage
imsg send --to "+14155551212" --text "Hi" --service sms        # force SMS

# Watch for new messages
imsg watch --chat-id 1 --attachments
```

### When NOT to use
- Telegram/Discord/Slack/WhatsApp → use the appropriate gateway channel
- Bulk/mass messaging → always confirm with user first

### Rules
1. **Always confirm recipient and message content** before sending.
2. **Never send to unknown numbers** without explicit user approval.
3. **Verify file paths** exist before attaching.

### Example workflow
```bash
# 1. Find a contact
imsg chats --limit 20 --json | python3 -c "
import sys, json
chats = json.load(sys.stdin)
for c in chats:
    if 'Mom' in c.get('displayName', ''):
        print(c)
"
# 2. Confirm with user, then:
imsg send --to "+1555123456" --text "I'll be late"
```

---

## § Find My — Devices and AirTags

Apple provides **no CLI or API** for Find My. This section uses AppleScript + screenshots.

### Prerequisites
- macOS with Find My app and iCloud signed in
- Devices/AirTags already registered in Find My
- Screen Recording permission: System Settings → Privacy → Screen Recording
- Optional (recommended): `brew install steipete/tap/peekaboo` for reliable UI automation

### Method 1: AppleScript + screenshot

```bash
osascript -e 'tell application "FindMy" to activate'
sleep 3
screencapture -w -o /tmp/findmy.png
```
Then analyze with `vision_analyze(image_url="/tmp/findmy.png", question="What devices/items are shown and what are their locations?")`.

Switch tabs:
```bash
# Switch to Items tab (AirTags)
osascript -e '
tell application "System Events"
    tell process "FindMy"
        click button "Items" of toolbar 1 of window 1
    end tell
end tell'
```

### Method 2: Peekaboo (recommended)
```bash
osascript -e 'tell application "FindMy" to activate'
sleep 3
peekaboo see --app "FindMy" --annotate --path /tmp/findmy-ui.png
# Click a device by element ID:
peekaboo click --on B3 --app "FindMy"
peekaboo image --app "FindMy" --path /tmp/findmy-detail.png
```
Then `vision_analyze` on the detail screenshot.

### AirTag location tracking over time
```bash
# Keep FindMy app in foreground — AirTags only update while the page is displayed
osascript -e 'tell application "FindMy" to activate'
sleep 3
# Switch to Items tab (see above)
# Then periodically capture:
while true; do
    screencapture -w -o /tmp/findmy-$(date +%H%M%S).png
    sleep 300   # every 5 minutes
done
```
Use a cronjob for automated long-running patrol-route tracking.

### Limitations
- AirTags only update while FindMy page is actively displayed
- Location accuracy depends on nearby Apple devices in the FindMy network
- AppleScript UI automation may break across macOS versions
- Keep FindMy in the foreground for AirTag tracking (updates stop when minimized)
