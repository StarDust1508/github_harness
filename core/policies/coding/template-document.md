---
name: template-document
description: Шаблон проектного документа: структура, обязательные разделы, стиль.
source: перенесено из правил агента, переписано под нейтральную семантику
---

# Шаблон проектных документов

Для бизнес-требований, спецификаций и прочих проектных документов.

**Когнитивный прайминг:** `$DOCUMENT_PLAN` заставляет вербализировать структуру ДО генерации тяжёлого тела документа (защита от context drift). Парные теги `$START / $END` работают как контекстные свитчеры — фокус строго на одной секции за раз.

```markdown
$START_DOC_NAME

**PURPOSE:** [Цель документа]
**SCOPE:** [Область охвата]
**KEYWORDS:** [Домены знаний и паттерны]

$START_DOCUMENT_PLAN
### План Документа
<!-- Сначала сгенерировать план полностью, затем раскрывать каждый пункт -->

**SECTION_GOALS:**
- GOAL [Описание цели] => [ID_ЦЕЛИ]

**SECTION_USE_CASES:**
- USE_CASE [Описание сценария] => [ID_СЦЕНАРИЯ]

$END_DOCUMENT_PLAN

$START_SECTION_NAME
### [Название Секции]

$START_ARTIFACT_NAME
#### [Имя Артефакта]

**TYPE:** [GOAL | KEY_RESULT | USE_CASE | PRINCIPLE | DECISION | TOOL | DATA_FORMAT | NFR]
**KEYWORDS:** [домены знаний и паттерны]

$START_CONTRACT
**PURPOSE:** [ЧТО делает артефакт?]
**DESCRIPTION:** [Развернутое описание. Для USE_CASE — AAG-нотация.]
**RATIONALE:** [ПОЧЕМУ этот артефакт важен/выбран?]
**ACCEPTANCE_CRITERIA:** [Как понять, что реализовано правильно?]
$END_CONTRACT

$START_BODY
<!-- Специфичное тело артефакта -->
$END_BODY

$START_LINKS
**IMPLEMENTS:** [ID другого артефакта]
**IMPACTS:** [ID другого артефакта]
**REQUIRES:** [ID другого артефакта]
$END_LINKS

$END_ARTIFACT_NAME

$END_SECTION_NAME

$END_DOC_NAME
```
