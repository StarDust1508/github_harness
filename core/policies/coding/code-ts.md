---
name: code-ts
description: Фаза реализации на TypeScript/React/Node: соглашения, структура, типизация, работа с состоянием и эффектами.
source: перенесено из правил агента, переписано под нейтральную семантику
---

# Фаза реализации (Code) — TypeScript / React / Node

Адаптация `code.md` под фронтенд-стек: **TS + React + Vite + Vitest + Playwright + Node/Express/WS**.
Python-вариант лежит в `code-py.md` (для скриптов/ETL/MCP на Python, если появятся).

Главная задача — **исполнять**, а не планировать. Реализовать решения из фазы Architect, обеспечить семантическую полноту кода и тестов.

## 1. Рабочий процесс

### Шаг 1: STUDY_THE_PLAN
- Найти и изучить `DevelopmentPlan.md`, `business_requirements.md`, `package.json`
- Проверить `tsconfig.json` (strict mode, paths), `vite.config.ts`, `.env.example`
- Не писать код, пока не понят архитектурный замысел и Data Flow

### Шаг 2: VERIFY_ENVIRONMENT
- `node -v`, `pnpm -v` (или npm/yarn — как в проекте)
- `pnpm install` → `pnpm typecheck` → `pnpm lint` перед любыми правками
- При ошибках — проверить версии пакетов, искать примеры в проекте, использовать Context7 MCP для актуальной доки библиотек

### Шаг 3: IMPLEMENT_THE_CODE
- **SFT-Прайминг:** сначала **TSDoc/JSDoc** (минимум 1 абзац), потом код
- **Keywords & Patterns:** указывать `PATTERN(X)`, `CONCEPT(Y)` в контрактах
- **Семантический экзоскелет:** парные комментарии `// START_BLOCK_ / // END_BLOCK_`
- **Структурное логирование:** вместо голого `console.log` — prefix-формат `[Scope][IMP:N][fn][block][op] msg [STATUS]` (см. §4)
- **Zero-Context Survival:** CONTRACT + KEYWORDS + RATIONALE — чтобы другой агент понял файл без документации
- **Устранение конфликтов разметки:** если TS-компилятор ругается из-за комментариев внутри JSX — временно убрать парные теги внутри тела, оставив START-END только на уровне функции/компонента

### Шаг 4: IMPLEMENT_TESTS

Минимум три уровня — см. §5 подробнее:

1. **Unit (Vitest)** — чистые функции, хуки, утилиты. Логи `IMP:7-10` проверяются через `vi.spyOn(console, 'debug')` или кастомный logger
2. **Component (Vitest + React Testing Library)** — рендер компонента, `userEvent`, `screen.findByRole` и т.п.
3. **E2E (Playwright)** — критические сценарии (auth, WS-коннект, чекаут). Headless по умолчанию
4. **Контракт-тесты WS/API (zod/io-ts)** — если есть шины событий, валидировать схемы на вход и выход

Правила:
- **Разметка в тестах:** те же START-END теги, что и в основном коде
- **Атомарность:** один `it(...)` — один функциональный элемент
- **Интегрирующий тест:** полный проход user-flow для проверки связей между модулями (Playwright)
- **Успешный PASSED ≠ корректность.** Читать trace-логи — семантическая верификация трассы

### Шаг 5: CHECK_LOG
- `pnpm test -- --reporter=verbose` или смотреть `playwright-report/`
- Если тест зелёный, но лог не соответствует контракту — это подгонка, доработать тест

### Шаг 6: LAUNCHER_DESIGN
- **Node-скрипты:** `tsx script.ts` вместо `ts-node` (быстрее, нулевая конфигурация). Для CLI-утилит — `commander` или `cac`
- **Dev-сервер:** `vite` / `next dev`. Never коммитить `localhost:3000` захардкоженным — брать из `.env`
- **Lazy-loading тяжёлых модулей:** `const mod = await import('heavy-lib')` внутри обработчика, не на модульном уровне
- **Graceful shutdown (Node/WS-серверы):** `process.on('SIGINT', ...)` с закрытием сокетов и сливом outbox

### Шаг 7: UPDATE_THE_GRAPH
- Обновить `AppGraph.xml` (см. `graph.md`, раздел про TS-суффиксы: `_tsx`, `_COMPONENT`, `_HOOK`, `_STORE`) — **строго финальный шаг**, после прохождения всех тестов

## 2. Семантический шаблон файла (TS/React)

