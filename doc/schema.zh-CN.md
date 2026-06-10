# Schema 设计

[English](schema.md)

本文档说明 `fluoh` 当前规范化 YAML 和 JSON 数据结构。解析与渲染逻辑位于
`lib/src/schema/`，Source 加载与缓存校验逻辑位于 `lib/src/source/`。

## Schema 版本

所有 YAML schema 都使用 `schema: 1`。命令只校验当前规范结构。

所有 `fluoh.yaml` 都必须包含 `kind`：

| Kind | 所属 | 用途 |
| --- | --- | --- |
| `project` | Flutter 项目 | 当前 SDK 和依赖替换策略。 |
| `package` | FlutterOH Package 适配仓库 | 当前适配分支元数据。 |
| `source` | Source 根目录 | Source 元数据、SDK 索引和 Manifest 路由。 |
| `manifest` | Source Package Manifest | 已发布的 Package 适配记录。 |

状态所属：

| Owner | 用途 |
| --- | --- |
| Project | 用户本地 Flutter 项目。 |
| Package | FlutterOH Package 适配仓库和分支。 |
| Source | 已发布或本地 Source，例如 `FlutterOH/source`。 |
| Manifest | 从 Source 根路由到的逐 Package 文件。 |

## 共享规则

- 完整 Flutter OHOS SDK 版本必须符合 `<major>.<minor>.<patch>-ohos-...`。
  SDK line 取前两个数字段，例如 `3.35.8-ohos-1.0.1 -> 3.35`。
- Source root `name` 是非空且不含空白字符的 token。Source Manifest route 名和
  `package.name` 必须是 Dart package 名。
- Package 路径是使用 `/` 的规范化相对路径，路径段非空，并且不做父目录跳转。
- `package.path: .` 是默认值，规范化输出可以省略。
- upstream 版本和 FlutterOH release 版本统一遵循 pub semver。
- `upstream.commit` 必须是完整 40 位十六进制 Git commit hash。
- Release status 取值为 `compatible`、`experimental`、`broken`。`compatible` 是默认值，
  规范化输出会省略。
- 消费命令默认只使用 `compatible` release。

## Project `fluoh.yaml`

```yaml
schema: 1
kind: project

sdk:
  version: 3.35.8-ohos-1.0.1

dependencyPolicy:
  pubspecSection: dependency_overrides
  versionChanges: compatible
```

规则：

- `sdk.version` 必填，并且必须存在于合并后的 Source SDK 索引中。
- `dependencyPolicy` 必填。
- `dependencyPolicy.pubspecSection` 取值为 `dependency_overrides` 或 `dependencies`。
- `dependencyPolicy.versionChanges` 取值为 `compatible` 或 `any`。
- 依赖 release status 的可见性是命令级行为，不写入项目 schema。`deps check`、
  `deps fix` 和 `deps upgrade` 默认只消费 compatible Source release，可通过
  `--all-release-statuses` 显式包含非 compatible release。

## Package `fluoh.yaml`

Package `fluoh.yaml` 描述一个 Package 适配分支。release 历史由 Source Manifest
持有，并从固定格式的 package release tag 导入。

```yaml
schema: 1
kind: package

sdk:
  version: 3.35.8-ohos-1.0.1

repository:
  git:
    url: https://github.com/FlutterOH/camera.git
    branch: ohos/3.35/camera

upstream:
  git:
    url: https://github.com/flutter/packages.git
    branch: main

package:
  name: camera
  path: packages/camera/camera
  release:
    version: 0.2.0
    upstream:
      version: 0.20.0
      ref: camera-v0.20.0
      commit: "0123456789abcdef0123456789abcdef01234567"
    status: experimental
```

规则：

- `kind` 必须为 `package`。
- `sdk.version` 必填；消费 SDK 数据的命令会要求它存在于合并后的 Source SDK 索引中。
- `repository.git.url` 和 `repository.git.branch` 必填。
- `repository.git.branch` 必须使用 `ohos/<sdkLine>/<package.name>`，例如
  `ohos/3.35/camera`。
