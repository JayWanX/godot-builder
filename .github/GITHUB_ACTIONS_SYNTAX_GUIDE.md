# GitHub Actions 核心语法与编写规则教学指南

> 面向完全不懂 GitHub Actions 和命令行的小白。
> 建议对照本仓库的工作流文件一起看（`build.yml` / `export.yml` / `linux_builds.yml` 等，已加详细中文注释）。
> 本文按"你在工作流里会遇到的真实语法"来讲解，而不是按官方文档目录。

---

## 目录

1. [什么是 GitHub Actions 工作流](#1-什么是-github-actions-工作流)
2. [YAML 基础：工作流文件的书写规则](#2-yaml-基础工作流文件的书写规则)
3. [on：触发方式（什么时候运行）](#3-on触发方式什么时候运行)
4. [inputs 与 secrets：参数和密钥](#4-inputs-与-secrets参数和密钥)
5. [jobs：任务定义](#5-jobs任务定义)
6. [steps：步骤（核心中的核心）](#6-steps步骤核心中的核心)
7. [表达式 ${{ }}：动态取值](#7-表达式--动态取值)
8. [矩阵构建 strategy.matrix](#8-矩阵构建-strategymatrix)
9. [上下文（Context）：needs / steps / inputs / secrets / github](#9-上下文contextneeds--steps--inputs--secrets--github)
10. [job 间传递：outputs 与 artifact](#10-job-间传递outputs-与-artifact)
11. [workflow_call：可复用工作流](#11-workflow_call可复用工作流)
12. [Composite Action：自定义 action](#12-composite-action自定义-action)
13. [Shell 与 run：执行命令的规则](#13-shell-与-run执行命令的规则)
14. [常用内置 Action 速查](#14-常用内置-action-速查)
15. [常见坑与最佳实践](#15-常见坑与最佳实践)

---

## 1. 什么是 GitHub Actions 工作流

**一句话**：GitHub Actions 是 GitHub 自带的"自动化执行任务"服务。你把要执行的步骤写成一个 `.yml` 文件放在 `.github/workflows/` 目录下，GitHub 就会在特定事件发生时（如手动点击、代码推送）自动在云端虚拟机上执行这些步骤。

**几个核心概念**：

```
工作流（Workflow）  = 一个 .yml 文件，定义"什么时候做什么"
    └── 任务（Job）    = 一次独立的执行单元（在一台虚拟机上跑）
          └── 步骤（Step）= 一个具体的动作（检代码 / 编译 / 上传）
```

**虚拟机的概念**：每个 job 会启动一台全新的、干净的虚拟机（Linux/Windows/macOS 任选）。虚拟机用完即销毁，所以：
- 不同 job 之间**文件不共享**（要共享得用 artifact，见第 10 节）
- 同一 job 内的步骤**共享同一个虚拟机**（上一步留下的文件下一步能读到）

---

## 2. YAML 基础：工作流文件的书写规则

工作流文件是 YAML 格式。YAML 是一种"用缩进表示层级"的文本格式。**缩进只能用空格，不能用 Tab**（这是最常见的报错原因）。

### 2.1 键值对

```yaml
name: 我的工作流     # 键名 + 冒号 + 空格 + 值
```

### 2.2 层级（缩进）

```yaml
on:                # 第一层
  workflow_dispatch:   # 第二层（缩进 2 空格）
    inputs:            # 第三层（再缩进 2 空格）
      my-input:        # 第四层
        type: string   # 第五层
```

### 2.3 列表（用 `-` 开头）

```yaml
options:            # 一个列表
  - editor          # 第一项
  - template_debug  # 第二项
```

### 2.4 多行文本块（`|` 和 `>`）

- `|`（竖线）：保留换行
- `>`（大于号）：多行折叠成一行（换行变空格）

```yaml
# | 保留换行（多行命令常用）
run: |
  echo "第一行"
  echo "第二行"

# > 折叠成一行（长描述常用）
description: >-
  这是一段很长的描述，
  换行会被折叠成空格。
```

### 2.5 注释

用 `#` 开头。`#` 后面的内容不生效，只给人看。

```yaml
name: 我的工作流   # 这是注释
```

**注意**：`#` 前面如果是值的一部分要小心（如 URL 里的 `#` 需引号包裹）。

### 2.6 布尔值 / 字符串 / 数组

```yaml
flag: true          # 布尔值：true / false（不要加引号）
text: "4.7.2-stable"  # 带特殊字符的字符串建议加引号
arr: [a, b, c]      # 数组（方括号写法）
arr2:               # 数组（列表写法，等价）
  - a
  - b
```

---

## 3. on：触发方式（什么时候运行）

`on` 声明工作流在什么事件下运行。**一个工作流可以有多种触发方式**。

### 3.1 workflow_dispatch：网页手动触发

```yaml
on:
  workflow_dispatch:
    inputs:          # 网页上会显示输入框，让用户填
      my-input:
        description: 说明文字
        required: false      # 是否必填
        default: "默认值"
        type: string         # 类型：string / boolean / choice
```

- `type: choice` 会变成下拉框，只能选 `options` 里的值
- `type: boolean` 会变成勾选框

### 3.2 workflow_call：被其他工作流调用

```yaml
on:
  workflow_call:
    inputs: ...      # 调用方通过 uses + with 传入
    secrets: ...     # 调用方通过 uses + secrets 传入
```

**关键规则**：被 `workflow_call` 调用的工作流，不能同时有 `on:` 里的其他触发方式？——**可以共存**（本仓库的 `build.yml` 就是 workflow_dispatch + workflow_call + repository_dispatch 三种都有）。但要注意不同触发方式下 `inputs` 的来源不同。

### 3.3 repository_dispatch：API 触发

```yaml
on:
  repository_dispatch:
    types: [godot-build]   # 监听的事件类型名
```

外部程序通过 GitHub API 发 POST 请求触发，参数放在 `client_payload` 里。

### 3.4 其他常用触发

```yaml
on:
  push:                # 代码推送时
    branches: [main]
  pull_request:        # 有 PR 时
  schedule:            # 定时（cron 表达式）
    - cron: "0 8 * * 1"
  workflow_run:        # 另一个工作流完成时
    workflows: ["其他工作流名"]
    types: [completed]
```

---

## 4. inputs 与 secrets：参数和密钥

### 4.1 inputs：普通参数（不是秘密）

在 `on` 里定义，运行时可读取。

```yaml
on:
  workflow_dispatch:
    inputs:
      ref:
        type: string
        default: master
```

读取方式：`${{ inputs.ref }}`（见第 7 节表达式）。

### 4.2 secrets：密钥（密码、令牌）

- 在仓库 Settings → Secrets 里配置，**不会显示在日志中**
- 读取方式：`${{ secrets.GIT_PAT }}`
- **限制**：secrets **不能用在 `if:` 条件里**，也不能作为普通字符串传给 action 的顶层 `with` 某些位置；正确用法是 `with` / `env` / `secrets:` 映射

```yaml
# ✅ 正确：传给 action 的 with
uses: actions/checkout@v4
with:
  token: ${{ secrets.GIT_PAT }}

# ❌ 错误：不能这样写
if: ${{ secrets.GIT_PAT != '' }}   # secrets 不能用于 if
```

**本仓库规则**：所有用户输入先放进 `env`，再由脚本从环境变量读，避免注入攻击（见 resolve 脚本）。

---

## 5. jobs：任务定义

`jobs:` 下面定义所有任务。每个 job 独立运行在虚拟机上。

```yaml
jobs:
  build-linux:          # 任务名（唯一标识）
    name: 🐧 Linux      # 显示名（可带 ${{ }} 动态化）
    runs-on: ubuntu-22.04   # 用什么虚拟机
    needs: resolve      # 依赖哪个 job（先完成）
    if: ...             # 条件（满足才运行）
    timeout-minutes: 120    # 超时时间
    steps: [...]        # 步骤列表
```

### 5.1 runs-on：选择虚拟机

| 值 | 说明 |
| --- | --- |
| `ubuntu-latest` / `ubuntu-22.04` | Linux |
| `windows-latest` | Windows |
| `macos-latest` / `macos-26` | macOS |

**注意**：不同系统的默认 shell 不同——Windows 默认是 **PowerShell**，Linux/macOS 默认是 **bash**。本仓库统一约定所有 `run` 步骤显式写 `shell: bash`（见第 13 节），以避免这种平台差异带来的坑。

### 5.2 needs：任务依赖

```yaml
jobs:
  build:
    ...
  merge:
    needs: build    # 等 build 完成后才运行
```

**坑**：如果 `needs` 的 job 被跳过（如 `if` 为 false），默认下游 job **也会被连带跳过**。要打破这种传播，用 `if: always()`（见第 8 节）。

### 5.3 if：条件执行（job 级）

```yaml
if: contains(fromJSON(needs.resolve.outputs.platforms), 'linux')
```

含义：如果 resolve 输出的 platforms 数组里包含 'linux'，才运行这个 job。

---

## 6. steps：步骤（核心中的核心）

一个 job 由多个步骤组成，**从上到下依次执行**。步骤只有两种核心动作：

### 6.1 uses：调用现成的 action

```yaml
- name: 检出代码
  uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
  with:              # 传给 action 的参数
    ref: ${{ github.sha }}
    path: project
```

- `uses` 后面跟"谁提供的什么 action"
  - `actions/checkout@xxx` = GitHub 官方 action
  - `./.github/actions/xxx` = 本仓库自定义的 action（相对路径）
  - `xxx/xxx@v1` = 第三方 action
- **@ 后面是版本**。本仓库统一用 commit SHA 固定版本（安全、可复现），注释标注版本号

### 6.2 run：直接执行命令

```yaml
- name: 安装依赖
  run: |
    sudo apt-get update
    sudo apt-get install libwayland-bin
```

- `run` 后面是 shell 命令
- 多行命令用 `|`（保留换行）
- 默认 shell 取决于 runs-on（Windows 是 PowerShell）；本仓库每个 `run` 都显式声明 `shell: bash` 保持一致（见第 13 节）

### 6.3 步骤的常用属性

```yaml
- name: 步骤名
  id: 别名            # 给步骤起别名，供 steps.<别名>.outputs 引用
  if: 条件            # 满足才执行本步骤
  uses: 或 run:       # 二选一
  with:               # uses 时的参数
  env:                # 给本步骤设置环境变量
  shell: bash         # 覆盖默认 shell（如 Windows 上强制用 bash）
  continue-on-error: true  # 本步骤失败也不中断 job
```

---

## 7. 表达式 ${{ }}：动态取值

`${{ }}` 是 GitHub Actions 的表达式语法，**在运行时被求值替换**。

```yaml
ref: ${{ github.sha }}                  # 取当前 commit
name: ${{ matrix.name }}                # 取矩阵变量
path: ${{ needs.resolve.outputs.x }}    # 取其他 job 的输出
token: ${{ secrets.GIT_PAT }}           # 取密钥
```

### 7.1 支持的运算

| 语法 | 含义 | 示例 |
| --- | --- | --- |
| `==` / `!=` | 等于 / 不等于 | `matrix.target == inputs.target` |
| `&&` / `||` | 与 / 或 | `a && b`、`a || b` |
| `!` | 非 | `!cancelled()` |
| `contains(a, b)` | a 是否包含 b | `contains(fromJSON(x), 'linux')` |
| `fromJSON(x)` | 把 JSON 字符串转成数组 | `fromJSON(needs.resolve.outputs.platforms)` |
| `always()` | 恒为 true（打破 skip 传播） | `if: always() && ...` |
| `cancelled()` | 工作流被取消 | `if: !cancelled()` |
| `success()` | 前置都成功 | `if: success()` |
| `startsWith/endsWith` | 字符串开头/结尾 | 较少用 |
| `||` 做默认值 | 左值空则用右值 | `inputs.repo-safe || github.event.repository.name` |

### 7.2 字符串比较注意

```yaml
if: matrix.target == inputs.target    # 字符串相等比较，不用加引号
if: inputs.flag == 'true'             # 布尔值比较（布尔类型 input 比较时用字符串）
```

---

## 8. 矩阵构建 strategy.matrix

**矩阵 = 一个 job 定义展开成多个并行实例**，每个实例用矩阵里的一组值。

```yaml
strategy:
  fail-fast: false        # 一个实例失败是否取消其他实例（多平台建议 false）
  matrix:
    include:              # 显式列出每个组合
      - name: Editor
        target: editor
        arch: x86_64
      - name: Template
        target: template_release
```

矩阵里自定义的字段（如 `name` / `target` / `arch` / `cache-name`）都可以在步骤里用 `${{ matrix.字段名 }}` 引用。

**关键配合**：每个矩阵实例并不都"干活"，通常用 `if: matrix.target == inputs.target` 过滤——只有用户选的 target 对应的实例真正执行，其余空转跳过。这样一份矩阵定义服务多种目标。

---

## 9. 上下文（Context）：needs / steps / inputs / secrets / github

上下文是 GitHub Actions 提供的"信息对象"，配合 `${{ }}` 使用。

| 上下文 | 内容 | 示例 |
| --- | --- | --- |
| `inputs` | 当前工作流的输入 | `${{ inputs.ref }}` |
| `secrets` | 密钥 | `${{ secrets.GIT_PAT }}` |
| `github` | 仓库/事件信息 | `${{ github.sha }}`、`${{ github.repository }}`、`${{ github.event_name }}` |
| `needs` | 依赖 job 的输出/结果 | `${{ needs.resolve.outputs.x }}`、`${{ needs.build.result }}` |
| `steps` | 本 job 内步骤的输出 | `${{ steps.inject.outputs.scons-profile-path }}` |
| `matrix` | 当前矩阵实例的值 | `${{ matrix.target }}` |
| `env` | 环境变量 | `${{ env.ANDROID_HOME }}` |

### 9.1 needs 的关键用法

```yaml
jobs:
  resolve:
    outputs:
      target: ${{ steps.resolve.outputs.target }}
  build:
    needs: resolve
    if: contains(fromJSON(needs.resolve.outputs.platforms), 'linux')
```

- `needs.resolve.outputs.xxx` = resolve job 输出的参数
- `needs.resolve.result` = resolve job 的结果（success / failure / skipped）
- 判断结果常用 `== 'success'` / `!= 'failure'`

### 9.2 github 上下文常用字段

| 字段 | 含义 |
| --- | --- |
| `github.sha` | 触发工作流的 commit SHA |
| `github.ref` | 触发工作流的分支/标签 |
| `github.repository` | 仓库名（owner/repo） |
| `github.event_name` | 触发方式名 |
| `github.workspace` | 虚拟机工作目录路径 |

---

## 10. job 间传递：outputs 与 artifact

**关键事实**：不同 job 跑在不同虚拟机上，文件不共享。跨 job 传数据只有两种方式：

### 10.1 outputs：传小数据（字符串）

```yaml
jobs:
  resolve:
    outputs:                 # 声明输出
      target: ${{ steps.resolve.outputs.target }}
    steps:
      - name: 解析
        id: resolve
        run: echo "target=editor" >> "$GITHUB_OUTPUT"   # 写入输出文件
  build:
    needs: resolve
    run: echo "得到 ${{ needs.resolve.outputs.target }}"
```

- 步骤通过 `echo "key=value" >> "$GITHUB_OUTPUT"` 输出
- job 用 `outputs:` 声明这些 key
- 下游用 `needs.<job>.outputs.<key>` 读取

### 10.2 artifact：传文件（构建产物）

```yaml
# 上传
- name: 上传
  uses: actions/upload-artifact@v4
  with:
    name: my-artifact
    path: bin/*

# 下载（同 job 或不同 job）
- name: 下载
  uses: actions/download-artifact@v4
  with:
    name: my-artifact
    path: download-dir
```

- `upload-artifact`：把文件打包上传，可指定 `retention-days` 保留天数
- `download-artifact`：下载，可用 `pattern` 按名字模式匹配多个，`merge-multiple: true` 合并目录

---

## 11. workflow_call：可复用工作流

**场景**：`build.yml` 要调用 `linux_builds.yml` 等平台工作流，把参数传过去。这就是 `workflow_call`。

```yaml
# 被调用方（linux_builds.yml）
on:
  workflow_call:
    inputs:
      target:
        type: string
        default: editor
    secrets:
      GIT_PAT:
        required: false

# 调用方（build.yml）
jobs:
  build-linux:
    uses: ./.github/workflows/linux_builds.yml   # 调用
    with:               # 传 inputs
      target: editor
    secrets:            # 传密钥
      GIT_PAT: ${{ secrets.GIT_PAT }}
```

**重要规则**：
1. 被调用方（`workflow_call` 工作流）**必须声明**它接收哪些 `inputs` 和 `secrets`
2. 调用方传的 key **必须**在被调用方声明过，否则报错 "Invalid input, xxx is not defined"
3. 调用方可以用 `matrix` 展开多个调用（本仓库 build.yml 就是 6 个 job 各调一个平台工作流）
4. **`uses` 的路径必须是静态的**，不能写成 `${{ matrix.workflow }}`（GitHub 不支持）——所以本仓库用了 6 个显式 job 而非矩阵动态调用

---

## 12. Composite Action：自定义 action

**场景**：多个工作流要复用同一段逻辑（如 resolve 解析、导出）。把逻辑封装成一个"自定义 action"。

结构（目录名即 action 名）：

```
.github/actions/godot-resolve-export/
├── action.yml      # action 定义
└── resolve.py      # 脚本（或其他文件）
```

### 12.1 action.yml 结构

```yaml
name: 我的 Action
description: 说明文字

inputs:                 # 输入参数（调用方用 with 传）
  target:
    description: 说明
    required: true      # 必填
    default: ""
outputs:                # 输出（调用方用 steps.<id>.outputs 读）
  result:
    description: 说明
    value: ${{ steps.run.outputs.result }}

runs:
  using: composite      # 复合类型（由多个步骤组成）
  steps:
    - name: 执行脚本
      id: run
      shell: bash
      run: python "$GITHUB_ACTION_PATH/script.py"
```

### 12.2 关键点

- `using: composite` = 复合 action（本仓库的 action 都是这种）
- `$GITHUB_ACTION_PATH` = action 自身目录（GitHub 自动把 action 检出到这里，**无需手动 checkout**）
- 步骤输出通过 `echo "key=value" >> "$GITHUB_OUTPUT"`，在 `outputs` 里映射
- 调用方用法：
  ```yaml
  - name: 调用
    id: resolve
    uses: ./.github/actions/godot-resolve-export
    with:
      target: editor
  # 后续用 ${{ steps.resolve.outputs.result }}
  ```

### 12.3 action 与工作流的区别

| | 工作流 | Composite Action |
| --- | --- | --- |
| 位置 | `.github/workflows/` | `.github/actions/<名字>/` |
| 独立运行 | 可以 | 不能（只能被调用） |
| 被复用 | 少（重） | 多（轻） |
| 自动检出 | 否 | 是（$GITHUB_ACTION_PATH） |

---

## 13. Shell 与 run：执行命令的规则

### 13.1 不同 runner 的默认 shell

| runs-on | 默认 shell |
| --- | --- |
| ubuntu-* | bash |
| windows-latest | PowerShell（**不是 bash！**） |
| macos-* | bash |

⚠️ 这是 GitHub 的默认值，**也是最常见的跨平台陷阱**：同一段 `run` 命令在 Linux/macOS 能跑，在 Windows 上可能因 PowerShell 语法不同而报错。

### 13.2 本仓库统一约定：所有 run 都显式写 `shell: bash`

为了跨平台行为一致、避免"换个 runner 语法就变"，本仓库约定：

1. **每个 `run:` 步骤都显式声明 `shell: bash`**，不依赖默认值
2. Windows 上的命令也跟着走 bash（通过 runner 自带的 Git Bash 执行）
3. Windows 专用的 PowerShell 写法（`Get-ChildItem`、`Remove-Item`、`$bin.FullName` 等）一律改写为等价 bash（`ls`、`rm`、`"$(pwd)/$BIN"`），参照 `windows_builds.yml`

```yaml
- name: Windows 上也用 bash
  shell: bash          # 显式声明，不依赖 runner 默认
  run: |
    BIN=$(ls -t bin/godot*.exe | head -1)     # bash 语法，跨平台一致
    [ -n "$BIN" ] || { echo "::error::no godot binary"; exit 1; }
    "$(pwd)/$BIN" --version
```

**为什么不用 `sh` 或 PowerShell？** `bash` 是 `sh` 的超集（语法兼容 sh，并多出数组等增强），而 Windows 默认的 PowerShell 与 bash 语法差异极大。统一 bash 既能拿到最广的跨平台兼容，又只有一套语法要记。

### 13.3 run 的常见坑

```yaml
run: |
  set -e                # bash 下：任何命令失败立即退出（GitHub 默认已加 -e）
  echo "hello"
  ls 2>/dev/null || true    # 允许失败用 || true
```

- 命令失败默认会导致步骤失败（退出码非 0）
- 想容忍失败：命令后加 `|| true`，或步骤设 `continue-on-error: true`
- 脚本里用 bash 专属特性（如数组）前，确认 shell 是 bash 而非 sh；纯 POSIX 脚本两种都能跑

---

## 14. 常用内置 Action 速查

| Action | 作用 | 关键参数 |
| --- | --- | --- |
| `actions/checkout` | 检出仓库代码 | `repository`、`ref`、`path`、`submodules`、`sparse-checkout`、`fetch-depth`、`filter` |
| `actions/upload-artifact` | 上传文件 | `name`、`path`、`retention-days`、`if-no-files-found` |
| `actions/download-artifact` | 下载文件 | `name`、`pattern`、`path`、`merge-multiple` |
| `actions/setup-python` | 装 Python | `python-version`、`architecture` |
| `actions/cache` | 缓存目录 | `path`、`key` |

### checkout 关键参数详解

```yaml
uses: actions/checkout@v7
with:
  repository: other/repo      # 检出别人的仓库（默认是当前仓库）
  ref: main                   # 检出哪个分支/commit
  path: subdir                # 检出到子目录（默认是根）
  submodules: recursive       # 递归检出子模块
  sparse-checkout: |          # 只检出部分路径
    .github/scripts
  fetch-depth: 1              # 只取最新一次提交（快）
  filter: blob:none           # 不下载历史文件（快）
  token: ${{ secrets.GIT_PAT }}  # 私有仓库需要
```

---

## 15. 常见坑与最佳实践

### 15.1 高频报错及原因

| 报错 | 原因 |
| --- | --- |
| `Invalid input, xxx is not defined in the referenced workflow` | 调用 workflow_call 时传了被调用方没声明的 inputs/secrets |
| `Unrecognized named-value: 'secrets'` | secrets 用在了 if: 里（不允许） |
| `Unrecognized function: 'split'` | 表达式用了不支持的函数（GitHub 没有 split，用 shell 处理） |
| `uses` 里用 `${{ matrix.workflow }}` 报错 | uses 路径必须静态 |
| `Invalid workflow file` | YAML 语法错 / 引用了不存在的 job / inputs 类型错误 |
| job 莫名被跳过 | 依赖的 job 被 skip 导致连带 skip，需 `if: always()` |

### 15.2 最佳实践（本仓库遵循）

1. **权限最小化**：`permissions:` 只声明需要的权限（`contents: read`、`actions: write`）
2. **固定 action 版本**：用 commit SHA 而非 `@v4` 这类可变 tag，防供应链篡改
3. **用户输入走 env**：不直接把不可信输入拼进命令，先放 `env` 再给脚本读
4. **超时保护**：耗时 job 加 `timeout-minutes`，防止卡死烧钱
5. **缓存**：编译用 SCons 缓存 + `engine-sha` 做 key，加速二次构建
6. **并行平台**：各平台 job 相互独立（`needs: resolve` 但彼此不依赖），并行跑
7. **fail-fast: false**：多平台矩阵一个失败不影响其他
8. **跨 job 传值**：小数据用 outputs，文件用 artifact

### 15.3 三个最容易混淆的概念

- **inputs vs secrets**：inputs 是普通参数（日志可见），secrets 是密钥（隐藏）
- **uses vs run**：uses 调用别人写好的 action，run 直接跑自己的命令
- **job 间 vs job 内**：job 内步骤共享虚拟机（文件互通），job 间隔离（靠 outputs/artifact）
