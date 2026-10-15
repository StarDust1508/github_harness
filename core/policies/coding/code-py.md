---
name: code-py
description: Фаза реализации на Python: соглашения, структура модулей, обработка ошибок, типизация, тесты.
source: перенесено из правил агента, переписано под нейтральную семантику
---

# Фаза реализации (Code)

Главная задача — **исполнять**, а не планировать. Реализовать решения из фазы Architect, обеспечить семантическую полноту кода и тестов.

## 1. Рабочий процесс

### Шаг 1: STUDY_THE_PLAN
- Найти и изучить `DevelopmentPlan.md`, `business_requirements.md`, `requirements.txt`
- Не писать код, пока не понят архитектурный замысел и Data Flow

### Шаг 2: VERIFY_ENVIRONMENT
- Проверить версии библиотек (запустить тест или скрипт проверки)
- При ошибках — проверить, не отличаются ли версии. Искать примеры в проекте или запросить через Context7 MCP

### Шаг 3: IMPLEMENT_THE_CODE
- SFT-Прайминг: **сначала docstring** (минимум 1 абзац), потом код
- Keywords & Patterns: указывать `PATTERN(X)`, `CONCEPT(Y)` в контрактах
- Семантический экзоскелет: парные теги `START_BLOCK / END_BLOCK`
- LDD-логирование: формат `[IMP:1-10]`
- Zero-Context Survival: CONTRACT + KEYWORDS + RATIONALE — чтобы другой агент понял файл без документации
- **Устранение конфликтов разметки:** Если код генерируется с синтаксическими ошибками (особенно в отступах), это может быть вызвано конфликтом парных тегов. В этом случае **временно убрать парные теги внутри тела функции**, оставив START-END только на уровне функции

### Шаг 4: IMPLEMENT_TESTS
1. **Бэкенд (LDD Telemetry):** pytest + вывод логов `IMP:7-10` через print/caplog. Успешный PASSED ≠ корректность — нужна семантическая верификация трассы
2. **Smoke-тесты CLI:** через `subprocess.run`, проверка `exit 0`
3. **Headless UI-тесты:** вызов обработчиков напрямую, без сервера
4. **Разметка в тестах:** те же правила семантической разметки, что и в основном коде
5. **Атомарность:** отдельные тесты для отдельных функциональных элементов
6. **Интегрирующий тест:** полный проход сценария для проверки связей между модулями

### Шаг 5: CHECK_LOG
- Прочитать лог целиком, проверить на логические ошибки, пропущенные тестами
- Если найдены — доработать тесты, пройти процедуру заново

### Шаг 6: LAUNCHER_DESIGN
- Lazy import тяжёлых библиотек внутри `main()`
- `try-except KeyboardInterrupt` для серверов
- Для Gradio: `inbrowser=True`
- Логирование в файл + stdout (StreamHandler)

### Шаг 7: UPDATE_THE_GRAPH
- Обновить `AppGraph.xml` — **строго финальный шаг**, после прохождения всех тестов

## 2. Семантический шаблон файла

