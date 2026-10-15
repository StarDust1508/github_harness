#!/bin/sh
# Проверки механизма обвязки.
#
# Зачем: механизм работает с файловой системой пользователя. Правка в установщике
# может молча сломать установку или, хуже, начать трогать чужие файлы. Поэтому
# инварианты проверяются автоматически, а не «я посмотрел — работает».
#
# Все проверки идут в подменённом HOME. Реальный домашний каталог не затрагивается:
# это проверяется отдельным тестом в конце.

set -eu

REPO=$(cd "$(dirname "$0")/.." && pwd)
HARNESS="$REPO/tools/harness"

PASS=0
FAIL=0
SANDBOX=""

ok()   { PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m %s\n' "$1"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# Всегда возвращает 0: под `set -e` функция с неуспешным последним выражением
# завершает весь скрипт — на этом тест уже один раз упал.
cleanup() {
  if [ -n "$SANDBOX" ] && [ -d "$SANDBOX" ]; then rm -rf "$SANDBOX"; fi
  return 0
}
trap cleanup EXIT

new_sandbox() {
  cleanup
  SANDBOX=$(mktemp -d)
  mkdir -p "$SANDBOX/.dsh" "$SANDBOX/.hermes"
  export HOME="$SANDBOX"
}

# ─────────────────────────────────────────────────────────────────────────────
head_ "1. Развёртывание на чистой машине"
new_sandbox
if HARNESS_YES=1 "$REPO/tools/bootstrap" >/dev/null 2>&1; then
  ok "bootstrap завершился успешно"
else
  bad "bootstrap упал"
fi
[ -L "$HOME/.agents/skills/agent-harness-audit" ] && ok "ссылка в общей точке создана" || bad "нет ссылки в ~/.agents/skills"
[ -e "$HOME/.dsh/skills/agent-harness-audit" ] && ok "ссылка для DeepSeek Harness создана" || bad "нет ссылки в ~/.dsh/skills"
[ -e "$HOME/.hermes/skills/diagnostics/agent-harness-audit" ] && ok "ссылка для Hermes создана (вложенная раскладка)" || bad "нет ссылки в ~/.hermes/skills"
[ -f "$HOME/.harness/state.json" ] && ok "состояние записано" || bad "нет state.json"

head_ "2. Проверка целостности после установки"
if "$HARNESS" doctor >/dev/null 2>&1; then ok "doctor без проблем"; else bad "doctor нашёл проблемы"; fi

head_ "3. Повторная установка идемпотентна"
BEFORE=$(find "$HOME/.agents/skills" "$HOME/.dsh/skills" -type l 2>/dev/null | wc -l | tr -d ' ')
"$HARNESS" install all >/dev/null 2>&1 || true
AFTER=$(find "$HOME/.agents/skills" "$HOME/.dsh/skills" -type l 2>/dev/null | wc -l | tr -d ' ')
[ "$BEFORE" = "$AFTER" ] && ok "второй запуск не создал дублей ($AFTER ссылок)" || bad "дубли: было $BEFORE, стало $AFTER"

head_ "4. prune не трогает чужое"
mkdir -p "$HOME/.agents/skills/чужой-каталог"
touch "$HOME/.agents/skills/чужой-каталог/SKILL.md"
"$HARNESS" prune >/dev/null 2>&1 || true
[ -e "$HOME/.agents/skills/чужой-каталог/SKILL.md" ] && ok "чужой каталог сохранён" || bad "prune удалил чужое"

head_ "5. prune убирает осиротевшую ссылку"
ln -sfn "$REPO/core/skills/несуществующий" "$HOME/.agents/skills/осиротевшая"
node -e '
const fs=require("fs"),p=process.env.HOME+"/.harness/state.json";
const s=JSON.parse(fs.readFileSync(p,"utf8"));
(s.tools._shared ||= {skills:[],links:[]}).links.push({name:"осиротевшая",dest:process.env.HOME+"/.agents/skills/осиротевшая",target:"/nonexistent",hash:"x"});
fs.writeFileSync(p,JSON.stringify(s,null,2));'
"$HARNESS" prune >/dev/null 2>&1 || true
[ -e "$HOME/.agents/skills/осиротевшая" ] && bad "осиротевшая ссылка осталась" || ok "осиротевшая ссылка удалена"
[ -e "$HOME/.agents/skills/agent-harness-audit" ] && ok "рабочая ссылка не задета" || bad "prune удалил рабочую ссылку"

head_ "6. Повреждённая ссылка ловится doctor-ом"
rm -f "$HOME/.agents/skills/agent-harness-audit"
if "$HARNESS" doctor >/dev/null 2>&1; then bad "doctor не заметил пропавшую ссылку"; else ok "doctor сообщил о проблеме (код возврата ненулевой)"; fi

head_ "7. candidate не устанавливается по умолчанию"
"$HARNESS" new probe-candidate >/dev/null 2>&1
OUT=$("$HARNESS" install all 2>&1 | head -1)
case "$OUT" in
  *"кандидатов: 0"*) ok "кандидат пропущен при установке" ;;
  *) bad "кандидат попал в установку: $OUT" ;;
