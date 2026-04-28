# my-claude-setup

如果你用 Claude Code、想要一条 **plan → build → ship 的成型流水线**，这个仓库帮你把社区里两套现成的、风格相反的 skill 框架装在同一台机器上各管一段：**gstack 管 Think → Plan，turbo 管 Build → Ship**。

不 fork、不 vendoring 上游，两边各自 `git pull` 升级。

---

## 这是什么

我个人的 dotfiles 仓库。目的不是再造一个框架，而是让两套现成的、风格相反的框架在同一台机器上各司其职：

- **[turbo](https://github.com/tobihagemann/turbo)** 是 Tobias Hagemann 的小颗粒 skill 集合，"skill is the prompt"，每个 skill 干一件事，组合起来是一条流水线。它的强项是**执行循环**：实施 plan、跑测试、提 PR、走 review、回评论、收尾。
- **[gstack](https://github.com/garrytan/gstack)** 是 Garry Tan（YC 总裁）的角色化重型 skill 集合。每个角色 review 是一个独立、长 SKILL.md 的"专家"。它的强项是**规划探讨**：office-hours 拷问需求、autoplan 跑四角色 review（CEO / 设计 / 工程 / DX）。

我两边都用，但用法不一样：写代码归 turbo，想清楚要不要写、写成什么样归 gstack。这个仓库是把这套分工固化下来的安装脚本。

它**不替代**任何一边——产物只有 `install.sh`、`turbo.config.json`、自己的 `skills/`。两个上游都从源仓库直接同步。

---

## TL;DR：装一次，三步出活

**装：**

```bash
git clone https://github.com/2093686099/my-cc.git my-claude-setup
cd my-claude-setup
./install.sh
```

前置依赖详见下面的[前置依赖](#前置依赖)章节，最小命令一行：`brew install git jq gh && npm i -g @openai/codex && gh auth login`。

`install.sh` **不**调用 gstack 的 `./setup`，所以 Playwright Chromium / browse 二进制 / `bun install` 都不会触发——keep-list 里只有规划/思考类 skill，用不到那些。

**装完**：所有 `/xxx` 命令都在 Claude Code 会话里输入。打开 Claude Code 进任意项目目录就行。

**用（最小三步走，turbo 主路径）：**

```text
Session 1:  /turboplan <任务>     # 唯一规划入口，按复杂度自动分流 Direct/Plan/Spec
              ↓                    # plan/spec 模式会主动 halt
            /clear                  # Claude Code 内建命令，清空当前会话上下文
              ↓                    # turbo halt 文案明确要求 fresh session
Session 2:  /implement-plan        # 在新 session 里读 plan、跑 /implement → /finalize
              ↓                    # /finalize 内部已 commit + push + PR（自动判断单 PR 或拆分）
            /finalize
```

**两个常见决策**（详见下文对应章节）：

- **加深规划思辨？** 把 gstack 的 `/gstack-office-hours`（前置）和 `/gstack-autoplan`（plan 文件评审）嫁接到 `/turboplan` 前后——见 [gstack 怎么嫁接](#gstack-怎么嫁接进来)。
- **想用古法编程？** 把 `/implement-plan` 换成 `/old-code`（本仓库自定义 skill），文档先行，原理反问/临摹模式——见 [`/old-code`](#old-code-build-阶段的慢档古法编程)。

---

## 工作流示例：加缓存层

一个真实的"加缓存层"流程，从 `/turboplan` 走到 PR 创建：

```text
[Session 1：规划]

You: /turboplan 给图片管线加一层 LRU 缓存，命中率指标进 metrics

Claude: [分析任务复杂度] → Plan mode
        [/draft-plan：survey-patterns 找现有缓存实现 → 4 个产品决策升级提问 →
                      讨论文件位置、数据流、边界 → 写入 .turbo/plans/<slug>.md]
        [/refine-plan：内部 + peer review → evaluate → apply → 再 review 直到稳定]
        [/self-improve：抽出本 session 学到的东西]
        [Mark plan ready：把 plan 文件 frontmatter 改成 status: ready]
        ★ halt ★ "Plan ready at .turbo/plans/<slug>.md. Run /clear, then /implement-plan."

You: /clear

[Session 2：实施 + 收尾]

You: /implement-plan

Claude: [resolve 到 .turbo/plans/<slug>.md，读 Context Files 全文]
        [/implement → 内部加载 /code-style → 写代码]
        [/finalize 4 phase：
            Phase 1 polish-code 循环 → Phase 2 update-changelog →
            Phase 3 self-improve →
            Phase 4 split analysis → AskUserQuestion → 单 PR 走 /ship 或拆分走 /split-and-ship]
        ✓ Tests pass ✓ Committed ✓ Pushed ✓ PR #42 created
```

如果是 30 行的小修——`/turboplan` 会自己路由到 **Direct mode**：跳过 plan 文件，直接 `/implement` → `/finalize`，不打断你。

---

## 复杂任务的完整流程：gstack 加固 + 可选慢档

上面那个加缓存层是 **Plan mode 标准流程**（纯 turbo）。如果任务大、不确定要不要做、想加四角色 review、或者关键代码想吃透——下面这条加固版的链路才是你要走的。

### 流程顺序（这里有个常见的坑）

`/gstack-autoplan` **不是从零生成 plan 的工具**，是 plan 文件**评审**工具——它要求 `.turbo/plans/<slug>.md` 已经存在。所以 office-hours 和 autoplan **不连**着调，中间必须有 `/turboplan` 把 plan 起出来：

```text
[Session 1：想清楚 + 出 plan + 加固 plan]

You: /gstack-office-hours <模糊想法>
       ↓
       6 个 forcing question 拷问你（要不要做？最窄楔子？观察根据？）
       产出：~/.gstack/projects/<slug>/*-design-*.md（gstack 格式的设计文档）
       ⚠️ 这是设计文档，不是 turbo 的 plan 文件——下一步还要走 /turboplan

You: /turboplan <用上一步澄清出来的清晰描述>
       ↓
       内部按复杂度路由 → 进 Plan mode（或 Spec mode 如果跨多子系统）
       跑 /draft-plan → /refine-plan → /self-improve → mark ready (status: ready)
       ★ halt ★
       产出：.turbo/plans/<slug>.md（这才是 turbo plan 文件）

You: /gstack-autoplan
       ↓
       读上一步的 plan 文件
       并行跑 CEO + 设计 + 工程 + DX 四角色 review
       按 6 大决策原则**改写回 plan 文件**（自动备份 restore point）
       产出：被加固过的 .turbo/plans/<slug>.md
       ⚠️ 改写后建议肉眼快速过一遍，autoplan 偶尔会引入 gstack 风格段落

You: /clear   ← Claude Code 内建命令，清空当前会话上下文

[Session 2：实施 + 收尾]

You: /implement-plan
       ↓
       resolve plan 文件 → 完整读 Context Files
       按 plan 内容自动加载相关 skill
       /implement → 内部加载 /code-style → 写代码
       自动链 /finalize

[/finalize 4-phase 自动跑]
       Phase 1 /polish-code 循环：
                stage → fmt → lint → test → /review-code（含 codex peer review）
                → /evaluate-findings → /apply-findings → /smoke-test → 直到稳定
       Phase 2 /update-changelog（CHANGELOG.md 不存在则跳过）
       Phase 3 /self-improve（抽出本 session 学到的东西）
       Phase 4 split analysis：
                按 reviewability 评估是否拆 PR
                → AskUserQuestion 让你选：单 PR 走 /ship，拆分走 /split-and-ship
       ✓ Tests pass ✓ Committed ✓ Pushed ✓ PR #42 created
```

### 每一步具体贡献什么

| 步骤 | 干什么 | 什么时候**省略** |
|---|---|---|
| `/gstack-office-hours` | 6 个 forcing question 拷问"值不值得做、做成什么样" | 你已经想清楚了，直接跳到 `/turboplan` |
| `/turboplan` | 路由 + 出 plan 文件（必经） | 永远不省略——所有任务都从这里进 |
| `/gstack-autoplan` | 四角色 review 加固 plan | 中小任务、不需要被挑战——纯 turbo 就够 |
| `/clear` | 给实施期一个 fresh session | 技术上不照做也不会报错，但 turbo halt 文案就是按 fresh session 写的，照做 |
| `/implement-plan` | 读 plan + 自动加载相关 skill + 写代码 + 链 /finalize | 不省略——Plan mode 的实施入口 |
| `/finalize` | 4-phase QA + ship | 不省略——commit / 测试 / PR 全部在这里 |

### 关键挂钩点 / 常见疑问

**`/finalize` 之后还要 `/review-code` 吗？** **不用**。`/finalize` Phase 1 内部已经叫 `/review-code`（而 `/review-code` 又内部并行跑 internal review + `/peer-review`/codex），三层嵌套。例外：单角度精细 scan（`/review-code security`）或手动改完代码不想跑完整 `/finalize` 时单独跑。

**用 `/old-code` 替换 `/implement-plan` 是什么样？** 流程图改成：

```text
You: /clear
You: /old-code   ← 替代 /implement-plan，不替代前后任何步骤
       resolve plan 文件
       /code-style 加载（仍然装风格规则）
       Pick mode（反问 默认 / 临摹 显式）+ TDD rhythm（按内容路由）
       逐段反问 / 临摹直到落盘
       自动链 /finalize（commit / 测试 / PR 仍走 turbo 主流程）
```

**Spec mode 长什么样？** Plan mode halt 之后是 `/implement-plan`，Spec mode halt 之后是先 `/pick-next-shell` 把每个 shell 拉出来 expand → refine → halt，**每个 shell 各起一个 fresh session 跑 `/implement-plan`**——见下方 [turbo 的核心执行流程](#turbo-的核心执行流程) 表格。

---

## turbo 的核心执行流程

`/turboplan` 是唯一规划入口，按任务复杂度自动选三种模式（**borderline 时会用 `AskUserQuestion` 让你确认走哪条**）：

| 模式 | 触发条件 | 执行链 | 产物 |
|---|---|---|---|
| **Direct** | 范围清楚、做法已知，开干即可 | `/implement` → `/finalize` | 不写 plan 文件 |
| **Plan** | 单 session 能做完，但需先把方法记下来 | `/draft-plan` → `/refine-plan` → `/self-improve` → **mark plan ready (status: ready)** → ★ halt ★ → 新 session：`/implement-plan` → `/implement` → `/finalize` | `.turbo/plans/<slug>.md` |
| **Spec** | 跨多子系统、需要架构讨论、多 session | `/draft-spec` → `/refine-plan`(spec) → `/draft-shells` → `/refine-plan`(shells) → `/self-improve` → ★ halt ★ → 每 shell 一个新 session：`/pick-next-shell` → `/expand-shell` → `/refine-plan` → `/self-improve` → ★ halt ★ → 再开新 session：`/implement-plan <slug>` → `/implement` → `/finalize` | `.turbo/specs/<slug>.md` + `.turbo/shells/*` |

**为什么 halt + 新 session？** turbo 强制纪律——execution 期重新装载 skill、重新跑 pattern survey、重新读上下文，比让 plan 期的 context 漂下去靠谱。规划和实施分会话是 turbo 的设计核心。技术上不照做也不会报错，但 turbo 的整套 halt 文案就是按 fresh session 写的，照做就是了。

**怎么"开新 session"？** halt 信息出来后，输入 `/clear`（Claude Code 内建命令，清空当前会话上下文），或者开一个新的 Claude Code chat 窗口，再调下一步命令。

**`/finalize` 内部已经 ship。** 它依次跑 `/polish-code`（stage→deterministic 清理→`/review-code`→`/evaluate-findings`→`/apply-findings`→`/smoke-test`，循环到稳定）→ `/update-changelog` → `/self-improve` → **Phase 4 split analysis**（按 reviewability 评估是否要拆 PR，用 `AskUserQuestion` 让你选：单 PR 走 `/ship`，拆分走 `/split-and-ship`）。**不要在 `/finalize` 之后再 `/ship`，重复了。**

---

## gstack 怎么嫁接进来

`/gstack-office-hours` 和 `/gstack-autoplan` 是**对 turbo Plan 阶段的可选增强**，不是替代。它们在 turbo 流程里的接入点：

```text
[可选前置]
You: /gstack-office-hours <模糊想法>
       → ~/.gstack/projects/<slug>/*-design-*.md（设计文档）
       6 个 forcing question 帮你想清楚到底要不要做、做成什么样

[然后走 turbo 主路径]
You: /turboplan <更清晰的任务描述>     # 用上面的 design 文档当输入
       → .turbo/plans/<slug>.md

[可选：4 角色 review 加固 plan 文件]
You: /gstack-autoplan
       autoplan 读现有 plan 文件 → 跑 CEO / 设计 / 工程 / DX 四角色 review →
       自动按 6 大决策原则改写回 plan 文件（带 restore point 自动备份）

[继续 turbo 主路径]
[/clear] → [Session 2] /implement-plan → ...
```

**几条容易踩的坑：**

- **`/gstack-autoplan` 不是从零生成 plan 的工具**，是 plan 文件**评审**工具。它要求 plan 文件已经存在。所以"`office-hours` → `autoplan` → `implement-plan`"中间必须有 turbo 的 `/draft-plan` 或 `/turboplan` 把 plan 起出来。
- `/gstack-office-hours` 产出的是设计文档（在 `~/.gstack/projects/`），不是 turbo 格式的 plan 文件。
- `/gstack-autoplan` 改写 plan 文件时可能引入 gstack 风格段落。turbo `/implement-plan` 读取的是固定结构（`# Plan: <Title>` + `## Context` + `## Pattern Survey` + `## Implementation Steps` + `## Verification` + `## Context Files`），autoplan 加段一般不破坏，但**首次混用建议肉眼检查 plan 文件**。

什么时候用：

- **小事 / 中事 / 不需要被挑战**：纯 turbo（`/turboplan` → halt → `/implement-plan`）。
- **大事 / 不确定要不要做 / 需要四角色 review 加固**：先 `/gstack-office-hours` → 再 `/turboplan`（draft 出 plan 文件）→ 再 `/gstack-autoplan` 评审 → halt → `/implement-plan`。

---

## `/old-code`：Build 阶段的慢档（古法编程）

`/gstack-*` 增强的是 **Plan 阶段的思辨深度**。`/old-code` 增强的是另一头——**Build 阶段的吃透深度**。它是这个仓库自己写的 skill（在 `skills/old-code/`），不来自 turbo 也不来自 gstack。

**它解决什么问题。** 在 AI 辅助开发里，最隐蔽的退化是"代码经过了屏幕，却没经过大脑"——AI 生成的代码看起来对、能跑，但开发者说不出每一行在内存/CPU/运行时里到底怎么动。日子久了，对代码坏味道的嗅觉会变钝，遇到 AI 语料稀少的领域（嵌入式驱动、锁机制、内存管理）就抓瞎。`/old-code` 把"理解每一行"做成 Build 阶段的硬约束。

**两种模式（互斥，选一个）：**

| 模式 | 默认 | 时机 | 谁打字 | 适合 |
|---|---|---|---|---|
| **原理反问 (Principle Questioning)** | ✓ | 代码生成**之后** | AI 写 + 用户解释 | 你已经会写但想检查理解 |
| **代码临摹 (Code Calligraphy)** | — | 代码生成**之前** | 用户**逐行**手动输入 | 学新技术 / 训练肌肉记忆 |

反问模式：AI 生成一段代码 → **不直接落盘** → 反问"解释这段的原理和底层实现细节" → 解释清晰 → 落盘；解释不通则继续反问；累计 3 次还不通则给答案 + 鼓励。

临摹模式：AI 逐行展示代码 + 每行注释（作用 + 底层原理）→ **用户敲完一行才允许看下一行** → AI 校验大致正确性（语义等价即可，不抠字符）→ 整段完成后落盘。

**TDD rhythm 开关（叠加在两种模式之上）：** 每段逻辑可选 test-first 双轮（先测试 → 跑确认 red → 再实现 → 跑确认 green），也可选 impl-only 单轮。**按内容自动路由**：算法 / 锁 / 状态机 / 复杂业务规则默认 on；UI / 配置 / glue code 默认 off；HTTP handler / DB query 边界情况问用户。"用 TDD" / "跳过 TDD" 用户显式覆盖优先。项目没有可跑的测试框架时自动降级关闭。**不无脑用，按场景挑。**

**接入位置（不替代 plan / 不替代 ship）：**

```text
[Plan 阶段，照常]
  /turboplan <任务>           → .turbo/plans/<slug>.md
  (可选 /gstack-office-hours / /gstack-autoplan 加固)

[Build 阶段，二选一]
  快档：  /implement-plan  → /implement → /finalize       (默认 AI 主导)
  慢档：  /old-code        → 反问 / 临摹 → /finalize     (人和 AI 协作)

[Ship 阶段，照常]
  /finalize：polish → changelog → self-improve → /ship 或 /split-and-ship
```

`/old-code` 替换的是中间这一段，**前后接口完全保留**：

- 上游：plan 文件**查找规则**和 `/implement-plan` 一致（显式路径 / 唯一 plan / 最新 mtime / 内联任务描述兜底）。但**不像** `/implement-plan` 那样按 plan 内容自动加载其它 skill——慢档下默认让用户主导，不自动堆 context。
- 下游：代码落盘后调 `/finalize`，commit / 测试 / PR 全部走 turbo 原有流程。
- Skill 装载：进入 Step 2 时仍调 `/code-style` 装项目风格规则——慢不等于野。

**什么时候用：**

| 场景 | 命令 |
|---|---|
| 普通业务 / 样板 / glue / 配置 | `/implement-plan`（默认快档） |
| 关键 / 易错 / 想吃透的逻辑（LRU 缓存 / 锁 / 状态机 / 内存敏感路径） | `/old-code`（慢档，**TDD 默认 on**） |
| 学新框架想训练手感 | `/old-code` 临摹模式 |
| AI 给的代码看着对但你不放心 | `/old-code` 反问模式（让 AI 反过来盘问你） |
| 算法 / 协议 / parser 之类输出可枚举的代码 | `/old-code` + TDD on（自动判断；test-first 双轮） |

**重要约束：**

- **永不自动触发**。skill description 写明 "Do NOT auto-invoke"，只在你**明示**说"用古法"或敲 `/old-code` 时入场——避免它在普通编码时自动改变工作流。
- **不替代 plan**。没 plan 也没清晰描述就调用 → halt。古法不是让 AI 边想边写得更慢，是让人在已经决定要写什么之后，更深入地参与"怎么写"。
- **不修改 plan 文件**。只读。

致谢：核心理念来自 [zjw-swun/old-code](https://github.com/zjw-swun/old-code)（MIT），本仓库的版本在原作基础上接上了 turbo / gstack 的工作流接口（plan 文件 resolve、`/code-style` 装载、`/finalize` 收尾）。

---

## 前置依赖

**最小命令一行：**

```bash
brew install git jq gh && npm i -g @openai/codex && gh auth login
```

下面是细节。`install.sh` **不会替你装** Claude Code 和这些工具——按 turbo 的运行模型，缺了之后某些 skill 会在调用时失败而不是安装时失败。`install.sh` 启动时只硬性 check `git` 和 `jq`（缺则退出）；`gh` 和 `codex` 是 turbo 的运行时依赖，由具体 skill 在被调用时报错——所以 `install.sh` 跑过去不代表你已经齐活，第一次跑 `/finalize` / `/create-pr` 之前最好提前装上。各依赖（含 `gh` 登录、`codex` API key、`agent-browser`、`/consult-oracle` 的 Chrome 配置等）的详细一步步安装指南，见 turbo 官方文档 [docs/manual-setup.md](https://github.com/tobihagemann/turbo/blob/main/docs/manual-setup.md)——下表只列我们这边用得到的最小集。

| 工具 | 用途 | install.sh 行为 | 装法 |
|---|---|---|---|
| `git` / `jq` | clone、改 JSON | 缺则退出 | `brew install git jq` |
| **`gh` CLI** | turbo 的 `/review-pr` / `/fetch-pr-comments` / `/create-pr` / `/resolve-pr-comments` 等都走 `gh` | **不检查**，调用 skill 时才报错 | `brew install gh && gh auth login` |
| **`codex` CLI** | turbo `/finalize` Phase 1 (polish-code → review-code → peer-review) 和裸 `/peer-review` 必备；turbo 把它当强依赖 | **不检查** | `npm install -g @openai/codex` |
| Claude Code | 这一切的运行环境 | — | 见 [docs.anthropic.com](https://docs.anthropic.com/en/docs/claude-code) |
| ~~`bun`~~ | 老版本要求；现在 `install.sh` 不调 gstack `./setup` 了，bun 不再是 install 的依赖 | — | — |

**可选**：

- `agent-browser`（turbo 浏览器 skill 首选）— 没装会自动 fallback 到 `claude-in-chrome` MCP。一句安装：`npx skills add https://github.com/vercel-labs/agent-browser --skill agent-browser --agent claude-code -y -g`
- ChatGPT Pro + Chrome（turbo `/consult-oracle` 用，会诊通道）— 不会诊就略
- statusLine（context 剩余进度条）— 这个仓库默认假设你已经装了 [claude-hud](https://github.com/claude-hud/claude-hud) 插件作为 statusline，turbo 自带的简单 statusLine 不再注入。没装 claude-hud 也行，turbo 流水线本身不依赖它

再次强调：详细一步步装环境就照 turbo 官方 [docs/manual-setup.md](https://github.com/tobihagemann/turbo/blob/main/docs/manual-setup.md) 走，那边有命令、有登录步骤、有踩坑提示，比这里的表格全得多。

---

## 命令速查

按"什么时候调"分类，不严格遵循 turbo 自家目录划分。带 ⭐ 的是**主路径**（80% 时间用这几个就够）；带 🪆 的会被某个 pipeline 内部覆盖（比如 `/finalize` 内部已经叫 `/polish-code`），但单独跑也合法。

### 1. 入口：根据任务类型选一个

| 场景 | 命令 |
|---|---|
| ⭐ **任何任务的入口**（按复杂度自动路由 direct/plan/spec） | `/turboplan` |
| ⭐ 临时小改、不写 plan，直接 implement → finalize | `/implement` |
| ⭐ 已有 plan 文件，**开新 session** 实施 | `/implement-plan` |
| 已有 spec，挑下一个 shell 走 expand → refine → halt | `/pick-next-shell` |
| 从 GitHub 挑最热的 issue 来做 | `/pick-next-issue` |
| **想吃透关键逻辑**（并发 / 锁 / 状态机 / 性能敏感路径） | `/old-code`（Build 阶段慢档，本仓库自定义） |
| 项目体检 / 上手新项目（项目级 pipeline） | `/audit`、`/onboard` |

### 2. Plan / Spec 单独用（绕过 `/turboplan` 自动路由）

| 场景 | 命令 |
|---|---|
| 找已有同类实现 / 复用工具，不写 plan | `/survey-patterns` |
| 直接起 plan / spec / shells | `/draft-plan`、`/draft-spec`、`/draft-shells` |
| 把一个 shell 展成具体步骤 | `/expand-shell` |
| review 计划文件（plan / spec / shells，含 peer review） | `/review-plan` |
| review → evaluate → apply → 再 review，迭代到稳定 | `/refine-plan` |

### 3. gstack（Plan 阶段加固，可选）

| 场景 | 命令 |
|---|---|
| 还没决定要不要做、想被挑战 6 个尖锐问题（前置） | `/gstack-office-hours` |
| 已有 plan 文件 → CEO+设计+工程+DX 四角色 review | `/gstack-autoplan` |
| 单角色 review：CEO / 设计 / 工程 / DX | `/gstack-plan-{ceo,design,eng,devex}-review` |
| autoplan 提问偏好调优 | `/gstack-plan-tune` |
| 跨 session 学习记录（gstack 侧） | `/gstack-learn` |

完整 keep-list：见下方 [gstack 8 个保留 skill](#gstack-当前保留的-skill共-8-个由-gstack-keeptxt-控制)。

### 4. Code QA / 审查 / 重构

| 场景 | 命令 |
|---|---|
| ⭐ 收尾 4-phase（polish → changelog → self-improve → ship/split-and-ship） | `/finalize`（自动跟在 `/implement*` 后面） |
| 🪆 polish 循环（stage→fmt→lint→test→review→evaluate→apply→smoke，循环到稳） | `/polish-code` |
| 多角度 code review（bugs / security / API / consistency / simplicity / 测试覆盖） | `/review-code`（不传 type 就并行跑全部） |
| 简化代码 / reuse 检查 | `/simplify-code` |
| 找死代码 | `/find-dead-code` |
| 出仓库架构报告（`.turbo/codebase-map.md` + html） | `/map-codebase` |
| 出威胁模型（`.turbo/threat-model.md`） | `/create-threat-model` |
| 加载本仓库代码风格规则（mirror / reuse / symmetry） | `/code-style`（通常 `/implement` 自动调） |
| 前端设计指引 | `/frontend-design`（`/audit`、`/onboard`、`/map-codebase` 内部会调） |

### 5. 测试

| 场景 | 命令 |
|---|---|
| 烟雾测试（启动应用、点几下确认能用） | `/smoke-test` 🪆（也是 `/polish-code` 的一步） |
| 多层级探索性测试（基础 / 复杂 / 对抗 / 跨 cutting） | `/exploratory-test` |
| 写测试计划（`.turbo/test-plan.md`） | `/create-test-plan` |

### 6. Debug / 回忆 / 解释

| 场景 | 命令 |
|---|---|
| ⭐ 系统化 root cause 分析 | `/investigate` |
| 找已发生的实施推理（按 commit / 文件） | `/recall-reasoning` |
| 解释当前光标 / 错误 / question / 任意 artifact | `/explain-this` |

### 7. Findings 处理

| 场景 | 命令 |
|---|---|
| 解读外部反馈（PR 评论 / AI review / 人评） | `/interpret-feedback` |
| 对抗式 triage：哪条 finding 真的要 fix | `/evaluate-findings` |
| 把 evaluated findings 应用到代码 | `/apply-findings` |
| evaluated findings → 走 direct 还是 plan 的派发器 | `/resolve-findings` |

### 8. Git / GitHub

| 场景 | 命令 |
|---|---|
| 选文件 stage | `/stage` |
| stage + commit / + push 一条龙 | `/stage-commit`、`/stage-commit-push` |
| 已 staged → commit / + push | `/commit-staged`、`/commit-staged-push` |
| **独立** ship 单 PR（跳过 polish；不要接在 `/finalize` 后面，会重复） | `/ship` |
| **独立** ship 拆分（多个 reviewable unit，分多个 commit/branch/PR） | `/split-and-ship` |
| 创建 / 更新 PR（不 commit，只动 PR 本体） | `/create-pr`、`/update-pr` |
| ⭐ 完整 PR review（拉评论 → review → evaluate → dispatch） | `/review-pr` |
| 拉 PR 上未解决的评论 | `/fetch-pr-comments` |
| ⭐ 处理 PR 评论循环（修 + 答 + 回） | `/resolve-pr-comments` |
| 写答复 reviewer 问题（含从 transcript 回忆） | `/answer-reviewer-questions` |
| 上传 PR 答复 | `/reply-to-pr-threads`、`/reply-to-pr-conversation` |

### 9. 外部模型咨询

| 场景 | 命令 |
|---|---|
| 独立 peer review（codex 跑） | `/peer-review`（`/review-code`、`/review-plan`、`/review-pr` 内部会调） |
| codex 单跑 code review | `/codex-review` |
| 多轮咨询 codex | `/consult-codex` |
| codex CLI 自治执行任务 | `/codex-exec` |
| ChatGPT Pro 会诊（最后一招，问题硬到 codex 也搞不定） | `/consult-oracle` |

### 10. 依赖 / Tooling 检查

| 场景 | 命令 |
|---|---|
| 看哪些依赖过期 / 漏洞 | `/review-dependencies` |
| 升级依赖（带 breaking change 调研） | `/update-dependencies` |
| 看 linter / formatter / hook / CI 缺什么 | `/review-tooling` |
| 看 CLAUDE.md / AGENTS.md / MCP / hooks / 跨工具兼容性 | `/review-agentic-setup` |

### 11. 学习 / 改进 backlog

| 场景 | 命令 |
|---|---|
| 把当前发现的小改记到 backlog | `/note-improvement`（写 `.turbo/improvements.md`） |
| 跑 backlog 一条 lane（direct / investigate / plan，每 session 一条） | `/implement-improvements` |
| 抽出本 session 学到的东西 | `/self-improve`（也是 `/finalize` 第 3 phase） |

### 12. 元 / 维护

| 场景 | 命令 |
|---|---|
| 升级 turbo 自身 | `/update-turbo`（turbo 自带；只升 turbo，不动 gstack） |
| 写 / 更新 changelog | `/create-changelog`、`/update-changelog` |
| 写 / 改 skill | `/create-skill` |
| 从代码库挖 project-specific skill | `/create-project-skills` |
| 老 `.turbo/` 文件迁移（plan / spec / improvements） | `/migrate-turbo-files` |
| 把改进推回上游 turbo | `/contribute-turbo`（默认 `excludeSkills` 里禁用，需要 fork 才能用） |

### gstack 当前保留的 skill（共 8 个，由 `gstack-keep.txt` 控制）

| 命令 | 用途 |
|---|---|
| `/gstack-office-hours` | YC office-hours 风格 6 forcing question，写设计文档 |
| `/gstack-autoplan` | 已有 plan 文件 → CEO+设计+工程+DX 四角色 review pipeline |
| `/gstack-plan-ceo-review` | 单角色：战略/范围 review |
| `/gstack-plan-eng-review` | 单角色：架构/数据流/边界 review |
| `/gstack-plan-design-review` | 单角色：UI 设计 review |
| `/gstack-plan-devex-review` | 单角色：开发者体验 review |
| `/gstack-plan-tune` | autoplan 提问偏好调优 |
| `/gstack-learn` | 跨 session 学习记录 |

> 砍掉的 35 个（含会重装 Playwright 的 `/gstack-upgrade`、bare `/gstack` browse skill，以及设计系统 / QA / deploy 链 / 安全围栏 / 浏览器栈等）turbo 那侧都有等价或更精简的替代。要找回某个：编辑 `gstack-keep.txt` 取消注释对应行，重跑 `./install.sh`。升级 gstack 一律用 `./install.sh` 而不是 `/gstack-upgrade`（见[升级](#升级)）。

> 完整 turbo skill 列表（按 turbo 自家目录分类）见 turbo 仓库的 [All Skills](https://github.com/tobihagemann/turbo#all-skills) 表格——本节挑了用户可调用的 user-facing skill，跳过了纯内部 rule 文件（`/commit-rules`、`/changelog-rules`、`/github-voice` 这些被别的 skill 内部 reference，不直接调用）。

---

## 安装脚本干了什么

| 动作 | 落点 |
|---|---|
| clone gstack 源码，**跳过 `./setup`** | `~/.claude/skills/gstack/`（git clone, no build, no node_modules, no Playwright） |
| `mkdir -p ~/.gstack/projects`（gstack 运行时状态目录，`./setup` 原本会建） | `~/.gstack/projects/` |
| 给 gstack 写配置：`skill_prefix=true` `proactive=false` `explain_level=terse` `telemetry=off`（用 `GSTACK_SETUP_RUNNING=1` 抑制 post-set relink hook） | gstack 自带 config |
| clone turbo 仓库 | `~/.turbo/repo/` |
| 维护 turbo 配置：写 `lastUpdateHead`、按 `MIGRATION.md` 写 `configVersion`、clone 模式自动把 `contribute-turbo` 加进 `excludeSkills` | `~/.turbo/config.json` |
| 把 turbo 每个 skill 平铺到 claude skills 目录（已排除项跳过） | `~/.claude/skills/<skill>/` |
| **把 `.turbo/` 加进全局 gitignore**（turbo 在每个项目根写 plans / specs / improvements，不忽略每个 repo 都会冒一堆 untracked） | `~/.config/git/ignore`（或 `git config --global core.excludesfile` 指定的文件） |
| 把本仓库 `skills/` 下的自定义 skill 同步过去 | `~/.claude/skills/<skill>/` |
| **按 `gstack-keep.txt` 给 keep-list 里的 gstack skill 建 symlink**（替代 `./setup` 的 `link_claude_skill_dirs`）：先调 `gstack-patch-names` 把 `name:` 字段加上 `gstack-` 前缀，再 sweep 旧 wrapper，再 `ln -s` 8 个 keep 项 | `~/.claude/skills/gstack-<name>/SKILL.md` → `gstack/<dir>/SKILL.md` |
| **防御检查**：扫 `~/.claude/settings.json` 是否被 gstack 写入了 SessionStart hook | 仅 WARN，不擅自改 |
| **追加 turbo 的 `CLAUDE-ADDITIONS.md` 到 `~/.claude/CLAUDE.md`**（带 marker，幂等） | `~/.claude/CLAUDE.md` |

**为什么追加 CLAUDE-ADDITIONS：** turbo 的 README 里讲得很死——没装这套 5 条规则，Claude 在嵌套流水线（`/finalize` 之类）里**会静默跳步**。代价 ~250 tokens/会话，换流水线可靠性，值。具体写入了什么可以看 `~/.turbo/repo/CLAUDE-ADDITIONS.md`；写入位置由 `<!-- turbo:claude-additions:start -->` / `<!-- turbo:claude-additions:end -->` 一对 marker 包起来，便于幂等和卸载。

**为什么不跑 gstack 自带的 `./setup`：** `./setup` 强制下载 ~500MB Playwright Chromium、构建 90MB browse 二进制、跑 `bun install`（700MB node_modules），全是为了 `/browse` `/qa` `/design-review` 这些浏览器系 skill 服务的——而 keep-list 里这些 skill 一个不留。gstack 没有 `--skip-browser` 之类的旗标可以绕过（只有 `--prefix` `--team` `--host` `GSTACK_SKIP_COREUTILS`），所以 `install.sh` 直接跳过 `./setup`，自己重写它必要的两步：先调 `gstack-patch-names`（gstack bin/ 里的纯 bash 工具）把源 SKILL.md 里 `name: office-hours` 改成 `name: gstack-office-hours`，再按 keep-list 给每个 kept skill 建 symlink。`bin/gstack-update-check`、`bin/gstack-config` 这些 keep 列表里的 skill 实际调用的运行时脚本，都是纯 bash，不依赖 node_modules / Playwright，所以这样跳过完全 OK。

**`/gstack-upgrade` 默认已注释掉：** 这个 skill 内部会 `cd ~/.claude/skills/gstack && ./setup`，**绕过我们的跳过逻辑**——意味着它会重新装 Playwright + 重建 node_modules + 重新生成所有 42 wrapper。所以 `gstack-keep.txt` 里它默认是注释状态、不暴露成 slash command。要更新 gstack 一律用 `./install.sh`（它做 `git fetch + reset --hard origin/main`，等价拉最新 + 不会触发那些副作用）。

**为什么用 keep-list 控注册项：** Claude Code 把每个 `~/.claude/skills/gstack-foo/` 都当独立 skill 注册，frontmatter description 进每会话 skill 列表。42 wrapper + 1 bare = 43 个 ≈ 13k 字符 ≈ 3.5k tokens 常驻。只链 8 个之后常驻 ~800 tokens。要加回某个：编辑 `gstack-keep.txt`（里面已经把全部可选项注释列出来了，按类别分组：build / QA / design / security / safety guards / state），取消注释对应行 + 重跑 `./install.sh`。源码在 `~/.claude/skills/gstack/` 没动。

**有一个例外**：keep-list 里的 bare `gstack`（裸 browse skill）即使取消注释也**不会**真的链接——它的 SKILL.md 是 `SKILL.md.tmpl` 模板，需要 gstack `./setup` 跑模板渲染（注入 host / prefix / team 等变量）才能生成。`install.sh` 跳过了 `./setup`，遇到 bare `gstack` 会打 `WARN: skip 'gstack' bare skill — needs SKILL.md.tmpl rendering, not supported here` 然后跳过。要用裸 gstack 浏览器只能完整跑 gstack `./setup`（=放弃我们这里的 Playwright 跳过策略），或者用 turbo `/exploratory-test` + `claude-in-chrome` MCP 的等价路径。

`turbo.config.json` 现在 `excludeSkills` 只有 `contribute-turbo`（clone 模式自动加，没 fork 跑这个会失败）；同时 `configVersion`、`lastUpdateHead` 由 `install.sh` 每次重跑时刷新，跟上游 turbo 的版本协调。其它 turbo skill 全装。

---

## 冲突怎么处理

经过 `skill_prefix=true` + keep-list 控注册之后，**已经没有撞名了**——gstack 那边的 `/investigate` `/ship` `/review` 等同名 skill 都不在列表里，只剩 8 个 `/gstack-*` 前缀的规划/学习类 skill。

- `skill_prefix=true`：所有保留的 gstack skill 都带 `gstack-` 前缀
- `proactive=false`：gstack skill 自身运行时不会主动建议其它 gstack skill
- **keep-list 控注册**：只链 keep-list 里的，不在的根本不创建。43 → 8，省 ~2.7k tokens 常驻

turbo 这边仍然按它原有的方式自动路由（`/turboplan` `/implement-plan` `/finalize` 等都是裸命名）。

---

## 升级

**一句话：在仓库根目录跑 `./install.sh`。**

```bash
cd path/to/my-claude-setup
./install.sh
```

它会做：
- gstack：`git fetch --depth 1 + reset --hard origin/main` 拉最新源码，按 keep-list 重链 8 个 symlink（不触发 ./setup，所以不下 Playwright）
- turbo：`git pull --ff-only` 拉最新，按 `excludeSkills` 重新平铺 skill
- 顺便刷新 `~/.turbo/config.json` 的 `lastUpdateHead` / `configVersion`

幂等，可以随时重跑。

**不要用 `/gstack-upgrade`**：它内部会 `cd ~/.claude/skills/gstack && ./setup`，绕过所有跳过逻辑——会重新下 ~500MB Playwright Chromium、重建 700MB node_modules、重新生成所有 42 wrapper。这就是为什么它在 `gstack-keep.txt` 里默认被注释掉、不暴露成 slash command。

如果你只想升 turbo（不动 gstack），可以单独用 `/update-turbo`——这是 turbo 自带的自我升级 skill，那一边不踩 Playwright 雷。

---

## 卸载

**一句话：在仓库根目录跑 `./uninstall.sh`。**

```bash
cd path/to/my-claude-setup
./uninstall.sh           # 交互确认
# 或
./uninstall.sh --yes     # 跳过确认（脚本里 -y 也认）
```

`uninstall.sh` 镜像 `install.sh` 的 8 步、按依赖安全的反序撤销：

| 步骤 | 撤销内容 |
|---|---|
| 1 | 从 `~/.claude/CLAUDE.md` 抹掉 `<!-- turbo:claude-additions:start/end -->` 之间的块 |
| 2 | 从 `~/.config/git/ignore`（或 `core.excludesfile` 指向的文件）移除 `.turbo/` 行 |
| 3 | 删 `~/.claude/skills/gstack-*` 所有 keep-list 软链 |
| 4 | 删本仓库 `skills/` 下每个自定义 skill 在 `~/.claude/skills/` 里的副本（按 basename 匹配） |
| 5 | 按 `~/.turbo/repo/skills/` 枚举 turbo skill 名，逐个从 `~/.claude/skills/` 删掉 |
| 6 | 删 `~/.turbo/`（turbo 仓库 + config） |
| 7 | 删 `~/.claude/skills/gstack/`（gstack 源码 + 它的 git） |
| 8 | 删 `~/.gstack/`（gstack 运行时：projects / sessions） |

**外科精度的几条保证：**

- 第 4 步只删本仓库 `skills/` 里**确实存在**的子目录对应的 skill——你手动放进 `~/.claude/skills/` 的其它东西不动。
- 第 5 步必须发生在第 6 步**之前**——它需要 `~/.turbo/repo/skills/*/` 还存在，才知道当初装了哪些 skill 名。
- 第 5 步只删名字匹配 `~/.turbo/repo/skills/<name>` 的 `~/.claude/skills/<name>`——上游 turbo 没有的同名目录不动（不太可能撞，但留了余地）。
- 不会动 `~/.claude/settings.json` / 你的 shell rc / Claude Code 本体 / `gh` / `codex` / `agent-browser` / `claude-hud` / 任何 Playwright cache。

跑完之后机器回到几乎"装这个仓库之前"的状态，唯一残留是仓库本身（你自己 `rm -rf` 即可）。再跑 `./install.sh` 可重新装回来。

---

## 自己写的 skill 放哪？

**放在本仓库 `skills/` 目录下**——`install.sh` 第 6 步会把它们 `cp -r` 到 `~/.claude/skills/`。

```text
my-claude-setup/
└── skills/
    └── my-skill/
        └── SKILL.md      # 你的 skill
```

加完重跑 `./install.sh` 就生效。

**为什么不放 `~/.turbo/repo/skills/` 或 `~/.claude/skills/gstack/<name>/`？**

那两个目录都是上游仓库的工作区——本仓库的 `install.sh` 每次跑都会对它们做：

- turbo：`cd ~/.turbo/repo && git pull --ff-only`
- gstack：`cd ~/.claude/skills/gstack && git fetch + git reset --hard origin/main`

`reset --hard` 会**直接把你写的东西 nuke 掉**；`pull --ff-only` 在你本地有改动时会拒绝合并。再加上你的 skill 没进 git，换台机器就丢。

**`my-claude-setup/skills/` 这一层的设计意义：**

1. **你自己拥有的 skill 层**——和 turbo / gstack 解耦，不被上游 git reset 影响
2. **跟 dotfiles 一起进 git**——换机器只要 clone 这个仓库 + `./install.sh` 就回来了
3. **不污染上游**——你的小习惯 / 团队约定不会被推回 turbo 或 gstack

什么样的东西适合放进来：
- 团队约定的工作流脚本（"我们这个项目的 PR 模板"、"我们的 release checklist"）
- 反复用的私人快捷动作
- 对 turbo / gstack skill 的薄包装（比如带固定参数的）
- 自己写的实验性 skill

**当前真实例子**：`skills/old-code/`（古法编程，见上文专节）。它是个"对 turbo Build 阶段的可选替换"，挂在 `/implement-plan` 和 `/finalize` 之间——这就是这一层 `skills/` 该干的事：在 turbo / gstack 的接缝处加自己的料，但不改它们本身。

什么样的东西**不适合**放进来：
- 改 turbo 自己的 skill 行为 → 该走 `/contribute-turbo` 提 PR 给上游
- 改 gstack 自己的 skill 行为 → 同理，不要 fork（参见下面"为什么不 fork"）
- 跨项目共享的代码片段 → 那是 library 不是 skill

---

## 为什么不 fork、不抠 gstack 子集

每过一段时间会有人问，所以写下来。

**不 fork turbo。** 我对 turbo 没要改的地方。诉求是把 gstack 嫁接到它**旁边**，不是改它本身。fork 只换来 rebase 上游的负担。

**不抠 gstack 的规划 skill 子集（我只想要 office-hours / autoplan / 几个角色 review）。** 试过，放弃了，理由是实测下来的成本：

- 6 个规划相关 SKILL.md 共 1 万多行；
- 每个文件 78–88 处 gstack runtime 引用散布全文（preamble / GBrain Sync / Telemetry / Skill Invocation 等多个 section）；
- `autoplan` 硬编码同伴 skill 的磁盘路径 `~/.claude/skills/gstack/plan-*/SKILL.md`，子集化以后必须一处处改路径。

抠出来就要长期维护一套手术补丁，gstack 升级一次就重做一次。**不值。**

**全装但精修的代价是按调用付的。** gstack 那几个大 SKILL.md（office-hours 在 26k tokens 量级）只在显式调用时进上下文，平时不烧。常驻成本是 frontmatter description——这一条之前我以为很小，实测 42 个 wrapper + 1 个 bare 一起算下来 ~3.5k tokens/会话，**不算很小**，所以 `install.sh` 里加了 `gstack-keep.txt` 砍注册项这一步，砍到 8 个之后常驻 ~800 tokens，可以接受。

这个取舍不是普适的，但对我够用。

---

## 立场

这个仓库是个人的，不是产品。两边的设计哲学我都欣赏：turbo 那种"克制 + 组合"的极简、gstack 那种"角色化 + 故事感"的厚重。我没本事二选一，于是让它们各管一段。
