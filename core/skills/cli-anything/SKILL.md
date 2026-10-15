---
name: cli-anything
description: Обёртка для CLI-Anything инструментов — AI-поиск (Exa), тренды (hfeeds), Safari-автоматизация
version: 1.0.0
triggers:
  - /cli
  - /exa
  - /trends
  - /safari-cli
author: claude
---

# CLI-Anything — Агентные CLI-инструменты

## Что это
Набор CLI-обёрток из проекта [CLI-Anything](https://github.com/HKUDS/CLI-Anything), 
установленных в отдельный venv. Каждая превращает существующий инструмент в 
agent-native CLI с JSON-выводом.

## Установленные инструменты

### 1. Exa — AI-поиск (нужен EXA_API_KEY)
```bash
source ~/.hermes/cli-anything-venv/bin/activate
cli-anything-exa --json search "запрос" --num-results 5
cli-anything-exa --json search "AI agents" --category research-paper
cli-anything-exa --json contents https://example.com --content text
```

### 2. Hacker Feeds — тренды GitHub/HN/Reddit/ProductHunt
```bash
hfeeds github --since daily      # GitHub trending за день
hfeeds github --since weekly     # За неделю
hfeeds github --lang python      # По языку
hfeeds news                      # Hacker News
hfeeds product                   # Product Hunt
hfeeds reddit                    # Reddit
```

### 3. Safari CLI — браузерная автоматизация (84 команды)
```bash
source ~/.hermes/cli-anything-venv/bin/activate
cli-anything-safari tools        # Список всех 84 инструментов
cli-anything-safari --json tool navigate --url "https://example.com"
cli-anything-safari --json tool screenshot
```

## Использование из Hermes

### /trends или /cli trends
Показать тренды с GitHub/HN/ProductHunt.

### /exa <запрос>
AI-поиск через Exa. Примеры:
- `/exa последние новости об AI агентах`
- `/exa site:arxiv.org transformer 2026`
- `/exa Anthropic funding --category company`

### /safari-cli <действие>
Управление Safari через CLI. Примеры:
- `/safari-cli navigate https://github.com`
- `/safari-cli screenshot`

## Пути
- Venv: `~/.hermes/cli-anything-venv/`
- `hfeeds` (npm global): `/opt/homebrew/lib/node_modules/hacker-feeds-cli/bin/main.js`
- Exa API key: задать в `~/.hermes/.env` как `EXA_API_KEY=...`

## Заметки и pitfalls
- ⚠️ **`hf` занят HuggingFace CLI** — не используй `hf` для hacker-feeds, команда резолвится в HF CLI. Правильный бинарник — `hfeeds`.
- Exa нужен API-ключ (бесплатный tier на exa.ai)
- Safari CLI требует safari-mcp (`npm install -g safari-mcp`)
- `hfeeds` работает без ключей — парсит публичные API
- Reddit может возвращать 403 (без User-Agent), заранее проверяй
- Все CLI поддерживают `--json` для машиночитаемого вывода
