---
name: template-dev-plan
description: Шаблон плана разработки: разделы, уровень детализации, критерии приёмки.
source: перенесено из правил агента, переписано под нейтральную семантику
---

# Шаблон DevelopmentPlan.md

**Когнитивный прайминг:** Draft Code Graph и Data Flow — ортогональные семантические проекции. XML-граф настраивает распределённое внимание, декларируя структурные якоря (от общего к частному). Data Flow заставляет "проиграть" алгоритм во времени. Согласование структурной и процессной проекций снижает вероятность логических ошибок.

```markdown
$START_DEV_PLAN

**PURPOSE:** [Цель плана]

### 1. Draft Code Graph

\`\`\`xml
<DraftCodeGraph>
  <Component_py FILE="path/to/file.py" TYPE="TYPE">
    <annotation>Описание</annotation>
    <Component_Class_CLASS NAME="MyClass" TYPE="IS_CLASS_OF_MODULE">
      <annotation>Описание класса</annotation>
      <Component_Class_method_METHOD NAME="method" TYPE="IS_METHOD_OF_CLASS">
        <annotation>Описание метода</annotation>
        <CrossLinks>
          <Link TARGET="Other_method_METHOD" TYPE="CALLS_METHOD" />
        </CrossLinks>
      </Component_Class_method_METHOD>
    </Component_Class_CLASS>
  </Component_py>
</DraftCodeGraph>
\`\`\`

### 2. Step-by-step Data Flow
1. **Шаг 1:** [Описание]
2. **Шаг 2:** [Трансформация данных]
3. **Шаг 3:** [Результат]

### 3. Acceptance Criteria
- [ ] Критерий 1
- [ ] Критерий 2

$END_DEV_PLAN
```
