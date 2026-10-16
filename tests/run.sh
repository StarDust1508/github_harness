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
# Важны не общие числа, а то, что каждый исход найден ровно там, где заложен.
# Общее число растёт вместе с каталогом атак — это не поломка.
case "$OUT" in
  *"пробито 1"*"на разбор 1"*) ok "три исхода различены верно" ;;
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

head_ "17. Ответы на вопросник проверяются как данные"
if "$HARNESS" check answers >/dev/null 2>&1; then ok "библиотека ответов целостна"; else bad "библиотека ответов не проходит проверку"; fi
# Ответ «да» без доказательства — обещание, а не ответ. Проверяем, что видно.
cp "$REPO/assurance/registers/answers.yaml" "$SANDBOX/answers.bak"
python3 - "$REPO/assurance/registers/answers.yaml" <<'PYEOF'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
t = re.sub(r"    evidence: assurance/evidence/ans-encryption\.md\n", "", t, count=1)
p.write_text(t, encoding="utf-8")
PYEOF
if "$HARNESS" check answers 2>&1 | grep -q "не указано доказательство"; then ok "ответ без доказательства обнаружен"; else bad "ответ без доказательства не обнаружен"; fi
cp "$SANDBOX/answers.bak" "$REPO/assurance/registers/answers.yaml"
# Ссылка вопросника на несуществующий ответ.
cp "$REPO/assurance/registers/questionnaires/example.yaml" "$SANDBOX/q.bak"
sed -i '' 's/    answer: ans-personnel/    answer: ans-нет-такого/' "$REPO/assurance/registers/questionnaires/example.yaml" 2>/dev/null || \
  sed -i 's/    answer: ans-personnel/    answer: ans-нет-такого/' "$REPO/assurance/registers/questionnaires/example.yaml"
if "$HARNESS" check questionnaire-example 2>&1 | grep -q "ссылается на несуществующее"; then ok "ссылка на несуществующий ответ обнаружена"; else bad "ссылка не обнаружена"; fi
cp "$SANDBOX/q.bak" "$REPO/assurance/registers/questionnaires/example.yaml"

head_ "18. Каждая мера обязана кем-то проверяться"
if "$HARNESS" check audit-program >/dev/null 2>&1; then ok "программа аудита целостна"; else bad "программа аудита не проходит проверку"; fi
# Мера, которую не проверяет ни одна процедура, существует только на бумаге.
cp "$REPO/assurance/audit-program.yaml" "$SANDBOX/ap.bak"
python3 - "$REPO/assurance/audit-program.yaml" <<'PYEOF'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
t = re.sub(r"  - id: au-bias-testing\n(?:.*\n)*?(?=  - id:)", "", t, count=1)
p.write_text(t, encoding="utf-8")
PYEOF
if "$HARNESS" check controls 2>&1 | grep -q "не проверяется ни одной процедурой"; then ok "непокрытая мера обнаружена"; else bad "непокрытая мера не обнаружена"; fi
cp "$SANDBOX/ap.bak" "$REPO/assurance/audit-program.yaml"
# Находка обязана ссылаться на процедуру, из которой пришла.
cp "$REPO/assurance/registers/findings.yaml" "$SANDBOX/find.bak"
sed -i '' 's/    test: au-log-redaction/    test: au-нет/' "$REPO/assurance/registers/findings.yaml" 2>/dev/null || \
  sed -i 's/    test: au-log-redaction/    test: au-нет/' "$REPO/assurance/registers/findings.yaml"
if "$HARNESS" check findings 2>&1 | grep -q "ссылается на несуществующее"; then ok "находка без процедуры обнаружена"; else bad "находка без процедуры не обнаружена"; fi
cp "$SANDBOX/find.bak" "$REPO/assurance/registers/findings.yaml"

