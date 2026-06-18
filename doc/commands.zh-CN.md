# 命令设计

[English](commands.md)

本文档说明 `fluoh` 的完整命令面，以及每个命令背后的设计边界。它和
[schema.zh-CN.md](schema.zh-CN.md) 互补：schema 文档定义数据结构，本文档定义
命令如何读取、写入和保护这些数据。

命令实现主要位于 `lib/src/<domain>/commands/`，顶层注册逻辑位于
`lib/src/cli/fluoh_command_runner.dart`。

## 端到端工作流

AI 驱动支持是主要端到端链路。内置的 `skills/fluoh` 工作流会判断工作区类型、
确认最终支持范围，然后执行 `fluoh` 命令。本文档定义这些命令契约；
详细 agent 路由、报告措辞和修复顺序由 `skills/fluoh/SKILL.md` 和
`skills/fluoh/references/` 维护。

### AI 驱动支持

先在 AI agent 中安装或刷新 skill：

```text
运行 `fluoh skill --path`，把打印的路径安装为 fluoh skill，并覆盖已有安装。
仅在尚未安装 fluoh 时，才使用
https://github.com/FlutterOH/fluoh/tree/main/skills/fluoh 作为初始来源。
```

然后用一句话把目标交给 AI agent：

```text
使用 $fluoh，必要时先安装 fluoh，然后为当前 Flutter 项目增加 FlutterOH 支持。
使用 $fluoh，按 SDK 3.35 将 <upstream-git-url> 移植为 FlutterOH Package。
使用 $fluoh，继续为 <package-name> 实现 FlutterOH 支持。
使用 $fluoh，预检查这个 FlutterOH Source 变更。
```

CLI 缺失时，skill 会处理安装。AI agent 可以用下面命令查看本地内置 skill 路径、
辅助脚本和报告模板：

```text
运行 `fluoh skill --path`，把打印的路径安装为 skill，必要时重载 skills。
```

AI agent 会用只读 preflight 收集并展示最终范围，等待用户确认后再修改文件。
release、push、force-push、破坏性 Git 操作和发布到外部服务仍是单独的维护者决策。
skill 版本跟随 CLI Package 版本；执行 `fluoh upgrade` 后，应重新安装或重载
`fluoh skill --path` 打印的路径。

### 手动为 App 项目增加 FlutterOH 支持

在已有 Flutter 项目中，如果不使用 AI agent，可以直接执行下面的命令，让项目使用
FlutterOH SDK 在 `ohos` 平台上构建或运行：

```sh
fluoh task start --type appSupport --scope <scope> --json
fluoh source update
fluoh sdk use 3.35 --pub-get
fluoh deps check --json
fluoh deps fix --dry-run --json
fluoh deps fix
fluoh deps get
fluoh doctor --platform ohos --project --json --strict
fluoh build ohos --auto-sign --json --trace
fluoh devices --platform ohos --json
fluoh emulators --platform ohos --json
fluoh run ohos --auto-emulator --json --trace
fluoh run ohos --device-id <id> --json --trace
fluoh drive ohos --json --trace
fluoh report create --scope <scope> --json
python3 <skill-dir>/scripts/check_report.py <report-path>
```

`fluoh task start` 会创建当前 task 工作区，用于归档 trace、截图、run session 和 report。
项目没有 `ohos/` 目录时，`fluoh sdk use` 默认会创建它。只有平台目录由其他流程维护时才使用
`--no-init-ohos`。如果没有可用设备或模拟器，可以把
`fluoh build ohos --auto-sign --json` 作为 build-only 证据，并根据 JSON diagnostic
里的 `nextCommand` 继续处理本机环境。

## 命令面

根帮助把 CLI 工具命令放在 `Fluoh` 分组（`skill`、`doctor`、`flutter`
和 `upgrade`），随后把 `SDK & Metadata` 放在项目工作流前面，因为 SDK 和 Source
状态通常会先卡住支持流程。`Project` 放顶层 App 项目命令：`create` 和 `deps`。
`Package` 放 `package` 仓库命令组。`Workflow` 放共享执行和证据命令，顺序是
`plan`、`verify`、`build`、`run`、`attach`、`drive`、`report` 和 `clean`。`Devices` 放 target
inventory 和启动辅助：`devices` 负责已连接 target 发现，`emulators` 负责
emulator/simulator 启动。

| 命令 | 实现 | 用途 |
| --- | --- | --- |
| `fluoh --version` | `lib/src/cli/fluoh_command_runner.dart` | 输出 `fluoh` 版本、Dart 版本、平台和仓库地址。 |
| `fluoh help [command]` | `package:args` command runner | 输出全局或指定命令的用法。 |
| `fluoh skill` | `lib/src/cli/skill_command.dart` | 输出内置 AI skill 的路径、版本、更新和提示词信息。 |
| `fluoh create [--sdk <version-or-series>] <args>` | `lib/src/project/create_command.dart` | 使用 FlutterOH SDK 创建 Flutter 项目，并把剩余参数透传给 `flutter create`。 |
| `fluoh plan app` | `lib/src/workflow/commands/plan_command.dart` | 检查当前 Flutter App 并输出只读 FlutterOH 支持命令队列。 |
| `fluoh plan package` | `lib/src/workflow/commands/plan_command.dart` | 检查当前 Package 分支并输出只读支持命令队列。 |
| `fluoh flutter <args>` | `lib/src/sdk/flutter_command.dart` | 使用最近的项目 `fluoh.yaml` 里选择的 SDK 运行 `flutter`。 |
| `fluohf <args>` | `bin/fluohf.dart` | `fluoh flutter <args>` 的快捷入口。 |
| `fluoh source` | `lib/src/source/source_commands.dart` | Package metadata source 使用和维护的命令组。 |
| `fluoh source list` | `lib/src/source/source_commands.dart` | 列出当前机器启用的 FlutterOH Package metadata Source。 |
| `fluoh source stats [--sdk <version-or-line>]` | `lib/src/source/source_commands.dart` | 按 FlutterOH SDK 版本或 line 汇总 Package 覆盖情况。 |
| `fluoh source enable <name> <url-or-path>` | `lib/src/source/source_commands.dart` | 在本机启用一个本地或 Git Source。 |
| `fluoh source disable <name>` | `lib/src/source/source_commands.dart` | 在本机停用非官方 Package metadata Source。 |
| `fluoh source update [name]` | `lib/src/source/source_commands.dart` | 刷新已配置 Source 的本地快照。 |
| `fluoh source init <path>` | `lib/src/source/source_commands.dart` | 创建本地 source 仓库模板。 |
| `fluoh source register <package-repo>` | `lib/src/source/source_commands.dart` | 把第一个已发布 FlutterOH Package 分支加入 Source 仓库。 |
| `fluoh source sync [path]` | `lib/src/source/source_commands.dart` | 为 Source 已有路由的 Package 导入后续 release。 |
| `fluoh source check [source]` | `lib/src/source/source_check_command.dart` | 校验 Source 文件并验证已声明的 Package release；本地 YAML/index 校验使用 `--schema-only`。 |
| `fluoh sdk` | `lib/src/sdk/sdk_commands.dart` | 本地 FlutterOH SDK 缓存的命令组。 |
| `fluoh sdk list` | `lib/src/sdk/sdk_commands.dart` | 列出远端 SDK 版本和本地 SDK 缓存。 |
| `fluoh sdk install <version-or-series>` | `lib/src/sdk/sdk_commands.dart` | 把 SDK 版本安装到 `$FLUOH_HOME/sdks`。 |
| `fluoh sdk current` | `lib/src/sdk/sdk_commands.dart` | 输出当前项目选择的 SDK。 |
| `fluoh sdk remove <version-or-series>` | `lib/src/sdk/sdk_commands.dart` | 删除一个已安装的 SDK 缓存。 |
| `fluoh sdk use <version-or-series>` | `lib/src/sdk/sdk_use_command.dart` | 为当前 Flutter 项目选择 SDK。 |
| `fluoh deps` | `lib/src/deps/commands/deps_command.dart` | 项目依赖命令组。 |
| `fluoh deps get` | `lib/src/deps/commands/deps_get_command.dart` | 为项目和 Package example 执行 `flutter pub get`。 |
| `fluoh deps check` | `lib/src/deps/commands/dependency_plan_commands.dart` | 输出依赖 FlutterOH 支持状态。 |
| `fluoh deps fix` | `lib/src/deps/commands/dependency_plan_commands.dart` | 应用推荐的 FlutterOH 依赖变更。 |
| `fluoh deps upgrade` | `lib/src/deps/commands/deps_upgrade_command.dart` | 只升级已有 FlutterOH 依赖替换。 |
| `fluoh package` | `lib/src/package/commands/package_command.dart` | FlutterOH Package 仓库命令组。 |
| `fluoh package list` | `lib/src/package/commands/package_list_command.dart` | 从已配置 source 列出 FlutterOH Package。 |
| `fluoh package new <name>` | `lib/src/package/commands/package_new_command.dart` | 基于 spec 在 SDK-line 分支创建新的 FlutterOH Package 仓库。 |
| `fluoh package port <upstream>` | `lib/src/package/commands/package_port_command.dart` | 把 upstream Flutter Package 移植到 SDK-line FlutterOH Package 分支。 |
| `fluoh package discover <upstream>` | `lib/src/package/commands/package_discover_command.dart` | 发现可能需要 FlutterOH 支持的 Flutter plugin Package。 |
| `fluoh package add <package-path>` | `lib/src/package/commands/package_add_command.dart` | 在已有 FlutterOH Package 仓库中创建另一个 Package 分支。 |
| `fluoh package queue <package-path>...` | `lib/src/package/commands/package_queue_command.dart` | 为 monorepo 解析只读多 Package 支持队列。 |
| `fluoh package upstream check` | `lib/src/package/commands/package_upstream_command.dart` | 检查 ported Package 分支的 upstream 目标。 |
| `fluoh package upstream sync` | `lib/src/package/commands/package_upstream_command.dart` | 把选中的 upstream Package release 合入当前 FlutterOH Package 分支。 |
| `fluoh package scope` | `lib/src/package/commands/package_scope_command.dart` | 维护支持计划和证据 gate 使用的 Package support scope。 |
| `fluoh package next` | `lib/src/package/commands/package_next_command.dart` | 输出下一条 Package 实现动作。 |
| `fluoh package status` | `lib/src/package/commands/package_status_command.dart` | 汇总 Package 发布就绪状态。 |
| `fluoh package handoff` | `lib/src/package/commands/package_handoff_command.dart` | 汇总 Package 分支状态、证据和 AI 交接下一步命令。 |
| `fluoh package version` | `lib/src/package/commands/package_version_command.dart` | 更新 Package 发布版本元数据。 |
| `fluoh package check` | `lib/src/package/commands/package_release_command.dart` | 运行发布前检查，不创建 tag。 |
| `fluoh package release` | `lib/src/package/commands/package_release_command.dart` | 完成 FlutterOH Package release。 |
| `fluoh verify` | `lib/src/workflow/commands/verify_command.dart` | 为项目或 Package 仓库运行 pub get、分析和测试。 |
| `fluoh build <platform>` | `lib/src/workflow/commands/build_command.dart` | 构建项目或 Package example。 |
| `fluoh run <platform>` | `lib/src/workflow/commands/run_command.dart` | 准备平台、通过 `flutter run` 启动并诊断 App。 |
| `fluoh attach <platform>` | `lib/src/workflow/commands/attach_command.dart` | 把 Flutter 调试工具 attach 到 `flutterRunSession`、VM Service URI 或 device id。 |
| `fluoh drive <platform>` | `lib/src/workflow/commands/drive_command.dart` | 在 OHOS、Android 和 iOS target 上执行移动端自动化场景和证据校验。 |
| `fluoh report create` | `lib/src/workflow/commands/report_command.dart` | 根据 trace manifest 和 automation JSON 创建本地忽略的 AI 支持报告。 |
| `fluoh task` | `lib/src/task/task_command.dart` | 管理 `.fluoh/tasks/` 下的项目本地任务工作区。 |
| `fluoh clean` | `lib/src/workflow/commands/clean_command.dart` | 删除当前 task 工作区中的可清理输出。 |
| `fluoh doctor` | `lib/src/doctor/doctor_command.dart` | 诊断环境、项目、SDK 和工具状态。 |
| `fluoh devices` | `lib/src/platform/platform_target_commands.dart` | 列出已连接的 Flutter target，包括 OHOS、Android、iOS、Web 和当前 host 支持的桌面 target。 |
| `fluoh emulators` | `lib/src/platform/platform_target_commands.dart` | 列出并启动 OHOS、Android 和 iOS 的本地 emulator/simulator；桌面和 Web 平台不提供 emulator。 |
| `fluoh upgrade` | `lib/src/upgrade/upgrade_command.dart` | 升级已安装的 `fluoh` CLI。 |