```python
# FILE: path/to/file.py
# VERSION: 1.0.0
# START_MODULE_CONTRACT:
# PURPOSE: Краткое описание ответственности модуля
# SCOPE: Основные функциональные области
# INPUT: Входные данные модуля
# OUTPUT: Что модуль предоставляет системе
# KEYWORDS: DOMAIN(X): ...; CONCEPT(Y): ...; TECH(Z): ...
# LINKS: USES_API(X): ...; READS_DATA_FROM(Y): ...
# END_MODULE_CONTRACT
#
# START_RATIONALE: (опционально, рекомендуется)
# Q: Почему реализовано именно так?
# A: Обоснование решения, ограничения среды.
# END_RATIONALE
#
# START_INVARIANTS: (опционально, для модулей со стейтом)
# - Условие/гарантия 1
# END_INVARIANTS
#
# START_CHANGE_SUMMARY:
# LAST_CHANGE: [v1.0.0 - Описание]
# PREV_CHANGE_SUMMARY: [предыдущая версия]
# END_CHANGE_SUMMARY
#
# START_MODULE_MAP:
# FUNC [Вес][Описание] => имя_функции
# END_MODULE_MAP
#
# START_USE_CASES: (AAG: Actor -> Action -> Goal)
# - имя: Кто -> Что делает -> Какой результат
# END_USE_CASES

import ...

# START_FUNCTION_function_name
# START_CONTRACT:
# PURPOSE: Описание ответственности функции
# INPUTS:
# - описание => имя: Тип
# OUTPUTS:
# - Тип - Описание
# SIDE_EFFECTS: Описание побочных эффектов
# KEYWORDS: PATTERN(X): ...; CONCEPT(Y): ...
# COMPLEXITY_SCORE: N [Оценка сложности 1-10]
# END_CONTRACT
def function_name(...):
    """
    Развернутый docstring (минимум 1 абзац).
    Описание логики функции перед кодом — обязательно.
    Это активирует наиболее надёжные веса генерации.
    """

    # START_BLOCK_NAME: Описание блока
    logger.debug(f"[Flow][IMP:4][function_name][BLOCK_NAME][Params] ... [INFO]")
    ...code...
    # END_BLOCK_NAME

    # START_BLOCK_RETURN: Возврат результата
    logger.info(f"[BeliefState][IMP:9][function_name][RETURN][ReturnData] ... [VALUE]")
    return result
    # END_BLOCK_RETURN
# END_FUNCTION_function_name
```

## 3. One-Shot пример (полный файл с разметкой)

