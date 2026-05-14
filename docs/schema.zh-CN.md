# Schema 设计

[English](schema.md)

本文档说明 `fluoh` 使用的 YAML 和 JSON 配置结构。解析和渲染逻辑位于
`lib/src/schema/`，Source 加载和缓存校验逻辑位于 `lib/src/source/`。

## `fluoh.yaml`

`fluoh.yaml` 会出现在不同目录。命令通过运行上下文选择对应 schema，不通过文件名推断。

| 所属 | 用途 |
| --- | --- |
| Project | 记录当前项目选择的 SDK 和依赖替换策略。 |
| Package | 记录 FlutterOH package 适配仓库的当前维护状态。 |
| Source | 记录 Source 元数据、可安装 SDK 版本和 Manifest 路由。 |
| Manifest | 记录已发布、可被项目消费的 FlutterOH package 适配记录。 |

### Project

项目配置保持很小：

```yaml
schema: 1

sdk:
  version: 3.35.8-ohos-0.0.3

dependencyPolicy:
  pubspecSection: dependency_overrides
  versionChanges: compatible
```

规则：

- `schema` 必填，目前必须为 `1`。
- Project 不使用 `kind`；命令在项目上下文中解析这套 schema。
- `sdk.version` 是当前项目选择的完整 Flutter OHOS SDK 版本。
- `dependencyPolicy.pubspecSection` 是 `fluoh pub fix` 写入的 pubspec section；
  支持 `dependency_overrides` 和 `dependencies`，默认 `dependency_overrides`。
- `dependencyPolicy.versionChanges` 控制 upstream package 版本变化范围；
  `compatible` 只允许精确匹配和 pub 语义化版本兼容升级，`any` 也允许不兼容变化和降级。
- `fluoh_test/` 不拥有独立 `fluoh.yaml`。测试工作区运行时向上查找最近的
  `fluoh.yaml`，通常使用项目根目录或 Package 仓库根目录的 SDK 配置。

### Package

Package `fluoh.yaml` 记录 FlutterOH package 适配仓库的当前工作流状态。它不是历史索引，
只描述当前分支正在维护或准备发布的版本关系；历史发布记录由 release tag 固化，再由
`fluoh source sync` 汇总进 Source Manifest。

非 monorepo 示例：

```yaml
schema: 1
name: webview

sdk:
  version: 3.35.8-ohos-0.0.3

repository:
  git:
    url: https://github.com/FlutterOH/webview.git
    branch: ohos/3.35

upstream:
  git:
    url: https://github.com/example/webview.git
    branch: main

packages:
  webview:
    version: "0.2.0"
    upstreamVersion: "0.11.0"
```

monorepo 示例：

```yaml
schema: 1
name: flutter_packages

sdk:
  version: 3.35.8-ohos-0.0.3

repository:
  git:
    url: https://github.com/FlutterOH/packages.git
    branch: ohos/3.35

upstream:
  git:
    url: https://github.com/flutter/packages.git
    branch: main

packages:
  path_provider:
    repository:
      path: packages/path_provider/path_provider
    upstream:
      path: packages/path_provider/path_provider
    version: "0.2.0"
    upstreamVersion: "2.1.5"

  camera:
    repository:
      path: packages/camera/camera
    upstream:
      path: packages/camera/camera
    version: "0.1.0"
    upstreamVersion: "0.11.0"
    status: experimental
```

规则：

- `schema` 必填，目前必须为 `1`。
- Package 不使用 `kind`；命令在 `fluoh pub ...` 上下文中解析这套 schema。
- `name` 必填，表示适配仓库或工作区的逻辑名，不是 Dart package 名。单包仓库通常
  使用 package 名；monorepo 使用稳定的工作区别名，例如 `flutter_packages`。