## 共享运行规则

- Help 请求不会加载 source 配置。
- Source lock 只有一个维护方：`lib/src/source/` 中的 Source 运行时。命令类
  不应该直接读写 `$FLUOH_HOME/sources.lock.json`。
- 会修改 Source 配置或已配置快照的命令，把变更交给 Source 运行时。运行时会校验所有
  已配置 source 快照，尽可能修复快照，重建合并后的 lock，然后才提交新的本地 Source 状态。
- 消费 Source 数据的命令只能通过 Source 运行时的 load-index API 读取。这个 API 负责
  首次默认 Source 初始化；当 `sources.lock.json` 记录的 fingerprint 仍然有效时会直接返回。
  lock 缺失或过期时，运行时会先校验或修复已配置 source 快照，再重新生成 lock 并返回数据。
- `fluoh source` 不带子命令和 `fluoh source list` 在打印配置前也会走同一套 Source
  运行时重建路径，所以用户会先看到无效或缺失的 source 状态，再依赖列表结果。
- `fluoh deps get` 会跳过 Package Source 数据，让依赖解析在 source 快照需要修复时仍然可用。
  `fluoh flutter`、`fluohf` 和 `fluoh deps get` 在已选择 SDK 缺失时，仍可能通过 SDK
  resolver 加载 Source index，因为安装已选择的 SDK 需要 SDK 元数据。
- 用法错误和 schema 格式错误返回退出码 `64`。
- 支持 `--json` 的命令只向 stdout 输出一个机器可读 JSON 对象。顶层契约保持稳定：
  `schema`、`command`、`ok` 和 `exitCode` 始终存在；`checks`、`targets`、
  `packages`、`dependencies`、`error` 等命令专属字段保留在顶层。`verify`、`build`、
  `run`、`drive` 这类 workflow 命令失败时还会输出顶层 `nextAction`，给自动化提供下一条
  可执行的恢复命令，或明确标记为 blocked；更详细的 target 和 step diagnostics 仍保留在
  `targets` 下。自动化应调用已安装的
  `fluoh` 可执行文件，不要用 `dart run bin/fluoh.dart ... --json` 作为机器接口，因为
  Dart launcher 可能在命令进程启动前输出依赖解析文本。严格机器解析优先使用
  native/Homebrew 可执行文件；Dart pub global shim 会调用 `dart pub global run`，
  只有确认当前环境的 stdout 直接以 JSON 对象开始时，才把它用于 JSON 自动化。
  从 checkout 外运行当前仓库编译出的可执行文件时，把 `FLUOH_SKILL_PATH` 设为该
  checkout 的 `skills/fluoh` 目录，避免 `skill` 元数据和内置 report helper 脚本解析
  回退到 pub global shim。
- `fluoh task start` 创建 `.fluoh/tasks/<task-id>/` 并更新
  `.fluoh/current-task.json`。Task 目录是本地、忽略、可清理的工作区，按任务聚合
  traces、reports、commands、screenshots、logs、sessions 和 scratch 文件。
- `verify`、`build`、`run` 和 `drive` 可以用 `--trace` 或
  `--trace-dir <path>` 写入本地 AI diagnostic trace manifest。使用 `--trace` 时，
  命令会复用当前 task 或创建一个 task，并写入
  `.fluoh/tasks/<task-id>/traces/`；使用 `--trace-dir <path>` 时，manifest 固定为
  `<path>/trace.json`，用于显式调试。Trace 是本地证据包，不是 verbose stdout；
  和 `--json` 一起使用时，JSON 对象包含 task 元数据、trace id、目录和
  `trace.json` 路径的 `trace` 引用。trace 写入失败时，workflow 结果和退出码仍以
  底层命令为准，JSON 对象会包含 `traceError`。
- 本地 AI report 是当前 task `reports/` 目录下的忽略证据。`fluoh report create`
  默认写入 `.fluoh/tasks/<task-id>/reports/report.md`；`new_report.py` 和
  `new_summary.py` helper 也写入当前 task。
- 命令类只负责参数解析和用户可见输出；可复用行为放到
  `lib/src/sdk/`、`lib/src/deps/`、`lib/src/package/` 和 `lib/src/source/`
  等领域 helper 中。
- 会修改文件的命令必须尽早校验、保留无关文件，并报告实际变更或下一步动作。

## 命令组

### `fluoh create [--sdk <version-or-series>] <args>`

`create` 是基于 FlutterOH SDK 的 `flutter create` 封装。它可以在 Flutter
参数前传 `--sdk <version-or-series>` 和 `--json` 等 fluoh 参数；省略 `--sdk`
时，会从已配置 Source 中选择最新 stable SDK，Source index 不可用时回退到本地最新已安装
SDK。所选 SDK 会按需安装。

除 fluoh 自身的 `--sdk` 之外，其余参数原样传给 `flutter create`。创建成功后，
命令会在新项目里写入 `fluoh.yaml` 和 `.fluoh/flutter_sdk`，后续 `fluoh deps`、
`fluoh run` 和 `fluoh drive` 会继续使用同一个 SDK。需要把可能被 fluoh 解析的
参数传给 Flutter 时，在 Flutter 参数前加 `--`：

```sh
fluoh create --sdk 3.35 -- --org com.example demo_app
fluoh create demo_app --platforms=android,ios,ohos
```

`--json` 只向 stdout 写一个标准机器输出对象，并抑制人类进度和 Flutter 子进程输出；
子命令参数、退出码和 stdout/stderr 尾部记录在 `flutter` 下。成功报告还会包含所选
`sdk`、创建的 `project`、是否写入 SDK 元数据，以及 `.fluoh/flutter_sdk` 链接路径。

### `fluoh plan app|package`

