# 命令设计

[English](commands.md)

本文档说明 `fluoh` 的完整命令面，以及每个命令背后的设计边界。它和
[schema.zh-CN.md](schema.zh-CN.md) 互补：schema 文档定义数据结构，本文档定义
命令如何读取、写入和保护这些数据。

命令实现主要位于 `lib/src/<domain>/commands/`，顶层注册逻辑位于
`lib/src/cli/fluoh_command_runner.dart`。

## 命令面

| 命令 | 实现 | 用途 |
| --- | --- | --- |
| `fluoh --version` | `lib/src/cli/fluoh_command_runner.dart` | 输出 `fluoh` 版本、Dart 版本、平台和仓库地址。 |
| `fluoh help [command]` | `package:args` command runner | 输出全局或指定命令的用法。 |
| `fluoh flutter <args>` | `lib/src/sdk/flutter_command.dart` | 使用最近的项目 `fluoh.yaml` 里选择的 SDK 运行 `flutter`。 |
| `fluohf <args>` | `bin/fluohf.dart` | `fluoh flutter <args>` 的快捷入口。 |
| `fluoh source` | `lib/src/source/source_commands.dart` | 数据源使用和维护的命令组。 |
| `fluoh source list` | `lib/src/source/source_commands.dart` | 列出已配置的 FlutterOH 数据源。 |
| `fluoh source add <name> <url-or-path>` | `lib/src/source/source_commands.dart` | 把本地或 Git 数据源加入工具配置。 |
| `fluoh source remove <name>` | `lib/src/source/source_commands.dart` | 从工具配置中移除非官方数据源。 |
| `fluoh source update [name]` | `lib/src/source/source_commands.dart` | 刷新并校验已配置的数据源快照。 |
| `fluoh source validate [path]` | `lib/src/source/source_commands.dart` | 校验本地 source 仓库但不注册它。 |
| `fluoh source init <path>` | `lib/src/source/source_commands.dart` | 创建本地 source 仓库模板。 |
| `fluoh source sync [path]` | `lib/src/source/source_commands.dart` | 把已发布 FlutterOH package 仓库元数据同步进 source 仓库。 |
| `fluoh sdk` | `lib/src/sdk/sdk_commands.dart` | 本地 Flutter OHOS SDK 缓存的命令组。 |
| `fluoh sdk list` | `lib/src/sdk/sdk_commands.dart` | 列出远端 SDK 版本和本地 SDK 缓存。 |
| `fluoh sdk install <version-or-series>` | `lib/src/sdk/sdk_commands.dart` | 把 SDK 版本安装到 `$FLUOH_HOME/sdks`。 |
| `fluoh sdk current` | `lib/src/sdk/sdk_commands.dart` | 输出当前项目选择的 SDK。 |
| `fluoh sdk remove <version-or-series>` | `lib/src/sdk/sdk_commands.dart` | 删除一个已安装的 SDK 缓存。 |
| `fluoh sdk use <version-or-series>` | `lib/src/sdk/sdk_use_command.dart` | 为当前 Flutter 项目选择 SDK。 |
| `fluoh deps` | `lib/src/deps/commands/deps_command.dart` | 项目依赖命令组。 |
| `fluoh deps get` | `lib/src/deps/commands/deps_get_command.dart` | 为项目和 package example 执行 `flutter pub get`。 |
| `fluoh deps check` | `lib/src/deps/commands/deps_dependency_commands.dart` | 输出依赖 FlutterOH 适配状态。 |
| `fluoh deps fix` | `lib/src/deps/commands/deps_dependency_commands.dart` | 应用推荐的 FlutterOH 依赖变更。 |
| `fluoh deps upgrade` | `lib/src/deps/commands/deps_upgrade_command.dart` | 只升级已有 FlutterOH 依赖替换。 |
| `fluoh package` | `lib/src/package/commands/package_command.dart` | FlutterOH package 仓库命令组。 |
| `fluoh package create <upstream>` | `lib/src/package/commands/package_create_command.dart` | 初始化 FlutterOH package 仓库。 |
| `fluoh package add <package-path>` | `lib/src/package/commands/package_add_command.dart` | 在 FlutterOH package 仓库中注册另一个 package。 |
| `fluoh package sync` | `lib/src/package/commands/package_sync_command.dart` | 把 upstream 合入当前 OHOS package 分支。 |
| `fluoh package check` | `lib/src/package/commands/package_check_command.dart` | 运行 pub get、分析和已有测试。 |
| `fluoh package release` | `lib/src/package/commands/package_release_command.dart` | 检查、打 tag，并可选择推送 FlutterOH package release。 |
| `fluoh package status` | `lib/src/package/commands/package_status_command.dart` | 汇总 package 发布就绪状态。 |
| `fluoh doctor` | `lib/src/doctor/doctor_command.dart` | 按 scope 诊断环境、项目、SDK 和工具状态。 |
| `fluoh upgrade` | `lib/src/upgrade/upgrade_command.dart` | 升级已安装的 `fluoh` CLI。 |