- `sdk.version` 必填，是适配、测试和发布当前 package 使用的完整 Flutter OHOS SDK 版本。
- `repository.git.url` 必填，是 FlutterOH 适配仓库 URL 或本地路径。
- `repository.git.branch` 必填，是维护分支。适配分支按 Flutter OHOS 大版本线创建，
  格式为 `ohos/<sdkLine>`，例如完整 SDK `3.35.8-ohos-0.0.3` 对应
  `ohos/3.35`。
- `repository.git.path` 可选，作为所有 package 在适配仓库内的默认路径，默认 `.`。
- `upstream.git.url` 必填，是原始 upstream 仓库 URL 或本地路径。
- `upstream.git.branch` 可选，是 `fluoh pub sync` 拉取 upstream 变更时使用的分支，默认
  `main`。
- `upstream.git.path` 可选，作为所有 package 在 upstream 仓库内的默认路径，默认 `.`。
- `packages.<name>.repository.path` 可选，覆盖 `repository.git.path`。
- `packages.<name>.upstream.path` 可选，覆盖 `upstream.git.path`。
- `packages.<name>.version` 必填，是 FlutterOH 适配发布版本，使用数字点分格式，例如
  `1` 或 `0.1.0`，不带 `v` 前缀。
- `packages.<name>.upstreamVersion` 必填，是当前适配对应的 upstream package 版本。
- `packages.<name>.status` 可选；不写表示 `compatible`。只有适配中或已知不可用时才写
  `experimental` 或 `broken`。

### Source

Source 根 `fluoh.yaml` 描述 Source 自身、可用 SDK 来源，以及 Manifest 文件路由。它不记录
package 名称、package 路径、package 版本、upstream 版本、advisory 或 maintenance。

目录结构：

```text
fluoh.yaml
manifests/
  flutter_packages/fluoh.yaml
  webview/fluoh.yaml
```

根文件示例：

```yaml
schema: 1
kind: source
name: flutteroh
description: Flutter OHOS SDK and package adaptation source.

repository:
  git:
    url: https://github.com/FlutterOH/pub.git

environment:
  fluoh: ">=0.1.0"

sdk:
  git:
    url: https://gitcode.com/openharmony-tpc/flutter_flutter.git
  versions:
    - 3.35.8-ohos-0.0.3
    - 3.35.8-ohos-0.0.2

manifests:
  - name: flutter_packages
  - name: webview
```

规则：

- `schema` 必填，目前必须为 `1`。
- `kind` 必填，固定为 `source`。
- `name` 必填，是 Source 自描述名称，不要求等于本机 `config.json` 中的 Source alias。
- `description` 可选。
- `repository.git.url` 必填，可以是 HTTPS URL、SSH URL、`file:` URL 或本地路径。
- `environment.fluoh` 可选，表示最低 `fluoh` 版本要求。
- `sdk` 和 `manifests` 都是可选项。Source 可以是既没有 SDK version、也没有 Manifest
  route 的空脚手架；它是合法配置，但合并时不贡献数据。
- 提供 SDK 安装清单的 Source 必须写 `sdk.git.url`。维护者准备 Source 时，
  `sdk.versions` 可以暂时为空。
- `sdk.versions` 记录可安装的完整稳定 SDK 版本。
- `manifests` 可选；维护者准备 Source 时可以暂时为空列表。
- `manifests[].name` 必填且唯一，映射到 `manifests/<name>/fluoh.yaml`。
- Source 校验时从 Manifest 文件的 `packages` keys 派生 package 名。package 名不能跨多个
  Manifest 重复出现。

### Manifest

Manifest 记录已发布、可被项目消费的 FlutterOH package 适配记录。它可以由
`fluoh source sync` 从 Package release tags 汇总生成，也可以由维护者手动补充
`advisory` 和 `maintenance`。

非 monorepo 示例：

```yaml
schema: 1
kind: manifest
name: webview

repository:
  git:
    url: https://github.com/FlutterOH/webview.git

upstream:
  git:
    url: https://github.com/example/webview.git
    branch: main

packages:
  webview:
    sdks:
      "3.35":
        releases:
          - version: "0.2.0"
            upstreamVersion: "0.11.0"
```