`plan app` 只检查当前 Flutter App 项目，不写文件。它会报告当前目录是否像
Flutter App、已有的平台目录、已选择或显式请求的 FlutterOH SDK，以及用于依赖检查、
目标平台 build/run 证据、OHOS device/emulator 发现、已有平台 build/run 回归检查、
已有移动平台自动化证据和报告创建的结构化命令队列。
队列会先创建本地 task；后续 `build`、`run`、`drive` 和 `report create` 命令会使用当前
task 保存 trace 和 report 输出。`--json` 会输出一个带
`changed: false` 和 `applied: false` 的机器可读对象，方便 AI agent 在请求修改命令前完成支持范围确认。
JSON 同时包含 `automationRunbook` 和 `deliveryGate`，用于定义修复循环、终态、最终检查命令、
报告检查命令，以及 AI 声明 `ready` 前必须满足的条件。Ready 要求先审查已有 test 和
`integration_test/` 是否覆盖功能；缺失时补齐或修复功能测试；为 OHOS 收集功能证据；
为当前 host/toolchain 支持的所有已有平台目录收集平台策略指定的 build/run 回归证据；
Android 和当前 host 支持的 iOS 这类已有移动 example 还必须收集 drive dry-run 和
drive-run 证据。环境不支持的平台必须记录具体 diagnostic 证据和跳过原因。
当已安装的 `fluoh` 可用时，bundled skill 的 preflight 会优先使用这个 plan 输出作为命令队列；
只有 CLI setup 还没就绪时，才退回脚本内置的只读分类器。

`plan package` 对当前 FlutterOH Package 分支执行同样的只读规划。它读取
Package `fluoh.yaml`，报告分支与工作区状态、已选择 SDK、上游和 release 元数据、
example 平台目录，以及一个以 `fluoh package next --package <name> --json`
为 implementation-loop 入口的命令队列。这里不再把 Package 实现展开成另一套线性的
verify/build/run/drive 队列；`package next` 通过 `nextAction` 负责 spec review、
support scope 计划、OHOS 和已有平台命令、visual page-readiness、报告创建和报告校验顺序。
plan 队列只在 `package next` ready 后保留 release readiness summary、handoff 和
`package check --report <report-path>` 步骤。交付 gate 仍会列出具体 final check
commands，包括 `package next`、已选择 SDK 的验证、平台证据、`check_report.py`、
handoff 和 `package check`，避免报告认证失败只降级成非阻断 warning。

### `fluoh flutter <args>` 和 `fluohf <args>`

这两个命令是已选择 FlutterOH SDK 的透传入口。它们通过
`SdkManager.currentSdkVersion()` 解析当前项目 SDK，查找或安装 SDK 缓存，然后用原始
参数执行 `<sdk>/bin/flutter`。单独传 help 参数时，命令输出 `fluoh` wrapper 的
帮助，而不是转发给 Flutter。

设计约束：

- 不改写 Flutter 参数。
- 未选择 SDK 时给出明确操作提示。
- SDK 缓存缺失时按需安装已选择的 SDK。
- 透传 Flutter stdout 和 stderr，不追加命令自身语义。

### `fluoh doctor`

`doctor` 是诊断命令，除非使用 `--strict`，否则打印结果后返回成功。裸
`fluoh doctor` 检查 fluoh 安装状态、Git 和 Dart、已配置 source 快照、OpenHarmony SDK
工具链、Android SDK 与 Java 工具链、Chrome/Web 工具链，以及当前 host 支持的 Apple 或桌面工具链。
普通输出会在每个检查完成后立即打印，避免设备发现较慢时命令长时间无反馈；JSON 模式会等待全部检查完成后，
只输出一个机器可读对象。

OpenHarmony toolchain 只关注 SDK 路径和版本、`hdc`、emulator 版本或缺失状态。当同时选择
iOS 和 macOS 时，Xcode 只检查并输出一次合并的 iOS/macOS 工具链；只选择其中一个平台时保留
对应平台的 Xcode 标题。Connected devices 使用类似 Flutter 的对齐行，展示 name、id、
platform 和 details。

命令特意不提供 `-v` 或 `--verbose`，因为 Dart 的 `pub global run` 在全局可执行文件
fallback 到 pub 时会把 verbose 参数当成 pub 自己的日志开关，可能在 fluoh 启动前输出依赖求解日志。
`doctor` 也没有单独的 `--details` 模式；普通输出已经打印完整的人类可读检查项，机器可读详情使用
`--json`。
只有传入 `-p` 或 `--project` 时才会追加检查项目结构、已选择的 FlutterOH SDK
和所选平台目录。使用 `--platform ohos|android|ios|macos|linux|web|windows` 可缩小原生工具链和项目平台检查范围。

缺失或过期状态会作为 warning 输出，不会自动修复。自动化只需要原生工具链门禁时，使用
`fluoh doctor --platform ohos --json --strict` 这类平台化 strict 检查；也需要当前项目门禁时使用
`fluoh doctor --platform ohos --project --json --strict`。项目 JSON 会包含所选平台集合的
`platformDirectories` 数据，方便自动化判断是否需要创建或跳过 OHOS、Android、iOS、macOS、Linux、Web、Windows
平台工程。`--json` 会输出机器可读的同一组检查结果，并在每个 check 中包含
`id`、`group`，以及检查项需要的结构化数据。`--json --strict` 还会附带 `state` 和单个
`nextAction`：所有 strict check 通过时为 `ready`；需要修复本机环境或项目时为 `blocked`，
并包含 warning check 摘要和重跑命令。

### `fluoh devices` 和 `fluoh emulators`

`fluoh devices` 默认列出已连接的 OHOS、Android、Web 和当前 host 支持的目标。它支持
`--platform all|ohos|android|ios|macos|linux|web|windows` 和 `--json`；显式传入
Linux、Windows、iOS 或 macOS 时，即使当前 host 无法运行该平台，也会把它作为被检查目标。
普通输出使用类似 Flutter 的 `Name • id • platform • details` 行；不可用平台的 warning 会在已发现目标之后输出。

`fluoh emulators` 列出本地 OHOS、Android 和 iOS simulator 目标，普通输出使用
`Id • Name • Manufacturer • Platform` 表格。macOS、Linux、Web 和 Windows 是 host
或浏览器目标，不提供本地 emulator。它支持同样的 `--platform` 和 `--json` 选项。
`--launch <id-or-name>` 会启动本地 emulator 或 simulator，并要求只选择一个平台。

### `fluoh upgrade`

`upgrade` 升级 CLI 自身，不升级项目依赖。Homebrew 安装执行
`brew upgrade fluoh`，Dart global 安装执行 `dart pub global activate fluoh`。
本地源码 checkout 会被拒绝，因为替换 checkout 属于用户主动决策。
内置 skill 跟随 CLI 版本；升级后应重新运行 `fluoh skill --path`，并在复制过
skill 的 AI agent 中覆盖安装或重载打印的路径。

## Source 命令

Source 命令分为两类：消费侧命令管理已配置的本地快照；维护侧命令编辑 source
仓库本身。source 快照是保存在 `$FLUOH_HOME/sources/<name>` 下、已经校验通过的
Source 本机副本。

### 消费侧命令

`fluoh source list` 会先要求 Source 运行时确保已配置 source 快照和 `sources.lock.json`
可用，然后读取 `$FLUOH_HOME/config.json`，输出每个已配置 source 的名称和显示值。
空配置是 warning，不是错误。`--json` 输出同一份 source 列表，包含 source 名称、
显示值、缓存路径、URL 和优先级。

`fluoh source stats [--sdk <version-or-line>]` 读取合并后的 Source SDK 和 Package
索引，按 FlutterOH SDK 版本或 line 汇总 compatible、experimental、broken 的 Package
记录数量。它不会修改配置、快照、lock 文件或 Source 仓库内容。`--json` 会输出同样的数量，
并按状态列出 Package 名称。

`fluoh source enable <name> <url-or-path>` 让当前机器可以使用一个本地或 Git Source。它会
校验 source 名称，拒绝替换官方 source 名称，并把缓存路径固定为
`$FLUOH_HOME/sources/<name>`。普通本地路径会在 `$FLUOH_HOME/config.json` 中规范化为
绝对 `file:` URL，后续 `source update` 才能从原始目录刷新缓存。本地路径和 `file:` URL
会复制校验后的快照；HTTPS/SSH URL 会立即 clone，并且在写入配置项前完成校验。
`--priority` 默认值为 `10`，source 数据重叠时优先级越高越先使用。`--json` 会把已启用
source 名称、原始输入、规范化 URL、缓存路径和优先级作为单个机器可读对象输出。新快照校验通过后，
Source 运行时会一起提交配置项和重新生成后的 lock。

重叠数据的合并规则是显式的：

- SDK release 按 tag 合并。优先级高的 source 胜出；同优先级下发布记录冲突会报错。
- Package 发布记录按 `package + sdkLine + upstreamVersion` 分组。高优先级会替换同组低优先级记录。
  默认消费侧索引只包含 `compatible` 发布记录。`deps check`、`deps fix` 和
  `deps upgrade` 可通过 `--all-release-statuses` 为单次命令显式包含非 compatible
  记录。
- 同优先级下，派生 tag 相同但 repository 或 path 不同会报错。同组内不同 tag 可以并存，由依赖规划器按项目策略选择最佳候选发布记录。
- Package 级 upstream URL 和 advisory 文本来自定义该 Package 的最高优先级 source。

