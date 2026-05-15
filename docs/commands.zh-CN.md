# Command 设计

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
| `fluoh clean` | `lib/src/clean/clean_command.dart` | 执行 `flutter clean` 并清理生成的 `fluoh_test` 产物。 |
| `fluoh source` | `lib/src/source/source_commands.dart` | 数据源使用和维护的命令组。 |
| `fluoh source list` | `lib/src/source/source_commands.dart` | 列出已配置的 FlutterOH 数据源。 |
| `fluoh source add <name> <url-or-path>` | `lib/src/source/source_commands.dart` | 把本地或 Git 数据源加入工具配置。 |
| `fluoh source remove <name>` | `lib/src/source/source_commands.dart` | 从工具配置中移除非官方数据源。 |
| `fluoh source update [name]` | `lib/src/source/source_commands.dart` | 刷新并校验已配置的数据源快照。 |
| `fluoh source init <path>` | `lib/src/source/source_commands.dart` | 创建本地 source 仓库模板。 |
| `fluoh source sync [path]` | `lib/src/source/source_commands.dart` | 把已发布 FlutterOH pub 仓库元数据同步进 source 仓库。 |
| `fluoh sdk` | `lib/src/sdk/sdk_commands.dart` | 本地 Flutter OHOS SDK 缓存的命令组。 |
| `fluoh sdk list` | `lib/src/sdk/sdk_commands.dart` | 列出远端 SDK version 和本地 SDK 缓存。 |
| `fluoh sdk install <version-or-series>` | `lib/src/sdk/sdk_commands.dart` | 把 SDK version 安装到 `$FLUOH_HOME/sdks`。 |
| `fluoh sdk current` | `lib/src/sdk/sdk_commands.dart` | 输出当前项目选择的 SDK。 |
| `fluoh sdk remove <version-or-series>` | `lib/src/sdk/sdk_commands.dart` | 删除一个已安装的 SDK 缓存。 |
| `fluoh sdk use <version-or-series>` | `lib/src/sdk/sdk_use_command.dart` | 为当前 Flutter 项目选择 SDK。 |
| `fluoh pub` | `lib/src/pub/commands/pub_command.dart` | 项目依赖和 FlutterOH pub 仓库的命令组。 |
| `fluoh pub get` | `lib/src/pub/commands/pub_get_command.dart` | 为项目和 `fluoh_test` 工作区执行 `flutter pub get`。 |
| `fluoh pub check` | `lib/src/pub/commands/pub_dependency_commands.dart` | 输出依赖 FlutterOH 适配状态。 |
| `fluoh pub fix` | `lib/src/pub/commands/pub_dependency_commands.dart` | 应用推荐的 FlutterOH 依赖变更。 |
| `fluoh pub upgrade` | `lib/src/pub/commands/pub_upgrade_command.dart` | 只升级已有 FlutterOH 依赖替换。 |
| `fluoh pub create <upstream>` | `lib/src/pub/commands/pub_create_command.dart` | 初始化 FlutterOH pub 仓库。 |
| `fluoh pub add <package-path>` | `lib/src/pub/commands/pub_add_command.dart` | 在 FlutterOH pub monorepo 中注册另一个 package。 |
| `fluoh pub sync` | `lib/src/pub/commands/pub_sync_command.dart` | 把 upstream 合入当前 OHOS pub 分支。 |
| `fluoh pub release` | `lib/src/pub/commands/pub_release_command.dart` | 校验、测试、打 tag，并可选择推送 FlutterOH package release。 |
| `fluoh test` | `lib/src/testing/test_commands.dart` | package 验证工作区的命令组。 |
| `fluoh test init` | `lib/src/testing/test_commands.dart` | 创建 `fluoh_test` 验证工作区。 |
| `fluoh test run` | `lib/src/testing/test_commands.dart` | 运行 package 测试和 `fluoh_test` 测试。 |
| `fluoh doctor` | `lib/src/doctor/doctor_command.dart` | 诊断本地项目、source、SDK 和工具状态。 |
| `fluoh upgrade` | `lib/src/upgrade/upgrade_command.dart` | 升级已安装的 `fluoh` CLI。 |

## 共享运行规则

- Help 请求不会加载 source 配置。
- Source lock 维护只有一个 owner：`lib/src/source/` 中的 Source runtime。Command
  class 不应该直接读写 `$FLUOH_HOME/sources.lock.json`。
- 会修改 Source 配置或已配置快照的命令，把变更交给 Source runtime。runtime 会校验所有
  已配置 source 快照，尽可能修复快照，重建合并后的 lock，然后再提交新的本地 Source 状态。
