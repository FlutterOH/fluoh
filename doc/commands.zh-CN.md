# 命令设计

[English](commands.md)

本文档说明 `fluoh` 的完整命令面，以及每个命令背后的设计边界。它和
[schema.zh-CN.md](schema.zh-CN.md) 互补：schema 文档定义数据结构，本文档定义
命令如何读取、写入和保护这些数据。

命令实现主要位于 `lib/src/<domain>/commands/`，顶层注册逻辑位于
`lib/src/cli/fluoh_command_runner.dart`。

## 端到端工作流

AI 驱动适配是主要端到端链路。内置的 `skills/fluoh` 工作流是交给 AI 的入口：
它会判断当前目录是 App 项目还是 Package 适配仓库，然后驱动确定性的 `fluoh`
命令。命令负责可审计步骤：`sdk use` 选择 SDK、维护稳定 IDE 链接并创建默认
OHOS 平台；`deps` 替换 FlutterOH 依赖；`doctor` 诊断环境和项目；
`build` 执行 build-only 检查；`run` 或 `drive` 负责目标选择、启动、日志、
UI 自动化和 JSON 失败路由。

### AI 驱动适配

先在 AI agent 中安装或刷新 skill：

```text
从 https://github.com/FlutterOH/fluoh/tree/main/skills/fluoh 安装 fluoh skill，如果已存在则覆盖安装。
```

然后用一句话把目标交给 AI agent：

```text
使用 $fluoh，必要时先安装 fluoh，然后把当前 Flutter 项目适配到 OHOS。
使用 $fluoh，把 <upstream-git-url> 按 SDK 3.35 适配为 FlutterOH Package。
使用 $fluoh，继续适配 <package-name> 到 OHOS。
```

skill 会在 `fluoh --version` 失败时安装 CLI：优先使用
`dart pub global activate fluoh`，如果 Dart 不可用且是 macOS，则回退到 Homebrew。
如果 CLI 已经安装，AI agent 可以用下面命令发现本地内置 skill 路径和 helper script
命令：

```text
运行 `fluoh skill --json`，把返回的 localPath 安装为 skill，必要时重载 skills。
```

JSON 结果也会暴露 preflight、创建报告、检查报告、创建功能场景的 helper script argv，
以及报告模板和交互场景模板的 reference 路径。

实现代码前，AI agent 必须先检查 preflight 的 `upgradeChecks`。schema blocker
会暂停流程，直到当前安装的 `fluoh` 能读取这些 metadata。Package 仓库如果生成文档缺失或
状态过期，应先运行 `fluoh package docs refresh --dry-run`；
当工作树干净且不是 review-only 请求时，再运行 `fluoh package docs refresh`。如果
preflight 因 dry-run 失败而无法判断生成文档是否最新，应先修复 dry-run。

全自动适配必须先完成适配范围确认。用户的初始请求只授权 CLI 安装或定位、只读
preflight 和适配信息收集，不等于已经批准修改项目、Package、Source、本地 Git 或实现代码。
CLI 准备和只读 preflight 完成后，AI agent 在修改项目、Package、
Source 文件、本地 Git 配置、checkpoint commit 或实现代码前，必须先展示最终确认清单。
确认清单展示后必须等待用户明确批准。确认清单包括适配类型、工作目录、必要时的输出目录、
SDK 版本或版本线、必要时的 Package name 和 path、FlutterOH repository URL 或 path、
可能创建提交时使用的 Git author 身份、即将执行的写操作或文件改动，以及 release、push、
force-push、破坏性 Git 命令等需要单独批准的操作。只有用户已经在当前任务中明确确认过
同一份已解析适配范围，AI agent 才能跳过这次暂停。

skill 版本跟随 `fluoh` CLI Package 版本。用 `fluoh upgrade` 更新 CLI 后，内置
skill 文件也会更新；已复制 skill 的 AI agent 应重新运行 `fluoh skill --json`，
再覆盖安装或重载返回的路径。AI agent 完成前会写入
`.fluoh/reports/<scope>/ai-report-...md`，报告内包含交付清单。发布前应复核
diff、报告和只能在设备上验证的行为。

### 手动让 App 项目支持 OHOS

在已有 Flutter 项目中，如果不使用 AI agent，可以直接执行下面的命令链路，让项目能在
OHOS 上构建或运行：

```sh
fluoh source update
fluoh sdk use 3.35 --pub-get
fluoh deps check
fluoh deps fix --dry-run
fluoh deps fix
fluoh deps get
fluoh doctor --platform ohos --project
fluoh build ohos --auto-sign
fluoh devices --platform ohos
fluoh emulators --platform ohos
fluoh run ohos --auto-emulator
fluoh run ohos --device-id <id>
fluoh drive all --json
```

项目没有 `ohos/` 目录时，`fluoh sdk use` 默认会创建它。只有平台目录由其他流程维护时才使用
`--no-init-ohos`。如果没有可用设备或模拟器，把
`fluoh build ohos --auto-sign --json` 作为 build-only 证据，并根据 JSON
diagnostic 里的 `nextCommand` 继续处理本机环境。

## 命令面

根帮助把 CLI 工具命令放在 `Core` 分组（`skill`、`doctor`、`flutter`、`clean`
和 `upgrade`），随后把 `SDK & Metadata` 放在项目工作流前面，因为 SDK 和 Source
状态通常会先卡住适配流程。`Project` 放顶层 App 项目命令：`create` 和 `deps`。
`Package` 放 `package` 仓库命令组。`Workflow` 放共享执行和证据命令，顺序是
`plan`、`verify`、`build`、`run`、`drive` 和 `report`。`Devices` 放 target
inventory 和启动辅助：`devices` 负责已连接 target 发现，`emulators` 负责
emulator/simulator 启动。

