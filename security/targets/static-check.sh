#!/bin/sh
# Пример проверки файлов: то, что не видно в диалоге.
#
# Это не атака, а осмотр. Обвязка запускает скрипт один раз и записывает
# результат как одну проверку.
set -eu
: "${SCAN_ROOT:?не задан SCAN_ROOT}"

echo "=== осмотр: $SCAN_ROOT ==="

echo "--- промпты и инструкции в открытом виде:"
find "$SCAN_ROOT" -maxdepth 4 -type f \( -name "*.md" -o -name "*.txt" \) \
  -path "*prompt*" 2>/dev/null | head -20 || true

echo "--- ключи в файлах конфигурации:"
grep -rlE '(sk-[A-Za-z0-9]{16,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16})' \
  "$SCAN_ROOT" --include="*.json" --include="*.yaml" --include="*.yml" --include="*.toml" 2>/dev/null | head -20 || true

echo "--- подтверждение человеком и права инструментов:"
grep -rnE '(auto_?approve|require_?confirmation|danger-?full-?access|yolo)' \
  "$SCAN_ROOT" --include="*.json" --include="*.yaml" --include="*.yml" --include="*.toml" 2>/dev/null | head -20 || true

echo "=== осмотр завершён ==="