## 共享运行规则

- Help 请求不会加载 source 配置。
- Source lock 只有一个维护方：`lib/src/source/` 中的 Source 运行时。命令类
  不应该直接读写 `$FLUOH_HOME/sources.lock.json`。
- 会修改 Source 配置或已配置快照的命令，把变更交给 Source 运行时。运行时会校验所有
  已配置 source 快照，尽可能修复快照，重建合并后的 lock，然后再提交新的本地 Source 状态。
- 消费 Source 数据的命令只能通过 Source 运行时的 load-index API 读取。这个 API 负责
  首次默认 Source bootstrap；当 `sources.lock.json` 记录的 fingerprint 仍然匹配时会直接返回。
  lock 缺失、过期或结构不兼容时，运行时会先校验或修复已配置 source 快照，
  再重新生成 lock 并返回数据。
- `fluoh source` 不带子命令和 `fluoh source list` 在打印配置前也会走同一套 Source
  运行时重建路径，所以用户会先看到无效或缺失的 source 状态，再依赖列表结果。
- `fluoh deps get` 会跳过 package Source 数据，让依赖解析在 source 快照需要修复时仍然可用。
  `fluoh flutter`、`fluohf` 和 `fluoh deps get` 在已选择 SDK 缺失时，仍可能通过 SDK
  resolver 加载 Source index，因为安装已选择的 SDK 需要 SDK 元数据。
- 用法错误和 schema 格式错误返回退出码 `64`。
- 命令类只负责参数解析和用户可见输出；可复用行为放到
  `lib/src/sdk/`、`lib/src/deps/`、`lib/src/package/` 和 `lib/src/source/`
  等领域 helper 中。
- 会修改文件的命令必须尽早校验、保留无关文件，并报告实际变更或下一步动作。

## 顶层命令

### `fluoh flutter <args>` 和 `fluohf <args>`

这两个命令是已选择 Flutter OHOS SDK 的透传入口。它们通过
`SdkManager.currentSdkVersion()` 解析当前项目 SDK，查找或安装 SDK 缓存，然后用原始
参数执行 `<sdk>/bin/flutter`。单独传 help 参数时，命令输出 `fluoh` wrapper 的
帮助，而不是转发给 Flutter。

设计约束：

- 不改写 Flutter 参数。
- 未选择 SDK 时给出明确操作提示。
- SDK 缓存缺失时按需安装已选择的 SDK。
- 透传 Flutter stdout 和 stderr，不追加命令自身语义。

### `fluoh doctor`

`doctor` 是诊断命令，除非使用 `--strict`，否则打印结果后返回成功。第一个参数是可选
scope：

- `fluoh doctor env`：检查 fluoh 安装状态、已配置 source 快照和本地平台工具链。默认检查
  OHOS 工具链；`--platform all` 还会检查 Android SDK、`adb`、emulator、
  `avdmanager`、Java、Xcode `xcrun` 和 `simctl`，不要求项目已选择 Flutter SDK，
  也不会调用全局 `flutter`。