monorepo 示例：

```yaml
schema: 1
kind: manifest
name: flutter_packages

repository:
  git:
    url: https://github.com/FlutterOH/packages.git

upstream:
  git:
    url: https://github.com/flutter/packages.git
    branch: main

packages:
  path_provider:
    repository:
      path: packages/path_provider/path_provider
    upstream:
      path: packages/path_provider/path_provider

    maintenance:
      status: frozen
      reason: Upstream now supports OHOS natively.

    advisory:
      message: Prefer upstream path_provider for new projects.
      alternatives:
        - name: path_provider_ohos
          reason: Provides native OHOS support.
          url: https://pub.dev/packages/path_provider_ohos

    sdks:
      "3.35":
        releases:
          - version: "0.1.0"
            upstreamVersion: "2.1.5"
          - version: "0.2.0"
            upstreamVersion: "2.1.5"
            status: experimental

  camera:
    repository:
      path: packages/camera/camera
    upstream:
      path: packages/camera/camera
    sdks:
      "3.35":
        releases:
          - version: "0.2.0"
            upstreamVersion: "0.11.0"
```

规则：

- `schema` 必填，目前必须为 `1`。
- `kind` 必填，固定为 `manifest`。
- `name` 必填，必须和 Source 根配置的 `manifests[].name` 一致。
- `repository.git.url` 必填，是 FlutterOH 适配仓库 URL 或本地路径。
- `repository.git.path` 可选，作为所有 package 在适配仓库内的默认路径，默认 `.`。
- `upstream.git.url` 必填，是原始 upstream 仓库 URL 或本地路径。
- `upstream.git.branch` 可选，默认 `main`；`fluoh source sync` 会从 Package 的
  `upstream.git.branch` 复制该值。
- `upstream.git.path` 可选，作为所有 package 在 upstream 仓库内的默认路径，默认 `.`。
- `packages.<name>.repository.path` 可选，覆盖 `repository.git.path`。
- `packages.<name>.upstream.path` 可选，覆盖 `upstream.git.path`。
- `maintenance.status` 可选，默认 `active`；支持 `active` 和 `frozen`。
  `frozen` 只影响 Source 维护命令，消费侧仍可使用已有发布记录。
- `advisory` 可选，是 package 级用户提示，会用于 `fluoh pub check`，但不改变机器
  判定状态。
- `sdks.<sdkLine>` 使用派生的 Flutter OHOS 大版本线，例如 `3.35`。项目选择完整 SDK
  版本后，消费侧从中推导 SDK line，再查 Manifest。
- `releases` 是当前 SDK line 下的历史发布记录列表。
- `releases[].version` 必填，是 FlutterOH 适配发布版本，使用数字点分格式，例如
  `1` 或 `0.1.0`，不带 `v` 前缀。
- `releases[].upstreamVersion` 必填，是对应的 upstream package 版本。
- `releases[].status` 可选；不写表示 `compatible`。只有适配中或已知不可用时才写
  `experimental` 或 `broken`。
- `fluoh pub check/fix/upgrade` 默认只推荐 `compatible` 发布记录。
- Manifest 不记录 `native`、`blocked` 或 `support` 机器状态。上游已原生支持时用
  `advisory` 提示；不支持或不再适配时，没有可推荐发布记录即自然不可用。

SDK line 推导规则在 Package 分支、Manifest key 和 release tag 中保持一致：取 `-ohos`
前语义化版本的前两个数字段。

```text
3.35.8-ohos-0.0.3 -> 3.35
3.35.0-ohos-0.0.1 -> 3.35
```

不符合该格式的完整 SDK 版本校验失败。

release tag 字符串不在 Manifest 中重复保存，而是按约定派生：

```text
<package>-<upstreamVersion>-ohos-<sdkLine>-<version>
```