| 命令 | 实现 | 用途 |
| --- | --- | --- |
| `fluoh --version` | `lib/src/cli/fluoh_command_runner.dart` | 输出 `fluoh` 版本、Dart 版本、平台和仓库地址。 |
| `fluoh help [command]` | `package:args` command runner | 输出全局或指定命令的用法。 |
| `fluoh skill` | `lib/src/cli/skill_command.dart` | 输出内置 AI skill 的路径、版本、更新和提示词信息。 |
| `fluoh clean` | `lib/src/clean/clean_command.dart` | 删除 `$FLUOH_HOME/cache` 下的可清理运行产物。 |
| `fluoh create [--sdk <version-or-series>] <args>` | `lib/src/project/create_command.dart` | 使用 FlutterOH SDK 创建 Flutter 项目，并把剩余参数透传给 `flutter create`。 |
| `fluoh plan app` | `lib/src/workflow/commands/plan_command.dart` | 输出只读 App 适配计划和命令队列。 |
| `fluoh plan package` | `lib/src/workflow/commands/plan_command.dart` | 输出只读 Package 适配计划和命令队列。 |
| `fluoh flutter <args>` | `lib/src/sdk/flutter_command.dart` | 使用最近的项目 `fluoh.yaml` 里选择的 SDK 运行 `flutter`。 |
| `fluohf <args>` | `bin/fluohf.dart` | `fluoh flutter <args>` 的快捷入口。 |
| `fluoh source` | `lib/src/source/source_commands.dart` | Package metadata source 使用和维护的命令组。 |
| `fluoh source list` | `lib/src/source/source_commands.dart` | 列出已配置的 FlutterOH Package metadata source。 |
| `fluoh source add <name> <url-or-path>` | `lib/src/source/source_commands.dart` | 把本地或 Git Package metadata source 加入工具配置。 |
| `fluoh source remove <name>` | `lib/src/source/source_commands.dart` | 从工具配置中移除非官方 Package metadata source。 |
| `fluoh source update [name]` | `lib/src/source/source_commands.dart` | 刷新并校验已配置的数据源快照。 |
| `fluoh source init <path>` | `lib/src/source/source_commands.dart` | 创建本地 source 仓库模板。 |
| `fluoh source sync [path]` | `lib/src/source/source_commands.dart` | 把已发布 FlutterOH Package 仓库元数据同步进 source 仓库。 |
| `fluoh source check [source]` | `lib/src/source/source_check_command.dart` | 校验 Source 文件并验证已声明的 Package release；本地 YAML/index 校验使用 `--schema-only`。 |
| `fluoh sdk` | `lib/src/sdk/sdk_commands.dart` | 本地 FlutterOH SDK 缓存的命令组。 |
| `fluoh sdk list` | `lib/src/sdk/sdk_commands.dart` | 列出远端 SDK 版本和本地 SDK 缓存。 |
| `fluoh sdk install <version-or-series>` | `lib/src/sdk/sdk_commands.dart` | 把 SDK 版本安装到 `$FLUOH_HOME/sdks`。 |
| `fluoh sdk current` | `lib/src/sdk/sdk_commands.dart` | 输出当前项目选择的 SDK。 |
| `fluoh sdk remove <version-or-series>` | `lib/src/sdk/sdk_commands.dart` | 删除一个已安装的 SDK 缓存。 |
| `fluoh sdk use <version-or-series>` | `lib/src/sdk/sdk_use_command.dart` | 为当前 Flutter 项目选择 SDK。 |
| `fluoh deps` | `lib/src/deps/commands/deps_command.dart` | 项目依赖命令组。 |
| `fluoh deps get` | `lib/src/deps/commands/deps_get_command.dart` | 为项目和 Package example 执行 `flutter pub get`。 |
| `fluoh deps check` | `lib/src/deps/commands/dependency_plan_commands.dart` | 输出依赖 FlutterOH 适配状态。 |
| `fluoh deps fix` | `lib/src/deps/commands/dependency_plan_commands.dart` | 应用推荐的 FlutterOH 依赖变更。 |
| `fluoh deps upgrade` | `lib/src/deps/commands/deps_upgrade_command.dart` | 只升级已有 FlutterOH 依赖替换。 |
| `fluoh package` | `lib/src/package/commands/package_command.dart` | FlutterOH Package 仓库命令组。 |
| `fluoh package list` | `lib/src/package/commands/package_list_command.dart` | 从已配置 source 列出 FlutterOH Package。 |
| `fluoh package create <upstream>` | `lib/src/package/commands/package_create_command.dart` | 初始化 FlutterOH Package 仓库。 |
| `fluoh package discover <upstream>` | `lib/src/package/commands/package_discover_command.dart` | 发现可能需要 OHOS 适配的 Flutter plugin Package。 |
| `fluoh package add <package-path>` | `lib/src/package/commands/package_add_command.dart` | 在 FlutterOH Package 仓库中创建另一个 Package 适配分支。 |
| `fluoh package queue <package-path>...` | `lib/src/package/commands/package_queue_command.dart` | 为 monorepo 解析只读多 Package 适配队列。 |
| `fluoh package sync` | `lib/src/package/commands/package_sync_command.dart` | 把选中的 upstream Package release 合入当前 OHOS Package 分支。 |
| `fluoh package status` | `lib/src/package/commands/package_status_command.dart` | 汇总 Package 发布就绪状态。 |
| `fluoh package handoff` | `lib/src/package/commands/package_handoff_command.dart` | 汇总 Package 分支状态、证据和 AI 交接下一步命令。 |
| `fluoh package version` | `lib/src/package/commands/package_version_command.dart` | 更新 Package 发布版本元数据。 |
| `fluoh package docs refresh` | `lib/src/package/commands/package_docs_command.dart` | 刷新 Package 仓库生成文档。 |
| `fluoh package check` | `lib/src/package/commands/package_release_command.dart` | 运行发布前检查，不创建 tag。 |
| `fluoh package release` | `lib/src/package/commands/package_release_command.dart` | 完成 FlutterOH Package release。 |
| `fluoh verify` | `lib/src/workflow/commands/workflow_commands.dart` | 为项目或 Package 仓库运行 pub get、分析和测试。 |
| `fluoh build <platform>` | `lib/src/workflow/commands/workflow_commands.dart` | 构建项目或 Package example。 |
| `fluoh run <platform>` | `lib/src/workflow/commands/workflow_commands.dart` | 构建、安装、启动并诊断 App。 |
| `fluoh drive <platform>` | `lib/src/workflow/commands/workflow_commands.dart` | 在 OHOS、Android 和 iOS target 上执行移动端自动化场景和证据校验。 |
| `fluoh report create` | `lib/src/workflow/commands/report_command.dart` | 根据 trace manifest 和 automation JSON 创建本地忽略的 AI 适配报告。 |
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
  `packages`、`dependencies`、`error` 等命令专属字段保留在顶层。自动化应调用已安装的
  `fluoh` 可执行文件，不要用 `dart run bin/fluoh.dart ... --json` 作为机器接口，因为
  Dart launcher 可能在命令进程启动前输出依赖解析文本。严格机器解析优先使用
  native/Homebrew 可执行文件；Dart pub global shim 会调用 `dart pub global run`，
  只有确认当前环境的 stdout 直接以 JSON 对象开始时，才把它用于 JSON 自动化。
