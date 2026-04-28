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

依赖 `git`、`jq`、`bun`。gstack 第一次跑 `./setup` 会下载 ~250MB 的 chromium for testing（playwright），等一下。

**用：**

```text
1. /gstack-office-hours    # 想清楚到底要不要做
2. /turboplan              # 写实施计划
3. /implement-plan → /finalize → /ship
```

中间任何一步想升级强度，gstack 那一侧的 `/gstack-autoplan`、`/gstack-plan-ceo-review` 都可以接进来。

---

## 安装脚本干了什么

| 动作 | 落点 |
|---|---|
| clone gstack 完整安装，跑它自带的 `./setup` | `~/.claude/skills/gstack/` |
| 给 gstack 写配置：`skill_prefix=true` `proactive=false` `explain_level=terse` `telemetry=off` | gstack 自带 config |
| clone turbo 仓库 | `~/.turbo/repo/` |
| 把 turbo 每个 skill 平铺到 claude skills 目录 | `~/.claude/skills/<skill>/` |
| 把本仓库 `skills/` 下的自定义 skill 同步过去 | `~/.claude/skills/<skill>/` |

**没动 `~/.claude/CLAUDE.md`。**流程指引是给人看的速查表，不该常驻进每次会话上下文，下面那张表就够了。

`turbo.config.json` 当前是 `excludeSkills: []`——turbo 全装，没排除。

---

## 命令速查

### Plan：按强度选

| 场景 | 命令 |
|---|---|
| 还没决定要不要做、想被挑战 6 个尖锐问题 | `/gstack-office-hours` |
| 大事，要 CEO + 设计 + 工程 + DX 四角色 review | `/gstack-autoplan` |
| 单维度深挖：只想要 CEO / 设计师 / 工程经理 / DX 视角 | `/gstack-plan-ceo-review`、`/gstack-plan-design-review`、`/gstack-plan-eng-review`、`/gstack-plan-devex-review` |
| 中小任务，让 turbo 自己判断走 direct / plan / spec | `/turboplan` |
| 已经清楚要写啥 plan 文件 | `/draft-plan` → `/refine-plan` → `/review-plan` |

### Build / Ship / Debug（turbo 主场）

| 场景 | 命令 |
|---|---|
| 实施已写好的 plan 文件 | `/implement-plan` |
| 临时小改、不写 plan | `/implement` |
| 收尾（测试 + 润色 + commit） | `/finalize` |
| 提 PR / 推送 | `/ship` |
| 排查 bug | `/investigate` |
| 代码 / PR 审查 | `/review-code`、`/review-pr`、`/peer-review` |
| PR 评论循环 | `/fetch-pr-comments`、`/reply-to-pr-conversation`、`/resolve-pr-comments` |
| 项目体检 / 上手新项目 | `/audit`、`/onboard` |
| 依赖升级 | `/update-dependencies` |

### gstack 重型工具（按需调用，全部 `/gstack-` 前缀）

| 场景 | 命令 |
|---|---|
| 真浏览器 QA（修 bug / 仅报告） | `/gstack-qa`、`/gstack-qa-only` |
| 部署链 | `/gstack-ship`、`/gstack-land-and-deploy`、`/gstack-canary` |
| 安全审计 | `/gstack-cso` |
| 设计探索 / mockup / 终稿 HTML | `/gstack-design-shotgun`、`/gstack-design-consultation`、`/gstack-design-html` |
| 性能基线 | `/gstack-benchmark` |
| 安全围栏 | `/gstack-careful`、`/gstack-freeze`、`/gstack-guard` |

---

## 工作流示例

一个真实的"想做个小工具"流程，从 0 到 PR：

```text
You: /gstack-office-hours 我想给个人博客加个评论系统

Claude: [跑 6 个 forcing questions：谁会用？最窄的楔子是什么？
        现状是怎么解决的？……]
        → 输出一份 .turbo/office-hours/<slug>.md

You: 嗯，问题问到点上了。/gstack-autoplan 这个

Claude: [并行跑 CEO / 设计 / 工程 / DX 四个角色 review，
        汇总分歧、给出 6 大决策原则下的判断]
        → .turbo/plans/<slug>.md，标了哪些是 taste call

You: 同意，落地。/implement-plan .turbo/plans/<slug>.md

Claude: [按 plan 走 implement → finalize：跑测试、polish、commit]

You: /ship

Claude: [推分支、开 PR、贴描述]
```

如果只是个 30 行的小修——直接 `/implement` 就行，不必走这一整套。强度跟着任务大小走。

---

## 冲突怎么处理

精确撞名只有两个：`/investigate` 和 `/ship`。

- **turbo 占用裸命名**——这两个是日常高频动作，让常用的那一边短。
- **gstack 一侧因 `skill_prefix=true` 自动变成** `/gstack-investigate`、`/gstack-ship`，需要时显式叫。
- **`proactive=false`** 让 gstack 不主动建议自己那 50 个 skill，自动路由也不会被它的 description 吸过去。turbo 仍然按它原有的方式自动路由。

撞名的处置原则：高频归裸命名，重型归前缀。

---

## 升级

两种方式，等价：

- 重跑 `./install.sh`：拉两边最新版并重新同步（幂等）
- 在 Claude Code 里：`/gstack-upgrade`（gstack 那一边）+ `/update-turbo`（turbo 那一边）

我个人偏好前者——一条命令，一致性强。

---

## 自己写的 skill

往本仓库 `skills/` 目录加新 skill，重跑 `install.sh` 即可同步到 `~/.claude/skills/`。这一层是给"我自己反复用、但不属于 turbo / gstack"的小习惯准备的——比如团队约定、特定项目快捷动作。

---

## 为什么不 fork、不抠 gstack 子集

每过一段时间会有人问，所以写下来。

**不 fork turbo。** 我对 turbo 没要改的地方。诉求是把 gstack 嫁接到它**旁边**，不是改它本身。fork 只换来 rebase 上游的负担。

**不抠 gstack 的规划 skill 子集（我只想要 office-hours / autoplan / 几个角色 review）。** 试过，放弃了，理由是实测下来的成本：

- 6 个规划相关 SKILL.md 共 1 万多行；
- 每个文件 78–88 处 gstack runtime 引用散布全文（preamble / GBrain Sync / Telemetry / Skill Invocation 等多个 section）；
- `autoplan` 硬编码同伴 skill 的磁盘路径 `~/.claude/skills/gstack/plan-*/SKILL.md`，子集化以后必须一处处改路径。

抠出来就要长期维护一套手术补丁，gstack 升级一次就重做一次。**不值。**

**全装的代价是按调用付的。** gstack 那几个大 SKILL.md（office-hours 在 26k tokens 量级）只在显式调用时进上下文，平时不烧 token。常驻成本只有 frontmatter description——很小。`proactive=false` 又把"模型主动推荐"那条路堵掉了，所以日常完全不会感觉到 gstack 的存在，需要它的时候 `/gstack-` 一下就在。

这个取舍不是普适的，但对我够用。

---

## 立场

这个仓库是个人的，不是产品。两边的设计哲学我都欣赏：turbo 那种"克制 + 组合"的极简、gstack 那种"角色化 + 故事感"的厚重。我没本事二选一，于是让它们各管一段。