- 消费 Source 数据的命令只能通过 Source runtime 的 load-index API 读取。这个 API 负责
  首次默认 Source bootstrap、校验或修复已配置 source 快照，并在返回数据前重新生成缺失或
  过期的 `sources.lock.json`。
- `fluoh pub get` 会跳过 package Source 数据，让依赖解析在 source 快照需要修复时仍然可用。
  `fluoh flutter`、`fluohf`、`fluoh clean` 和 `fluoh pub get` 在已选择 SDK 缺失时，
  仍可能通过 SDK resolver 加载 Source index，因为需要 SDK 元数据来安装 selected SDK。
- 用法错误和 schema 格式错误返回退出码 `64`。
- Command class 只负责参数解析和用户可见输出；可复用行为放到
  `lib/src/sdk/`、`lib/src/pub/`、`lib/src/source/`、`lib/src/testing/`
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

### `fluoh clean`

`clean` 会对每个 primary package 目录执行已选择 SDK 的 `flutter clean`。在
FlutterOH pub 仓库中，package 目录来自 Package `fluoh.yaml`；否则使用当前目录。

Flutter clean 后，命令会删除根级和 package 级 `fluoh_test` 工作区中的生成产物，
例如 `.dart_tool`、`.pub-cache`、`build`、`coverage` 和 `local.properties`。
删除前会检查 Git 跟踪文件，包含已跟踪内容的产物目录会被跳过。

### `fluoh doctor`

`doctor` 是诊断命令，打印结果后返回成功。它会检查安装方式和 pub.dev 最新版本、
已配置 source 快照、Flutter 项目结构、项目 SDK，以及 `ohos` 平台目录。缺失或
过期状态会作为 warning 输出，不会自动修复。

### `fluoh upgrade`

`upgrade` 升级 CLI 自身，不升级项目依赖。Homebrew 安装执行
`brew upgrade fluoh`，Dart global 安装执行 `dart pub global activate fluoh`。
本地源码 checkout 会被拒绝，因为替换 checkout 属于用户主动决策。

## Source 命令

Source 命令分为两类：消费侧命令管理已配置的本地快照；维护侧命令编辑 source
仓库本身。source 快照是保存在 `$FLUOH_HOME/sources/<name>` 下、已经校验通过的
Source 本机副本。

### 消费侧命令

`fluoh source list` 会先通过 Source runtime 确保已配置 source 快照和合并后的
Source lock 可用，然后从 `$FLUOH_HOME/config.json` 输出每个已配置 source 的名称和
显示值。空配置是 warning，不是错误。

`fluoh source add <name> <url-or-path>` 校验 source 名称，拒绝替换官方 source
名称，并把缓存路径固定为 `$FLUOH_HOME/sources/<name>`。本地路径和 `file:` URL 会复制
校验后的快照；HTTPS/SSH URL 会立即 clone，并且在写入配置项前完成校验。
`--priority` 默认值为 `10`，source 数据重叠时优先级越高越先使用。新快照校验通过后，
Source runtime 会一起提交配置项和重新生成后的 lock。

重叠数据的合并规则是显式的：

- SDK release 按 tag 合并。优先级高的 source 胜出；同优先级下发布记录冲突会报错。
- Package 发布记录按 `package + sdkLine + upstreamVersion` 分组。高优先级会替换同组低优先级记录。
  消费侧索引只包含 `compatible` 发布记录；`experimental` 和 `broken` 记录仍保留在
  Manifest 文件中，但不会覆盖低优先级的 compatible 推荐。
- 同优先级下，派生 tag 相同但 repository 或 path 不同会报错。同组内不同 tag 可以并存，由 dependency planner 选择最佳 compatible 发布记录。
- package 级 upstream URL 和 advisory 文本来自定义该 package 的最高优先级 source。

`fluoh source remove <name>` 从工具配置中移除非官方 source。官方 Source alias
`flutteroh` 不允许删除。该命令不拥有配置项以外的无关文件，lock 维护交给 Source runtime。

`fluoh source update [name]` 刷新全部 source 或单个指定 source。Git source 会先
同步命令选中的 source。随后 Source runtime 会校验所有已配置 source 快照，因为 lock 是
基于全部已配置 source 的合并索引。

会修改 source 状态的命令把候选 config 或快照状态交给 Source runtime。校验或 lock
生成失败时，runtime 必须保留上一份可用的 config、快照和 lock。

