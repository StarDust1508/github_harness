---
name: graph
description: Генерация XML-графа знаний о коде: структура, узлы, связи, правила актуализации.
source: перенесено из правил агента, переписано под нейтральную семантику
---

# Генерация AppGraph.xml — XML-граф знаний о коде

Граф служит высокоуровневой семантической картой проекта для навигации, понимания структуры, зависимостей и потоков управления.

## 1. Общая структура

```xml
<KnowledgeGraph>
  <ProjectName_Version_Info>
    <keywords>...</keywords>
    <terms>...</terms>
    <annotation>Описание проекта</annotation>
    <BusinessScenarios>
      ...
    </BusinessScenarios>

    <!-- Модули, классы, функции -->
    ...

    <ProjectCrossLinks TYPE="MODULE_INTERACTIONS_OVERVIEW">
      <!-- Высокоуровневые взаимодействия между модулями -->
    </ProjectCrossLinks>
  </ProjectName_Version_Info>
</KnowledgeGraph>
```

## 2. Именование тегов

1. **Уникальность** — каждое имя тега уникально в пределах всего документа
2. **Формирование:**
   - Точки (`.`) → подчёркивание (`_`)
   - Суффикс типа: `_py` (модуль), `_CLASS` (класс), `_FUNC` (функция), `_METHOD` (метод)
   - Пример: `utils.load_data` → `<utils_load_data_FUNC>`
3. **Атрибуты:** `FILE="..."` для модулей, `NAME="..."` для остальных сущностей

## 3. Структура тега сущности

1. **Атрибут `TYPE`** — обязателен:
   - Модули: `DATA_PROCESSING_MODULE`, `UI_MODULE`, `CLI_MODULE` и т.п.
   - Классы: `IS_CLASS_OF_MODULE`
   - Методы: `IS_METHOD_OF_CLASS`
   - Функции: `IS_FUNC_OF_MODULE`

2. **Дочерние элементы:**
   - `<keywords>` — ключевые слова для поиска
   - `<terms>` — доменные термины
   - `<annotation>` — описание сущности

3. **Вложенность:** иерархическая (модуль → класс → метод)

4. **Связи (`<CrossLinks>`):**
   ```xml
   <CrossLinks>
     <Link TARGET="Уникальное_Имя_Тега" TYPE="ТИП_СВЯЗИ" />
   </CrossLinks>
   ```
   Типы связей: `CALLS_METHOD`, `CREATES_INSTANCE_OF`, `SENDS_EVENT_TO`, `READS_DATA_FROM`, `WRITES_DATA_TO`

## 4. Полный пример

```xml
<KnowledgeGraph>
  <MyProject_v1_Info>
    <keywords>ETL, data processing, ML pipeline</keywords>
    <terms>DataFrame, Model, Pipeline</terms>
    <annotation>Проект обработки данных и обучения ML-моделей</annotation>

    <data_loader_py FILE="data_loader.py" TYPE="DATA_PROCESSING_MODULE">
      <keywords>load, CSV, SQLite</keywords>
      <annotation>Модуль загрузки данных из различных источников</annotation>

      <data_loader_DataLoader_CLASS NAME="DataLoader" TYPE="IS_CLASS_OF_MODULE">
        <annotation>Класс-загрузчик с поддержкой CSV и SQLite</annotation>

        <data_loader_DataLoader_load_csv_METHOD NAME="load_csv" TYPE="IS_METHOD_OF_CLASS">
          <annotation>Загрузка данных из CSV-файла в DataFrame</annotation>
          <CrossLinks>
            <Link TARGET="transformer_Transformer_transform_METHOD" TYPE="CALLS_METHOD" />
          </CrossLinks>
        </data_loader_DataLoader_load_csv_METHOD>
      </data_loader_DataLoader_CLASS>
    </data_loader_py>

    <transformer_py FILE="transformer.py" TYPE="DATA_PROCESSING_MODULE">
      <annotation>Модуль трансформации данных</annotation>

      <transformer_Transformer_CLASS NAME="Transformer" TYPE="IS_CLASS_OF_MODULE">
        <transformer_Transformer_transform_METHOD NAME="transform" TYPE="IS_METHOD_OF_CLASS">
          <annotation>Основной метод трансформации DataFrame</annotation>
        </transformer_Transformer_transform_METHOD>
      </transformer_Transformer_CLASS>
    </transformer_py>

    <ProjectCrossLinks TYPE="MODULE_INTERACTIONS_OVERVIEW">
      <Link TARGET="transformer_py" TYPE="DATA_FLOWS_TO" SOURCE="data_loader_py" />
    </ProjectCrossLinks>
  </MyProject_v1_Info>
</KnowledgeGraph>
```

## 5. Правила обновления

- Обновлять AppGraph.xml **после прохождения всех тестов** (финальный шаг фазы Code)
- При добавлении модуля — добавить тег модуля + CrossLinks
- При изменении связей — обновить CrossLinks и ProjectCrossLinks
- Графы могут быть локальными (в папке модуля) и глобальными (в корне проекта)