- `verify`、`build` 和 `run` 可以用 `--trace` 或
  `--trace-dir <path>` 写入本地 AI diagnostic trace manifest。Trace 是本地证据包，
  不是 verbose stdout；和 `--json` 一起使用时，JSON 对象只增加包含 trace id、目录和
  `trace.json` 路径的 `trace` 引用。trace 写入失败时，workflow 结果和退出码仍以底层命令为准，
  JSON 对象会包含 `traceError`。多条命令复用同一个 `--trace-dir` 时，会在同一个
  session manifest 中追加多次 invocation。
- 本地 AI report 是 `.fluoh/reports/` 下的忽略证据。skill helper `new_report.py`
  会写入 `.fluoh/reports/<report-group>/ai-report-YYYYMMDD-HHMMSS.md`；
  `<report-group>` 在提供 `--package` 时是 package slug，否则是 scope slug。
  summary helper `new_summary.py` 会写入
  `.fluoh/reports/<scope-slug>/summary-YYYYMMDD-HHMMSS.md`。
  时间戳使用本地 24 小时时间，精确到秒；如果同名文件已存在，helper 会在 `.md`
  前追加 `-2`、`-3` 等后缀。
- 本地 trace manifest 是 `.fluoh/traces/` 下的忽略证据。使用 `--trace` 时，项目或
  多目标命令写入 `.fluoh/traces/<trace-id>/trace.json`；单个 package 目标写入
  `.fluoh/traces/<package-slug>/<trace-id>/trace.json`。自动生成的 trace id 为
  `<command-slug>-YYYYMMDD-HHMMSS-micros`。使用 `--trace-dir <path>` 时，manifest
  固定为 `<path>/trace.json`，相对路径从 working directory 解析，trace id 来自目录
  最后一段。AI 适配循环应使用一个稳定的 session 目录，例如
  `.fluoh/traces/<package-or-scope>/<session-id>`，让 `verify`、
  `build` 和 `run` 追加到同一个 manifest。
- 命令类只负责参数解析和用户可见输出；可复用行为放到
  `lib/src/sdk/`、`lib/src/deps/`、`lib/src/package/` 和 `lib/src/source/`
  等领域 helper 中。
- 会修改文件的命令必须尽早校验、保留无关文件，并报告实际变更或下一步动作。

## 命令组

### `fluoh clean`

`clean` 只删除 `$FLUOH_HOME/cache`，里面是可清理运行产物，例如 OHOS debug signing
材料和 Package run log。它不会删除 SDK 安装、Source 快照、配置、lock 文件或项目
`.fluoh/` 报告。使用 `--dry-run` 可以只查看 cache 而不删除；使用 `--json` 可以输出机器可读
清理报告。

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
OHOS build/run 证据、OHOS device/emulator 发现、已有平台回归检查、自动化证据和报告创建的结构化命令队列。
当底层命令支持 trace 输出时，`build`、`run`、`drive` 和 `report create` 命令会共用同一个
`.fluoh/traces/<scope>/adaptation` session。`--json` 会输出一个带
`changed: false` 和 `applied: false` 的机器可读对象，方便 AI agent 在请求修改命令前完成适配范围确认。

`plan package` 对当前 FlutterOH Package 分支执行同样的只读规划。它读取
Package `fluoh.yaml`，报告分支与工作区状态、已选择 SDK、上游和 release 元数据、
example 平台目录，以及用于生成文档、验证、OHOS build/run 证据、OHOS
device/emulator 发现、统一平台自动化、已有平台 example 回归、handoff、报告创建和
release 检查的命令队列。当底层命令支持 trace 输出时，`verify`、`build`、`run`、`drive`
和 `report create` 命令会共用同一个 `.fluoh/traces/<package>/adaptation` session。计划让
Android、iOS 和 OHOS 的实现细节分别落在平台步骤里，上层通过同一个 `plan package`
合约调用。

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
`id`、`group`，以及检查项需要的结构化数据。

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
内置 skill 跟随 CLI 版本；升级后应重新运行 `fluoh skill --json`，并在复制过
skill 的 AI agent 中覆盖安装或重载返回的路径。

## Source 命令

Source 命令分为两类：消费侧命令管理已配置的本地快照；维护侧命令编辑 source
仓库本身。source 快照是保存在 `$FLUOH_HOME/sources/<name>` 下、已经校验通过的
Source 本机副本。

### 消费侧命令

`fluoh source list` 会先要求 Source 运行时确保已配置 source 快照和 `sources.lock.json`
可用，然后读取 `$FLUOH_HOME/config.json`，输出每个已配置 source 的名称和显示值。
空配置是 warning，不是错误。`--json` 输出同一份 source 列表，包含 source 名称、
显示值、缓存路径、URL 和优先级。

