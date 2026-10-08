# Asmory 智能体指南

Asmory 是面向汇编的包注册表、规范和包管理器实验。长期目标是随着可复用汇编包生态
完善，逐步将整个项目环境汇编化，包括包管理、Registry、构建、测试和辅助工具。
当前使用 Bash、Python 等语言的地方，是汇编轮子尚不充分时的过渡实现；开发任务应推动
补齐可复用的汇编能力，并逐步替换这些实现。

当前可运行目标为 Linux x86-64：CLI 和只读 Registry 使用 GNU `as` / `ld` 构建静态
ELF，核心入口不依赖 libc；部分包管理和 Registry 写入流程仍使用 Bash / Python helpers。

## 从哪里开始

- 先查看 `git status --short`，保留已有改动；用 `rg` 定位任务涉及的入口，再读取相关文件。
- 模型和协议约束查看 `spec/`，设计背景查看 `docs/ARCHITECTURE.md` 和相关 MVP 文档。
  当前已实现的行为以源码、`Makefile` 和 smoke scripts 为准，部分早期 README 描述的是旧阶段。

| 修改内容 | 主要入口 |
| --- | --- |
| CLI 命令分派、宿主 ISA 检测、内置解析 | `cli/src/main.S`、`scripts/render-cli-registry-inc.sh` |
| 只读 HTTP Registry、内嵌页面和索引 | `registry/src/server.S`、`registry/static/`、`registry/data/` |
| 获取、缓存、安装、物化 | `scripts/asmory-{acquire,cache,add}.sh`、`scripts/asmory-materialize.py` |
| Exact / Modified、restore、Delta、vendor | `scripts/asmory-{state,delta,vendor}.py` |
| Repository workspace、fork、准备发布 | `scripts/asmory-{workspace,fork,publish}.py`、`asmory.workspace.toml` |
| 认证、staging、promotion、远程消费 | `scripts/asmory-registry-{auth,write}.py`、`scripts/asmory-{promote,remote}.py` |
| Semantic Facets、Profile、Provider 解析 | `scripts/semantic_model.py`、`scripts/asmory-semantic-resolver.py` |
| SIMD 内核、conformance、性能证据 | `examples/simd-dot/`、`scripts/bench-simd-dot*.sh` |
| Pages 网站、主题 | `site/`、`docs/THEMING.md`、`.github/workflows/pages.yml` |
| 构建、验证、发布流程 | `Makefile`、`scripts/*-smoke.sh`、`.github/workflows/` |

## 必须保留的契约

- Semantic Facets 是语义兼容性的依据；Capability 用于发现，Profile / Contract 是命名的
  Facet 集合。不能仅按名字、指纹或 Provider 身份判定兼容。
- Resolver 先检查语义和 Machine Contract，再考虑 trust 与可比较的性能证据。
  架构、OS、object format、ABI、ISA 和 toolchain 要求是约束，调优偏好不能替代它们。
- AVX 系列的可用性必须同时检查 CPU 能力和 OS 启用的扩展寄存器状态；维护
  `CPUID` / `XGETBV` 检测。汇编改动核对调用约定、栈对齐、寄存器保存、边界访问和导出符号。
- Release / Artifact 以不可变内容和精确 SHA-256 绑定；staged 候选通过 promotion gate
  才能成为 active。完整性校验、conformance 和安全审查各自证明不同事项。
- 全局内容寻址缓存保持不可变；项目物化目录可编辑，不使用可写硬链接连接二者。
  Modified 依赖必须保留 base Artifact 身份，不能伪装成 Exact。

## 实现与维护

- 新能力和重构优先寻找、复用或补齐汇编轮子；缺少轮子也是 Asmory 要解决的生态问题。
  包管理或工具逻辑的复杂程度不能成为长期交给其他语言的理由。
- 汇编化按任务范围逐步推进，保持行为、协议和验证能力。确需过渡实现时，说明缺失的
  汇编能力和替换条件；迁移完成后退役对应脚本、运行时依赖和失效构建入口。
- 修改现有实现时沿用文件的汇编语法与语言风格。尚未迁移的 Python helpers 当前使用
  标准库（包括 `tomllib`，需要 Python 3.11+）；Bash 脚本沿用 `#!/usr/bin/env bash`
  和 `set -euo pipefail`，保留参数引用、退出码和清理逻辑。
- `build/` 是生成目录。修改上游 `.S`、JSON/TOML 模板或生成脚本，再用 Make 重建；
  不直接编辑 `build/generated/cli_registry.inc` 或复制到 `build/` 的 helpers。