- `fluoh doctor project`：检查当前 Flutter 项目结构、项目 SDK 和项目平台目录。默认检查
  OHOS；`--platform all` 还会检查 `android` 和 `ios` 目录。
- `fluoh doctor all`：同时运行两类检查。裸 `fluoh doctor` 是兼容入口，等价于
  `fluoh doctor all`。

缺失或过期状态会作为 warning 输出，不会自动修复。自动化需要 Android/iOS 原生环境门禁时，
使用 `fluoh doctor env --platform all --json --strict`；需要当前项目门禁时，使用
`fluoh doctor project --json --strict`。`--json` 会输出机器可读的同一组检查结果，并在每个
check 中包含 `group`。

### `fluoh upgrade`

`upgrade` 升级 CLI 自身，不升级项目依赖。Homebrew 安装执行
`brew upgrade fluoh`，Dart global 安装执行 `dart pub global activate fluoh`。
本地源码 checkout 会被拒绝，因为替换 checkout 属于用户主动决策。

## Source 命令

Source 命令分为两类：消费侧命令管理已配置的本地快照；维护侧命令编辑 source
仓库本身。source 快照是保存在 `$FLUOH_HOME/sources/<name>` 下、已经校验通过的
Source 本机副本。

### 消费侧命令

`fluoh source list` 会先要求 Source 运行时确保已配置 source 快照和 `sources.lock.json`
可用，然后读取 `$FLUOH_HOME/config.json`，输出每个已配置 source 的名称和显示值。
空配置是 warning，不是错误。

`fluoh source add <name> <url-or-path>` 校验 source 名称，拒绝替换官方 source
名称，并把缓存路径固定为 `$FLUOH_HOME/sources/<name>`。普通本地路径会在
`$FLUOH_HOME/config.json` 中规范化为绝对 `file:` URL，后续 `source update` 才能从原始目录
刷新缓存。本地路径和 `file:` URL 会复制校验后的快照；HTTPS/SSH URL 会立即 clone，
并且在写入配置项前完成校验。`--priority` 默认值为 `10`，source 数据重叠时优先级越高越先使用。
新快照校验通过后，Source 运行时会一起提交配置项和重新生成后的 lock。

重叠数据的合并规则是显式的：

- SDK release 按 tag 合并。优先级高的 source 胜出；同优先级下发布记录冲突会报错。
- Package 发布记录按 `package + sdkLine + upstreamVersion` 分组。高优先级会替换同组低优先级记录。
  消费侧索引只包含 `compatible` 发布记录；`experimental` 和 `broken` 记录仍保留在
  Manifest 文件中，但不会覆盖低优先级的 compatible 推荐。
- 同优先级下，派生 tag 相同但 repository 或 path 不同会报错。同组内不同 tag 可以并存，由依赖规划器选择最佳 compatible 发布记录。
- package 级 upstream URL 和 advisory 文本来自定义该 package 的最高优先级 source。

`fluoh source remove <name>` 从工具配置中移除非官方 source。官方 Source alias
`flutteroh` 不允许删除。该命令不拥有配置项以外的无关文件，lock 维护交给 Source 运行时。

`fluoh source update [name]` 刷新全部 source 或单个指定 source。命令选中的 Git source
会重新 clone，命令选中的 `file:` source 会从配置的本地目录重新复制。随后 Source 运行时会校验
所有已配置 source 快照，因为 lock 是基于全部已配置 source 的合并索引。

会修改 source 状态的命令把候选 config 或快照状态交给 Source 运行时。校验或 lock
生成失败时，运行时必须保留上一份可用的 config、快照和 lock。

### 维护侧命令

`fluoh source validate [path]` 校验本地 Source 仓库，但不会读取或写入
`$FLUOH_HOME/config.json`、source 快照或 `sources.lock.json`。不传 `path` 时默认使用当前目录。
该命令会检查 Source root schema、`environment.fluoh`、SDK 元数据、Manifest routes、
Manifest name、重复 package、package release 记录，以及 package index 能否构建。它不会 fetch
SDK tags 或 package 仓库；发布数据更新仍由 `fluoh source sync` 负责。