`fluoh source add <name> <url-or-path>` 校验 source 名称，拒绝替换官方 source
名称，并把缓存路径固定为 `$FLUOH_HOME/sources/<name>`。普通本地路径会在
`$FLUOH_HOME/config.json` 中规范化为绝对 `file:` URL，后续 `source update` 才能从原始目录
刷新缓存。本地路径和 `file:` URL 会复制校验后的快照；HTTPS/SSH URL 会立即 clone，
并且在写入配置项前完成校验。`--priority` 默认值为 `10`，source 数据重叠时优先级越高越先使用。
新快照校验通过后，Source 运行时会一起提交配置项和重新生成后的 lock。

重叠数据的合并规则是显式的：

- SDK release 按 tag 合并。优先级高的 source 胜出；同优先级下发布记录冲突会报错。
- Package 发布记录按 `package + sdkLine + upstreamVersion` 分组。高优先级会替换同组低优先级记录。
  默认消费侧索引只包含 `compatible` 发布记录。`deps check`、`deps fix` 和
  `deps upgrade` 可通过 `--all-release-statuses` 为单次命令显式包含非 compatible
  记录。
- 同优先级下，派生 tag 相同但 repository 或 path 不同会报错。同组内不同 tag 可以并存，由依赖规划器按项目策略选择最佳候选发布记录。
- Package 级 upstream URL 和 advisory 文本来自定义该 Package 的最高优先级 source。

`fluoh source remove <name>` 从工具配置中移除用户 Source。官方 Source alias
`flutteroh` 由工具持有，priority 固定为 `0`。该命令只拥有被移除的配置项，lock 维护交给
Source 运行时。

`fluoh source update [name]` 刷新全部 source 或单个指定 source。命令选中的 Git source
会重新 clone，命令选中的 `file:` source 会从配置的本地目录重新复制。随后 Source 运行时会校验
所有已配置 source 快照，因为 lock 是基于全部已配置 source 的合并索引。Git 传输失败会作为
sync 失败输出并给出重试提示；clone 成功后 source 内容未通过 schema 校验时，保留 source
校验诊断，不会包装成网络问题。

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
元数据应来自已发布适配记录，而不是维护中的仓库状态。当 `<path>` 是
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

`fluoh deps fix` 根据依赖计划应用推荐 FlutterOH 适配变更。它会按照
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
`skills/fluoh/references/` 中维护。用户文档只保留简短入口，所有 AI agent 都使用同一套工作流面。

### 适配流程

适配以 Package 分支和 FlutterOH 大版本线为单位维护，而不是以 SDK patch 版本为单位维护。
例如完整 SDK `3.35.8-ohos-0.0.3` 对应 SDK 版本线 `3.35`，Package `camera`
维护在 `ohos/3.35/camera`。

推荐流程：

1. 选择完整 SDK 版本。
2. 从 SDK 版本推导 SDK 版本线。
3. 创建或切换 `ohos/<sdkLine>/<package>` 分支。
4. 在 Package `fluoh.yaml` 中记录当前适配的 upstream Package 版本和 FlutterOH
   适配 Package 版本。
5. 开始写 OHOS 代码前，先用已选择 SDK 做基线检查，包括 `fluoh deps get`、
   `fluoh flutter analyze`、已有 Package 测试或 example 构建；先修复非 OHOS 平台
   因 SDK 切换暴露的问题。
6. 适配中使用 `status: experimental`；完成并可推荐时省略 `status`，默认就是
   `compatible`。
7. `fluoh package version` 更新适配 Package 的发布版本和状态。
8. `fluoh package check` 运行最终本地 gate，不创建 tag。
9. `fluoh package release` 打 release tag，tag 固化当前代码、测试和 Package
   `fluoh.yaml`。
10. `fluoh source sync` 从 release tags 导入逐 Package Source Manifest。

`fluoh package create <upstream>` clone upstream 仓库，选择一个 Package，配置
`upstream` 和 `origin`，创建 `ohos/3.35/camera` 这类 FlutterOH Package 分支，配置
FlutterOH SDK，写入 `fluoh.yaml`、`FLUOH.md`、`FLUOH_CHANGELOG.md` 和 agent
指令，然后暂存生成文件。如果选中的 Package 已有 Flutter example，命令会给该 example
新增 OHOS 平台、写入 example SDK 配置，并暂存 example 变更。生成的引导会要求维护者先
建立已选择 SDK 基线并修复非 OHOS 平台回归，再实现 OHOS 代码。
生成的 agent 指令也会要求 AI 在维护者要求本地提交时，按已完成且已验证的 checkpoint
拆分小的本地 commit。
不传 `--package-path` 时，命令只选择 upstream 仓库根目录 Package，不表示适配 monorepo
中的全部 Package。适配 monorepo 时，为 upstream 仓库创建一份 FlutterOH 适配仓库，不要为每个
Package 分别建仓；为当前要创建的 Package 分支传一个 `--package-path <subdir>`。要在同一仓库继续适配
另一个 Package，从生成仓库中运行 `fluoh package add <package-path>`；它会在保留原 monorepo 布局的同时，
基于该 Package 选中的 release/ref 创建独立 Package 分支。默认情况下，package create/add 会选择所选 Package 最新有效 upstream release
tag；需要指定 Package 版本时传 `--upstream-version`，只有 release tags 无法识别目标快照时才用
`--upstream-ref`。传入显式 target 时，所选 Package path 会在该 target 上解析；即使 upstream
default branch 已经移动或删除历史 Package path，也仍可适配该历史版本。
命令始终要求 `--repository-name <repository-name>`。`--repository-name` 只决定未传
`--output` 时的默认输出目录，以及省略 `--repository` 时的默认 FlutterOH origin URL。
它不会写入 Package `fluoh.yaml`；Package 身份来自 `package.name`。只选择一个子目录
Package path 且遗漏 `--repository-name` 时，usage error 会根据 path 给出候选建议，
但命令仍要求显式传入该参数。
生成的 `fluoh.yaml` 会在 `repository`、`upstream`、Package 路径、`version` 和
`status` 等维护者常改字段旁提供注释。它不会创建 commit。可用参数包括
`--package-path`、`--upstream-version`、`--upstream-ref`、`--output`、
`--repository-name`、`--sdk`、`--repository`、`--git-author-name`、`--git-author-email`、
`--org`、`--plan` 和 `--json`。Git 作者参数只配置新仓库
本地 Git `user.name` 和 `user.email`，供后续适配 commit 使用，不写入被跟踪文件。
`--org` 用于覆盖给已有 example 新增 OHOS 平台时传给 `flutter create` 的 organization；
不传时，fluoh 会从现有 Android、iOS 或 macOS example 元数据中推断。`--plan` 会把 upstream clone 到临时目录，解析所选 Package、SDK、输出路径、repository
URL、目标分支和 Git author；临时 clone 会优先使用默认分支 shallow clone 加 shallow
tag fetch 来选择 release tag，只在需要时回退到 partial 或 full clone。解析完成后会删除临时 clone；它不会创建目标仓库、配置 SDK link、
写文件、stage 文件或 commit。`--json` 只支持和 `--plan` 一起使用，并输出一个机器可读
plan 对象，供 AI 最终适配范围确认使用。plan 对象包含 `warnings[]`；AI agent 在创建仓库前必须
检查它。例如 `package.dart_sdk_incompatible` 会报告所选 upstream Package 需要更高 Dart
SDK，并在可用时给出当前 SDK 兼容的最新 upstream tag，作为诊断参考。默认策略是保留所选
upstream target，把 package pubspec、example 配置和 Dart 代码适配到当前选择的 FlutterOH
SDK，然后重新 verify。已知当前 Dart SDK 版本时，JSON warning 会包含
`policy.suggestedEnvironmentSdkConstraint`。只有维护者明确批准旧 upstream baseline 时，才能使用
较旧 tag。`package.default_branch_version_unreleased` 表示默认分支声明的 Package
版本不同于当前选中的最新 release tag；warning 会记录选中的 release ref/version 和默认
分支版本。AI 适配默认继续使用选中的 release tag，只有维护者明确批准适配未发布的默认分支
快照时，才使用 `--upstream-ref <branch>`。所选 Package 如果是带 `default_package` 声明、但没有 OHOS 平台的
federated app-facing plugin，plan 还会包含 `implementationRecommendation`：
Source 路由仍指向 app-facing Package，同时说明 `<package>_ohos` 实现 Package
以及需要修改的 app-facing pubspec 条目。

