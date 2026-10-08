# 项目 skills 来源

这些技能于 2026-10-07 首次从本机技能目录复制，随 Asmory 仓库保存；运行时不依赖源机器的
home 路径。子目录保留源技能的 `SKILL.md`、引用资源、脚本、已有 UI 元数据和许可文件。
根目录 `AGENTS.md` 提供本项目的任务入口与适用约束。

2026-10-08 对照下表来源检查现有 9 个技能，保留增删改和时效淘汰要求。
`project-maintenance` 围绕当前源码、文档、构建和测试核对维护结果，移除独立导航索引
要求及专用分类。其余技能的差异均为下表已有项目适配，予以保留。

| Skill | 本机来源 | 原有许可 / 声明 | 项目适配 |
| --- | --- | --- | --- |
| `project-maintenance` | `~/.codex/skills/project-maintenance/` | 源目录未附独立许可 | 直接核对源码、接口、文档和验证入口；helper 统一跟踪文件，不维护导航索引 |
| `performance-gradient-optimization` | `~/.claude/skills/performance-gradient-optimization/` | 源目录未附独立许可 | 提交、tag 与发布按用户任务范围执行 |
| `debugging` | `~/.claude/skills/debugging/` | CC BY-NC-SA 4.0，保留讲义署名 | 用本项目调试入口替代未携带的 dsh skills 引用 |
| `profiling` | `~/.claude/skills/profiling/` | CC BY-NC-SA 4.0，保留讲义署名 | 关联本项目性能 skill 与 Performance Contract |
| `shell-scripting` | `~/.claude/skills/shell-scripting/` | CC BY-NC-SA 4.0，保留讲义署名 | 对齐 Bash shebang 与验证入口；其他语言仅为过渡，迁移沿项目整体汇编化方向推进 |
| `testing` | `~/.claude/skills/testing/` | CC BY-NC-SA 4.0，保留讲义署名 | 关联现有 smoke / conformance，移除未携带技能的引用 |
| `code-review` | `~/.claude/skills/code-review/` | CC BY-NC-SA 4.0，保留讲义署名 | 无 |
| `git-cli` | `~/.claude/skills/git-cli/` | CC BY-NC-SA 4.0，保留讲义署名 | 用 Pro Git 与项目 CONTRIBUTING 替代未携带技能的引用 |
| `writing-for-readers` | `~/.claude/skills/writing-for-readers/` | CC BY-NC-SA 4.0，保留讲义署名 | 先使用已有上下文，仅询问影响准确性的缺口；移除不可用命令 |

Missing Semester 改编材料仍遵循其原声明和
[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/)，课程来源为
[MIT The Missing Semester](https://missing.csail.mit.edu/)，各技能及练习保留具体讲座来源。
本仓库根目录的 MIT 许可不替代这些材料已有的许可；“未附独立许可”只描述源目录状态。

维护时直接编辑仓库副本，不修改个人技能目录。重新同步本机技能时先比较差异，保留本项目
适配及来源声明，再验证 frontmatter、相对引用和脚本入口。无需把教学练习加载进普通开发任务。

项目技能发现目录采用 OpenAI Docs 的
[Agent skills](https://developers.openai.com/codex/skills) 文档所述 `.agents/skills/`。
