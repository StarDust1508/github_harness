# SkillsMP — конспект

**Сайт:** https://skillsmp.com/ · **Машинные точки входа:** `/llms.txt`, `/agents.md`, API `/api/v1/skills/search`

## Что это

Community-платформа, агрегирующая **2 000 000+ открытых Agent Skills из GitHub**. Поиск по ключевым словам, категориям и профессиям (SOC). Независимый проект, не аффилирован с Anthropic. Поддерживает 9 языков интерфейса.

Формат скиллов — `SKILL.md` (Claude Code / Codex CLI / ChatGPT и другие агентские воркфлоу). Это ровно тот же формат, который понимает DSH, поэтому найденное переносится напрямую.

## API

```sh
# Анонимный поиск (без ключа)
curl "https://skillsmp.com/api/v1/skills/search?q=playwright"

# С ключом — выше лимиты
curl "https://skillsmp.com/api/v1/skills/search?q=playwright" \
  -H "Authorization: Bearer sk_live_..."
```

- Канонический URL скилла — `skillUrl` из ответа (не собирать вручную из `id`).
- Ключи API выдаются в личном кабинете (вход через Google/GitHub); для агентов есть отдельный раздел *Agent Authentication*.
- Есть developer-портал, песочница, вебхуки (в роадмапе), feed таймлайна.

## Как я это использую

1. Перед тем как писать новый скилл — искать готовый (`50-TOOLS/skillsmp-search.sh "<тема>"`).
2. Найденные репозитории устанавливать экосистемным CLI: `skills add <owner/repo> -g -a '*' -s '*' -y`.
3. Дальше — это обычные скиллы в `~/.dsh/skills`, подхватываются DSH без перезапуска.

## Смежное: CLI `skills`

Глобально уже установлен `skills` (v1.4.3, актуальная 1.7.0) — это **vercel-labs/skills**, «open agent skills ecosystem»:

```sh
skills add <package>        # добавить пакет скиллов (owner/repo или URL)
skills list | ls            # что установлено
skills find [query]         # интерактивный поиск
skills check | update       # обновления
skills init [name]          # создать новый скилл
# флаги: -g (глобально), -a <agents> (кому ставить, '*' — всем), -s <skills>, -y, --copy
```

Важно: `-g` ставит скилл на уровне пользователя, `-a '*'` — во все известные агентские каталоги. Это удобный способ раскладывать скиллы и в `~/.dsh/skills`.

## Решение

Использовать SkillsMP как **поисковый слой**, а `skills` CLI — как **установщик**. Собственные скиллы держать в `20-SKILLS/` этой папки и симлинковать.