`fluoh package discover <upstream> --json` 会把 upstream 仓库 shallow clone 到临时目录，
扫描非 example 的 `pubspec.yaml`，并报告 `flutter.plugin.platforms` 未声明
`ohos` 的 Flutter plugin Package。它是只读命令，不会创建 Package 仓库、配置
remote、checkout 分支或写入项目文件。JSON 输出包含筛选条件、已检查 pubspec
数量、有效 Flutter plugin 数量、候选和推荐数量、候选 Package 名称、路径、版本、已声明平台、缺失平台、
federated `default_package` 声明、每个候选的 `createCommand`，当 app-facing
plugin 应新增 `<package>_ohos` 这类平台实现 Package 时给出的
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
`package create`。传 `--include-existing-platform` 可以把已经声明目标平台的 Flutter plugin
也列出；`--missing-platform` 默认是 `ohos`。

`fluoh package queue <package-path>... --json` 会在现有 FlutterOH Package 仓库中解析只读
多 Package 队列。它会拉取 upstream refs，但保持当前分支不变，并为每个 Package 输出名称、
路径、选中的 upstream 目标、目标 `ohos/<sdkLine>/<package>` 分支、该分支是否已存在、
SDK/Dart 兼容性预警，以及下一条 `fluoh package add` 或 `package status` 命令。适配同一个
upstream monorepo 的多个 Package 前，先用它排队，然后一次完成一个 Package 分支 checkpoint。
跨多个已存在 Package 分支运行 verify/build/run/check 时，优先为每个 Package 分支使用新的 clone
或独立 Git worktree，避免某个分支中被忽略的平台构建产物在切到另一个分支后变成 untracked 文件。
不要在未获维护者明确批准时运行 `git clean` 等破坏性清理命令。

`fluoh package add <package-path>` 在现有 FlutterOH Package 仓库中创建另一个 Package 分支。
它要求工作树干净，基于同步后的 upstream 分支解析目标 Package，切到选中的 release/ref
commit，创建 `ohos/<sdkLine>/<package>`，写入单 Package `fluoh.yaml` 和文档，在已有
Flutter example 时准备 example，并暂存生成文件。它支持 `--upstream-version` 和
`--upstream-ref`，选择规则和 package create 相同；也支持 `--org` 覆盖传给 `flutter create`
的 example organization。`--plan --json` 会在不 checkout、不写项目文件、且不要求工作树干净的
情况下解析 add 计划；计划里的 `warnings[]` 使用和 package create 相同的保留最新 upstream
目标的 SDK 兼容性策略。如果目标 Package 分支已经存在，命令会提示维护者切到已有分支，
用 `fluoh package status` 查看现有适配，或用 `fluoh package sync` 更新它，而不是创建重复适配状态。
命令失败时会通过文件快照保护本地状态。

`fluoh package sync` 会拉取 upstream 分支和 tags，快进 Package `upstream.git.branch` 记录的
upstream 分支，从 `--upstream-version`、`--upstream-ref` 或最新有效 release tag 解析 Package
目标提交，回到 `fluoh.yaml` 记录的 `repository.git.branch` 分支，先把选中的目标提交合并
进来但不立即提交，然后更新 `fluoh.yaml` 中的 upstream 元数据并暂存；存在变更时提交
`Sync upstream package`。如果没有有效 release tag 且未传显式 target，则回退到已同步的
upstream 分支 HEAD。如果解析出的目标已经和当前分支 metadata 及 commit 一致，`sync` 会明确提示
该 Package 分支已经适配对应 upstream version，并且不创建 commit。`sync` 会拒绝低于当前分支
upstream version 的显式 Package 版本；这种情况应使用 `fluoh package version --status broken`
标记当前适配为 broken，而不是降级分支。合并冲突会留给用户解决，之后
`fluoh package sync --continue` 校验已暂存的解决结果并完成流程。如果中断的 merge 使用了自定义非
tag ref，继续时传同一个 `--upstream-ref`；release tag 通常可以从 `MERGE_HEAD` 自动推断，
但非 tag ref 不能。
continue 还会在更新 `fluoh.yaml` 前校验已解决工作树中的 Package version 是否匹配选中的 upstream
target。`--abort` 对进行中的 sync 执行 `git merge --abort`。`--json` 会输出完成的 sync 动作列表和提交状态。
fetch 失败输出 `sync.fetch_failed`；合并冲突输出 `sync.merge_conflict`，包含冲突文件列表和
`--continue` 下一步命令；没有产生可解决冲突的 merge 失败输出 `sync.merge_failed`。Git 有有效输出时，
JSON diagnostic 会包含裁剪后的 stdout 和 stderr 尾部。

