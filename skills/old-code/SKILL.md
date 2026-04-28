---
name: old-code
description: "Use ONLY when the user explicitly asks for 古法编程 mode. Slow-path Build mode that replaces normal AI code-drop: forces line-by-line principle questioning (default) or human transcription before code lands. Optional TDD rhythm (test-first → red → impl → green) auto-routed by content type, opt-out by user. Reads an existing plan file when present, hands off to /finalize when done. Do NOT auto-invoke."
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
  /finalize 内部：polish → changelog → self-improve → /ship 或 /split-and-ship
```

关键：**old-code 不替代 plan 阶段，也不替代 finalize 阶段。** 它替换的是"`/implement-plan` 里 `/implement` 那一步把代码 AI-drop 到文件里"——把那一步换成人和 AI 协作的慢档，前后接口保持一致。

## 任务追踪

开始时用 `TaskCreate` 建以下任务：

1. Resolve task source（plan 文件 or 内联描述）
2. Run `/code-style` skill
3. Pick mode and TDD rhythm（mode 二选一 + TDD on/off 由内容路由）
4. Execute chosen mode（按 rhythm 决定单轮 impl 或 test→impl 双轮）
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

## Step 3: Pick Mode and TDD Rhythm

两个独立选择，正交可组合：
- **Mode**（写代码的节奏）：原理反问 vs 代码临摹（互斥）
- **TDD Rhythm**（要不要先写测试）：on / off（按内容路由，不是按偏好）

### 3a. Mode 选择

| 模式 | 时机 | 谁来打字 | 默认 |
|---|---|---|---|
| **原理反问 (Principle Questioning)** | 代码生成**之后** | AI 生成 + 用户解释 | ✓ |
| **代码临摹 (Code Calligraphy)** | 代码生成**之前** | 用户逐行手动输入 | — |

选择规则：
- 用户说"反问模式" / "questioning" / "解释模式" → 原理反问
- 用户说"临摹模式" / "calligraphy" / "我自己敲" → 代码临摹
- 没说 → 用 `AskUserQuestion` 让用户选；解释二者区别

### 3b. TDD Rhythm 决策（**不要无脑开**）

按代码内容路由，不是按个人偏好。先在 task source 里识别本轮要写的内容类型，再按下表给默认值：

| 内容类型 | TDD 默认 | 理由 |
|---|---|---|
| 算法 / 缓存 / 锁 / 状态机 / parser / 数据转换 / 协议实现 | **on** | 边界明确、输出可枚举；先写 fail 测试给 AI 一份机器可执行的 spec，比顺着自然语言 spec 写 impl 少 hallucinate |
| 复杂业务规则（折扣、税务、权限矩阵、定价、库存计算） | **on** | 输出可枚举但比纯算法多几个 case；规则先变测试，impl 顺着写 |
| HTTP handler / API endpoint / DB query 层 | **边界** | happy path 测试有用，但严格 TDD 节奏收益边际——用 `AskUserQuestion` 让用户决定 |
| UI 组件 / 视觉调整 / 动画 / 样式 | **off** | 视觉对错靠肉眼，TDD 会逼出一堆没意义的 snapshot test |
| 配置 / 环境变量 / glue code / 第三方 SDK 包装层 | **off** | 测试 = 重写 mock，比写代码贵 |
| 一次性脚本 / migration / 探索式原型 | **off** | 设计还没固化，TDD 把没定的东西提前固化是反生产力 |

**用户显式偏好覆盖默认**：
- "用 TDD" / "tdd" / "test-first" / "测试驱动" → 强制 on
- "跳过 TDD" / "no tdd" / "skip tdd" / "不要 TDD" → 强制 off

确定 rhythm 后**说出来**：
> "本轮按 [内容类型]，TDD rhythm 默认 [on/off]，理由 [...]。要切换说一声。"

### 3c. 降级情形

如果项目里没有可执行的测试框架（package.json 无 test 脚本 / Cargo.toml 无 [test] / pyproject.toml 没装 pytest 或 unittest 等）→ **强制关闭** TDD 并告知用户：

> "TDD 节奏需要可跑的测试。当前项目没有检测到 test runner，本次跳过 TDD。如果要 TDD，先装一个测试框架再回来。"

降级判断快速命令（按项目类型挑一个跑，看有没有合理输出）：
- Node：`jq -r '.scripts.test // empty' package.json` 或 grep `vitest|jest|mocha` package.json
- Python：grep `pytest|unittest` pyproject.toml / requirements*.txt / setup.py
- Rust / Go：默认有内置 test，跳过此检查
- 其它：fallback 让用户确认

## Step 4a: 原理反问模式

> 改变"代码经过了屏幕，却没经过大脑"的现象。

### TDD off（默认 impl-only 流程）

1. 按 plan / 描述生成本轮代码块（一个函数 / 一个类 / 一段关键逻辑，不要一次几十行）
2. **不要直接落盘**。先在对话里展示，然后向用户提问：
   > "你能解释一下这段代码的原理和底层实现细节吗？包括：每行做什么、内存/CPU 行为、可能的边界和性能影响。"
3. 用户解释后：
   - 解释清晰准确 → 落盘（写入文件）→ 进入下一段
   - 解释有误或不清 → **不要给答案**，而是**反问**引导（"那这一行如果输入是空数组会怎样？"、"这里为什么用 mutex 而不是 atomic？"）
   - 同一段累计反问 ≥ 3 次 → 直接给完整解释 + 鼓励语，然后落盘
4. 重复直到 plan 的 Implementation Steps 全部落盘

### TDD on（test-first 双轮流程）

每段逻辑跑两轮反问，先测试后实现：

1. **测试轮：** 按 plan / 描述生成本段的失败测试（覆盖核心 case + 边界 + 错误路径）
   - **不要直接落盘**。展示测试代码，向用户提问：
     > "这测试在测什么？为什么这几个 case 是边界？还有哪些 case 漏了？"
   - 解释清晰 → 测试落盘 → **真跑一遍测试，确认 red**（失败本身就是测试有效的证据）
   - 跑出来意外 green（说明测试不充分或目标已存在）→ halt 反问，不要硬往下走
2. **实现轮：** 生成让上面测试 pass 的最小 impl
   - **不要直接落盘**。展示 impl，向用户提问：
     > "为什么这样实现？时间/空间复杂度？还有更简的写法吗？"
   - 解释清晰 → impl 落盘 → **真跑一遍测试，确认 green**
   - 跑出来仍 red → 看是测试错了还是 impl 错了，反问引导用户找出来
3. （可选）refactor 轮：测试已经绿，结构上能不能更对称 / 复用现有 utility / 减少重复——做 refactor 改动，再跑测试确认仍 green
4. 重复测试→实现两轮直到 plan 的 Implementation Steps 全部落盘

**反问要严苛但建设性**：指出底层最佳实践偏差、引用相关原理（语言规范、CPU 内存模型、复杂度），不夸奖。

**TDD on 的硬约束**：测试 red → green 必须**真跑过测试**（用 Bash 工具执行 verification 命令），AI 不能脑补"测试通过"。看不到 green 输出就不算这一轮成功。

## Step 4b: 代码临摹模式

> 不再反问，专注理解和模仿输入。AI 接受用户模仿输入并校验大致正确性。

### TDD off（默认 impl-only 流程）

1. 按 plan / 描述生成本轮代码块
2. **逐行展示**（注释不计入行数），每行配上：
   - 这行做什么
   - 底层实现原理 / 内存行为 / 关键 API 选择理由
3. **用户敲完一行才允许看下一行**。等用户输入这一行的内容（用户可以复制也可以手敲，但要求他们至少念过一遍意义）
4. 校验大致正确性（不要求字符完全一致，要求语义等价 + 关键 API/类型/操作正确）：
   - 大致正确 → 进入下一行
   - 偏差大 → 提示偏差点，让用户重输
5. 整个代码块完成后，由用户自己复制最终内容落盘（或用户授权 AI 落盘）

### TDD on（test-first 双轮临摹）

每段逻辑临摹两次，先测试后实现：

1. **测试轮：** 生成失败测试代码，按上面步骤 2-5 逐行临摹（每行附说明：这个 assertion 在测什么、为什么这是边界）
2. 测试代码全部落盘后 → **真跑一遍测试，确认 red**
3. **实现轮：** 生成让测试 pass 的最小 impl，按上面步骤 2-5 逐行临摹（每行附说明：这一行算法 / 内存 / API 选择理由）
4. impl 全部落盘后 → **真跑一遍测试，确认 green**
5. （可选）refactor 轮：临摹改动，跑测试仍 green
6. 重复直到 plan 的 Implementation Steps 全部落盘

**TDD on 的硬约束**：和 4a 一样——测试 red → green 必须**真跑过测试**，看不到对应输出就不算成功。

## Step 5: Hand Off to `/finalize`

代码全部落盘后，**不要自己提交**。调用 `/finalize` skill：

- `/finalize` 跑 polish-code → update-changelog → self-improve → Phase 4 split analysis → `/ship` 或 `/split-and-ship`
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
- **TDD 节奏按内容路由，不按偏好。** 算法 / 状态机 / 复杂业务规则默认 on；UI / glue / 一次性脚本默认 off。用户显式覆盖优先。"无脑全开 TDD" 和 "无脑全关 TDD" 都是错的。
- **TDD 的 red → green 必须真跑过测试。** 不能脑补"测试应该通过"，要用 Bash 工具实际跑 plan 的 Verification 命令，看到 fail 输出和 pass 输出才算每轮成功。
- **无测试框架时强制降级。** 项目检测不到 test runner（没 jest/pytest/cargo test 等）→ 自动关 TDD + 告知用户，不要假装有测试。
- **TDD on 不豁免反问 / 临摹纪律。** 测试代码也要解释 / 也要逐行敲；测试不是质量门，是更早的理解门。
