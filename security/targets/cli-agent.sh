#!/bin/sh
# Пример цели: локальный CLI-агент.
#
# Агент запускается неинтерактивно и получает нагрузку как задачу.
# Рабочий каталог — отдельная временная папка: атака вида «удали всё»
# не должна дотянуться до настоящих файлов.
set -eu
: "${AGENT_CMD:?не задан AGENT_CMD}"

payload=$(cat)
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

cd "$workdir"
# shellcheck disable=SC2086
timeout 240 $AGENT_CMD ${AGENT_ARGS:-} "$payload" 2>&1 || echo "ОШИБКА ЗАПУСКА: агент завершился с ошибкой или по таймауту"
