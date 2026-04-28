---
name: old-code
description: "Use ONLY when the user explicitly asks for old-code / 古法编程 / 原理反问 / 代码临摹 mode, or types /old-code. Slow-path Build mode that replaces normal AI code-drop: forces line-by-line principle questioning (default) or human transcription before code lands. Reads an existing plan file when present, hands off to /finalize when done. Do NOT auto-invoke."
---

# 古法编程（Old Code Mode）

Build 阶段的"慢档"。用来替代正常的"AI 一气呵成生成代码"——强制开发者要么**逐行能解释**，要么**亲手敲一遍**才让代码落地。

> 来源：https://github.com/zjw-swun/old-code（作者 zjw-swun，MIT 许可）。
> 本 SKILL.md 在原作基础上改造为可衔接 turbo / gstack 工作流的 Build 模式。

## 何时用 / 不用

- **用**：你想吃透某段关键逻辑（并发、锁、状态机、性能敏感路径），不希望 AI 直接糊一坨过来；想训练对代码坏味道的嗅觉；写要长期维护的核心模块。
- **不用**：纯样板代码、配置文件、UI 微调、glue code。这些跑 `/implement` 就够。
- **不要在 `/turboplan` 直接路由到的快路径上自动触发**——只在用户**明确要求**时入场。

## 在 turbo / gstack 工作流中的位置

```text
[Plan 阶段，照常走]
  /turboplan <任务>           → .turbo/plans/<slug>.md     (Plan / Spec 模式)
  或
  /gstack-office-hours        → 设计文档
  /turboplan + /gstack-autoplan → .turbo/plans/<slug>.md   (评审过的 plan)

[Build 阶段，二选一]
  快档：  /implement-plan  → /implement → /finalize         (默认，AI 主导)
  慢档：  /old-code        → 人工吃透 → /finalize           (本 skill)

[Ship 阶段，照常]
  /finalize 内部：polish → changelog → self-improve → commit + push + PR
```

关键：**old-code 不替代 plan 阶段，也不替代 finalize 阶段。** 它替换的是"`/implement-plan` 里 `/implement` 那一步把代码 AI-drop 到文件里"——把那一步换成人和 AI 协作的慢档，前后接口保持一致。

## 任务追踪

开始时用 `TaskCreate` 建以下任务：

1. Resolve task source（plan 文件 or 内联描述）
2. Run `/code-style` skill
3. Pick mode（反问 默认 / 临摹 显式）
4. Execute chosen mode
5. Hand off to `/finalize`

## Step 1: Resolve Task Source

按以下顺序确定本次实施的内容：

1. **显式 plan 路径** — 用户传了 `.turbo/plans/<slug>.md` 路径或 slug，按 `/implement-plan` 的规则 resolve
2. **唯一 plan 文件** — `.turbo/plans/*.md` 只有一个则用之
3. **最近修改的 plan** — 多个则用最新 mtime
4. **用户内联描述** — 如果用户在调用时直接描述了任务（"用古法实现这个 LRU 缓存"），把这段描述当 task source
5. **都没有** — halt，提示用户先 `/turboplan` 出一个 plan，或在调用时附上任务描述

确定来源后**说出来**再继续。

如果 source 是 plan 文件：完整读 plan 的 **Context Files / Pattern Survey / Implementation Steps / Verification** 四节，并读 Context Files 里列出的所有源文件。

**Plan 文件在本 skill 里只读。** 如果实施过程发现 plan 有问题，halt，让用户去跑 `/refine-plan`。

## Step 2: Run `/code-style` Skill

调用 `/code-style` 装载本仓库的 mirror / reuse / symmetry 风格规则。古法编程不豁免风格规则——慢不等于野。

## Step 3: Pick Mode

两种模式互斥，选一种：

| 模式 | 时机 | 谁来打字 | 默认 |
|---|---|---|---|
| **原理反问 (Principle Questioning)** | 代码生成**之后** | AI 生成 + 用户解释 | ✓ |
| **代码临摹 (Code Calligraphy)** | 代码生成**之前** | 用户逐行手动输入 | — |

选择规则：
- 用户说"反问模式" / "questioning" / "解释模式" → 原理反问
- 用户说"临摹模式" / "calligraphy" / "我自己敲" → 代码临摹
- 没说 → 用 `AskUserQuestion` 让用户选；解释二者区别

## Step 4a: 原理反问模式

> 改变"代码经过了屏幕，却没经过大脑"的现象。

流程：

1. 按 plan / 描述生成本轮代码块（一个函数 / 一个类 / 一段关键逻辑，不要一次几十行）
2. **不要直接落盘**。先在对话里展示，然后向用户提问：
   > "你能解释一下这段代码的原理和底层实现细节吗？包括：每行做什么、内存/CPU 行为、可能的边界和性能影响。"
3. 用户解释后：
   - 解释清晰准确 → 落盘（写入文件）→ 进入下一段
   - 解释有误或不清 → **不要给答案**，而是**反问**引导（"那这一行如果输入是空数组会怎样？"、"这里为什么用 mutex 而不是 atomic？"）
   - 同一段累计反问 ≥ 3 次 → 直接给完整解释 + 鼓励语，然后落盘
4. 重复直到 plan 的 Implementation Steps 全部落盘

**反问要严苛但建设性**：指出底层最佳实践偏差、引用相关原理（语言规范、CPU 内存模型、复杂度），不夸奖。

## Step 4b: 代码临摹模式

> 不再反问，专注理解和模仿输入。AI 接受用户模仿输入并校验大致正确性。

流程：

1. 按 plan / 描述生成本轮代码块
2. **逐行展示**（注释不计入行数），每行配上：
   - 这行做什么
   - 底层实现原理 / 内存行为 / 关键 API 选择理由
3. **用户敲完一行才允许看下一行**。等用户输入这一行的内容（用户可以复制也可以手敲，但要求他们至少念过一遍意义）
4. 校验大致正确性（不要求字符完全一致，要求语义等价 + 关键 API/类型/操作正确）：
   - 大致正确 → 进入下一行
   - 偏差大 → 提示偏差点，让用户重输
5. 整个代码块完成后，由用户自己复制最终内容落盘（或用户授权 AI 落盘）

## Step 5: Hand Off to `/finalize`

代码全部落盘后，**不要自己提交**。调用 `/finalize` skill：

- `/finalize` 跑 polish-code → update-changelog → self-improve → ship-it（commit + push + PR）
- 如果 plan 有 Verification section，`/finalize` 内部的 polish-code 会执行那些命令；古法编程的"理解"和 turbo 的"测试"叠加，不冲突

完成后用 `TaskUpdate` 把任务全部 mark 完成。

## Rules

- **永不自动触发。** 描述里"Do NOT auto-invoke"是硬规则。只在用户明示请求时入场（slash command 或自然语言"用古法实现"）。
- **不替代 plan 阶段。** 不要在没有 plan 的情况下让 AI 边想边写。如果用户没给 plan 也没给清晰描述，halt。
- **不绕过 `/code-style` 和 `/finalize`。** 慢档 ≠ 散漫，turbo 的纪律照常执行。
- **不修改 plan 文件。** 只读。
- **反问要质量不要数量。** 三次反问后还是不通就给答案——不是惩罚用户，是教学。
- **临摹模式校验语义等价，不抠字符。** 用户用 `i++` 还是 `i += 1`、用 `let` 还是 `const` 不影响——前提是该 const 的没改成 let。
- **每段代码块的粒度**：函数级或十几行内的关键逻辑。不要把一整个文件丢进反问/临摹，那不是慢档是折磨。