### 维护侧命令

`fluoh source init <path>` 创建 source root `fluoh.yaml`、
`manifests/example/fluoh.yaml` 注释 Manifest 模板和 README。目标文件已存在时会保守
跳过并报告。生成的 `fluoh.yaml` 是合法的空 Source 脚手架，并带有注释形式的 SDK 和
Manifest 路由示例，维护者可按需取消注释。维护者直接编辑 Manifest 文件中的 advisory
和 maintenance 信息；发布记录由 `fluoh source sync` 生成。

`fluoh source sync [path]` 读取 Source root 里的 Manifest routes，把每个
Manifest 的 `repository.git.url` 作为 FlutterOH pub 仓库，读取 release tags，读取每个
tag 下固化的 Package `fluoh.yaml`，然后把历史发布记录汇总到 Manifest。不传
`path` 时默认使用当前目录。source 元数据应来自已发布适配记录，而不是维护中的仓库
状态。当 `<path>` 是 `$FLUOH_HOME/sources/<name>` 下的某个已配置 source 快照时，
sync 会被视为已配置 Source 快照变更，由 Source runtime 重建合并后的 lock。当
`<path>` 是配置快照之外的维护仓库时，本机 lock 不会变化；发布或复制到已配置快照后，
再运行 `fluoh source update <name>`。

## SDK 命令

`fluoh sdk list` 合并远端 source release 和本地已安装 SDK 缓存。source index 不可用
但本地已有 SDK 时，仍会列出本地条目。

`fluoh sdk install <version-or-series>` 支持精确 SDK version，也支持 `3.35`
这样的版本系列。版本系列优先选择最新 stable version。管理器会把 SDK 仓库 clone 到
`$FLUOH_HOME/sdks/<version>`，checkout 对应 Git tag；失败时删除未完成的目标目录。

`fluoh sdk current` 读取当前项目 SDK version。未选择 SDK 时输出 warning，并返回退出码
`1`。

`fluoh sdk remove <version-or-series>` 解析请求的 release 或精确本地缓存 version，只删除
`$FLUOH_HOME/sdks` 下匹配的 SDK 目录。

`fluoh sdk use <version-or-series>` 是项目修改命令。它要求当前目录是 Flutter 项目，
拒绝覆盖 FlutterOH pub 仓库元数据，解析或安装 SDK，写入项目 `fluoh.yaml`，并更新
`.fluoh/flutter_sdk` 作为稳定的 IDE SDK 路径。`--pub-get` 会在切换后执行
`flutter pub get`。

## Pub 项目命令

这些命令面向普通 FlutterOH 项目，并保留 `pubspec.yaml` 中的无关内容。

`fluoh pub get` 会通过已选择 SDK 执行 `flutter pub get`，并允许透传额外参数。它会在
所有 primary package 目录和已发现且包含 `pubspec.yaml` 的 `fluoh_test` 工作区中运行。
它刻意跳过 package Source 数据，让依赖解析在 source 快照需要修复时仍然可用。如果已选择
SDK 缺失，SDK resolver 只会为查询并安装该 SDK 而加载 Source index。

`fluoh pub check` 读取项目 `fluoh.yaml` 中的依赖策略，根据已配置 source 构建依赖计划，
并把依赖分组为 ready、needs decision、manual action、unavailable、already OK、
transitive 和 advisory。`--json` 输出同一计划的机器可读 JSON。

`fluoh pub fix` 根据依赖计划应用推荐 FlutterOH 适配变更。它会按照
`dependencyPolicy.pubspecSection` 写入 `dependency_overrides` 或直接改写依赖声明。
版本不匹配默认跳过，除非 `dependencyPolicy.versionChanges` 为 `any`。
`--dry-run` 或 `-n` 只打印计划，不修改 `pubspec.yaml`。

`fluoh pub upgrade` 比 `pub fix` 更窄：只升级已有 FlutterOH 依赖替换，不新增替换。它使用
同样的版本变化策略和 dry-run 行为。

## Pub 仓库命令

这些命令维护 FlutterOH pub 仓库。它们假设当前是 Git 仓库，并且对分支和工作树状态
保持严格要求。

### 适配流程

适配以 Flutter OHOS 大版本线为单位维护，而不是以 SDK patch version 为单位维护。
例如完整 SDK `3.35.8-ohos-0.0.3` 对应 SDK line `3.35`，适配仓库分支使用
`ohos/3.35`。

推荐流程：