```python
# FILE: tools/check_ai_libs.py
# VERSION: 1.0.0
# START_MODULE_CONTRACT:
# PURPOSE: Проверка наличия установленных целевых библиотек, наиболее эффективных для обучения ИИ.
# SCOPE: Интроспекция системного окружения, проверка зависимостей.
# INPUT: Отсутствует (работает с текущим окружением Python).
# OUTPUT: Словарь со статусами установки запрошенных модулей.
# KEYWORDS: DOMAIN(8): Environment; CONCEPT(7): DependencyCheck; TECH(9): PythonImport
# LINKS: USES_API(8): importlib
# END_MODULE_CONTRACT
#
# START_INVARIANTS:
# - Функция check_all_libraries ВСЕГДА возвращает словарь.
# - Словарь ВСЕГДА содержит все библиотеки из целевого списка в качестве ключей.
# END_INVARIANTS
#
# START_RATIONALE:
# Q: Почему используется importlib.util.find_spec, а не прямые import выражения?
# A: Прямой импорт (import numpy) вызовет ImportError и прервёт скрипт на первой же
#    отсутствующей библиотеке. find_spec позволяет безопасно собрать полную картину окружения.
# END_RATIONALE
#
# START_CHANGE_SUMMARY:
# LAST_CHANGE: [v1.0.0 - Первичное создание модуля проверки системных и ML-библиотек.]
# END_CHANGE_SUMMARY
#
# START_MODULE_MAP:
# FUNC 10[Проверяет наличие списка целевых ИИ библиотек в окружении] => check_all_libraries
# END_MODULE_MAP
#
# START_USE_CASES:
# - check_all_libraries: System (Startup) -> VerifyEnvironmentDependencies -> EnvironmentStatusReported
# END_USE_CASES

import logging
import importlib.util

logger = logging.getLogger(__name__)

# START_FUNCTION_check_all_libraries
# START_CONTRACT:
# PURPOSE: Итерируется по спискам системных и ML-библиотек, проверяя их доступность.
# INPUTS: Нет
# OUTPUTS:
# - dict - Словарь, где ключ - имя библиотеки (str), значение - статус установки (bool)
# SIDE_EFFECTS: Отсутствуют.
# KEYWORDS: PATTERN(6): Iterator; CONCEPT(8): Introspection
# COMPLEXITY_SCORE: 5 [Средняя сложность из-за итерации и обработки исключений.]
# END_CONTRACT
def check_all_libraries() -> dict:
    """
    Функция выполняет интроспекцию текущего окружения Python для поиска предустановленных библиотек.
    Она использует importlib для безопасной проверки наличия пакетов без их фактической загрузки в память,
    что предотвращает побочные эффекты и ошибки импорта. Результат возвращается в виде словаря
    для последующего анализа системной готовности к задачам ML.
    """

    # START_BLOCK_INITIALIZE_LISTS: Формирование списков целевых библиотек
    system_libs = [
        "math", "random", "statistics", "decimal", "datetime", "time", "re",
        "os", "sys", "csv", "json", "sqlite3", "xml.etree.ElementTree",
        "configparser", "pickle", "base64", "hashlib", "collections",
        "itertools", "functools", "logging", "argparse", "typing", "uuid",
        "zipfile", "tarfile", "gzip", "zlib", "shutil", "tempfile"
    ]
    ml_libs = [
        "numpy", "pandas", "scipy", "sklearn", "matplotlib", "seaborn",
        "h5py", "openpyxl", "requests", "lxml", "PIL", "reportlab",
        "sympy", "dateutil", "pytz"
    ]
    all_libs = system_libs + ml_libs
    result_map = {}

    logger.debug(f"[VarCheck][IMP:4][check_all_libraries][INITIALIZE_LISTS][Params] Списки инициализированы. Всего библиотек: {len(all_libs)} [INFO]")
    # END_BLOCK_INITIALIZE_LISTS

    # START_BLOCK_VERIFY_DEPENDENCIES: Итерация и безопасная проверка спецификаций импорта
    for lib_name in all_libs:
        try:
            spec = importlib.util.find_spec(lib_name)
            is_installed = spec is not None
            result_map[lib_name] = is_installed

            logger.debug(f"[LibCheck][IMP:3][check_all_libraries][VERIFY_DEPENDENCIES][ConditionCheck] Пакет {lib_name} найден: {is_installed} [{'SUCCESS' if is_installed else 'FAIL'}]")
        except Exception as e:
            # BUG_FIX_CONTEXT: Ранее ловили ImportError, но find_spec может кидать ValueError на кривых путях. Расширили до Exception.
            result_map[lib_name] = False
            logger.critical(f"[SystemError][IMP:10][check_all_libraries][VERIFY_DEPENDENCIES][ExceptionEnrichment] Сбой при поиске {lib_name}. Local vars: lib_name={lib_name}. Err: {e} [FATAL]")
    # END_BLOCK_VERIFY_DEPENDENCIES

    # START_BLOCK_RETURN_RESULTS: Подведение итогов и возврат
    installed_count = sum(result_map.values())
    logger.info(f"[BeliefState][IMP:9][check_all_libraries][RETURN_RESULTS][ReturnData] Установлено {installed_count} из {len(all_libs)} библиотек. [VALUE]")

    return result_map
    # END_BLOCK_RETURN_RESULTS
# END_FUNCTION_check_all_libraries
```

## 4. Log Driven Development (LDD)

Формат строки лога:
```
f"[{КЛАССИФИКАТОР}][IMP:{1-10}][{ИМЯ_ФУНКЦИИ}][{ИМЯ_БЛОКА}][{ТИП_ОПЕРАЦИИ}] Описание [{СТАТУС}]"
```

Шкала IMPORTANCE:
- `IMP:1-3` (Trace) — дампы переменных в циклах
- `IMP:4-6` (Flow) — начало/конец блоков, ветвления
- `IMP:7-8` (I/O & Boundary) — обращение к БД, API, файлам
- `IMP:9-10` (Business Logic & AI Belief) — проверка гипотез, критические ошибки

При падении сложных функций — Exception Enrichment: логировать локальный контекст на `IMP:10`.