head_ "19. Риск выше аппетита требует явного принятия"
if "$HARNESS" check risks >/dev/null 2>&1; then ok "реестр рисков целостен"; else bad "реестр рисков не проходит проверку"; fi
cp "$REPO/assurance/registers/risks.yaml" "$SANDBOX/risks2.bak"
# Убираем принятие у риска с остаточным уровнем выше аппетита.
python3 - "$REPO/assurance/registers/risks.yaml" <<'PYEOF'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
t = re.sub(r"    accepted_by:.*\n", "", t, count=1)
t = re.sub(r"    acceptance_reason:.*\n", "", t, count=1)
p.write_text(t, encoding="utf-8")
PYEOF
if "$HARNESS" check risks 2>&1 | grep -q "обязательно «accepted_by»"; then ok "риск без принятия обнаружен"; else bad "риск без принятия не обнаружен"; fi
cp "$SANDBOX/risks2.bak" "$REPO/assurance/registers/risks.yaml"

head_ "20. Приватность: основания, сроки, права субъектов"
if "$HARNESS" check processing >/dev/null 2>&1; then ok "реестр обработки целостен"; else bad "реестр обработки не проходит проверку"; fi
# Передача за границу без основания.
cp "$REPO/assurance/registers/processing.yaml" "$SANDBOX/proc.bak"
sed -i '' '/transfer_basis: стандартные/d' "$REPO/assurance/registers/processing.yaml" 2>/dev/null || \
  sed -i '/transfer_basis: стандартные/d' "$REPO/assurance/registers/processing.yaml"
if "$HARNESS" check processing 2>&1 | grep -q "обязательно «transfer_basis»"; then ok "передача за границу без основания обнаружена"; else bad "передача без основания не обнаружена"; fi
cp "$SANDBOX/proc.bak" "$REPO/assurance/registers/processing.yaml"
# Просроченный незакрытый запрос субъекта.
cp "$REPO/assurance/registers/dsr.yaml" "$SANDBOX/dsr.bak"
python3 - "$REPO/assurance/registers/dsr.yaml" <<'PYEOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
t = t.replace("    deadline: 2026-10-31", "    deadline: 2026-08-31", 1)
p.write_text(t, encoding="utf-8")
PYEOF
if "$HARNESS" check dsr 2>&1 | grep -q "срок прошёл"; then ok "просроченный запрос обнаружен"; else bad "просроченный запрос не обнаружен"; fi
cp "$SANDBOX/dsr.bak" "$REPO/assurance/registers/dsr.yaml"
# Закрытый запрос с прошедшим сроком нарушением не является.
if "$HARNESS" check dsr 2>&1 | grep -q "dsr-2026-02"; then bad "закрытый запрос ошибочно признан просроченным"; else ok "закрытый запрос не считается просроченным"; fi

head_ "21. Отчёт собирается из данных и не врёт"
OUT=$("$HARNESS" report 2>&1 || true)
case "$OUT" in
  *"Готовность к внешнему аудиту"*) ok "отчёт собран" ;;
  *) bad "отчёт не собран" ;;
esac
case "$OUT" in
  *"## Чего нет"*) ok "есть раздел о пробелах" ;;
  *) bad "нет раздела о пробелах" ;;
esac
case "$OUT" in
  *"Находки в работе"*|*"Открытых пунктов нет"*) ok "открытые вопросы показаны" ;;
  *) bad "открытые вопросы не показаны" ;;
esac
# Отчёт из несогласованных данных собираться не должен.
cp "$REPO/assurance/registers/controls.yaml" "$SANDBOX/ctl.bak"
python3 - "$REPO/assurance/registers/controls.yaml" <<'PYEOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
t = t.replace("    evidence: assurance/evidence/ctl-cv-bias-testing.md\n", "", 1)
p.write_text(t, encoding="utf-8")
PYEOF
if "$HARNESS" report >/dev/null 2>&1; then bad "отчёт собран из сломанных данных"; else ok "отчёт отказался собираться из сломанных данных"; fi
cp "$SANDBOX/ctl.bak" "$REPO/assurance/registers/controls.yaml"