```typescript
// FILE: src/features/auth/useLoginForm.ts
// VERSION: 1.0.0
// START_MODULE_CONTRACT:
// PURPOSE: Хук управления формой логина — валидация, submit, обработка ошибок API.
// SCOPE: Auth flow, form state, server error mapping.
// INPUT: Начальные значения формы (email, password).
// OUTPUT: { values, errors, isSubmitting, handleSubmit, register }.
// KEYWORDS: DOMAIN(8): Auth; CONCEPT(7): FormState; TECH(6): ReactHookForm, Zod
// LINKS: USES_API(8): /api/auth/login; READS_STORE_FROM(5): useAuthStore
// END_MODULE_CONTRACT
//
// START_RATIONALE:
// Q: Почему react-hook-form + zod, а не formik?
// A: RHF не ре-рендерит родителя на каждый keystroke (uncontrolled inputs + refs),
//    а zod даёт типы из схемы одной строкой (z.infer<typeof schema>).
// END_RATIONALE
//
// START_INVARIANTS:
// - isSubmitting === true между onSubmit и резолвом промиса.
// - errors.server очищается при следующем submit.
// END_INVARIANTS
//
// START_CHANGE_SUMMARY:
// LAST_CHANGE: [v1.0.0 - Первичная реализация login-формы с zod-валидацией]
// END_CHANGE_SUMMARY
//
// START_MODULE_MAP:
// HOOK 10[Управление состоянием формы + submit] => useLoginForm
// FUNC 7[Маппинг API-ошибок в поля формы] => mapServerErrors
// END_MODULE_MAP
//
// START_USE_CASES:
// - useLoginForm: User -> SubmitsCredentials -> AuthenticatedSession
// END_USE_CASES

import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { log } from '@/lib/log';
import { loginApi } from '@/api/auth';

const schema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
});
type LoginValues = z.infer<typeof schema>;

// START_FUNCTION_useLoginForm
// START_CONTRACT:
// PURPOSE: Инкапсулирует form-state, валидацию и submit для экрана логина.
// INPUTS:
//   - Начальные значения формы => defaults?: Partial<LoginValues>
// OUTPUTS:
//   - { register, handleSubmit, errors, isSubmitting, serverError }
// SIDE_EFFECTS: Вызывает POST /api/auth/login, пишет в useAuthStore.
// KEYWORDS: PATTERN(7): CustomHook; CONCEPT(8): FormState; TECH(8): ReactHookForm
// COMPLEXITY_SCORE: 5 [Стандартный form-hook с API-интеграцией]
// END_CONTRACT
export function useLoginForm(defaults?: Partial<LoginValues>) {
  /**
   * Хук login-формы: строит контролы через react-hook-form с zod-валидацией,
   * оборачивает submit в try/catch для маппинга 4xx-ошибок API в конкретные поля,
   * и сохраняет токен в auth-store при успехе. 401 из API → errors.server.
   */

  const [serverError, setServerError] = useState<string | null>(null);
  const rhf = useForm<LoginValues>({ resolver: zodResolver(schema), defaultValues: defaults });

  // START_BLOCK_SUBMIT: Submit + маппинг серверных ошибок
  const handleSubmit = rhf.handleSubmit(async (values) => {
    log.debug('[Flow][IMP:4][useLoginForm][SUBMIT][START] payload prepared [INFO]');
    setServerError(null);
    try {
      const res = await loginApi(values);
      log.info('[BeliefState][IMP:9][useLoginForm][SUBMIT][RETURN] login ok [VALUE]');
      return res;
    } catch (e) {
      // BUG_FIX_CONTEXT: Раньше ловили только AxiosError и теряли network-ошибки.
      // Переключились на instanceof Error + structured field на e.code.
      log.error(`[SystemError][IMP:10][useLoginForm][SUBMIT][ExceptionEnrichment] ${e instanceof Error ? e.message : String(e)} [FATAL]`);
      setServerError(e instanceof Error ? e.message : 'Unknown error');
    }
  });
  // END_BLOCK_SUBMIT

  return { ...rhf, handleSubmit, serverError };
}
// END_FUNCTION_useLoginForm
```

## 3. Семантический шаблон React-компонента

```tsx
// FILE: src/features/auth/LoginForm.tsx
// VERSION: 1.0.0
// START_MODULE_CONTRACT:
// PURPOSE: Презентационный компонент login-формы.
// SCOPE: UI только — вся логика в useLoginForm.
// INPUT: onSuccess?: () => void (колбек после успеха).
// OUTPUT: JSX.
// KEYWORDS: DOMAIN(8): Auth; CONCEPT(6): PresentationalComponent; TECH(7): React, Tailwind
// LINKS: USES_HOOK(9): useLoginForm; USES_UI_KIT(6): Button, Input
// END_MODULE_CONTRACT

import { useLoginForm } from './useLoginForm';
import { Input } from '@/ui/Input';
import { Button } from '@/ui/Button';

// START_COMPONENT_LoginForm
// START_CONTRACT:
// PURPOSE: Рендерит форму, делегирует всю логику хуку. Нет локального стейта.
// PROPS:
//   - onSuccess?: () => void - вызывается после успешного логина
// KEYWORDS: PATTERN(7): ContainerPresentational
// COMPLEXITY_SCORE: 3 [Чистая презентация]
// END_CONTRACT
export function LoginForm({ onSuccess }: { onSuccess?: () => void }) {
  const { register, handleSubmit, formState: { errors, isSubmitting }, serverError } = useLoginForm();

  return (
    <form onSubmit={(e) => { handleSubmit(e).then(() => onSuccess?.()); }} className="space-y-4">
      <Input {...register('email')} label="Email" error={errors.email?.message} />
      <Input {...register('password')} type="password" label="Password" error={errors.password?.message} />
      {serverError && <p className="text-red-500">{serverError}</p>}
      <Button type="submit" disabled={isSubmitting}>Войти</Button>
    </form>
  );
}
// END_COMPONENT_LoginForm
```

