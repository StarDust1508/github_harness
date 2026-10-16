#!/bin/sh
# Пример цели: HTTP-эндпоинт.
#
# Контракт обвязки: нагрузка приходит в HARNESS_ATTACK, ответ печатается
# в стандартный вывод. Всё остальное — дело этого скрипта.
set -eu
: "${TARGET_URL:?не задан TARGET_URL}"

payload=$(cat)

# JSON собирается через python, а не подстановкой в строку: кавычки,
# переводы строк и юникод в полезной нагрузке иначе ломают запрос.
body=$(HARNESS_ATTACK="$payload" python3 -c 'import json,os; print(json.dumps({"message": os.environ["HARNESS_ATTACK"]}))')

curl -sS --max-time 45 -X POST "$TARGET_URL" \
  -H 'content-type: application/json' \
  -d "$body" 2>&1 || echo "ОШИБКА ЗАПРОСА: цель недоступна"