`fluoh source disable <name>` 在当前机器停用用户 Source。官方 Source alias
`flutteroh` 由工具持有，priority 固定为 `0`。该命令只拥有被停用的配置项，lock 维护交给
Source 运行时。`--json` 会把被停用的 source 名称和停用状态作为单个机器可读对象输出。

`fluoh source update [name]` 刷新全部 source 或单个指定 source。命令选中的 Git source
会重新 clone，命令选中的 `file:` source 会从配置的本地目录重新复制。随后 Source 运行时会校验
所有已配置 source 快照，因为 lock 是基于全部已配置 source 的合并索引。Git 传输失败会作为
sync 失败输出并给出重试提示；clone 成功后 source 内容未通过 schema 校验时，保留 source
校验诊断，不会包装成网络问题。`--json` 会把刷新数量和 source 条目作为单个机器可读对象输出。

会修改 source 状态的命令把候选 config 或快照状态交给 Source 运行时。校验或 lock
生成失败时，运行时必须保留上一份可用的 config、快照和 lock。

### 维护侧命令

`fluoh source check [path] --schema-only` 校验本地 Source 仓库，但不会读取或写入
`$FLUOH_HOME/config.json`、source 快照或 `sources.lock.json`。不传 `path` 时默认使用当前目录。
该模式会检查 Source root schema、SDK 元数据、Manifest routes、Manifest name、Package
route/name 一致性、Package release 记录，以及 Package index 能否构建。它不会读取 Git diff、
fetch SDK tags、clone Package 仓库，也不会验证已声明的 release；发布数据更新仍由
`fluoh source sync` 负责。`--schema-only` 是本地 Source 校验模式，不能和 diff、release、
work-root 或 Package 验证选项组合使用。

`fluoh source init <path>` 创建 source root `fluoh.yaml`、
`manifests/example/fluoh.yaml` 注释 Manifest 模板和 README。目标文件已存在时会保守
跳过并报告。生成的 `fluoh.yaml` 是合法的空 Source 脚手架，并带有注释形式的
repository、SDK 和 Manifest 路由示例，维护者可按需取消注释。维护者直接编辑 Manifest
文件中的 advisory 和 maintenance 信息；发布记录由 `fluoh source sync` 生成。

`fluoh source sync [path]` 读取 Source root 里的 Manifest routes，把每个
Manifest 的 `repository.git.url` 作为 FlutterOH Package 仓库，先用
`git ls-remote --tags` 发现 release tags，并和当前 Source release records 对比；只有发现
所选 tag 尚未记录时，才打开 Package 仓库读取该 tag 下固化的 Package `fluoh.yaml`，再把
历史发布记录写入同名 Package Manifest route。不传 `path` 时默认使用当前目录。source
元数据应来自已发布支持记录，而不是维护中的仓库状态。当 `<path>` 是
`$FLUOH_HOME/sources/<name>` 下的某个
已配置 source 快照时，sync 会被视为已配置 Source 快照变更，由 Source 运行时重建合并后的
lock。当 `<path>` 是配置快照之外的维护仓库时，本机 lock 不会变化；发布或复制到已配置快照
后，再运行 `fluoh source update <name>`。使用 `--manifest <name>` 或 `--package <name>`
可以定向 sync discovery；大型 Source 可用 `--concurrency <n>` 限制并行 tag discovery。
`--json` 会输出已同步和跳过的 Package 记录，并附带包含 `knownTags`、`discoveredTags`、
`tagsToSync`、`skippedTags` 和 route 状态的 `plan`。当 Source 根声明了
`sdk.versions` 时，SDK line 未被这些 SDK 版本覆盖的 tag 会以
`sdk-line-not-in-source` 原因跳过。缺少或无效 Package `fluoh.yaml`、tag 和
metadata 不一致、或 `package.path` 和当前 Source Manifest 不一致的 tag 也会按 tag
跳过并记录在 `skippedTags`，不会中断整轮 sync。release tag 视为由 release metadata
推导出的不可变记录；移动已有 tag 不会自动 sync，应发布新的 release tag 或人工维护。

`fluoh source check [source]` 是给 Source 维护者和 CI 使用的只读验证命令。
不传 `source` 时默认检查当前目录。`source` 可以是本地 Source checkout 路径，也可以是
GitHub pull request URL。命令会校验 Source 文件，识别变更的 Manifest route，然后验证已
声明的 Package release 引用。Release 验证会克隆引用的 FlutterOH Package 仓库，检查声明的
release tag，读取每个 tag 下 Package manifest 记录的分支，并在 tag 固化的提交上运行
`fluoh package check --package <name> --json`。Source metadata 导入和文件更新仍由
`fluoh source sync` 负责。JSON 输出包含
`recommendation`、`changeType`、`affectedManifests`、`changedReleaseRecords`、
`releaseCheckPlan`、`skippedReleaseChecks`、`sdkChecks`、`changedFiles`、`errors`、
`warnings`，以及 checkout/check 细节。默认按 `--base-ref` 识别变更 Manifest 文件。只有 Source 根
`fluoh.yaml` 变更时，命令会比较 base ref 和 HEAD 的 Manifest route 名，只检查新增或删除
的 route，并用 `git ls-remote --tags` 检查新增 SDK tag；SDK-only 根元数据变更只检查根文件。
Manifest 文件变更时，命令会对比 base ref 的 release records，只
验证新增或修改的 release record、package 新增、SDK line 新增、repository 变化或
`package.path` 变化。PR diff 检查只校验 Source root 和受影响的 Manifest
route；显式全量审计、diff fallback，以及 push/manual 的 `--skip-release-checks` 检查会校验
全部 Manifest route。只改 advisory、maintenance 或删除 release record 时作为 YAML-only
检查处理。目标不是 Git worktree 或 diff 无法读取时，会退回检查所有 Manifest route，并报告
warning。明确需要全量审计所有 Manifest route 时传 `--all`；只想校验 Source YAML 和变更
route 选择、不克隆 Package 仓库时传 `--skip-release-checks`。全量审计可以用
`--manifest <name>`、`--package <name>`、`--shard <index>/<total>`、
`--concurrency <n>` 和 `--max-release-checks <n>` 收窄或分片。
`--all` 和 `--base-ref` 不能同时使用。`ready` 只表示技术检查通过，`blocked` 表示修复
errors 前不应合并，`needs-maintainer-decision` 表示需要人工判断。Pull request 自动化应把
它作为 check + comment 使用；最终 approval 和 merge 仍由维护者负责。

## SDK 命令

`fluoh sdk list` 合并远端 source release 和本地已安装 SDK 缓存。source index 不可用
但本地已有 SDK 时，仍会列出本地条目。`--json` 输出 SDK 版本、channel、安装状态和
status。

`fluoh sdk install <version-or-series>` 支持精确 SDK 版本，也支持 `3.35`
这样的版本系列。版本系列优先选择最新 stable 版本。管理器会把 SDK 仓库 clone 到
`$FLUOH_HOME/sdks/<version>`，checkout 对应 Git tag；失败时删除未完成的目标目录。

`fluoh sdk current` 读取当前项目 SDK 版本。未选择 SDK 时输出 warning，并返回退出码
`1`。`--json` 会报告是否已选择 SDK，以及已选择时的版本。

`fluoh sdk remove <version-or-series>` 解析请求的 release 或精确本地缓存版本，只删除
`$FLUOH_HOME/sdks` 下匹配的 SDK 目录。

`fluoh sdk use <version-or-series>` 是项目修改命令。它要求当前目录是 Flutter 项目，
拒绝覆盖 FlutterOH Package 仓库元数据，解析或安装 SDK，写入项目 `fluoh.yaml`，并更新
`.fluoh/flutter_sdk` 作为稳定的 IDE SDK 路径。默认情况下，它会在项目缺少 `ohos/`
目录时使用已选择 SDK 执行 `flutter create --no-pub --platforms=ohos .`。
`--no-init-ohos` 可跳过这个默认初始化。`--pub-get` 会在切换和可能的 OHOS 初始化后
执行 `flutter pub get`。

## 依赖命令

这些命令面向普通 FlutterOH 项目，并保留 `pubspec.yaml` 中的无关内容。

`fluoh deps get` 会通过已选择 SDK 执行 `flutter pub get`，并允许透传额外参数。
它会在所有主 Package 目录和已有且包含 `pubspec.yaml` 的 Package example 中运行。
它刻意跳过 Package Source 数据，让依赖解析在 source 快照需要修复时仍然可用。如果已选择
SDK 缺失，SDK resolver 只会为查询并安装该 SDK 而加载 Source index。

`fluoh deps check` 读取项目 `fluoh.yaml` 中的依赖策略，根据已配置 source 构建依赖计划，
并把依赖分组为 ready、needs decision、manual action、unavailable、already OK、
transitive 和 advisory。fresh Source lock 会提供 Package 路由提示；命令随后只读取可能包含
项目 lockfile 中 Package 的 Manifest 文件。默认只考虑 `compatible` Source release 记录；
传入 `--all-release-statuses` 会额外考虑 experimental 和 broken release。`--json`
输出同一计划的机器可读 JSON。