- `upstream.git.url` 和 `upstream.git.branch` 必填。
- `package.name` 必填。
- `package.path` 同时表示适配仓库和 upstream 仓库中的 Package 路径。
- `package.release.version` 必填，并遵循 pub semver。
- `package.release.upstream.version` 和 `package.release.upstream.commit` 必填。
  `package.release.upstream.ref` 可选。
- `package.release.status` 可选。省略或写成 `compatible` 都表示该分支可正常消费；
  非默认状态才写 `experimental` 或 `broken`。

Package release tag 使用固定格式：

```text
<package>-<upstream.version>-ohos-<sdkLine>-<release.version>
```

例如：

```text
camera-0.11.0-ohos-3.35-1.0.1
```

`fluoh source sync` 按这种固定格式解析 release tag。
当 Source 根声明了 `sdk.versions` 时，sync 只导入 SDK line 已被这些 SDK 版本覆盖的
package release tag。更高 SDK line 的 tag 会被跳过，直到 Source 根添加对应 SDK 版本。

## Source 根 `fluoh.yaml`

Source 根 `fluoh.yaml` 描述 Source 自身、可选 SDK 数据和逐 Package Manifest 路由。

```yaml
schema: 1
kind: source
name: flutteroh
description: Flutter OHOS SDK and package adaptation source.

repository:
  git:
    url: https://github.com/FlutterOH/source.git

sdk:
  git:
    url: https://gitcode.com/CPF-Flutter/flutter_flutter.git
  versions:
    - 3.35.8-ohos-0.0.2
    - 3.35.8-ohos-0.0.3
    - 3.35.8-ohos-1.0.1

manifests:
  - name: camera
  - name: webview
```

规则：

- `kind` 必须为 `source`。
- `name` 必填，必须是非空且不含空白字符的 token。
- `description` 可选，只作为 Source 自描述信息。
- `repository.git.url` 可选，只作为 Source 自描述信息。
- `sdk` 和 `manifests` 都可选，并且准备 Source 时可以为空。
- 如果存在 `sdk`，`sdk.git.url` 必填。
- `sdk.versions` 按语义化版本升序列出完整可安装 SDK 版本。准备 Source 时可以省略；
  空 SDK 索引的规范化输出会写成 `versions: []`。
- `sdk.versions[]` 取值唯一。
- `manifests[].name` 必填且唯一，映射到 `manifests/<name>/fluoh.yaml`。
  规范化输出按名称排序 route。

## Source Manifest `fluoh.yaml`

Source Manifest 只描述一个 Package。它按 SDK line 记录 release 历史。
`fluoh source sync` 从固定格式的 package release tag 导入这些记录；维护者可以补充
advisory 和 maintenance 元数据。

```yaml
schema: 1
kind: manifest

repository:
  git:
    url: https://github.com/FlutterOH/camera.git

upstream:
  git:
    url: https://github.com/flutter/packages.git

package:
  name: camera
  path: packages/camera/camera
  maintenance:
    frozen: true
    note: Upstream now supports OHOS natively.
  advisory:
    message: Prefer upstream camera when OHOS native support is available.
    alternatives:
      - name: camera_ohos
        reason: Provides native OHOS support.
        url: https://pub.dev/packages/camera_ohos
  sdks:
    "3.35":
      releases:
        - version: 0.1.0
          upstream:
            version: 0.11.0
            ref: camera-v0.11.0
            commit: "0123456789abcdef0123456789abcdef01234567"
        - version: 0.2.0
          upstream:
            version: 0.20.0
            ref: camera-v0.20.0
            commit: "0123456789abcdef0123456789abcdef01234567"
          status: experimental
```

规则：

- route 名由 Source 根 `manifests[].name` 持有，并且必须匹配 `package.name`。
- `kind` 必须为 `manifest`。
- `repository.git.url` 和 `upstream.git.url` 必填。
- Source Manifest 的 repository/upstream 块记录 Git URL；branch 和 path 由 Package
  metadata 与 release tag 持有。