## 4. Log Driven Development (LDD) в JS/TS

В JS-экосистеме нет единого `logging`-модуля как в Python, поэтому:

- **Фронт:** тонкая обёртка `@/lib/log` над `console.*` + опционально отправка в Sentry/Logtail
- **Бэк (Node):** `pino` (быстрый) или `winston`. Формат — всегда JSON в prod, красивый в dev через `pino-pretty`

**Формат строки:**
```
`[${КЛАССИФИКАТОР}][IMP:${1-10}][${fn}][${block}][${type}] msg [${STATUS}]`
```

Пример обёртки (`src/lib/log.ts`):
```typescript
const isDev = import.meta.env.DEV;
export const log = {
  debug: (msg: string, ctx?: object) => isDev && console.debug(msg, ctx ?? ''),
  info:  (msg: string, ctx?: object) => console.info(msg, ctx ?? ''),
  warn:  (msg: string, ctx?: object) => console.warn(msg, ctx ?? ''),
  error: (msg: string, ctx?: object) => console.error(msg, ctx ?? ''),
};
```

Шкала IMPORTANCE — та же, что в `code-py.md`:
- `IMP:1-3` (Trace) — дампы переменных в циклах
- `IMP:4-6` (Flow) — начало/конец блоков, ветвления, render-старт
- `IMP:7-8` (I/O & Boundary) — fetch, WS-событие, Zustand action
- `IMP:9-10` (Business Logic & AI Belief) — проверка гипотез, критические ошибки

При падении — **Exception Enrichment:** логировать локальный контекст на `IMP:10` (значения props, state, params).

## 5. Стратегия тестирования

### Unit (Vitest)
```typescript
import { describe, it, expect, vi } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useLoginForm } from './useLoginForm';

// START_TEST_SUITE_useLoginForm
describe('useLoginForm', () => {
  it('[Flow][IMP:7] валидирует email до submit', async () => {
    const { result } = renderHook(() => useLoginForm());
    await act(() => result.current.handleSubmit());
    expect(result.current.formState.errors.email).toBeDefined();
  });
});
// END_TEST_SUITE_useLoginForm
```

### Component (RTL)
```typescript
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { LoginForm } from './LoginForm';

it('показывает server error при 401', async () => {
  // mock loginApi → reject
  render(<LoginForm />);
  await userEvent.type(screen.getByLabelText(/email/i), 'a@b.co');
  await userEvent.type(screen.getByLabelText(/password/i), '12345678');
  await userEvent.click(screen.getByRole('button', { name: /войти/i }));
  expect(await screen.findByText(/invalid/i)).toBeVisible();
});
```

### E2E (Playwright)
```typescript
import { test, expect } from '@playwright/test';

test('login golden path', async ({ page }) => {
  await page.goto('/login');
  await page.getByLabel('Email').fill('test@hunter.local');
  await page.getByLabel('Password').fill('12345678');
  await page.getByRole('button', { name: 'Войти' }).click();
  await expect(page).toHaveURL(/\/training/);
});
```

### Контракт-тесты WS/API
Любая схема событий — через `zod`. Рантайм-валидация на границе (WS `onmessage`, API-ответ). Тест: взять фикстуру JSON → `schema.parse()` → не должно бросить.

## 6. Специфика React/Zustand

- **Не мутировать state.** Zustand: `set((s) => ({ ...s, field: value }))`, в React: новые массивы/объекты
- **`useEffect` cleanup обязателен** для WS-коннектов, таймеров, observers
- **Error boundaries** на уровне фичи (не только root) — ловят SSR/рендер-ошибки без падения всего экрана
- **Suspense + lazy** для крупных роутов
- **Никаких `any` в public API** компонентов/хуков. `unknown` + типгард в боундари

## 7. Anti-patterns (фронт-специфика)

- `useEffect` с async-функцией напрямую (`useEffect(async () => ...)`) — React ругается, писать `useEffect(() => { (async () => ...)() }, [])`
- Завязка layout-эффектов на `window` без проверки SSR — в Next.js упадёт на билде
- Fetch без AbortController при unmount — утечки и race conditions
- Стейт в `useRef` вместо `useState` когда нужен ре-рендер
- Глобальные стили, ломающие инкапсуляцию Tailwind-утилит
