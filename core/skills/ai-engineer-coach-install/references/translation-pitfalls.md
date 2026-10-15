# AI Engineer Coach — translation pitfalls

Lessons from translating Preact/htm UI strings to Russian.

## Sidebar vs page files — разные бандлы

- **Sidebar (панель навигации)**: `src/webview/panel-html.ts` — строки вида `Наблюдение`, `Панель`, `Хронология`. Компилируется в `dist/extension.js`.
- **Страницы (page-*.ts)**: Preact-компоненты. Компилируются в `dist/webview/app.js`.
- После перевода проверять ОБА бандла.

## esbuild Unicode escaping

В скомпилированном JS русские строки кодируются как `\u041D\u0430\u0431\u043B...` (нормально для esbuild).
Обычный `grep '[А-Яа-я]'` их НЕ находит. Проверять структурно:
```bash
grep -o 'nav-group-header">[^<]*' dist/extension.js
```

## Preact/htm template escaping — критический баг

**Плохо** (ломает esbuild):
```
placeholder=${\"{{message}}...\"}
```

**Хорошо** (рабочие варианты):
```
placeholder=" {{message}}..."                # plain string
placeholder=${'line1\nline2\nline3'}          # single-quoted JS string
```

Признаки плохих эскейпов: `\\\"` внутри html-шаблонов, `${\"...\"}` с экранированными кавычками, лишние `\` в конце строк.

## VS Code кеширует HTML панели

После `npm run build` ОБЯЗАТЕЛЬНО: `Cmd+Shift+P → Developer: Reload Window`.
Без этого пользователь видит старый кешированный интерфейс.

## Проверка после delegate_task

Если перевод делался через delegate_task:
1. Проверить `ls -la` даты файлов — пропущенные видны по старой дате
2. Запустить сборку — выявит синтаксические ошибки
3. Проверить оба бандла (extension.js + webview/app.js)
4. Сказать пользователю перезагрузить VS Code