`fluoh source init <path>` 创建 source root `fluoh.yaml`、
`manifests/example/fluoh.yaml` 注释 Manifest 模板和 README。目标文件已存在时会保守
跳过并报告。生成的 `fluoh.yaml` 是合法的空 Source 脚手架，并带有注释形式的
repository、SDK 和 Manifest 路由示例，维护者可按需取消注释。维护者直接编辑 Manifest
文件中的 advisory 和 maintenance 信息；发布记录由 `fluoh source sync` 生成。

`fluoh source sync [path]` 读取 Source root 里的 Manifest routes，把每个
Manifest 的 `repository.git.url` 作为 FlutterOH package 仓库，读取 release tags，读取每个
tag 下固化的 Package `fluoh.yaml`，然后把历史发布记录汇总到 Manifest。不传
`path` 时默认使用当前目录。source 元数据应来自已发布适配记录，而不是维护中的仓库
状态。当 `<path>` 是 `$FLUOH_HOME/sources/<name>` 下的某个已配置 source 快照时，
sync 会被视为已配置 Source 快照变更，由 Source 运行时重建合并后的 lock。当
`<path>` 是配置快照之外的维护仓库时，本机 lock 不会变化；发布或复制到已配置快照后，
再运行 `fluoh source update <name>`。`--json` 会以 JSON 输出已同步和跳过的 package 记录。

## SDK 命令

`fluoh sdk list` 合并远端 source release 和本地已安装 SDK 缓存。source index 不可用
但本地已有 SDK 时，仍会列出本地条目。

`fluoh sdk install <version-or-series>` 支持精确 SDK 版本，也支持 `3.35`
这样的版本系列。版本系列优先选择最新 stable 版本。管理器会把 SDK 仓库 clone 到
`$FLUOH_HOME/sdks/<version>`，checkout 对应 Git tag；失败时删除未完成的目标目录。

`fluoh sdk current` 读取当前项目 SDK 版本。未选择 SDK 时输出 warning，并返回退出码
`1`。

`fluoh sdk remove <version-or-series>` 解析请求的 release 或精确本地缓存版本，只删除
`$FLUOH_HOME/sdks` 下匹配的 SDK 目录。

`fluoh sdk use <version-or-series>` 是项目修改命令。它要求当前目录是 Flutter 项目，
拒绝覆盖 FlutterOH package 仓库元数据，解析或安装 SDK，写入项目 `fluoh.yaml`，并更新
`.fluoh/flutter_sdk` 作为稳定的 IDE SDK 路径。默认情况下，它会在项目缺少 `ohos/`
目录时使用已选择 SDK 执行 `flutter create --no-pub --platforms=ohos .`。
`--no-init-ohos` 可跳过这个默认初始化。`--pub-get` 会在切换和可能的 OHOS 初始化后
执行 `flutter pub get`。

## 依赖命令

这些命令面向普通 FlutterOH 项目，并保留 `pubspec.yaml` 中的无关内容。

`fluoh deps get` 会通过已选择 SDK 执行 `flutter pub get`，并允许透传额外参数。
它会在所有主 package 目录和已有且包含 `pubspec.yaml` 的 package example 中运行。
它刻意跳过 package Source 数据，让依赖解析在 source 快照需要修复时仍然可用。如果已选择
SDK 缺失，SDK resolver 只会为查询并安装该 SDK 而加载 Source index。

`fluoh deps check` 读取项目 `fluoh.yaml` 中的依赖策略，根据已配置 source 构建依赖计划，
并把依赖分组为 ready、needs decision、manual action、unavailable、already OK、
transitive 和 advisory。fresh Source lock 会提供 package 路由提示；命令随后只读取可能包含
项目 lockfile 中 package 的 Manifest 文件。`--json` 输出同一计划的机器可读 JSON。