esac
rm -rf "$REPO/core/skills/probe-candidate"
"$HARNESS" prune >/dev/null 2>&1 || true

head_ "8. Отказ при секрете"
TMP_SKILL="$SANDBOX/секретный-скилл"
mkdir -p "$TMP_SKILL"
printf -- '---\nname: секрет-тест\ndescription: Проверка отказа сканера на настоящем на вид ключе\n---\n\nsk-AbCdEfGhIjKlMnOpQrStUvWxYz012345\n' > "$TMP_SKILL/SKILL.md"
if "$HARNESS" import "$TMP_SKILL" --dry-run >/dev/null 2>&1; then
  bad "импорт не отказал при секрете"
else
  [ "$?" -eq 2 ] && ok "импорт отказал с кодом 2" || ok "импорт отказал (ненулевой код)"
fi

head_ "9. Многострочное значение YAML принимается"
# Имя обязательно латиницей (kebab-case): на кириллическом имени этот тест
# сначала падал по другой причине и проверял не то, что заявлено.
MULTI="$SANDBOX/multi-line-test"
mkdir -p "$MULTI"
printf -- '---\nname: multi-line-test\ndescription: Первая часть описания,\n  которая продолжается на следующей строке и должна разбираться\n---\n\ntext\n' > "$MULTI/SKILL.md"
if "$HARNESS" import "$MULTI" --dry-run >/dev/null 2>&1; then ok "многострочное значение принято"; else bad "многострочное значение забраковано"; fi

head_ "10. Нелатинское имя отклоняется"
CYR="$SANDBOX/кириллица"
mkdir -p "$CYR"
printf -- '---\nname: кириллица\ndescription: Проверка отказа на имени не в kebab-case\n---\n\ntext\n' > "$CYR/SKILL.md"
if "$HARNESS" import "$CYR" --dry-run >/dev/null 2>&1; then bad "кириллическое имя принято"; else ok "кириллическое имя отклонено"; fi

head_ "11. Ссылки не ведут наружу"
# Каждая созданная ссылка обязана вести либо в песочницу, либо в репозиторий.
# Ссылка «куда-то ещё» означала бы, что установщик трогает чужие данные.
BAD_LINKS=$(find "$SANDBOX" -type l 2>/dev/null | while read -r l; do
  t=$(readlink "$l")
  if [ "${t#"$SANDBOX"}" = "$t" ] && [ "${t#"$REPO"}" = "$t" ]; then echo "$l"; fi
done | wc -l | tr -d ' ')
[ "$BAD_LINKS" = "0" ] && ok "все ссылки ведут внутрь песочницы или репозитория" || bad "есть ссылки наружу: $BAD_LINKS"

# ─────────────────────────────────────────────────────────────────────────────
printf '\n\033[1mИтог:\033[0m пройдено %s, провалено %s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