`fluoh verify` 会为当前项目或 Package `fluoh.yaml` 中记录的当前 Package 运行自动化验证。它会先用已选择 SDK 执行 `pub get` 和 `analyze`：Flutter Package 使用
`flutter`，非 Flutter Package 使用 `dart`；如果存在 `test/**/*_test.dart`，继续运行测试。
在 Package 仓库中，如果存在顶层 Flutter example（`example/pubspec.yaml`），也会验证
example。当发现 `integration_test/` 时，`verify` 会记录 skipped discovery step，并给出后续平台化
`fluoh run ... --json` 命令；这只是采集设备证据的提示，不代表交互证据已通过。
使用 `--package <name>` 可校验请求的 Package 名是否匹配当前分支。
`--json` 会在 `targets` 下输出每个项目或 Package 的目标身份、phase、steps、diagnostics 和
`nextCommand`。使用 `--trace` 会在 `.fluoh/traces/` 下写入本地 AI diagnostic trace；
选择到单个 Package 时默认写入 `.fluoh/traces/<package>/<trace-id>/trace.json`，
使用 `--trace-dir <path>` 可以指定 trace session 目录，manifest 为 `<path>/trace.json`。
JSON 模式仍只向 stdout 输出一个对象，并只在对象里加入本地 manifest
的 `trace` 引用；trace 无法写入时则加入 `traceError`。当目标位于 Git 工作树中时，还会输出
`dirtyAfterVerify` 和 `workingTreeChanges`，方便 AI 发现 `pub get` 留下的生成文件或 lockfile
变化并在提交前复核。一个适配循环内复用同一个 `--trace-dir` 可以把多条命令追加到同一个
session。

`fluoh build ohos|android|ios|macos|linux|web|windows` 构建当前 Flutter 项目或所选 Package example。iOS
构建会自动加入 `--no-codesign`。OHOS 构建可用 `--auto-sign` 根据项目或 example 申请的权限
生成临时本地 debug 签名 profile，为本次构建 patch `ohos/build-profile.json5`，并在构建后恢复原文件。
如果 Hvigor 签名失败但 Flutter 留下了新的 unsigned HAP，`fluoh` 会直接签这个 HAP，并在 JSON
中报告 `signingMode: direct-sign-fallback` 和可安装 HAP 路径。JSON 失败会对当前项目和
Package example 都使用平台化 diagnostic code，例如 `ohos.hap_build_failed`、
`android.apk_build_failed`、`ios.build_failed`、`macos.build_failed`、`linux.build_failed`、`web.build_failed` 和
`windows.build_failed`。`--trace` 和
`--trace-dir <path>` 使用与 `fluoh verify` 相同的本地 AI diagnostic trace 契约。

`fluoh run ohos|android|ios|macos|linux|web|windows` 会构建、安装、启动并诊断当前项目或所选 Package
example。OHOS 当前项目和 Package example 会签名 HAP、用 `hdc` 安装、启动 ability、采集短
hilog，并通过 JSON diagnostics 报告运行时 crash 或 Flutter channel 运行时错误。Android、iOS、macOS、Linux、Web 和 Windows 当前项目与
Package example 会通过已选择 SDK 的 `flutter run` 启动，把 run-smoke 输出保存到
`$FLUOH_HOME/cache/package-runs`，并在存在 `integration_test/` 且有具体 target 时继续运行
`flutter test integration_test -d <device>`。Web run 使用 Chrome 等浏览器 target。如果
`flutter run` 输出 VM Service 或 debug service URI，`--json` 会在 run step 的
`details.vmServiceUri` 返回它，方便 AI agent 或外部工具 attach。Android、iOS、macOS、Linux、Web 或 Windows run
可以传 `--session-file <path>`，在 App 仍运行时写入实时 `flutterRunSession` JSON 文件；
文件会更新进程 id、target、`vmServiceUri`、启动状态、最终状态和输出日志路径。AI agent 可以用
`python3 <skill-dir>/scripts/inspect_session.py <session-file> --wait 30 --expect-platform <platform>`
检查这个文件，等待启动、读取 VM Service URI，并决定 attach、查看日志或转入失败排查。已有目标时用
`--device-id <id>`，要指定本地 emulator/simulator 时用 `--emulator <name>`，要优先启动本地
emulator/simulator 并且只在没有模拟器时回退到已连接真机，则用 `--auto-emulator`。OHOS
自动模拟器选择会优先选择本地 DevEco 模拟器中可识别的最高 API 版本，无法识别 API 时按名称稳定
排序选择。iOS 自动 simulator 选择会优先 iPhone，再选较新的 iOS runtime，并在启动后等待
`xcrun simctl bootstatus <udid> -b` 完成，再选择 Flutter run target。当 OHOS run 没有发现
已连接 target 时，diagnostics 会保持不自动启动模拟器的默认行为，
除非已传 `--auto-emulator` 或 `--emulator`；同时给出 target 选择建议：自动化证据优先使用本地
DevEco 模拟器；只有没有模拟器时才使用已连接真机。若本地有多个 OHOS 模拟器且能识别 API 信息，
diagnostic 会建议最低和最高 API 版本都测一遍。
run-smoke 成功只表示 App 已启动。需要点击 UI、处理权限弹窗、选择文件、调用相机、定位、
播放媒体、deep link 或外部 App 的流程，必须有功能场景证据：优先用平台 runner 支持的
`integration_test`，否则用 AI 在 emulator 或真机上执行交互。人工操作只能作为
`manual-assisted` 证据，并且需要 fluoh 可读取的日志、session 状态、稳定文本、语义标签、test key、
组件状态、命令 JSON、hilog 或 App 日志标记支撑。验收标准应是功能行为，不是视觉布局；
AI 辅助验证不能依赖识图能力。如果没有交互流程，报告必须写明
`No interaction required: <reason>`。