`fluoh deps fix` 根据依赖计划应用推荐 FlutterOH 适配变更。它会按照
`dependencyPolicy.pubspecSection` 写入 `dependency_overrides` 或直接改写依赖声明。
版本不匹配默认跳过，除非 `dependencyPolicy.versionChanges` 为 `any`。
`--dry-run` 或 `-n` 只打印计划，不修改 `pubspec.yaml`。

`fluoh deps upgrade` 比 `deps fix` 更窄：只升级已有 FlutterOH 依赖替换，不新增替换。它使用
同样的版本变化策略和 dry-run 行为。

## Package 仓库命令

这些命令维护 FlutterOH package 仓库。它们假设当前是 Git 仓库，并且对分支和工作树状态
保持严格要求。

### 自动适配命令流

AI 自动适配只使用一组职责清晰的命令：

1. 建仓：新 package 仓库使用 `fluoh package create <upstream>`，追加 package 使用
   `fluoh package add <package-path>`；只有在已完成并提交一个 checkpoint 后，才用
   `fluoh package sync` 合入 upstream。
2. 基线门禁：写 OHOS 代码前运行 `fluoh deps get`、`fluoh doctor project --json --strict`、
   `fluoh doctor env --json --strict`、`fluoh doctor env --platform all --json --strict`、
   `fluoh flutter analyze`，以及相关的既有 package 或 example 测试。project warning
   指向仓库文件；environment warning 指向本机工具链或 Source 配置。
3. 实现循环：每次有意义的代码或元数据变更后，如果依赖或 SDK 元数据变了先跑
   `fluoh deps get`，再用 `fluoh package check --package <name> --json` 跑到 pub get、
   analyze 和已有测试全部通过。
4. OHOS 验证：使用
   `fluoh package check --package <name> --preset ohos-run --json`；已有 hdc 目标时添加
   `--device <id>`。没有设备时，用
   `fluoh package check --package <name> --build-example hap --debug --auto-sign --json`
   作为 build-only 证据。
5. 既有平台回归：存在 `example/android` 时，先跑
   `fluoh doctor env --platform android --json --strict`，再跑
   `fluoh package check --package <name> --preset android-run --json`。
   存在 `example/ios` 时使用对应 iOS doctor 和
   `fluoh package check --package <name> --preset ios-run --json`。
6. diagnostics 循环：编辑前先读 JSON 里的 `nextCommand`、`diagnostics[].code`、
   `stdoutTail`、`stderrTail` 和已保存运行日志。`doctor env` 失败修本机工具链，
   `doctor project` 失败修仓库配置，`package check` 失败修产生 diagnostic 的代码或
   example。
7. 完成报告：写入 `.fluoh/ai-report-<package-or-scope>-YYYYMMDD-HHMMSS.md`，包含命令、
   结果、平台矩阵、签名模式、日志、剩余风险和发布建议。
8. 发布门禁：运行 `fluoh package status --package <name>`、最终
   `fluoh package check --package <name>` 和
   `fluoh package release --package <name> --dry-run`。只有相关门禁通过后才提交；维护者确认
   打 tag 后再运行 `fluoh package release --package <name>`。

### 适配流程

适配以 Flutter OHOS 大版本线为单位维护，而不是以 SDK patch 版本为单位维护。
例如完整 SDK `3.35.8-ohos-0.0.3` 对应 SDK 版本线 `3.35`，适配仓库分支使用
`ohos/3.35`。

推荐流程：

1. 选择完整 SDK 版本。
2. 从 SDK 版本推导 SDK 版本线。
3. 创建或切换 `ohos/<sdkLine>` 分支。
4. 在 Package `fluoh.yaml` 中记录当前适配的 upstream package 版本和 FlutterOH
   适配 package 版本。
5. 开始写 OHOS 代码前，先用已选择 SDK 做基线检查，包括 `fluoh deps get`、
   `fluoh flutter analyze`、已有 package 测试或 example 构建；先修复非 OHOS 平台
   因 SDK 切换暴露的问题。