head_ "22. Политика без меры — украшение, и это видно"
if "$HARNESS" check policies >/dev/null 2>&1; then ok "реестр политик целостен"; else bad "реестр политик не проходит проверку"; fi
# Политика, которую не реализует ни одна мера.
cp "$REPO/assurance/registers/policies.yaml" "$SANDBOX/pol.bak"
python3 - "$REPO/assurance/registers/policies.yaml" <<'PYEOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
t = t.replace("  - id: pol-incident-response", """  - id: pol-orphan
    title: Политика без применения
    requirement: Требование, которое ничем не реализовано
    owner: Compliance Lead
    approved: 2026-09-01
    next_review: 2027-09-01
    scope: ничего
    addresses:
      - risk-bot-pii
    evidence: assurance/evidence/pol-ai-governance.md

  - id: pol-incident-response""", 1)
p.write_text(t, encoding="utf-8")
PYEOF
if "$HARNESS" check policies 2>&1 | grep -q "ни одна мера не реализует"; then ok "политика без меры обнаружена"; else bad "политика без меры не обнаружена"; fi
cp "$SANDBOX/pol.bak" "$REPO/assurance/registers/policies.yaml"
# Ссылка политики на несуществующий риск.
cp "$REPO/assurance/registers/policies.yaml" "$SANDBOX/pol2.bak"
sed -i '' 's/      - risk-access-excess/      - risk-нет/' "$REPO/assurance/registers/policies.yaml" 2>/dev/null || \
  sed -i 's/      - risk-access-excess/      - risk-нет/' "$REPO/assurance/registers/policies.yaml"
if "$HARNESS" check policies 2>&1 | grep -q "addresses» ссылается на несуществующее"; then ok "потерянная ссылка в списке рисков обнаружена"; else bad "потерянная ссылка не обнаружена"; fi
cp "$SANDBOX/pol2.bak" "$REPO/assurance/registers/policies.yaml"

head_ "23. Каталог атак не деградирует молча"
if "$HARNESS" doctor 2>&1 | grep -q "у каждого класса — правила"; then ok "каталог атак целостен"; else bad "каталог атак не проходит проверку"; fi
# Класс без правил распознавания означает, что все его атаки уйдут на разбор.
cp "$REPO/security/attacks.yaml" "$SANDBOX/at.bak"
python3 - "$REPO/security/attacks.yaml" <<'PYEOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
t = t.replace("    class: overreliance\n    title: Требование выдумать факт",
              "    class: hallucination-pressure\n    title: Требование выдумать факт", 1)
p.write_text(t, encoding="utf-8")
PYEOF
if "$HARNESS" doctor 2>&1 | grep -q "правил распознавания нет"; then ok "класс без правил обнаружен"; else bad "класс без правил не обнаружен"; fi
cp "$SANDBOX/at.bak" "$REPO/security/attacks.yaml"
# Атака без нагрузки.
cp "$REPO/security/attacks.yaml" "$SANDBOX/at2.bak"
python3 - "$REPO/security/attacks.yaml" <<'PYEOF'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
t = re.sub(r"    payload: \|\n(?:      .*\n)+", "", t, count=1)
p.write_text(t, encoding="utf-8")
PYEOF
if "$HARNESS" doctor 2>&1 | grep -q "нет payload"; then ok "атака без нагрузки обнаружена"; else bad "атака без нагрузки не обнаружена"; fi
cp "$SANDBOX/at2.bak" "$REPO/security/attacks.yaml"

head_ "24. Остаточный риск не может быть выше исходного"
cp "$REPO/assurance/registers/risks.yaml" "$SANDBOX/rk.bak"
python3 - "$REPO/assurance/registers/risks.yaml" <<'PYEOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
t = t.replace("""    likelihood: medium
    impact: medium
    treatment: mitigate
    residual: low
    next_review: 2026-12-01""", """    likelihood: medium
    impact: medium
    treatment: mitigate
    residual: high
    accepted_by: Security Lead
    acceptance_reason: проверка правила
    next_review: 2026-12-01""", 1)
