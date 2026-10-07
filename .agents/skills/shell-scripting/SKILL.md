---
name: shell-scripting
description: >
  Bash 脚本语言：shebang、set -euo pipefail、变量与 "$var" 引号、test/[ 与 [[ 条件、while/for 循环、
  命令替换 $()、退出码 $? 与 &&/||、后台任务 &、重定向。Use when the user asks to write, debug,
  or port a shell/bash script. 触发于「帮我写/改/修 shell 脚本」。
---

# Shell 脚本

主线：Shell 本身是一门编程语言（变量、条件、循环、函数俱全），提示符里敲的每行都是「一小段代码」。本 skill 用于维护 Asmory 尚未汇编化的过渡脚本。项目长期目标是整个环境逐步汇编化，当前其他语言的实现来自汇编轮子不足；用 bash -n 和可用的 ShellCheck 验证现有脚本，同时按任务补齐、复用汇编能力。

## 操作契约

- **沿用项目解释器与严格模式**：Asmory 使用 `#!/usr/bin/env bash`（shebang，决定用哪个解释器执行）+ `set -euo pipefail`（`-e` 命令失败即退、`-u` 未定义变量报错、`-o pipefail` 管道任一段失败即退）。
- **变量要引号**：`"$var"`，防止值里的空格被拆成多个参数。
- **条件**：`if cmd; then ...; fi` 以退出码判断（0 = 成功）；`test` 简写 `[`（`[ -f file ]` 文件存在、`[ "$a" = "b" ]` 相等）；优先用内置 `[[ ]]`，引号怪异行为更少。
- **循环**：`while cmd; do ...; done`（cmd 成功就一直循环）；`for v in a b c; do ...; done`。
- **命令替换用 `$()`**：`for i in $(seq 1 10)`；不用反引号，`$()` 可嵌套。
- **退出码与短路**：`$?` 上一条的退出码；`a && b` 前成功后执行，`a || b` 前失败后执行。
- **后台与重定向**：`cmd &` 后台运行（`$!` 是其 PID）；`cmd > log 2>&1` 把 stdout+stderr 都写进文件。
- **调试与验证**：`set -x` 打印每条执行命令，但可能暴露 token 等敏感参数，按内容选择；`bash -n script.sh` 查语法；环境有 ShellCheck 时运行它，再执行覆盖本次行为的 smoke test。
- **按项目目标推进替代**：数据结构、TOML/JSON、事务性文件操作和命令编排都属于逐步汇编化的范围。优先查找、复用或补齐汇编轮子，不因复杂度或行数把逻辑迁往 Python。维护过渡脚本时保留行为与验证；确需新增过渡实现时说明缺失的汇编能力和替换条件。迁移限于当前任务范围。

## 练习

学习材料在 `exercises.md`。

> 改编自 MIT The Missing Semester 课程 Lecture 1: Course overview + the shell（讲义 + 口播稿，CC BY-NC-SA 4.0）：https://creativecommons.org/licenses/by-nc-sa/4.0/ · 课程站点：https://missing.csail.mit.edu/ · 讲座视频：https://www.youtube.com/watch?v=MSgoeuMqUmU