交互场景放在 `.fluoh/scenarios/<package>/<platform>-<name>.md`，使用内置
`skills/fluoh/references/interaction-scenario-template.md`。场景 Markdown 可以包含 fenced YAML，
写明 `kind: fluoh.automationScenario`、`platform`、`steps`，以及可选的 `coverage`
元数据。`fluoh drive --scenario <path>` 会在 OHOS、Android 或 iOS App 启动后执行该场景。
支持动作以模板为准，包括文本断言、日志断言、权限允许和拒绝、App 启动、等待、支持平台上的文本输入，
以及平台特定的 reset 或 tap 行为。

`fluoh drive --dry-run --json` 和真实运行都会输出 `automation.coveragePolicy`，
用于让 AI 和报告在 Package 标记 ready 前发现缺失测试、缺失场景行、权限覆盖缺口、缺失负向/错误路径、
缺失工具可读断言和 blocked 交接。稳定的覆盖字段包括 `scenarioCoverage`、`coverageSummary`、
`inventory`、`capabilityCoverage`、`manifestPermissionCoverage`、`pathCoverage`、
`scenarioEvidence`、`qualityGates` 和 `repairLoop`。Package 测试缺口会以
`type: testCoverage` 修复项出现，并带具体测试路径和命令；能力、manifest permission、行为路径和断言缺口会以
`type: scenarioCoverage`、`type: permissionCoverage`、`type: pathCoverage`
或 `type: scenarioEvidence` 出现。详细修复顺序属于 skill reference 和 report template，不放在命令面文档里展开。

对于 runtime permission，不能只抽样测一个权限。每个支持平台上每个暴露或可请求权限都需要覆盖 grant、
deny 和行为不同的 error 路径，或用带原因的 `notApplicable`/`blocked` 行明确说明。
`scenarioEvidence` 要求 `assertText`、`waitText`、`assertLog` 或 `assertSession`
等工具可读验证动作；只点击按钮或权限弹窗不能作为 release-ready 证据。

iOS 自动化优先使用内置 XCTest runner 匹配可见 App UI，并在可行时点击系统权限弹窗。runner 会在
`$FLUOH_HOME/cache/automation/ios-xctest` 生成临时 Xcode 工程并运行 `xcodebuild test`；
当前 Xcode 工具链需要显式路径时可设置 `FLUOH_XCODEBUILD`。如果 XCTest 不可用，应在报告中记录
Xcode/工具链 blocker，而不是把它当作 Package 已修复。`FLUOH_IOS_PERMISSION_DRIVER`
可以强制为 `xctest`、`xcuitest` 或 `simctl`；只有在接受 simulator privacy 状态修改作为证据而不是弹窗 UI 点击时才使用 `simctl`。

当前项目 run 的 JSON 失败会包含 `ohos.run_failed`、`android.run_failed`、`ios.run_failed`、`macos.run_failed`、`linux.run_failed`、`web.run_failed` 和 `windows.run_failed` 等平台 diagnostic；
Package example 则在可判断时继续使用更细的安装、启动、runtime 和 integration test diagnostic。
`--trace` 和 `--trace-dir <path>` 使用与 `fluoh verify` 相同的本地 AI diagnostic trace 契约。

`fluoh drive all|ohos|android|ios` 是面向 AI 的移动端 target
启动、交互场景和证据校验封装。它复用 `fluoh run` 的 target 选择和运行行为，
默认优先使用本地 emulator/simulator，可针对当前项目、一个 Package 或全部 Package 运行。
dry-run 和真实运行 JSON 都包含 `deliveryRecommendation`、`repairPlan` 和 `repairQueue`；
真实运行还会输出普通 workflow `targets` 以及 `automation` 对象，记录 target 选择、App 启动、
session 证据、`nextCommand` 路由和可 replay/debug 的本地材料。Android 和 iOS 自动化默认把
`flutterRunSession` 写到 `.fluoh/run-sessions/automation`，内容包含进程 id、target、启动状态、
可用时的 VM Service URI 和输出日志路径。OHOS 自动化记录可安装 HAP、启动 ability、target id、
hilog 路径和现有 OHOS runner 的 runtime findings。

`fluoh report create` 默认把 Markdown 报告写到忽略的
`.fluoh/reports/<scope>/ai-report-YYYYMMDD-HHMMSS.md`，也可以用 `--output`
指定路径。它接受一个或多个 `--trace-dir` 以及保存下来的 `--automation-json` 文件，
提取命令行、覆盖 gate、交互证据、diagnostics 和 fluoh feedback candidates，然后写入
package check 和交接流程需要的标准 AI 报告章节。`--json` 会输出报告路径和行数统计。
该命令只拥有本地报告创建，不单独认证 ready 状态。

`fluoh package version` 更新 `fluoh.yaml` 中当前 Package 的发布元数据。
用 `--bump patch|minor|major` 递增 FlutterOH 适配 Package 版本，用
`--set <version>` 设置精确版本，用 `--status experimental|compatible|broken`
设置发布状态。`compatible` 会移除 status 字段，因为 compatible 是默认状态。
`--bump` 和 `--set` 互斥。`--dry-run` 只打印计划不写入，`--json` 输出机器可读结果。