例如 package `path_provider`、upstream 版本 `2.1.5`、SDK line `3.35`、version
`0.2.0` 会派生：

```text
path_provider-2.1.5-ohos-3.35-0.2.0
```

同一个 package、upstream 版本和 SDK line 下，只要适配内容发生变化，就必须递增
`version`。

## 适配规则和流程

1. 选择完整 Flutter OHOS SDK 版本，例如 `3.35.8-ohos-0.0.3`。
2. 从完整 SDK 版本推导 SDK line：取 `-ohos` 前语义化版本的前两个数字段，例如
   `3.35.8-ohos-0.0.3 -> 3.35`。
3. 为适配库创建或切换分支 `ohos/<sdkLine>`，例如 `ohos/3.35`。分支按大版本线维护，
   不按 SDK patch 版本维护。
4. Package `fluoh.yaml` 只记录当前分支正在维护或准备发布的 upstream package 版本
   和 FlutterOH 适配 package 版本。
5. 适配中可以把 `packages.<name>.status` 或 `releases[].status` 写成 `experimental`；
   完成并可推荐给项目使用时省略 `status`，默认就是 `compatible`。
6. `fluoh pub release` 使用 Package `fluoh.yaml` 派生 release tag。tag 固化当时的代码、
   测试和配置快照。
7. `fluoh source sync` 扫描已发布 release tags，读取每个 tag 下的 Package
   `fluoh.yaml`，把历史发布记录汇总进 Manifest。
8. 项目消费时先读取 Project `sdk.version`，推导 SDK line，再在 Manifest 的
   `sdks.<sdkLine>.releases` 下寻找匹配的 `compatible` 发布记录。

## Dependency Report 和 Plan

`fluoh pub check` 读取本机已解析的 Source lock。source 输入变化或 lock 缺失时，lock
会从 Source root 和 Manifest YAML 重新生成。不需要提交生成的 matrix 文件。

消费侧状态只由发布记录决定：

- 精确匹配当前 lockfile 中 package 版本和 SDK line 的 `compatible` 发布记录 -> `ready`。
- 同一 SDK line 下存在 pub 语义化版本兼容的更新 upstream 版本 -> `version upgrade`。
- 某个 package 有其它 SDK line 的发布记录，但没有当前 SDK line -> `SDK mismatch`。
- 版本变化策略不允许当前候选 -> `needs decision`。
- 没有可推荐发布记录 -> `unavailable`。

`advisory` 只作为提示输出，不改变依赖状态。

## `config.json`

工具配置使用 JSON，因为它是机器生成的运行时状态：

```json
{
  "sources": {
    "flutteroh": {
      "url": "https://github.com/FlutterOH/pub.git",
      "path": "/home/user/.fluoh/sources/flutteroh",
      "priority": 0
    },
    "local": {
      "url": "/Users/user/source/pub",
      "path": "/home/user/.fluoh/sources/local",
      "priority": 10
    }
  }
}
```

规则：

- 官方 Source alias 固定为 `flutteroh`，默认 priority 为 `0`，不允许删除。
- 用户新增 Source 默认 priority 为 `10`。数值越大优先级越高。
- `url` 支持 HTTPS URL、SSH URL、`file:` URL 和本地路径。
- HTTPS/SSH URL 走 Git clone/update；本地路径和 `file:` URL 复制校验后的 Source
  快照。
- `path` 是本机缓存路径。
- Source 缓存只保留最新校验通过的快照，不保留 Git 历史和无关仓库文件。

## `sources.lock.json`

`$FLUOH_HOME/sources.lock.json` 是机器生成、仅存在于本机的已解析 Source 索引。它由
`config.json` 和每个已校验 Source 快照派生，再按 priority 合并，让消费 source 的命令
读取一个稳定 JSON 文件，而不是每次重新解析所有 Source YAML。

结构示例：

