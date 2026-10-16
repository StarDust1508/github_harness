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
# На macOS /tmp — это символьная ссылка на /private/tmp, поэтому один и тот же
# путь приходит в двух видах. Сравнивать их напрямую нельзя: тест падал при
# запуске из /tmp и проходил из домашнего каталога. CI на Linux молчал,
# потому что там /private нет.
norm() { case "$1" in /private/*) printf '%s' "${1#/private}" ;; *) printf '%s' "$1" ;; esac; }
SANDBOX_N=$(norm "$SANDBOX"); REPO_N=$(norm "$REPO")
BAD_LINKS=$(find "$SANDBOX" -type l 2>/dev/null | while read -r l; do
  t=$(norm "$(readlink "$l")")
  if [ "${t#"$SANDBOX_N"}" = "$t" ] && [ "${t#"$REPO_N"}" = "$t" ]; then echo "$l"; fi
done | wc -l | tr -d ' ')
[ "$BAD_LINKS" = "0" ] && ok "все ссылки ведут внутрь песочницы или репозитория" || bad "есть ссылки наружу: $BAD_LINKS"

head_ "12. Инструмент статистики не падает без журналов"
# В песочнице журналов нет. Инструмент обязан сказать об этом внятно,
# а не выдать трассировку стека.
OUT=$(node "$REPO/tools/session-stats" 2>&1 || true)
case "$OUT" in
  *"нет каталога журналов"*) ok "сообщение понятное" ;;
  *) bad "непонятный вывод: $(printf '%s' "$OUT" | head -1)" ;;
esac
case "$OUT" in
  *"at "*) bad "в выводе трассировка стека" ;;
  *) ok "трассировки стека нет" ;;
esac

head_ "13. Точка входа: создаётся, но чужое не перезаписывает"
"$HARNESS" entrypoint --write >/dev/null 2>&1 || true
if [ -f "$HOME/.dsh/AGENTS.md" ]; then ok "точка входа создана там, где файла не было"; else bad "точка входа не создана"; fi
echo "МОИ ПРАВИЛА" > "$HOME/.dsh/AGENTS.md"
"$HARNESS" entrypoint --write >/dev/null 2>&1 || true
[ "$(cat "$HOME/.dsh/AGENTS.md")" = "МОИ ПРАВИЛА" ] && ok "существующий файл инструкций не тронут" || bad "чужой файл инструкций перезаписан"

head_ "14. Проверка реестров ловит разрыв ссылки"
# Сначала — что реестры целостны как есть.
if "$HARNESS" check >/dev/null 2>&1; then ok "реестры целостны"; else bad "проверка реестров падает на целых данных"; fi
# Затем добавляем запись со ссылкой в никуда и убеждаемся, что её видно.
cp "$REPO/assurance/registers/risks.yaml" "$SANDBOX/risks.bak"
{
  printf '\n  - id: risk-probe\n'
  printf '    title: Проверка\n'
  printf '    system: системы-с-таким-именем-нет\n'
  printf '    owner: probe\n'
  printf '    treatment: mitigate\n'
  printf '    residual: low\n'
  printf '    next_review: 2099-01-01\n'
} >> "$REPO/assurance/registers/risks.yaml"
if "$HARNESS" check risks >/dev/null 2>&1; then bad "битая ссылка не найдена"; else ok "битая ссылка найдена"; fi
cp "$SANDBOX/risks.bak" "$REPO/assurance/registers/risks.yaml"

head_ "15. Маршрутизатор попадает агенту и проверяется"
OUT=$("$HARNESS" entrypoint)
case "$OUT" in
  *"Что умеет обвязка"*) ok "маршрут есть в точке входа" ;;
  *) bad "маршрута нет в точке входа" ;;
esac
case "$OUT" in
  *"tools/harness check"*) ok "в маршруте есть вызовы, а не только названия" ;;
  *) bad "вызовы в маршрут не попали" ;;
esac
# Возможность без условия применения должна быть видна проверке.
cp "$REPO/capabilities.yaml" "$SANDBOX/caps.bak"
python3 - "$REPO/capabilities.yaml" <<'PYEOF'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
t = re.sub(r"    when:\n(      - .*\n)+", "", t, count=1)
p.write_text(t, encoding="utf-8")
PYEOF
if "$HARNESS" doctor 2>&1 | grep -q "нет when"; then ok "возможность без условия обнаружена"; else bad "возможность без условия не обнаружена"; fi
cp "$SANDBOX/caps.bak" "$REPO/capabilities.yaml"

head_ "16. Прогонщик атак различает три исхода"
# Самопроверочная цель даёт заранее известные числа: одна атака пробивает,
# одна уходит на разбор, остальные удерживаются. Если числа другие —
# сломался прогонщик, а не цель.
rm -f "$REPO"/security/evals/self-test-*.yaml
OUT=$("$HARNESS" eval self-test 2>&1 || true)
case "$OUT" in
  *"пробито 1 · удержано 14 · на разбор 1"*) ok "три исхода различены верно" ;;
  *) bad "неожиданный итог: $(printf '%s' "$OUT" | grep 'Итог по цели' || printf '%s' "$OUT" | tail -1)" ;;
esac
case "$OUT" in
  *"ПРОБОЙ tool-destructive-01"*) ok "пробитие найдено и названо" ;;
  *) bad "пробитие не найдено" ;;
esac
case "$OUT" in
  *"leak-prompt-02"*) ok "неоднозначное отдано на разбор" ;;
  *) bad "неоднозначное не отдано на разбор" ;;
esac
rm -f "$REPO"/security/evals/self-test-*.yaml

head_ "17. Расхождение раскладки с манифестом ловится"
# Манифест обещает, что каталог скиллов DeepSeek Harness плоский. Положим туда
# вложенный скилл — doctor обязан предупредить, что flat его не увидит.
mkdir -p "$HOME/.dsh/skills/вложенный/скилл"
printf -- '---\nname: nested-probe\ndescription: Проверка обнаружения вложенной раскладки там где обещан плоский список\n---\n\ntext\n' > "$HOME/.dsh/skills/вложенный/скилл/SKILL.md"
if "$HARNESS" doctor 2>&1 | grep -q "раскладка flat их не увидит"; then
  ok "вложенность в плоском каталоге обнаружена"
else
  bad "расхождение раскладки не обнаружено"
fi
rm -rf "$HOME/.dsh/skills/вложенный"

# ─────────────────────────────────────────────────────────────────────────────
printf '\n\033[1mИтог:\033[0m пройдено %s, провалено %s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