- `package` 必填，并描述一个 Package。
- `package.path` 同时表示两个仓库中的路径，默认 `.`。
- 一个 Source Manifest 对所有 release record 只有一个 `package.path`。`source sync`
  会跳过 Package metadata 声明了不同路径的 release tag。
- `package.maintenance.frozen` 可选，默认 `false`。
- `package.maintenance.note` 可选。
- `package.advisory` 是可选用户提示；机器 release status 由 `releases[].status`
  持有。
- `package.advisory.message` 可选。`package.advisory.alternatives[]` 可选；
  每个 alternative 必须包含 `name`，并且可以包含 `reason` 和 `url`。
- `package.sdks` 必填，并至少包含一个 SDK line。
- `package.sdks.<sdkLine>.releases[]` 是对应 SDK line 的 release 历史，并至少包含一个
  release record。
- 每个 Package SDK line 必须存在于消费命令使用的合并 Source SDK 索引中。
- 同一个 SDK line 下的 Release 记录使用唯一的 `upstream.version` 和 `version` 组合。
- Release tag 始终由固定 release tag 规则派生。
- `releases[].version` 和 `releases[].upstream.version` 必填。
- `releases[].upstream.ref` 可选。
- `releases[].upstream.commit` 必填。
- `releases[].status` 可选。省略表示 `compatible`。
- 规范化输出按 SDK line 升序排列。每个 SDK line 内的 Release 按 upstream 版本和
  release 版本从早到晚排序，所以新增 release 会追加到已有记录后面。

## 生成 Markdown 段

生成的 `FLUOH.md` 和 `AGENTS.md` Package 仓库指导文档独立于 YAML schema 版本管理。
生成段使用 Markdown 注释包围：

```text
<!-- fluoh:generated:start id=<section> template=<templateVersion> -->
...
<!-- fluoh:generated:end id=<section> -->
```

只有匹配的生成段属于工具。生成段前后的手写内容属于用户，必须保留。

## Source 缓存和 Lock 文件

工具配置和合并后的 Source 状态是 JSON 文件，不属于 `fluoh.yaml` schema。

- `config.json` 记录已配置 Source alias、路径、URL 和优先级。
- `sources.lock.json` 记录项目命令使用的合并 Source 快照。
- Lock 条目包含 `"fingerprint"` 数据，便于 `fluoh` 检测 Source 变化。
- Lock 条目包含 `"packageRoutes"`，依赖命令可以直接定位
  `manifests/<name>/fluoh.yaml` 数据，避免扫描所有 Source。
- Source 数据合并后，Package 记录会暴露 `upstreamVersion` 等机器字段。

## `config.json`

工具配置使用 JSON，因为它是机器生成的运行时状态：

```json
{
  "sources": {
    "flutteroh": {
      "url": "https://github.com/FlutterOH/source.git",
      "path": "/home/user/.fluoh/sources/flutteroh",
      "priority": 0
    },
    "local": {
      "url": "file:///Users/user/local/source",
      "path": "/home/user/.fluoh/sources/local",
      "priority": 10
    }
  }
}
```

规则：

- 官方 Source alias 固定为 `flutteroh`，默认 priority 为 `0`。
- 用户新增 Source 默认 priority 为 `10`。数值越大优先级越高。
- Source alias 使用字母、数字、`_`、`.` 或 `-`；`.` 和 `..` 为保留值。
- `url` 支持 HTTPS URL、SSH URL 和 `file:` URL。`fluoh source add` 会把用户传入的
  本地路径规范化为绝对 `file:` URL。
- HTTPS/SSH URL 走 Git clone/update；`file:` URL 复制校验后的 Source 快照。
- `path` 是本机缓存路径。
- Source 缓存只保留最新校验通过的快照，不保留 Git 历史和无关仓库文件。

## `sources.lock.json`

`$FLUOH_HOME/sources.lock.json` 是机器生成、仅存在于本机的已解析 SDK lock manifest，
同时包含轻量 Package 路由索引。它由 `config.json` 和每个已校验 Source 快照派生，
让命令读取稳定 JSON，而不是每次重新解析 Source YAML。完整 Package entries 不写入
lock；Package 命令先用路由索引找到相关 Manifest 文件，再按需从已配置 Source 快照读取
Package metadata。