6. 适配中使用 `status: experimental`；完成并可推荐时省略 `status`，默认就是
   `compatible`。
7. `fluoh package release` 打 release tag，tag 固化当前代码、测试和 Package
   `fluoh.yaml`。
8. `fluoh source sync` 从 release tags 汇总 Source Manifest。

`fluoh package create <upstream>` clone upstream 仓库，选择一个或多个 package，配置
`upstream` 和 `origin`，创建 `ohos/3.35` 这类 Flutter OHOS SDK 版本线分支，配置
Flutter OHOS SDK，写入 `fluoh.yaml`、`FLUOH.md`、`FLUOH_CHANGELOG.md` 和 agent
指令，然后暂存生成文件。如果选中的 package 已有 Flutter example，命令会给该 example
新增 OHOS 平台、写入 example SDK 配置，并暂存 example 变更。生成的引导会要求维护者先
建立已选择 SDK 基线并修复非 OHOS 平台回归，再实现 OHOS 代码。
生成的 agent 指令也会要求 AI 在维护者要求本地提交时，按已完成且已验证的 checkpoint
拆分小的本地 commit。
不传 `--package-path` 时，命令只选择 upstream 仓库根目录 package。若 upstream
仓库同时有根目录 package 和子目录 package，需要传 `--package-path .`，并为每个要注册的
子 package 重复传 `--package-path <subdir>`。
生成的 `fluoh.yaml` 会在 `repository`、`upstream`、package path、`version` 和
`status` 等维护者常改字段旁提供注释。它不会创建 commit。可用参数包括可重复的
`--package-path`、`--output`、`--sdk`、`--repository`、`--git-author-name` 和
`--git-author-email`。Git 作者参数只配置新仓库本地 Git `user.name` 和 `user.email`，
供后续适配 commit 使用，不写入被跟踪文件。

`fluoh package add <package-path>` 在现有 FlutterOH package 仓库中注册另一个 package。它要求
工作树干净且位于 Package `repository.git.branch` 记录的维护分支，校验
`<package-path>`，可选校验 `--expected-package`，追加 Package `fluoh.yaml` 和文档，
在已有 Flutter example 时准备 example，并暂存生成文件。命令失败时会通过文件快照保护
本地状态。

`fluoh package sync` 会拉取 upstream，快进 Package `upstream.git.branch` 记录的 upstream
分支，回到 `fluoh.yaml` 记录的 `repository.git.branch` 分支，先把 upstream 分支合并进来但
不立即提交，然后更新 `fluoh.yaml` 中的 upstream 元数据并暂存；
存在变更时提交 `Sync upstream packages`。合并冲突会留给用户解决，之后
`fluoh package sync --continue` 校验已暂存的解决结果并完成流程。`--abort` 对进行中的 sync
执行 `git merge --abort`。`--json` 会输出完成的 sync 动作列表和提交状态。

`fluoh package check` 会运行 Package `fluoh.yaml` 中已注册 package 的现有自动化检查。
它会先用已选择 SDK 为 package 执行 `pub get` 和 `analyze`：Flutter package 使用
`flutter`，非 Flutter package 使用 `dart`；如果 package 存在 `test/**/*_test.dart`，
继续运行 package 测试。如果存在顶层 Flutter example（`example/pubspec.yaml`），也会在
example 中运行 `flutter pub get`、`flutter analyze` 和已有测试。使用 `--package <name>`
检查单个 package，或用 `--all` 检查所有已注册 package。

`--preset baseline`、`--preset ohos-run`、`--preset android-run`、`--preset ios-run`、
`--preset all-run` 和 `--preset release` 会展开常用自动化流程，避免记长参数。单平台 run
preset 默认启动本地 emulator 或 simulator；已有目标时加 `--device <id>`，需要选择本地
emulator 时加 `--emulator <name>`。`release` preset 运行 OHOS、Android 和 iOS 的 build-only
门禁。