`fluoh package docs refresh` 根据当前 Package `fluoh.yaml` 和当前 checkout 中的
Package pubspec 重新生成 `FLUOH.md` 和 `AGENTS.md` 中 fluoh 拥有的生成段。
当所选 Package 是带 `default_package` 声明、但没有 OHOS 平台的 federated
app-facing plugin 时，refresh 会重新推导与 `package create` 相同的 `<package>_ohos`
实现 Package 路线，因此旧的生成仓库在工具升级后也能获得当前 AI 指引。生成段使用包含稳定
section id 和 template version 的 `fluoh:generated` marker，因此后续模板升级只会替换被工具拥有的段落，
保留手写内容。已有非空 `FLUOH_CHANGELOG.md` 不会被整体重写；如果 changelog 缺失或为空，
命令会根据当前 Package metadata 创建带 TODO 占位条目的初始 release heading，发布前必须替换为
真实 release notes。`--dry-run` 只报告会变化的文件，不要求干净工作树。实际写入要求当前分支匹配
`fluoh.yaml` 记录的 Package 分支且工作树干净，不会 stage 文件，也不会修改 `fluoh.yaml`。
`--allow-dirty` 会显式允许在尚未形成干净 checkpoint 前写入生成文档，例如刚执行完
`package create` 后；它仍只写计划中的生成文档文件，且不会 stage。`--json` 输出
`changed`、`applied`、`files`、`dryRun` 和 `allowDirty`。

`fluoh package handoff --json` 读取当前 Package 分支、Git 状态、最新的
`.fluoh/traces/**/trace.json` 和 `.fluoh/reports/<package>/*.md`，然后输出一个
JSON 对象，包含 Package 元数据、当前分支、manifest 分支、分支是否匹配、工作树脏状态摘要、
证据路径、后续命令应复用的 trace 目录和下一步命令。当当前 Package 已有 trace 时，
handoff 会复用 `.fluoh/traces/<package>/` 下最新的 trace 目录；否则默认使用
`.fluoh/traces/<package>/adaptation`。它不修改仓库。AI 任务需要恢复、转交，或确认分支是否可以进入最终 verify、
drive 证据、报告创建或 `package check` 时使用它。

`fluoh package check` 校验 release 元数据，确认配置的 SDK 版本存在于 source，运行
`fluoh verify`，确认工作树仍然干净，并报告将要创建的 release tag。它不会创建或推送
tag。使用 `--package <name>` 可校验请求的 Package 名是否匹配当前分支。
`--json` 会输出 tag、warning、认证状态和验证结果。Check 默认不要求设备或 AI report
证据；没有提供认证报告时只输出非阻断 warning。需要 AI/CI 认证交付时，传
`--report <path>` 强制检查已完成的
`.fluoh/reports/<scope>/ai-report-...md`。认证报告必须是 `ready`，完成所有交付 checklist，包含通过的
`fluoh verify` 证据，包含通过的 OHOS build 或 run 证据，包含通过的 `fluoh drive --json`
证据，包含 `Automation Coverage` 章节和完整必需自动化 gate 集合，且所有 gate 行都是 ready/covered/passed/notApplicable，
并包含通过的交互证据或明确的 `No interaction required: <reason>`。当 CI 或 AI 交接必须证明真机或模拟器上的 OHOS run 已通过，
而不是只有 build-only 证据时，再加 `--require-ohos-run`。

`fluoh package release` 会运行同一套校验和验证，然后通过在 HEAD 创建 release tag
完成 fluoh package release，并可用 `--push` 推送。已有 tag 只有在已经指向 HEAD
时才会被接受。它不会发布到 pub.dev。

`fluoh package status` 读取 Package `fluoh.yaml` 并汇总发布就绪状态，不修改仓库。它会检查
当前分支、工作树是否干净、package status、release notes、license warning、Package 测试、
Flutter example、example OHOS 平台、example 测试，以及 tracked 文件是否包含本机 fluoh home
路径。对于已有 `default_package` 声明但没有 OHOS 平台的 federated app-facing plugin，
它也会为缺失的 `<package>_ohos` 实现 Package、`ohos.default_package` 和依赖路径报告
readiness blocker。如果已经声明了 `ohos.default_package`，status 还会校验 app-facing
Package 是否依赖该 default package，以及实现 Package 是否存在并声明 OHOS。使用
`--package <name>` 可校验请求的 Package 名是否匹配当前分支，`--json` 输出机器可读结果。

## 状态归属

| 状态 | 所属方 / 维护入口 |
| --- | --- |
| `$FLUOH_HOME/config.json` | `source add`、`source remove`、`source update`、首次默认 Source 初始化 |
| `$FLUOH_HOME/sources/<name>` | `source add`、`source update` |
| `$FLUOH_HOME/sources.lock.json` | `lib/src/source/` 中的 Source 运行时；Source 状态变更、首次默认 Source 初始化，以及 load-index 检查发现过期或需要 SDK 元数据来安装已选择的 SDK 时重建 |
| `$FLUOH_HOME/sdks/<version>` | `sdk install`、`sdk remove`、按需执行的 Flutter wrapper |
| `$FLUOH_HOME/cache/` | 可清理运行产物，例如 OHOS debug signing 材料和 Package run log |
| 项目 `.fluoh/run-sessions/` | `drive` 和 `run --session-file` 的实时 Flutter run session 证据 |
| 项目或 Package `.fluoh/reports/` | `report create` 和 AI 交接报告产物 |
| 项目 `fluoh.yaml` | `create`、`sdk use`、`deps check`、`deps fix`、`deps upgrade` |
| 项目 `pubspec.yaml` | `deps fix`、`deps upgrade` |
| FlutterOH Package 仓库 `fluoh.yaml` | `package create`、`package add`、`package sync`、`package status`、`package handoff`、`package version`、`package check`、`package release` 校验 |
| Package 生成文档 | `package create`、`package add`、`package docs refresh` |
| Source root 和 Manifest 文件 | `source init`、`source sync` |
| `.fluoh/flutter_sdk` | `create`、`sdk use`、`package create` 的 SDK 设置 |
| Package examples | `package create`、`package add`、`deps get`、`verify`、`package check`、`package release` |