- 改公开命令、模型、协议或文件布局时，同步受影响的 `spec/`、`docs/`、示例、
  构建依赖和行为测试。Registry 页面与 `site/` Pages 是两个入口，按任务分别检查。
- 每次代码变更评估任务范围内的增、删、改；替代实现已验证且消费者已迁移时，
  同步退役旧实现及其专属测试、依赖、构建入口和文档。保留的兼容层要有具体消费者
  或当前契约及可检查的移除条件，不能仅凭文件年龄或无本地文本引用删除。
- 汇编内核改动要同时核对 `asm.toml`、`variants.toml`、exports、语义和 conformance；
  `examples/simd-dot/` 的文件变化会改变打包 Artifact 身份。

## 验证入口

当前工具链：Linux x86-64、GNU binutils、Make、Bash、Python 3.11+、Git、curl 和常用
归档 / coreutils 工具。这些是现阶段的验证依赖，随汇编替代能力完善逐步迁移。
优先运行能覆盖本次行为的现有入口。

```sh
make -j"$(nproc)"
make check
make smoke
make cli-smoke
```

- 上面是当前 CI 基线；`make check` 已包含 contract、semantic、workspace 和
  repo-workspace 检查。纯文档 / agent 配置改动只需验证格式、引用和相关技能资源。
- 按改动选择 `make acquire-smoke`、`cache-smoke`、`add-smoke`、`state-smoke`、
  `delta-smoke`、`vendor-smoke`、`repo-workspace-smoke`、`fork-publication-smoke`、
  `remote-publish-smoke`、`promotion-smoke`、`remote-index-smoke` 或 `semantic-provider-smoke`。
- smoke tests 必须串行运行，不用 `make -j` 执行这些测试：部分脚本共用端口，且会清理
  同名 `asmory-registry` 进程。验证服务改动前留意已运行的本地 Registry。
- 内核正确性用 `make conformance`；性能任务用 `make perf`、`make perf-variants`
  或 `make optimize-simd-dot`。先检查 `make perf-power-status`，读取 `spec/PERFORMANCE.md`；
  基准脚本会临时切换并恢复宿主电源策略，不把性能测试加入普通文档验证。
- 性能结论绑定精确 Artifact、工作负载、Machine Profile 和测量协议，保留原始样本；
  fallback 测量只能用作本地诊断，不能作为该 Contract 下接受的 Registry Evidence。
- 完成后检查 `git diff --check`，如实报告已运行的验证和环境限制。

## 仓库推送

`main` 同时发布到两个 GitHub 仓库：`origin`（`AntheaLaffy/Asmory`，个人开发）
和 `upstream`（`Asmory/Asmory`，对外组织）。两者同等承载提交，`origin` 配置了
两个 push URL，普通 `git push` 会同时更新两者；也可 `git push upstream main`
显式推送。公开身份仍是 `Asmory/Asmory`：CI / Pages 徽章、Package `provider`
字段和 Registry provenance 都指向它，不要把个人仓库写进这些位置。命令与重建
方式见 [docs/RELEASING.md](docs/RELEASING.md)。

## 项目 skills

技能位于 `.agents/skills/<name>/SKILL.md`，是随仓库携带的本机技能副本。
按任务读取对应入口和必要引用，不一次加载全部 skills；来源、许可和适配见
[SOURCES.md](.agents/skills/SOURCES.md)。同名个人技能也存在时，明确使用本项目路径。

| Skill | 何时使用 |
| --- | --- |
| `project-maintenance` | 功能、接口或汇编迁移后评估增删改，同步文档、构建和测试，核对旧实现退役条件 |
| `debugging` | 崩溃、错误结果、内存问题或偶发失败的排查 |
| `profiling` | 测量瓶颈、CPU / 内存 / I/O 占用，选择分析工具 |
| `performance-gradient-optimization` | 定义性能目标、比较候选与基线、决定是否接受优化 |
| `shell-scripting` | 维护尚未汇编化的 Bash helpers / 验证脚本，明确过渡边界 |
| `testing` | 增加行为 / 回归测试，或选择测试策略 |
| `code-review` | 用户请求代码 / diff / PR 评审或处理评审意见 |
| `git-cli` | 用户请求提交、分支、合并、冲突解决或历史恢复 |
| `writing-for-readers` | 编写注释、README、提交信息或 PR 描述，记录已有依据支持的动机 |

并行智能体仅在用户明确要求时启用。skill 中的示例命令和其他项目场景按本项目契约选择，不自动安装新框架、
接入 CI 或扩大任务范围。完成授权范围内的工作；已明确的需求与决定无需重复询问。