`fluoh deps fix` 根据依赖计划应用推荐 FlutterOH 支持变更。它会按照
`dependencyPolicy.pubspecSection` 写入 `dependency_overrides` 或直接改写依赖声明。
版本不匹配默认跳过，除非 `dependencyPolicy.versionChanges` 为 `any`；非 compatible
release 状态默认跳过，除非本次命令使用了 `--all-release-statuses`。
`--dry-run` 或 `-n` 只打印计划，不修改 `pubspec.yaml`。`--json` 输出机器可读 JSON，
包含变更摘要、已应用数量和 dry-run 标记。写入前会校验生成后的 YAML；如果校验或写入失败，
会恢复原始 `pubspec.yaml`。

`fluoh deps upgrade` 比 `deps fix` 更窄：只升级已有 FlutterOH 依赖替换，不新增替换。它使用
同样的版本变化策略、命令级 release status 选项和 dry-run 行为。`--json`
输出依赖计划、变更摘要、已应用数量和 dry-run 标记，并且不会输出人类可读进度文本。

## Package 仓库命令

`fluoh package list` 是消费 source 的查询命令。它列出已配置 source 中声明的 Package
名称、兼容 SDK 版本线和 source 别名。命令通过 Source 运行时读取数据，所以必要时会初始化
或刷新 Source lock。`--json` 输出同一列表的机器可读 JSON。

其余命令维护 FlutterOH Package 仓库。它们假设当前是 Git 仓库，并且对分支和工作树状态
保持严格要求。

这些命令的 AI 实现循环由 `skills/fluoh/SKILL.md` 负责路由，详细流程放在
`skills/fluoh/references/` 中维护。用户文档只保留简短入口，所有 AI agent 都使用同一个维护入口。

### 支持流程

支持以 Package 分支和 FlutterOH 大版本线为单位维护，而不是以 SDK patch 版本为单位维护。
例如完整 SDK `3.35.8-ohos-0.0.3` 对应 SDK 版本线 `3.35`，Package `camera`
维护在 `ohos/3.35/camera`。

推荐流程：

1. 选择完整 SDK 版本。
2. 从 SDK 版本推导 SDK 版本线。
3. 不管 Package 是 spec-first 新建还是从 upstream port，都创建或切换
   `ohos/<sdkLine>/<package>` 分支。
4. 在 Package `fluoh.yaml` 中记录 origin：`created` 表示基于本地 spec 新建，
   `ported` 表示基于 upstream 仓库移植；ported Package 还要记录当前目标 upstream
   版本/ref 和 commit。
5. 开始实现变更前，先把生成的 `doc/fluoh/<package>/spec.md` TODO 替换为已
   review 的 Package contract：需求、public API、目标平台矩阵、平台行为、平台 API
   映射、example、测试期望和验收证据。`fluoh package next` 会把残留的生成 spec TODO 作为
   `spec-review` blocker，也会拦截未填写的 Package spec 模板占位符。AI agent
   可以使用 `skills/fluoh/references/package-spec-template.md` 作为填写结构。
6. 开始实现变更前，先用 `fluoh package scope init` 和
   `fluoh package scope check` 初始化并补齐 P0 support scope。support scope 位于
   `doc/fluoh/<package>/scope.yaml`，按 scope entry × platform 矩阵记录
   支持决策、平台来源或原因、必要的实现计划、测试用例，以及功能或回归证据。
7. 开始实现变更前，先用已选择 SDK 做基线检查，包括 `fluoh deps get`、
   `fluoh flutter analyze`、已有 Package 测试或 example 构建；先修复非 OHOS 平台
   因 SDK 切换暴露的问题。
8. 支持实现中使用 `status: experimental`；完成并可推荐时省略 `status`，默认就是
   `compatible`。
9. `fluoh package version` 更新Package 支持发布版本和状态。
10. `fluoh package check` 运行最终本地 gate，不创建 tag。
11. `fluoh package release` 打 release tag，tag 固化当前代码、测试和 Package
   `fluoh.yaml`。
12. `fluoh source register` 把第一个已发布 Package 分支注册到 Source 仓库；后续 release
    由 `fluoh source sync` 导入。

`fluoh create` 只负责 Flutter-like 项目骨架。它通过所选 FlutterOH SDK 转发
`flutter create` 参数，可以用 `fluoh create . --platforms=ohos` 给已有 App 补平台目录，
但不创建 FlutterOH Package 生命周期 metadata、Package 分支、release tag 或 Source 记录。

`fluoh package new <name>` 创建 spec-first FlutterOH Package 仓库。它先初始化
`main` 分支并提交固定仓库索引 `README.md`，再创建 `ohos/3.35/my_plugin` 这类
Package 分支，配置 FlutterOH SDK，运行请求的 Flutter package/plugin template，
写入带 `origin.kind: created` 的 `fluoh.yaml`，创建
`doc/fluoh/<package>/spec.md`，生成 `FLUOH.md` Package 上下文，并暂存生成文件。
`--platforms` 接受逗号分隔的 fluoh workflow 平台列表：`ohos`、`android`、`ios`、
`macos`、`linux`、`web`、`windows`。新建 Package 也必须遵守和 port Package 相同的
SDK-line 分支和 release 规则，这样 Source 才能按不同 FlutterOH SDK line 解析不同实现。
该命令不发布 pub.dev、不 push，也不创建 release tag。

`fluoh package port <upstream>` clone upstream 仓库，选择一个 Package，创建
`ohos/3.35/camera` 这类 FlutterOH 分支，配置 SDK 和 remote，写入带
`origin.kind: ported` 的 `fluoh.yaml`，记录 upstream 版本/ref/commit，生成
`FLUOH.md` Package 上下文，创建 `doc/fluoh/<package>/spec.md`，然后暂存生成文件。如果选中的 Package 已有 Flutter example，
命令会新增 OHOS 平台文件和 example SDK 配置。它不会创建 commit。
不传 `--package-path` 时，只选择 upstream 仓库根目录 Package。处理 monorepo 时，为
upstream 仓库保留一份支持仓库，并用 `fluoh package add <package-path>` 增加后续 ported
Package 分支。`package port` 和 `package add` 默认选择所选 Package 最新有效 upstream
release tag；指定 Package 版本用 `--upstream-version`，只有 release tags 无法识别目标快照时才用
`--upstream-ref`。
命令始终要求 `--repository-name <repository-name>`；它用于推导默认输出目录和默认
FlutterOH origin URL，Package 身份仍来自 `package.name`。可用参数包括
`--package-path`、`--upstream-version`、`--upstream-ref`、`--output`、`--repository-name`、
`--sdk`、`--repository`、`--git-author-name`、`--git-author-email`、`--org`、`--plan`
和 `--json`。Git 作者参数只配置新仓库的本地 Git 身份；`--org` 用于覆盖给 example
新增 OHOS 平台时传给 `flutter create` 的 organization。
`--plan --json` 只在临时目录完成 clone 和解析，输出单个机器可读 plan 对象；不会创建仓库、
写文件、stage 文件或 commit。plan 包含 `warnings[]`，用于报告 Dart SDK 不兼容、默认分支未发布版本、
federated implementation 推荐等情况，并包含所选 Package 的 `supportProfile`。

`fluoh package discover <upstream> --json` 会把 upstream 仓库 shallow clone 到临时目录，
扫描非 example 的 `pubspec.yaml`，并报告 `flutter.plugin.platforms` 未声明
`ohos` 的 Flutter plugin Package。它是只读命令，不会创建 Package 仓库、配置
remote、checkout 分支或写入项目文件。JSON 输出包含筛选条件、已检查 pubspec
数量、有效 Flutter plugin 数量、候选和推荐数量、候选 Package 名称、路径、版本、已声明平台、缺失平台、
federated `default_package` 声明、每个候选的 `supportProfile` 能力分类、
复杂度、风险原因、必需证据、建议覆盖种子、`officialDocsRequired`、
`officialDocTopics` 和 `portCommand`，当 app-facing plugin 应新增
`<package>_ohos` 这类平台实现 Package 时给出的
`implementationRecommendation`、多 Package 的 `queueCommand`，以及非致命
`issues[]`。默认 `queueCommand` 只包含推荐候选；被 app-facing Package
的 `default_package` 引用，或属于同一 federated family（例如
`<package>_android`）的 Android、iOS、Web、Linux、macOS、Windows
现有实现 Package 仍会显示，但会标记为
`covered_by_federated_app_facing_package` 并带有
`coveredByImplementationRecommendations[]`。测试 fixture plugin 和平台辅助 plugin
也会作为上下文保留，并带有 `test_fixture` 或
`platform_specific_helper` 等 role，但不会进入默认队列。当 AI 或维护者拿到
monorepo upstream URL 但没有明确 package path 时，先用它列出简短候选，再运行
`package port`。传 `--include-existing-platform` 可以把已经声明目标平台的 Flutter plugin
也列出；`--missing-platform` 默认是 `ohos`。

`fluoh package queue <package-path>... --json` 会在现有 FlutterOH Package 仓库中解析只读
多 Package 队列。它会拉取 upstream refs，但保持当前分支不变，并为每个 Package 输出名称、
路径、选中的 upstream 目标、目标 `ohos/<sdkLine>/<package>` 分支、该分支是否已存在、
SDK/Dart 兼容性预警，以及下一条 `fluoh package add` 或 `package status` 命令。维护同一个
upstream monorepo 的多个 Package 前，先用它排队，然后一次完成一个 Package 分支 checkpoint。
跨多个已存在 Package 分支运行 verify/build/run/check 时，优先为每个 Package 分支使用新的 clone
或独立 Git worktree，避免某个分支中被忽略的平台构建产物在切到另一个分支后变成 untracked 文件。
不要在未获维护者明确批准时运行 `git clean` 等破坏性清理命令。