```json
{
  "generatedBy": "fluoh 0.1.0",
  "generatedAt": "2026-05-13T12:00:00Z",
  "inputs": {
    "toolVersion": "0.1.0",
    "configHash": "hash64:...",
    "sources": [
      {
        "name": "flutteroh",
        "path": "/home/user/.fluoh/sources/flutteroh",
        "url": "https://github.com/FlutterOH/pub.git",
        "priority": 0,
        "snapshotHash": "hash64:..."
      },
      {
        "name": "local",
        "path": "/home/user/.fluoh/sources/local",
        "url": "/Users/user/source/pub",
        "priority": 10,
        "snapshotHash": "hash64:..."
      }
    ]
  },
  "sdk": {
    "versions": {
      "3.35.8-ohos-0.0.3": {
        "source": "flutteroh",
        "priority": 0,
        "versionSeries": "3.35",
        "flutterVersion": "3.35.8",
        "channel": "stable",
        "tag": "3.35.8-ohos-0.0.3",
        "git": {
          "url": "https://gitcode.com/openharmony-tpc/flutter_flutter.git"
        }
      }
    }
  },
  "packages": {
    "path_provider": {
      "source": "flutteroh",
      "priority": 0,
      "repository": {
        "git": {
          "url": "https://github.com/FlutterOH/packages.git"
        },
        "path": "packages/path_provider/path_provider"
      },
      "upstream": {
        "git": {
          "url": "https://github.com/flutter/packages.git",
          "branch": "main"
        },
        "path": "packages/path_provider/path_provider"
      },
      "advisory": {
        "message": "Prefer upstream path_provider for new projects."
      },
      "sdks": {
        "3.35": {
          "releases": [
            {
              "version": "0.2.0",
              "upstreamVersion": "2.1.5",
              "status": "compatible",
              "tag": "path_provider-2.1.5-ohos-3.35-0.2.0",
              "repository": {
                "git": {
                  "url": "https://github.com/FlutterOH/packages.git"
                },
                "path": "packages/path_provider/path_provider"
              },
              "upstream": {
                "git": {
                  "url": "https://github.com/flutter/packages.git",
                  "branch": "main"
                },
                "path": "packages/path_provider/path_provider"
              },
              "source": "flutteroh",
              "priority": 0
            }
          ]
        }
      }
    }
  }
}
```

规则：

- lock 不包含 `schema` 字段。它是可丢弃的生成状态，不兼容或过期时直接重建，不做迁移。
- Source root 和 Manifest YAML 仍然是唯一需要人工编辑的 Source 数据。
- Source lock 维护由 `lib/src/source/` 中的 Source runtime 统一负责。命令不应该自己组装
  或局部更新 lock。
- `config.json`、任一已配置 Source 快照、Source 合并规则或 `fluoh` 工具版本变化时，
  Source runtime 都会整体重新生成 lock。
- Source 状态变更入口，包括 `fluoh source add`、`fluoh source remove`、
  `fluoh source update`、已配置快照 repair、目标是已配置快照的 `fluoh source sync`、
  以及首次默认 Source bootstrap，都会请求 Source runtime 重建 lock。消费 source 的流程使用
  同一个 load-index API；发现 lock 缺失或过期时，或者已选择 SDK 缺失且需要 SDK 元数据来安装
  selected SDK 时，会按需重新生成。
- lock 保存规范化默认值和派生字段，例如 `status: compatible`、
  `upstream.git.branch: main`、SDK line、release tag、胜出的 Source alias、
  priority，以及最终 repository path。
- release 记录也保存自己的 repository URL/path。这样多个 Source 为同一个 package
  贡献不同 release 时，lock 读回后不会丢失该 release 原本来自哪个实现仓库。
- lock 生成使用 Source 命令文档中的 priority 和冲突规则。发生冲突时生成失败，消费命令
  不读取半解析状态。
- 写入使用临时文件加原子替换。生成失败时，除非旧文件记录的输入仍然匹配，否则旧文件不会被
  当成新状态使用。