1. 选择完整 SDK version。
2. 从 SDK version 推导 SDK line。
3. 创建或切换 `ohos/<sdkLine>` 分支。
4. 在 Package `fluoh.yaml` 中记录当前适配的 upstream package version 和 FlutterOH
   适配 package version。
5. 适配中使用 `status: experimental`；完成并可推荐时省略 `status`，默认就是
   `compatible`。
6. `fluoh pub release` 打 release tag，tag 固化当前代码、测试和 Package
   `fluoh.yaml`。
7. `fluoh source sync` 从 release tags 汇总 Source Manifest。

`fluoh pub create <upstream>` clone upstream 仓库，选择一个或多个 package，配置
`upstream` 和 `origin`，创建 `ohos/3.35` 这类 Flutter OHOS SDK line 分支，配置
Flutter OHOS SDK，写入
`fluoh.yaml`、`FLUOH.md`、`FLUOH_CHANGELOG.md`、agent 指令和 `fluoh_test`
工作区，然后暂存生成文件。它不会创建 commit。可用参数包括可重复的 `--path`、
`--output`、`--sdk` 和 `--repo`。

`fluoh pub add <package-path>` 在现有 FlutterOH pub monorepo 中注册另一个 package。它要求工作树干净且位于
Package `repository.git.branch` 记录的维护分支，校验 `<package-path>`，可选校验
`--expected-package`，追加 Package `fluoh.yaml`、文档和测试工作区状态，并暂存生成文件。单包仓库转为多包仓库时，
根级 `fluoh_test` 会迁移到 `fluoh_test/<package>`。命令失败时会通过文件快照和
workspace rollback 保护本地状态。

`fluoh pub sync` fetch upstream，快进 Package `upstream.git.branch` 记录的 upstream
分支，回到 `fluoh.yaml` 记录的 `repository.git.branch` 分支，先把 upstream 分支合并进来但
不立即提交，然后更新 `fluoh.yaml` 中的 upstream 元数据并暂存；
存在变更时提交 `Sync upstream packages`。合并冲突会留给用户解决，之后
`fluoh pub sync --continue` 校验已暂存的解决结果并完成流程。`--abort` 对进行中的 sync
执行 `git merge --abort`。

`fluoh pub release` 校验 release 元数据，确认配置的 SDK version 存在于 source，运行 package
和 `fluoh_test` 验证，确认工作树仍然干净，在 HEAD 创建 release tag，并可选择推送。使用
`--package <name>` 发布单个 package，或用 `--all` 发布所有已注册 package。已有 tag 只有在
已经指向 HEAD 时才会被接受。

## Test 命令

`fluoh test init` 为 Flutter package 创建 `fluoh_test`。多包仓库中，
`--package <name>` 选择已注册 package，并创建 `fluoh_test/<name>`。命令会写入测试 package，
使用已选择 SDK 创建 example app；`--force` 表示用户明确确认替换已有目标
`fluoh_test` 工作区。

`fluoh test run` 定位 package 和已有测试工作区。如果 package 存在
`test/**/*_test.dart`，会先运行 package 的 `pub get` 和 Flutter 测试；然后在 `fluoh_test`
中运行 `pub get` 和测试。非 Flutter package 会被跳过，因为没有需要验证的 FlutterOH
平台行为。

## 状态归属

| 状态 | 所属方 / 维护入口 |
| --- | --- |
| `$FLUOH_HOME/config.json` | `source add`、`source remove`、`source update`、首次默认 Source bootstrap |
| `$FLUOH_HOME/sources/<name>` | `source add`、`source update` |
| `$FLUOH_HOME/sources.lock.json` | `lib/src/source/` 中的 Source runtime；Source 状态变更、首次默认 Source bootstrap，以及 load-index 检查发现过期或需要 SDK 元数据来安装 selected SDK 时重建 |
| `$FLUOH_HOME/sdks/<version>` | `sdk install`、`sdk remove`、按需执行的 Flutter wrapper |
| 项目 `fluoh.yaml` | `sdk use`、`pub check`、`pub fix`、`pub upgrade` |
| 项目 `pubspec.yaml` | `pub fix`、`pub upgrade` |
| FlutterOH pub 仓库 `fluoh.yaml` | `pub create`、`pub add`、`pub sync`、`pub release` 校验 |
| Source root 和 Manifest 文件 | `source init`、`source sync` |
| `.fluoh/flutter_sdk` | `sdk use`、`pub create` 的 SDK setup |
| `fluoh_test/` | `test init`、`test run`、`pub create`、`pub add`、`pub get`、`clean`、`pub release` |