`fluoh package scope init --package <name>` 创建
`doc/fluoh/<package>/scope.yaml`。这个文件是 support-scope 记录，不是工具自动判定：
AI agent 和维护者在阅读 public Dart API、目标平台行为、已有平台实现、example、测试和平台 API
来源后填写它。init 默认从 branch-local spec 的 `Support Scope Seeds` 表导入具体行；
当该表过期或刻意留空时传 `--no-from-spec`。
`fluoh package scope check --json` 校验 P0 平台行是否有支持决策、平台来源或原因、
必要的实现计划状态、测试用例，以及功能或回归证据；support scope 不完整时返回非零。
`fluoh package scope status --json` 输出同一状态但不失败，便于交接脚本汇总剩余的计划或证据缺口。
所有 package scope JSON 输出都使用 `supportScope` 表示解析后的状态对象。

`fluoh package add <package-path>` 在现有 FlutterOH Package 仓库中创建另一个 Package 分支。
它要求工作树干净，基于同步后的 upstream 分支解析目标 Package，切到选中的 release/ref
commit，创建 `ohos/<sdkLine>/<package>`，写入单 Package `fluoh.yaml` 和文档，在已有
Flutter example 时准备 example，创建 `doc/fluoh/<package>/spec.md`，并暂存生成文件。它支持 `--upstream-version` 和
`--upstream-ref`，选择规则和 package port 相同；也支持 `--org` 覆盖传给 `flutter create`
的 example organization。`--plan --json` 会在不 checkout、不写项目文件、且不要求工作树干净的
情况下解析 add 计划；计划里的 `warnings[]` 使用和 package port 相同的保留最新 upstream
目标的 SDK 兼容性策略。如果目标 Package 分支已经存在，命令会提示维护者切到已有分支，
用 `fluoh package status` 查看现有支持分支，或用 `fluoh package upstream sync` 更新它，而不是创建重复支持状态。
命令失败时会通过文件快照保护本地状态。

`fluoh package upstream check` 和 `fluoh package upstream sync` 只适用于
`origin.kind: ported`。created Package 没有 upstream；实现继续走
`fluoh package next`，Source 元数据继续走 `fluoh source sync`。`upstream check`
会拉取 upstream 并报告当前 Package 分支是否已经指向选中的 upstream 目标。

`fluoh package upstream sync` 会拉取 upstream 分支和 tags，快进 Package `upstream.git.branch` 记录的
upstream 分支，从 `--upstream-version`、`--upstream-ref` 或最新有效 release tag 解析 Package
目标提交，回到 `fluoh.yaml` 记录的 `repository.git.branch` 分支，先把选中的目标提交合并
进来但不立即提交，然后更新 `fluoh.yaml` 中的 upstream 元数据，确保
`doc/fluoh/<package>/spec.md` 存在并暂存；存在变更时提交 `Sync upstream package`。
如果没有有效 release tag 且未传显式 target，则回退到已同步的 upstream 分支 HEAD。
如果解析出的目标已经和当前分支 metadata 及 commit 一致，`upstream sync` 会明确提示
该 Package 分支已经指向对应 upstream version，并且不创建 commit。`upstream sync` 会拒绝低于当前分支
upstream version 的显式 Package 版本；这种情况应使用 `fluoh package version --status broken`
标记当前支持分支为 broken，而不是降级分支。sync 后，`fluoh package next` 会要求
branch-local spec 引用当前 upstream version 和 commit，之后才继续实现工作。合并冲突会留给用户解决，之后
`fluoh package upstream sync --continue` 校验已暂存的解决结果并完成流程。如果中断的 merge 使用了自定义非
tag ref，继续时传同一个 `--upstream-ref`；release tag 通常可以从 `MERGE_HEAD` 自动推断，
但非 tag ref 不能。
continue 还会在更新 `fluoh.yaml` 前校验已解决工作树中的 Package version 是否匹配选中的 upstream
target。`--abort` 对进行中的 sync 执行 `git merge --abort`。`--json` 会输出完成的 sync 动作列表和提交状态。
fetch 失败输出 `package.upstream.fetch_failed`；合并冲突输出 `package.upstream.merge_conflict`，包含冲突文件列表和
`--continue` 下一步命令；没有产生可解决冲突的 merge 失败输出 `package.upstream.merge_failed`。Git 有有效输出时，
JSON diagnostic 会包含裁剪后的 stdout 和 stderr 尾部。

`fluoh verify` 会为当前项目或 Package `fluoh.yaml` 中记录的当前 Package 运行自动化验证。它会先用已选择 SDK 执行 `pub get` 和 `analyze`：Flutter Package 使用
`flutter`，非 Flutter Package 使用 `dart`；如果存在 `test/**/*_test.dart`，继续运行测试。
在 Package 仓库中，如果存在顶层 Flutter example（`example/pubspec.yaml`），也会验证
example。当发现 `integration_test/` 时，`verify` 会记录 skipped discovery step，并给出后续平台化
`fluoh run ... --json` 命令；这只是采集设备证据的提示，不代表交互证据已通过。
使用 `--package <name>` 可校验请求的 Package 名是否匹配当前分支。
`--json` 会在 `targets` 下输出每个项目或 Package 的目标身份、phase、steps、diagnostics 和
`nextCommand`。目标失败时，顶层 `nextAction` 会汇总下一条恢复命令和 rerun 命令，方便 AI
继续执行一轮聚焦修复。使用 `--trace` 会在当前 task 的 `traces/` 目录下写入本地 AI diagnostic trace；
使用 `--trace-dir <path>` 可以指定 trace session 目录，manifest 为 `<path>/trace.json`。
JSON 模式仍只向 stdout 输出一个对象，并只在对象里加入本地 manifest
的 `trace` 引用；trace 无法写入时则加入 `traceError`。当目标位于 Git 工作树中时，还会输出
`dirtyAfterVerify` 和 `workingTreeChanges`，方便 AI 发现 `pub get` 留下的生成文件或 lockfile
变化并在提交前复核。一个实现循环内复用同一个 `--trace-dir` 可以把多条命令追加到同一个
session。

`fluoh build all|ohos|android|ios|macos|linux|web|windows` 构建当前 Flutter
项目或所选 Package example。`all` 会展开为当前项目根目录或所选 Package `example/` 中已经
存在的平台目录，按顺序执行这些适用 workflow platform，并记录每个平台结果，不会因为某个平台失败
就跳过后续平台。需要诊断缺失平台目录或明确补齐某个平台时，使用具体平台参数。iOS 构建会自动加入
`--no-codesign`。OHOS 构建可用 `--auto-sign` 根据项目或 example 申请的权限生成临时本地 debug
签名 profile，为本次构建 patch `ohos/build-profile.json5`，并在构建后恢复原文件。`build all --auto-sign`
只会把自动签名应用到支持该能力的平台。如果 Hvigor 签名失败但 Flutter 留下了新的 unsigned HAP，`fluoh` 会直接签这个 HAP，并在 JSON
中报告 `signingMode: direct-sign-fallback` 和可安装 HAP 路径。JSON 失败会对当前项目和
Package example 都使用平台化 diagnostic code，例如 `ohos.hap_build_failed`、
`android.apk_build_failed`、`ios.build_failed`、`macos.build_failed`、`linux.build_failed`、`web.build_failed` 和
`windows.build_failed`。`--trace` 和
`--trace-dir <path>` 使用与 `fluoh verify` 相同的本地 AI diagnostic trace 契约。JSON
输出的是事实证据摘要，不是 release-ready 判定。它包含
`workflowEvidence.classification: buildOnly`、`observedEvidence`、
`collectedEvidenceKinds`、`notCollectedEvidenceKinds`、`workflowContinuations`，
并在 build 通过时通过 `toolCommands` 给出后续 run smoke 命令。`collectedEvidenceKinds`
只表示命令结果或 artifact 已被收集；是否通过、失败、跳过或阻塞以 `observedEvidence` 为准。

