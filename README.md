# my-claude-setup

把两个 Claude Code skill 框架编排到同一个 `~/.claude` 下：**gstack 管 Think → Plan，turbo 管 Build → Ship**。

不 fork、不 vendoring 上游，两边各自 `git pull` 升级。

---

## 这是什么

我个人的 dotfiles 仓库。目的不是再造一个框架，而是让两套现成的、风格相反的框架在同一台机器上各司其职：

- **[turbo](https://github.com/tobihagemann/turbo)** 是 Tobias Hagemann 的小颗粒 skill 集合，"skill is the prompt"，每个 skill 干一件事，组合起来是一条流水线。它的强项是**执行循环**：实施 plan、跑测试、提 PR、走 review、回评论、收尾。
- **[gstack](https://github.com/garrytan/gstack)** 是 Garry Tan（YC 总裁）的角色化重型 skill 集合。每个角色 review 是一个独立、长 SKILL.md 的"专家"。它的强项是**规划探讨**：office-hours 拷问需求、autoplan 跑四角色 review（CEO / 设计 / 工程 / DX）。

我两边都用，但用法不一样：写代码归 turbo，想清楚要不要写、写成什么样归 gstack。这个仓库是把这套分工固化下来的安装脚本。

它**不替代**任何一边——产物只有 `install.sh`、`turbo.config.json`、自己的 `skills/`。两个上游都从源仓库直接同步。

---

## TL;DR：三步装好，三步出活

**装：**

```bash
git clone <this-repo> && cd my-claude-setup
./install.sh
```

前置依赖见下面的[前置依赖](#前置依赖)章节，至少需要 `git` `jq` `gh` `codex`。`install.sh` **不**再调用 gstack 的 `./setup`，所以 Playwright Chromium / browse 二进制 / `bun install` 都不会触发——keep-list 里只有规划/思考类 skill，用不到那些。

**用（最小三步走，turbo 主路径）：**

```text
Session 1:  /turboplan <任务>     # 唯一规划入口，按复杂度自动分流
              ↓                    # plan/spec 模式会主动 halt
Session 2:  /implement-plan        # 在新 session 里读 plan、跑 /implement → /finalize
              ↓                    # /finalize 内部已经 commit + push + PR
            完成
```

`/turboplan` **不是中小任务专用**——这是 turbo 唯一的规划入口，所有任务都从它进去。它内部按复杂度自动选 Direct / Plan / Spec 三种模式之一。

想加强 Plan 阶段的思辨深度时，gstack 的 `/gstack-office-hours`（前置）和 `/gstack-autoplan`（plan 文件评审）可以嫁接进来，详见下面"gstack 怎么嫁接"。

---

## 前置依赖

`install.sh` **不会替你装** Claude Code 和下面这些工具——按 turbo 的运行模型，缺了之后某些 skill 会在调用时失败而不是安装时失败。

| 工具 | 用途 | install.sh 行为 | 装法 |
|---|---|---|---|
| `git` / `jq` | clone、改 JSON | 缺则退出 | `brew install git jq` |
| **`gh` CLI** | turbo 的 `/review-pr` / `/fetch-pr-comments` / `/create-pr` / `/resolve-pr-comments` 等都走 `gh` | **不检查**，调用 skill 时才报错 | `brew install gh && gh auth login` |
| **`codex` CLI** | turbo `/finalize` Phase 3 (peer-review) 和裸 `/peer-review` 必备；turbo 把它当强依赖 | **不检查** | `npm install -g @openai/codex` |
| Claude Code | 这一切的运行环境 | — | 见 [docs.anthropic.com](https://docs.anthropic.com/en/docs/claude-code) |
| ~~`bun`~~ | 老版本要求；现在 `install.sh` 不调 gstack `./setup` 了，bun 不再是 install 的依赖 | — | — |

**可选**：

- `agent-browser`（turbo 浏览器 skill 首选）— 没装会自动 fallback 到 `claude-in-chrome` MCP。一句安装：`npx skills add https://github.com/vercel-labs/agent-browser --skill agent-browser --agent claude-code -y -g`
- ChatGPT Pro + Chrome（turbo `/consult-oracle` 用，会诊通道）— 不会诊就略
- statusLine（context 剩余进度条）— 这个仓库默认假设你已经装了 [claude-hud](https://github.com/claude-hud/claude-hud) 插件作为 statusline，turbo 自带的简单 statusLine 不再注入。没装 claude-hud 也行，turbo 流水线本身不依赖它

完整 turbo 前置清单（含 oracle / agent-browser 详细配置）见 [turbo SETUP.md](https://github.com/tobihagemann/turbo/blob/main/SETUP.md)。

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

**为什么追加 CLAUDE-ADDITIONS：** turbo 的 README 里讲得很死——没装这套 5 条规则，Claude 在嵌套流水线（`/finalize` 之类）里**会静默跳步**。代价 ~250 tokens/会话，换流水线可靠性，值。

**为什么不跑 gstack 自带的 `./setup`：** `./setup` 强制下载 ~500MB Playwright Chromium、构建 90MB browse 二进制、跑 `bun install`（700MB node_modules），全是为了 `/browse` `/qa` `/design-review` 这些浏览器系 skill 服务的——而 keep-list 里这些 skill 一个不留。gstack 没有 `--skip-browser` 之类的旗标可以绕过（只有 `--prefix` `--team` `--host` `GSTACK_SKIP_COREUTILS`），所以 `install.sh` 直接跳过 `./setup`，自己重写它必要的两步：先调 `gstack-patch-names`（gstack bin/ 里的纯 bash 工具）把源 SKILL.md 里 `name: office-hours` 改成 `name: gstack-office-hours`，再按 keep-list 给每个 kept skill 建 symlink。`bin/gstack-update-check`、`bin/gstack-config` 这些 keep 列表里的 skill 实际调用的运行时脚本，都是纯 bash，不依赖 node_modules / Playwright，所以这样跳过完全 OK。

**`/gstack-upgrade` 默认已注释掉：** 这个 skill 内部会 `cd ~/.claude/skills/gstack && ./setup`，**绕过我们的跳过逻辑**——意味着它会重新装 Playwright + 重建 node_modules + 重新生成所有 42 wrapper。所以 `gstack-keep.txt` 里它默认是注释状态、不暴露成 slash command。要更新 gstack 一律用 `./install.sh`（它做 `git fetch + reset --hard origin/main`，等价拉最新 + 不会触发那些副作用）。

**为什么用 keep-list 控注册项：** Claude Code 把每个 `~/.claude/skills/gstack-foo/` 都当独立 skill 注册，frontmatter description 进每会话 skill 列表。42 wrapper + 1 bare = 43 个 ≈ 13k 字符 ≈ 3.5k tokens 常驻。只链 8 个之后常驻 ~800 tokens。要加回某个：编辑 `gstack-keep.txt`（里面已经把全部可选项注释列出来了，按类别分组：build / QA / design / security / safety guards / state），取消注释对应行 + 重跑 `./install.sh`。源码在 `~/.claude/skills/gstack/` 没动。

`turbo.config.json` 现在 `excludeSkills` 只有 `contribute-turbo`（clone 模式自动加，没 fork 跑这个会失败）；同时 `configVersion`、`lastUpdateHead` 由 `install.sh` 每次重跑时刷新，跟上游 turbo 的版本协调。其它 turbo skill 全装。

---

## 命令速查

### Plan：按强度选

| 场景 | 命令 |
|---|---|
| **任何任务的入口**（按复杂度自动路由 direct/plan/spec） | `/turboplan` |
| 还没决定要不要做、想被挑战 6 个尖锐问题（前置） | `/gstack-office-hours` |
| 已经有 plan 文件，要 CEO + 设计 + 工程 + DX 四角色 review 加固（评审） | `/gstack-autoplan` |
| 单维度深挖：只想要 CEO / 设计师 / 工程经理 / DX 一种视角 | `/gstack-plan-ceo-review`、`/gstack-plan-design-review`、`/gstack-plan-eng-review`、`/gstack-plan-devex-review` |
| 想跳过 turboplan 的复杂度判断，直接写 plan 文件 | `/draft-plan` → `/refine-plan` |
| 已有 plan 文件，开新 session 实施 | `/implement-plan` |
| 已有 spec，挑下一个 shell 实施 | `/pick-next-shell` |

### Build / Ship / Debug（turbo 主场）

| 场景 | 命令 |
|---|---|
| 临时小改、不写 plan | `/implement` |
| 收尾 4-phase（polish → changelog → self-improve → commit+push+PR） | `/finalize`（自动跟在 `/implement*` 后面，手写代码后也可以单独叫） |
| 单独 ship（仅 commit + push + PR，跳过 polish） | `/ship` |
| 排查 bug | `/investigate` |
| 代码 / PR 审查 | `/review-code`、`/review-pr`、`/peer-review` |
| PR 评论循环 | `/fetch-pr-comments`、`/reply-to-pr-conversation`、`/resolve-pr-comments` |
| 项目体检 / 上手新项目 | `/audit`、`/onboard` |
| 依赖升级 | `/update-dependencies` |
| 改进点 backlog | `/note-improvement`（写入 `.turbo/improvements.md`）→ `/implement-improvements`（按 lane 跑） |
| 跨 session 学习提取 | `/self-improve`（也是 `/finalize` 第 3 phase） |

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

> 砍掉的 34 个（包含会重装 Playwright 的 `/gstack-upgrade`，以及设计系统、QA、deploy 链、安全围栏、浏览器栈等）turbo 那侧都有等价或更精简的替代。要找回某个：编辑 `gstack-keep.txt` 取消注释对应行，重跑 `./install.sh`。升级 gstack 一律用 `./install.sh` 而不是 `/gstack-upgrade`（见[升级](#升级)）。

---

## turbo 的核心执行流程

`/turboplan` 是唯一规划入口，按任务复杂度自动选三种模式：

| 模式 | 触发条件 | 执行链 | 产物 |
|---|---|---|---|
| **Direct** | 范围清楚、做法已知，开干即可 | `/implement` → `/finalize` | 不写 plan 文件 |
| **Plan** | 单 session 能做完，但需先把方法记下来 | `/draft-plan` → `/refine-plan` → `/self-improve` → **★ halt ★** → 新 session：`/implement-plan` → `/implement` → `/finalize` | `.turbo/plans/<slug>.md` |
| **Spec** | 跨多子系统、需要架构讨论、多 session | `/draft-spec` → `/refine-plan` → `/draft-shells` → `/refine-plan` → `/self-improve` → **★ halt ★** → 每个 shell 一个新 session：`/pick-next-shell` → `/expand-shell` → `/refine-plan` → halt → 再开新 session：`/implement-plan` → `/implement` → `/finalize` | `.turbo/specs/<slug>.md` + `.turbo/shells/*` |

**为什么 halt + 新 session？** turbo 强制纪律——execution 期重新装载 skill、重新跑 pattern survey、重新读上下文，比让 plan 期的 context 漂下去靠谱。规划和实施分会话是 turbo 的设计核心。

**`/finalize` 内部已经 ship。** 它依次跑 `/polish-code`（stage→format→lint→test→review→evaluate→apply→smoke-test 直到稳定）→ `/update-changelog` → `/self-improve` → ship-it（commit + push + PR）。**不要在 `/finalize` 之后再 `/ship`，重复了。**

## 工作流示例

一个真实的"加缓存层"流程：

```text
[Session 1：规划]

You: /turboplan 给图片管线加一层 LRU 缓存，命中率指标进 metrics

Claude: [分析任务复杂度] → Plan mode
        [运行 /draft-plan：survey-patterns 找现有缓存实现 → 4 个产品决策升级提问 →
                          深度讨论文件位置、数据流、边界 → 写入 .turbo/plans/<slug>.md]
        [运行 /refine-plan：内部 + peer review → evaluate → apply → 再 review 直到稳定]
        [运行 /self-improve：抽出本 session 学到的东西]
        ★ halt ★ "Plan ready at .turbo/plans/<slug>.md. Run /implement-plan in a fresh session."

[Session 2：实施 + 收尾]

You: /implement-plan

Claude: [resolve 到 .turbo/plans/<slug>.md，读 Context Files 全文]
        [/implement → /code-style → 写代码]
        [/finalize 4 phase：polish-code 循环 → update-changelog → self-improve → ship-it]
        ✓ Tests pass ✓ Committed ✓ Pushed ✓ PR #42 created
```

如果是 30 行的小修——`/turboplan` 会自己路由到 **Direct mode**：跳过 plan 文件，直接 `/implement` → `/finalize`，不打断你。

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
[Session 2] /implement-plan → ...
```

**重要事实**（之前的 README 写错了，这里更正）：

- **`/gstack-autoplan` 不是从零生成 plan 的工具**，是 plan 文件**评审**工具。它要求 plan 文件已经存在。所以"`office-hours` → `autoplan` → `implement-plan`"中间必须有 turbo 的 `/draft-plan` 或 `/turboplan` 把 plan 起出来。
- `/gstack-office-hours` 产出的是设计文档（在 `~/.gstack/projects/`），不是 turbo 格式的 plan 文件。
- `/gstack-autoplan` 改写 plan 文件时可能引入 gstack 风格段落。turbo `/implement-plan` 读取的是固定结构（`## Pattern Survey` `## Implementation Steps` `## Verification` `## Context Files`），autoplan 加段一般不破坏，但**首次混用建议肉眼检查 plan 文件**。

什么时候用：

- **小事 / 中事 / 不需要被挑战**：纯 turbo（`/turboplan` → halt → `/implement-plan`）。
- **大事 / 不确定要不要做 / 需要四角色 review 加固**：先 `/gstack-office-hours` → 再 `/turboplan`（draft 出 plan 文件）→ 再 `/gstack-autoplan` 评审 → halt → `/implement-plan`。

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

如果你只想升 turbo（不动 gstack），可以单独用 `/update-turbo`——那一边不踩 Playwright 雷。

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

**全装但精修的代价是按调用付的。** gstack 那几个大 SKILL.md（office-hours 在 26k tokens 量级）只在显式调用时进上下文，平时不烧。常驻成本是 frontmatter description——这一条之前我以为很小，实测 42 个 wrapper + 1 个 bare 一起算下来 ~3.5k tokens/会话，**不算很小**，所以 `install.sh` 里加了 `gstack-keep.txt` 砍注册项这一步，砍到 9 个之后常驻 ~800 tokens，可以接受。

这个取舍不是普适的，但对我够用。

---

## 立场

这个仓库是个人的，不是产品。两边的设计哲学我都欣赏：turbo 那种"克制 + 组合"的极简、gstack 那种"角色化 + 故事感"的厚重。我没本事二选一，于是让它们各管一段。