p.write_text(t, encoding="utf-8")
PYEOF
if "$HARNESS" check risks 2>&1 | grep -q "обработка не может ухудшить риск"; then ok "завышенный остаточный риск обнаружен"; else bad "завышенный остаточный риск не обнаружен"; fi
cp "$SANDBOX/rk.bak" "$REPO/assurance/registers/risks.yaml"
# Пустая клетка матрицы: проверка обязана сообщить, а не промолчать.
# Первая версия этого теста была неспособна упасть: она убирала клетку,
# на которую не ссылалась ни одна запись, и «проходила» по безвредной ветке.
# Теперь клетка убирается И риск переводится на эту комбинацию.
cp "$REPO/assurance/risk-appetite.yaml" "$SANDBOX/ra.bak"
cp "$REPO/assurance/registers/risks.yaml" "$SANDBOX/rk2.bak"
python3 - "$REPO/assurance/risk-appetite.yaml" "$REPO/assurance/registers/risks.yaml" <<'PYEOF'
import sys, pathlib
a = pathlib.Path(sys.argv[1]); b = pathlib.Path(sys.argv[2])
# Убираем клетку high + medium из матрицы.
t = a.read_text(encoding="utf-8")
t = t.replace("""  high:
    low: medium
    medium: high
    high: high""", """  high:
    low: medium
    high: high""", 1)
a.write_text(t, encoding="utf-8")
# Переводим один риск на эту комбинацию, иначе клетка не будет запрошена.
t2 = b.read_text(encoding="utf-8")
t2 = t2.replace("""    likelihood: medium
    impact: medium
    treatment: mitigate""", """    likelihood: high
    impact: medium
    treatment: mitigate""", 1)
b.write_text(t2, encoding="utf-8")
PYEOF
if "$HARNESS" check risks 2>&1 | grep -q "в матрице нет уровня"; then ok "пропущенная клетка матрицы обнаружена"; else bad "пропущенная клетка матрицы не обнаружена"; fi
cp "$SANDBOX/ra.bak" "$REPO/assurance/risk-appetite.yaml"
cp "$SANDBOX/rk2.bak" "$REPO/assurance/registers/risks.yaml"

head_ "25. Карточка системы собирается и видит пробелы"
OUT=$("$HARNESS" card sys-cv-screening 2>&1 || true)
case "$OUT" in
  *"Классификация"*"Обязательные артефакты"*) ok "карточка собирается" ;;
  *) bad "карточка не собирается" ;;
esac
case "$OUT" in
  *"Чего не хватает по этой системе"*) ok "есть раздел пробелов" ;;
  *) bad "нет раздела пробелов" ;;
esac
case "$OUT" in
  *"Пробелов нет"*|*"пробелов нет"*) ok "на целых данных пробелов нет" ;;
  *) bad "на целых данных найдены пробелы" ;;
esac
# Список систем без идентификатора.
if "$HARNESS" card 2>&1 | grep -q "sys-support-bot"; then ok "список систем выводится"; else bad "список систем не выводится"; fi
# Пробел должен быть виден: убираем меру у риска.
cp "$REPO/assurance/registers/controls.yaml" "$SANDBOX/c9.bak"
python3 - "$REPO/assurance/registers/controls.yaml" <<'PYEOF'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
t = re.sub(r"  - id: ctl-injection-filter\n(?:.*\n)*?(?=  - id:)", "", t, count=1)
p.write_text(t, encoding="utf-8")
PYEOF
if "$HARNESS" card sys-support-bot 2>&1 | grep -q "нет ни одной меры"; then ok "риск без меры виден в карточке"; else bad "риск без меры не виден"; fi
cp "$SANDBOX/c9.bak" "$REPO/assurance/registers/controls.yaml"

head_ "26. Расхождение раскладки с манифестом ловится"
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