`fluoh run all|ohos|android|ios|macos|linux|web|windows` 会先准备平台，再通过已选择 SDK
的 `flutter run` 启动当前项目或所选 Package example。`all` 会展开为当前项目根目录或所选
Package `example/` 中已经存在的平台目录，按顺序执行这些适用 workflow platform，并在前面平台
失败后继续收集后续平台结果。OHOS 与其他平台走同一条 Flutter run 路径；OHOS run 会应用临时
debug 签名准备和恢复。Android、iOS 的签名、设备、emulator/simulator 前置条件也使用同一套
run-preparation 和 target-selection 层。Web run 使用 Chrome 等浏览器 target。
OHOS hdc 调用有单次命令超时，设备发现失败时应返回 JSON diagnostics，而不是无限挂住。
默认 hdc 命令超时为 10 秒；本地调试或测试需要更短超时时可设置
`FLUOH_OHOS_HDC_TIMEOUT_SECONDS`。
当存在 `integration_test/` 且有具体 target 时，`fluoh run` 会继续在同一 target 上运行
`flutter test integration_test -d <device>`。Release 报告应单独记录这条已通过的测试命令，
因为普通 `fluoh run --json` 行只表示启动证据。
OHOS grant-path integration test 只有在自动点击允许不会改变测试意图时，才传
`--ohos-permission-dialog-policy allow`。默认 `disabled` 会把系统权限弹窗交给测试或
`fluoh drive` 场景处理，避免遮蔽 deny/error 路径。
`--session-file <path>` 会写入 `flutterRunSession`，包含进程、target、启动、日志以及可用时的
VM Service URI。`fluoh attach` 可以复用该 session，也可以直接接收
`--vm-service-uri <uri>` 或 `--device-id <id>`。它优先执行
`flutter attach --debug-uri <uri>`，除非设置 `--require-vm-service`，否则可回退到
`flutter attach -d <targetId>`。
run 和 drive 共用 target 参数：`--device-id <id>` 使用已有 target，`--emulator <name>`
指定本地 emulator/simulator，`--auto-emulator` 优先使用本地 emulator/simulator，再回退到已连接设备。
`run all` 可以使用 `--auto-emulator`，但 `--device-id`、`--emulator` 和
`--session-file` 都是单平台选项。
JSON 会输出 `workflowEvidence.classification: launchSmoke`、`observedEvidence`、
`collectedEvidenceKinds`、`notCollectedEvidenceKinds`、`workflowContinuations`，以及该
run 命令实际观察到的交互证据摘要。`collectedEvidenceKinds` 也可能包含失败的命令结果；
通过、失败、跳过或阻塞状态以 `observedEvidence` 为准。移动端平台启动成功后，`workflowEvidence.toolCommands`
会给出匹配的 `fluoh drive ... --dry-run --json` 命令，让 AI 继续规划点击、滑动、
权限 grant/deny 路径、截图和结果断言，而不是把启动当成交付完成。
移动端启动成功后必须至少获取一张截图或等价 UI 状态证据，并断言页面进入预期功能页。
如果示例 App 空白、停在 splash、被隐藏或显示异常，必须先修复 demo，再继续更完整的自动化。
对 `observedEvidence.interaction.status`，`integrationTestEvidenceFailed`
优先于同一矩阵里的其它通过行；`partialIntegrationTestEvidence` 表示只有部分 target
产出了通过的 integration-test 证据。两种情况都必须继续修复或补证据，不能当作 release-ready。

run-smoke 成功只证明 App 已启动。需要 UI、权限、文件、相机、定位、媒体、deep link 或外部
App 的流程，还需要功能验证证据，来源可以是已通过的 `integration_test`、`fluoh drive`
或带工具可读证据的 `manual-assisted`。manual-assisted 是操作方式，仍需要日志、session 状态、
稳定文本、语义标签、test key、命令 JSON、hilog 或 App 日志标记支撑。如果没有交互流程，报告必须写明
`No interaction required: <reason>`。
Package 支持不能只验证 OHOS。已有 Android、iOS、macOS、Linux、Web、Windows package/example
平台目录在当前 host 和 toolchain 支持时也必须作为功能测试目标；环境不支持的 target 必须记录
diagnostic 命令和阻塞原因。

交互场景放在 `doc/fluoh/<package>/scenarios/<platform>-<name>.md`，并以
`skills/fluoh/references/interaction-scenario-template.md` 作为动作契约。场景 Markdown
可以包含 fenced YAML，写明 `kind: fluoh.automationScenario`、`platform`、`steps`
和可选 `coverage` 元数据。

`fluoh drive all|ohos|android|ios` 是移动端 target 启动、交互场景和证据校验封装。
它复用 `fluoh run` 的 target 选择，`all` 会展开为已经存在的 OHOS、Android、iOS 平台目录，
默认优先使用本地 emulator/simulator，可针对当前项目或当前/指定 Package 分支运行。dry-run 和真实运行 JSON 都包含
`deliveryRecommendation`、`repairPlan`、`repairQueue` 和
`automation.coveragePolicy`；真实运行还会输出 workflow `targets` 以及记录启动/session
证据和 replay 材料的 `automation` 对象。稳定覆盖字段包括 `scenarioCoverage`、
`coverageSummary`、`inventory`、`capabilityCoverage`、`manifestPermissionCoverage`、
`pathCoverage`、`scenarioEvidence`、`qualityGates` 和 `repairLoop`。详细修复顺序属于
skill 和 report template。
真实 drive 会先执行同一套启动和可用的 `integration_test/` 步骤；只有 run 与
integration-test 都通过的 target 才会继续执行 scenario。
`--profile exploratory-smoke` 会加入内置的有界探索 profile，记录 session 检查、截图、
短等待和一次可选的通用滑动手势。它适合发现 crash、空白页和明显的 launch-smoke 回归，
但会标记为非 release gate 的探索证据；它不能替代明确的 scenario 断言、`integration_test`
或有记录的 no-interaction-required 理由。

可执行 scenario 支持 `captureScreenshot` 和 `screenshot` 作为辅助观察动作。
Android 会保存 `adb exec-out screencap -p`，iOS 会保存 `xcrun simctl io <target>
screenshot`，OHOS 会保存 `snapshot_display` 并通过 `hdc file recv` 拉取到本地。
动作结果会记录本地路径和字节数。截图是证据产物；功能是否通过仍应由 `assertText`、
`assertLog`、`assertSession` 或 integration-test 输出等工具可读断言支撑。

runtime permission 需要在每个支持平台覆盖 grant、deny 和行为不同的 error 路径。
只有平台不存在该行为时才使用 `notApplicable`；`blocked` 行仍是待修复项，不是 release-ready 证据。
iOS 自动化可用内置 XCTest runner；需要指定 Xcode 时设置
`FLUOH_XCODEBUILD`，只有必须强制权限驱动时才设置 `FLUOH_IOS_PERMISSION_DRIVER`。

当前项目 run 的 JSON 失败会包含 `ohos.run_failed`、`android.run_failed`、
`ios.run_failed`、`macos.run_failed`、`linux.run_failed`、`web.run_failed` 和
`windows.run_failed` 等平台 diagnostic；Package example 则在可判断时继续使用更细的设备、
run、runtime 和 integration test diagnostic。`--trace` 和 `--trace-dir <path>` 使用与
`fluoh verify` 相同的本地 AI diagnostic trace 契约。

`fluoh report create` 默认把 canonical Markdown 报告写到 Git 忽略的当前 task
`reports/` 目录；也可以用
`--output` 指定报告路径。
它接受一个或多个 `--trace-dir` 以及保存下来的 `--automation-json` 文件，提取命令行、
覆盖 gate、交互证据、diagnostics 和 fluoh feedback candidates，然后写入 package check
和交接流程需要的标准 AI 报告章节。传入 `--package <name>` 时，它还会读取
`doc/fluoh/<package>/scope.yaml`，写入 Support Scope 章节和
`supportScope` JSON 摘要。报告还会包含 `Official Platform Basis` 章节和对应交付 checklist 项；
ready 报告必须在这里写入已审查的官方平台资料，或明确说明不适用原因。
`check_report.py` 会校验包含 Support Scope 的 ready 报告是否已经完成
P0 计划和功能证据 gate。`--json` 只用 `report` 输出报告路径。该命令只拥有本地报告创建和发布建议；
最终发布批准以及 publish、push、tag、应用商店或 registry 动作仍由维护者负责。
`check_report.py` 和 `package check --report` 同时接受 CLI 默认的 `report.md`
以及 helper 生成的 `report-<timestamp>.md`；其他报告文件名会被拒绝，方便 handoff
和 release gate 识别 fluoh 生成的报告。

`fluoh clean` 默认删除当前 task 的可清理输出。使用 `--tasks` 删除整个选中 task
工作区，使用 `--all` 删除全部 task 工作区。它不会删除 SDK 安装、Source 快照、配置、
lock 文件、`.fluoh/flutter_sdk`、`fluoh.yaml`、`FLUOH.md`、`doc/fluoh/` 或 Source
元数据。使用 `--dry-run` 可以只查看目标而不删除；使用 `--json` 可以输出机器可读清理报告。

`fluoh package version` 更新 `fluoh.yaml` 中当前 Package 的发布元数据。
用 `--bump patch|minor|major` 递增 FlutterOH Package 支持版本，用
`--set <version>` 设置精确版本，用 `--status experimental|compatible|broken`
设置发布状态。`compatible` 会移除 status 字段，因为 compatible 是默认状态。
`--bump` 和 `--set` 互斥。`--dry-run` 只打印计划不写入，`--json` 输出机器可读结果。

`package new`、`package port` 和 `package add` 只在缺失时创建
`doc/fluoh/<package>/spec.md`。这个 spec 是跟随具体分支的人/AI 维护文档，负责 Package
需求、API 设计、平台行为、平台 API 映射、example 和测试计划。生成 spec 里的 TODO
和 Package spec 模板占位符都不算有效计划证据；`fluoh package next` 会把残留占位作为
`spec-review` 动作，直到它们被替换为已 review 的 Package contract。AI agent 可以使用
`skills/fluoh/references/package-spec-template.md` 作为填写结构。这些命令还会根据当前
Package `fluoh.yaml` 和所选 Package pubspec 重写 fluoh 拥有的 `FLUOH.md` Package 上下文。
`FLUOH.md` 用于让 fluoh skill 快速了解 Package 快照、spec 和 support scope 路径、可选
federated 路线、fluoh 工作流入口和当前 Package 分支的 FlutterOH Release History；重写时会保留已有 release history，其余内容全量重新生成。
当所选 Package 是带 `default_package` 声明、但没有 OHOS 平台的
federated app-facing plugin 时，`FLUOH.md` 会包含与 package discovery 相同的
`<package>_ohos` 实现 Package 路线。Release history 中的 TODO 条目发布前必须替换为真实
release notes。