结构示例：

```json
{
  "fingerprint": {
    "toolVersion": "0.1.0",
    "sources": [
      {
        "name": "flutteroh",
        "path": "/home/user/.fluoh/sources/flutteroh",
        "url": "https://github.com/FlutterOH/source.git",
        "priority": 0,
        "snapshotHash": "hash64:..."
      },
      {
        "name": "local",
        "path": "/home/user/.fluoh/sources/local",
        "url": "file:///Users/user/local/source",
        "priority": 10,
        "snapshotHash": "hash64:..."
      }
    ]
  },
  "sdk": {
    "sources": {
      "flutteroh": {
        "git": {
          "url": "https://gitcode.com/CPF-Flutter/flutter_flutter.git"
        }
      }
    },
    "versions": {
      "3.35.8-ohos-0.0.2": {
        "source": "flutteroh"
      },
      "3.35.8-ohos-0.0.3": {
        "source": "flutteroh"
      },
      "3.35.8-ohos-1.0.1": {
        "source": "flutteroh"
      }
    }
  },
  "packageRoutes": {
    "flutteroh": {
      "camera": ["3.35"],
      "path_provider": ["3.35"]
    },
    "local": {
      "camera": ["3.35"]
    }
  }
}
```

规则：

- lock 是可丢弃的生成状态，不包含 `schema` 字段；缺失或过期时直接重建。
- Source root 和 Manifest YAML 仍然是唯一需要人工编辑的 Source 数据。
- Source lock 维护由 `lib/src/source/` 中的 Source 运行时统一负责；命令通过该运行时访问
  lock。
- `config.json`、任一已配置 Source 快照、SDK 合并规则或 `fluoh` 工具版本变化时，
  Source 运行时都会整体重新生成 lock。
- 每个已配置 Source 快照包含生成的 `.fluoh-source-state.json`，记录快照 hash。
  常规 lock 新鲜度检查读取这个 state 文件，而不是每次命令都递归 hash 整个快照。
  state 文件缺失时，运行时会重新计算快照 hash 并补写 state 文件。
- Source 状态变更入口，包括 `fluoh source add`、`fluoh source remove`、
  `fluoh source update`、已配置快照 repair、目标是已配置快照的 `fluoh source sync`、
  以及首次默认 Source 初始化，都会请求 Source 运行时重建 lock。消费 source 的流程使用
  同一个 load-index API；发现 lock 缺失或过期时，或者已选择 SDK 缺失且需要 SDK 元数据来安装
  已选择的 SDK 时，会按需重新生成。
- lock 在 `sdk.sources` 中按 Source alias 保存一次 SDK repository。每个已解析 SDK
  release 在 `sdk.versions` 中保存胜出的 Source alias。能从对象 key、默认值或
  `fingerprint.sources` 推导的数据会省略：source priority 只保存在 `fingerprint.sources`，
  SDK `versionSeries` 和 `flutterVersion` 由 SDK version key 推导，SDK `tag` 默认等于
  version key，SDK `channel` 默认为 `stable`。
- lock 按语义化版本升序写出 `sdk.versions`。
- `packageRoutes` 索引保存 Source/Package 路由，以及该 route 下 Package 出现过的
  compatible SDK line。完整 Package metadata 保留在 Source Manifest 文件中。
- 生成的 lock 文件使用 compact-pretty JSON：根区段和大对象保持多行，短的叶子对象和数组压成单行。
- SDK 命令读取 SDK lock。Package 命令使用 Package 路由索引，只解析可能包含当前项目
  Package 的 Manifest 文件，然后在内存中执行 Package priority 和冲突规则。
- lock 生成使用 Source 命令文档中的 SDK priority 和冲突规则。Package priority 和冲突规则
  在依赖工作流加载 Package metadata 时执行。
- 写入使用临时文件加原子替换。lock 只有在记录的 fingerprint 匹配当前 Source 状态时才会被
  视为 fresh。