底层的 `--build-example hap`、`--build-example apk` 或 `--build-example ios` 会在分析和测试
之后构建每个 Flutter example；配合 `--debug` 会把 `--debug` 传给 `flutter build`。iOS
example 构建会自动加入 `--no-codesign`，用于捕获编译回归，不要求开发者团队或 provisioning
profile。`--auto-sign` 会根据 example 申请的权限生成临时本地 OHOS debug 签名 profile，并在构建后
恢复 `example/ohos/build-profile.json5`；它只适用于 `--build-example hap`。
`--run-example` 会用 `hdc` 安装构建出的 HAP、启动 example ability，并把一段 hilog 保存到
`$FLUOH_HOME/package-runs`。对于 APK 和 iOS target，`--run-example` 会通过已选择 SDK 的
`flutter run` 启动 example，把 run-smoke 输出保存到
`$FLUOH_HOME/package-runs`，并在 example 存在 `integration_test/` 目录时继续运行
`flutter test integration_test -d <device>`。Android/iOS 运行检查前，先使用
`fluoh doctor env --platform android --json --strict` 或
`fluoh doctor env --platform ios --json --strict` 检查原生环境。没有连接设备时可以加
`--start-emulator`，fluoh 会通过原生工具启动 Android AVD 或 iOS simulator，然后等待已选择
SDK 识别目标；`--emulator <name>` 指定本地 emulator id 或名称，多个 target 已连接时用
`--device <id>` 指定。
`--device-timeout <seconds>` 控制等待 target 上线的时间。`--log-duration <seconds>` 调整
OHOS hilog 或 Android/iOS Flutter run-smoke 采集窗口。`--json` 会输出结构化检查结果，其中
package 和 step 可包含 `nextCommand`，每个 step 可包含带稳定错误码的 `diagnostics`、失败命令
输出尾部，以及签名、运行、HAP 或平台目标明细，方便自动化流程判断下一步动作。

`fluoh package release` 校验 release 元数据，确认配置的 SDK 版本存在于 source，运行
`fluoh package check`，确认工作树仍然干净，在 HEAD 创建 release tag，并可选择推送。使用
`--package <name>` 发布单个 package，或用 `--all` 发布所有已注册 package。已有 tag 只有在
已经指向 HEAD 时才会被接受。`--dry-run` 会执行校验和 package check，但不会创建或推送
tag。`--json` 会输出 tag、warning 和 package check 结果。

`fluoh package status` 读取 Package `fluoh.yaml` 并汇总发布就绪状态，不修改仓库。它会检查
当前分支、工作树是否干净、package status、release notes、license warning、package 测试、
Flutter example、example OHOS 平台、example 测试，以及 tracked 文件是否包含本机 fluoh home
路径。使用 `--package <name>` 检查单个 package，`--all` 检查全部 package，`--json`
输出机器可读结果。

## 状态归属

| 状态 | 所属方 / 维护入口 |
| --- | --- |
| `$FLUOH_HOME/config.json` | `source add`、`source remove`、`source update`、首次默认 Source bootstrap |
| `$FLUOH_HOME/sources/<name>` | `source add`、`source update` |
| `$FLUOH_HOME/sources.lock.json` | `lib/src/source/` 中的 Source 运行时；Source 状态变更、首次默认 Source bootstrap，以及 load-index 检查发现过期或需要 SDK 元数据来安装已选择的 SDK 时重建 |
| `$FLUOH_HOME/sdks/<version>` | `sdk install`、`sdk remove`、按需执行的 Flutter wrapper |
| 项目 `fluoh.yaml` | `sdk use`、`deps check`、`deps fix`、`deps upgrade` |
| 项目 `pubspec.yaml` | `deps fix`、`deps upgrade` |
| FlutterOH package 仓库 `fluoh.yaml` | `package create`、`package add`、`package sync`、`package status`、`package release` 校验 |
| Source root 和 Manifest 文件 | `source init`、`source sync` |
| `.fluoh/flutter_sdk` | `sdk use`、`package create` 的 SDK 设置 |
| Package examples | `package create`、`package add`、`deps get`、`package check`、`package release` |