`fluoh source register <package-repo> --package <name> --source <path> --json`
把第一个已发布 FlutterOH Package 分支注册到 Source 仓库。它读取 Package 仓库 release tag、
加载 tag 内的 Package `fluoh.yaml`、用 `fluoh package check` 验证 release，创建或更新
`manifests/<package>/fluoh.yaml`，并把 route 写入 Source root `manifests[]`。
它同时接受 `origin.kind: created` 和 `origin.kind: ported`。created Package 使用
`<package>-ohos-<sdkLine>-<release.version>` 这类 tag；ported Package 使用
`<package>-<upstream.version>-ohos-<sdkLine>-<release.version>`。`source register` 只负责
首次 Source 注册；已注册 Package 的后续 release 由 `source sync` 导入。

`fluoh package handoff --json` 读取当前 Package 分支、Git 状态、当前 task trace 和
当前 task report，然后输出一个
JSON 对象，包含 Package 元数据、当前分支、manifest 分支、分支是否匹配、工作树脏状态摘要、
证据路径、后续命令应复用的 task trace 目录和下一步命令。下一步命令会先运行报告校验，再运行
`package check`；已有报告时，`check_report.py` 和 `package check` 都会使用最新
report 路径，并且 AI workflow 必须在声明 ready 前完成独立审核反馈循环。它不修改仓库。
AI 任务需要恢复、转交，或确认分支是否可以进入最终 verify、drive 证据、报告创建、
报告校验、独立审核或 `package check` 时使用它。

`fluoh package check` 校验 release 元数据，确认配置的 SDK 版本存在于 source，运行
`fluoh verify`，确认工作树仍然干净，并报告将要创建的 release tag。它不会创建或推送
tag。使用 `--package <name>` 可校验请求的 Package 名是否匹配当前分支。
`--json` 会输出 tag、warning、认证状态和验证结果。Check 默认不要求设备或 AI report
证据；没有提供认证报告时只输出非阻断 warning。需要 AI/CI 认证交付时，传
`--report <path>` 强制检查已完成的当前 task 报告。认证报告必须是 `ready`，完成所有交付
checklist，包含通过的 `fluoh verify` 证据，包含通过的 OHOS build 或 run 证据，并包含交互
readiness 证据。交互证据必须来自已通过的 `fluoh drive --json`、带证据支撑的
`flutter test integration_test -d <device>` 命令行，或带工具可读证据的 `manual-assisted`。
报告还必须包含 `Automation Coverage` 章节和完整必需自动化 gate 集合；所有 gate 行都必须是
ready/covered/passed/notApplicable。最后，报告必须包含通过的交互证据，或明确写出
`No interaction required: <reason>`。当 CI 或 AI 交接必须证明真机或模拟器上的 OHOS run
已通过，而不是只有 build-only 证据时，再加 `--require-ohos-run`。

`fluoh package release` 会运行同一套校验和验证，然后通过在 HEAD 创建 release tag
完成 fluoh package release，并可用 `--push` 推送。已有 tag 只有在已经指向 HEAD
时才会被接受。它不会发布到 pub.dev。

`fluoh package next` 读取当前 Package 仓库并只输出一个实现阶段动作。它会有意忽略 release
notes、compatible status、tracked local path 这类发布末端 blocker，直到实现循环已经产出证据
和报告。它会先检查 branch-local spec：缺失 spec、残留生成 TODO、Package spec 模板占位符，
或 ported spec 未引用当前 upstream version/commit 时，都会输出 `spec-review` edit 动作。之后才检查
`doc/fluoh/<package>/scope.yaml` 下的 support scope：缺少 scope 时输出
`scope` 动作，P0 调研/计划/测试不完整时输出 edit 动作，执行阶段都通过后如果还缺 P0
功能证据则阻止创建报告。只有报告还不足以进入 `ready`；命令还要求 trace 中已经有 verify、
OHOS build、OHOS run、automation dry-run、automation run，以及所选 Package example 下每个
已有非 OHOS 平台按平台策略执行的 build/run 回归证据。Android 和当前 host 支持的 iOS
example 还需要已有平台 drive dry-run 和 drive-run 证据。使用 `--json` 时，`ok`
表示已成功计算下一步；应读取顶层 `state` 和 `nextAction.type` 来决定是运行命令、做一次聚焦修改、
以 blocked 停止，还是转交发布就绪检查。最新报告会先通过 bundled `check_report.py`
校验，`nextAction.type` 才能变成 `ready`；报告未通过时会输出 `report-check` edit 动作，
并把 checker 错误放到 `nextAction.details`。当 `nextAction.type` 为 `ready` 时，
`nextAction.nextCommands` 会列出后续 release-readiness 命令，包括 status、handoff
以及带已验证报告路径的 package check。默认 automation-run 动作使用普通
`fluoh drive ohos --json`，让场景或 integration-test 证据进入交互 gate。可选的
`--profile exploratory-smoke` 仍可作为有界诊断证据，但不能满足功能自动化。JSON 还会包含 `evidenceSummary`、
`remainingRisks` 和 `failureStreak`。它还会包含 `scope` support-scope 状态摘要和 `qualityProfile`，只读扫描
`integration_test` 文件、`doc/fluoh/<package>/scenarios/` 场景文档，以及 Android、iOS、macOS、
Linux、Web、Windows 等已有 example 平台目录。缺少功能验证面时，
命令会输出非阻塞的 `quality.functional_surface_missing` 风险，让实现循环区分 launch-smoke
证据和更强的功能证据。如果同一个 traced command 连续失败三次，`nextAction.type` 会变成
`blocked`，让自动化停止，而不是围绕同一个未解决失败反复改动。
如果没有当前 task，`package next` 会创建一个本地 task 工作区，让 trace、
visual-readiness 和 report 证据共用同一个本地上下文；它不会为了计算 `nextAction`
而修改 Package 源码文件。

`fluoh package status` 读取 Package `fluoh.yaml` 并汇总发布就绪状态，不修改仓库。它会检查
当前分支、工作树是否干净、package status、OHOS run 证据、功能交互证据、移动运行后的
visual page-readiness、release notes、license warning、Package 测试、Flutter example、
example OHOS 平台、example 测试，以及 tracked 文件是否包含本机 fluoh home
路径。即使 Package 已标记为 `compatible`，这些证据检查也仍然生效。对于已有 `default_package` 声明但没有 OHOS 平台的 federated app-facing plugin，
它也会为缺失的 `<package>_ohos` 实现 Package、`ohos.default_package` 和依赖路径报告
readiness blocker。如果已经声明了 `ohos.default_package`，status 还会校验 app-facing
Package 是否依赖该 default package，以及实现 Package 是否存在并声明 OHOS。使用
`--package <name>` 可校验请求的 Package 名是否匹配当前分支。使用 `--json` 时，输出包含
`state` 和唯一的机器可执行 `nextAction`，方便 agent 每次只处理或运行这一个动作，
然后重新执行 `nextAction.rerunCommand`。

## 状态归属

| 状态 | 所属方 / 维护入口 |
| --- | --- |
| `$FLUOH_HOME/config.json` | 通过 `source enable` 启用的本机 Source 配置、`source disable`、`source update`、首次默认 Source 初始化 |
| `$FLUOH_HOME/sources/<name>` | `source enable` 创建的本机快照、`source update` 刷新的快照 |
| `$FLUOH_HOME/sources.lock.json` | `lib/src/source/` 中的 Source 运行时；Source 状态变更、首次默认 Source 初始化，以及 load-index 检查发现过期或需要 SDK 元数据来安装已选择的 SDK 时重建 |
| `$FLUOH_HOME/sdks/<version>` | `sdk install`、`sdk remove`、按需执行的 Flutter wrapper |
| 项目 `.fluoh/tasks/<task-id>/` | task 本地 traces、reports、evidence、logs、sessions、commands 和 scratch 产物；由 `task` 和 `clean` 管理 |
| 项目 `.fluoh/current-task.json` | workflow trace/report/evidence 命令使用的当前 task 指针 |
| 项目 `fluoh.yaml` | `create`、`sdk use`、`deps check`、`deps fix`、`deps upgrade` |
| 项目 `pubspec.yaml` | `deps fix`、`deps upgrade` |
| FlutterOH Package 仓库 `fluoh.yaml` | `package new`、`package port`、`package add`、`package upstream sync`、`package status`、`package handoff`、`package version`、`package check`、`package release` 校验 |
| Package 分支本地 `doc/fluoh/<package>/spec.md` | `package new`、`package port`、`package add` 缺失时创建；由维护者/AI 维护，并在 `package upstream sync` 后 review |
| Package 生成的 `FLUOH.md` 上下文 | `package new`、`package port`、`package add` |
| Source root 和 Manifest 文件 | `source init`、`source register`、`source sync` |
| `.fluoh/flutter_sdk` | `create`、`sdk use`、`package new`、`package port` 的 SDK 设置 |
| Package examples | `package new`、`package port`、`package add`、`deps get`、`verify`、`package check`、`package release` |
