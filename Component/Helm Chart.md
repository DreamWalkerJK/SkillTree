# Helm Chart

> 本文面向需要开发、评审、发布和运维 Helm Chart 的 Kubernetes 使用者。示例以 Chart API 的 apiVersion: v2 为基线，适用于 Helm 3 及 Helm 4；实际命令和可用 API 以本地 helm version 以及目标集群版本为准。

## 1. Helm Chart 的定位

Helm 是 Kubernetes 生态中的包管理与发布工具。Chart 是 Helm 使用的可分发软件包，描述一组相互关联的 Kubernetes 资源模板、默认配置、依赖和元数据。Chart 可以打包为版本化的 .tgz 文件，也可以作为 OCI Artifact 存储在容器镜像仓库中。

一个 Chart 的典型处理链路如下：

~~~text
Chart 源码 + values
        │
        ├─ values 合并、Schema 校验
        │
        ├─ Go Template / Sprig 渲染
        │
        ▼
Kubernetes manifest
        │
        ├─ helm install / upgrade 调用 Kubernetes API
        ├─ Kubernetes 创建或更新资源
        └─ Helm 在命名空间内保存 Release 修订记录
~~~

### 1.1 核心对象

| 对象 | 技术含义 | 生命周期 |
| --- | --- | --- |
| Chart | 可复用、可版本化的 Kubernetes 资源包 | 源码开发、打包、发布 |
| Release | 某个 Chart 在某个集群、命名空间和 Release 名称下的一次部署实例 | install、upgrade、rollback、uninstall |
| Revision | Release 的修订号；每次升级和回滚都会产生新的修订记录 | 由 Helm 维护 |
| Repository | 通过 index.yaml 分发 Chart 包的经典仓库 | helm repo add/update/search |
| OCI Registry | 通过 OCI Distribution API 存储 Chart Artifact 的仓库 | helm registry login/push/pull |
| Values | 传入模板的配置数据 | 默认值、环境文件、命令行覆盖 |
| Manifest | Helm 渲染后提交给 Kubernetes 的 YAML 资源清单 | install/upgrade 时生成 |

在 Helm 3 及后续版本中，Helm 客户端直接调用 Kubernetes API，不再依赖 Helm 2 的 Tiller 服务。Release 元数据默认存储在目标命名空间的 Secret 中；因此，执行 Helm 操作的身份必须同时具备 Kubernetes API 权限和读取相关 Release 元数据的权限。

### 1.2 Chart 版本与应用版本

- Chart.yaml 中的 version 是 Chart 本身的版本，决定包名，例如 myapp-1.4.0.tgz。它应遵循 Semantic Versioning 2.0.0。
- appVersion 是 Chart 默认部署的应用版本，仅用于描述和展示，不参与 Helm 的依赖解析或升级判断。建议始终用字符串写法，例如 appVersion: "2.8.1"。
- 应用镜像、配置或模板行为发生兼容性变化时，应按变更类型递增 Chart 的 MAJOR、MINOR 或 PATCH 版本。
- Chart 版本和应用版本可以不同：一次 Chart 修复可能只递增 Chart PATCH；应用升级通常至少需要同步更新 appVersion。

## 2. Chart 目录结构

### 2.1 推荐结构

~~~text
mychart/
├── Chart.yaml                  # 必需：Chart 元数据
├── Chart.lock                  # 可选：依赖解析结果与摘要
├── values.yaml                 # 默认配置值
├── values.schema.json           # 可选：values 的 JSON Schema
├── .helmignore                 # 可选：打包时排除文件
├── README.md                   # 使用、配置和兼容性说明
├── LICENSE                     # 许可证
├── charts/                     # 已下载或打包的依赖 Chart
├── crds/                       # 非模板化的 CustomResourceDefinition
└── templates/
    ├── _helpers.tpl             # 命名、标签等可复用模板
    ├── deployment.yaml
    ├── service.yaml
    ├── ingress.yaml
    ├── serviceaccount.yaml
    ├── configmap.yaml
    ├── secret.yaml
    ├── NOTES.txt                # 安装后显示的提示信息
    └── tests/
        └── test-connection.yaml # 带 test Hook 的验证 Job
~~~

Helm 保留 charts/、crds/ 和 templates/ 目录的特殊语义。模板目录中以下划线开头的文件（例如 _helpers.tpl）只用于定义辅助模板，不会被当作独立的 Kubernetes manifest 输出。其他未被 Helm 保留的文件会原样进入 Chart 包，除非被 .helmignore 排除。

### 2.2 关键文件职责

| 文件 | 是否必需 | 说明 |
| --- | --- | --- |
| Chart.yaml | 是 | Chart 名称、版本、类型、兼容性、依赖等元数据 |
| values.yaml | 否但强烈建议 | 默认配置；模板通过 .Values 访问 |
| values.schema.json | 否 | 对用户输入的值做类型、必填项、枚举和范围校验 |
| templates/ | 否 | 渲染为 Kubernetes manifest 的 Go 模板 |
| charts/ | 否 | 依赖 Chart 的归档包或本地 Chart |
| crds/ | 否 | 安装 CRD 声明；文件不参与模板渲染 |
| templates/NOTES.txt | 否 | install、upgrade 或 status 后输出的简短使用提示 |
| Chart.lock | 否 | 依赖版本解析结果；用于可重复构建 |
| .helmignore | 否 | 排除测试数据、构建产物、私密文件等 |
| README.md | 否但建议 | 面向 Chart 使用者的安装前提、配置和升级说明 |

README.md 应至少说明 Kubernetes 和 Helm 版本要求、依赖、默认资源、重要 Values、持久化和备份策略、网络入口、升级/回滚注意事项以及卸载行为。不要把密码、Token、私钥或生产环境 values 文件放入 Chart 包。

## 3. Chart.yaml 元数据

### 3.1 常用字段

| 字段 | 必需 | 说明 |
| --- | --- | --- |
| apiVersion | 是 | Chart API 版本；Helm 3/4 Chart 通常使用 v2 |
| name | 是 | Chart 名称，只能使用适合包名和 DNS 的字符 |
| version | 是 | Chart 的 SemVer 版本 |
| kubeVersion | 否 | 支持的 Kubernetes SemVer 范围 |
| description | 否 | 一句话说明 |
| type | 否 | application（默认）或 library |
| keywords | 否 | 搜索和分类关键字 |
| home | 否 | 项目主页 |
| sources | 否 | 源码仓库或相关项目地址 |
| dependencies | 否 | 子 Chart 依赖及其版本约束 |
| maintainers | 否 | 维护者姓名、邮箱和主页 |
| icon | 否 | Chart 图标地址 |
| appVersion | 否 | 应用版本，仅供展示；建议加引号 |
| deprecated | 否 | 是否废弃该 Chart |
| annotations | 否 | 自定义元数据；不要向 Chart.yaml 添加未定义的顶级字段 |

### 3.2 示例

~~~yaml
apiVersion: v2
name: myapp
description: A production-ready web application chart
type: application
version: 1.4.0
appVersion: "2.8.1"
kubeVersion: ">=1.27.0-0 <1.33.0-0"

keywords:
  - web
  - api

home: https://example.com/myapp
sources:
  - https://git.example.com/platform/myapp

maintainers:
  - name: Platform Team
    email: platform@example.com

dependencies:
  - name: postgresql
    version: "~15.5.0"
    repository: "oci://registry.example.com/third-party"
    condition: postgresql.enabled
    tags:
      - database

annotations:
  artifacthub.io/containsSecurityUpdates: "false"
~~~

kubeVersion 是 SemVer 约束，不是 Kubernetes API 版本列表。例如 >=1.27.0-0 <1.33.0-0 表示允许 1.27 至 1.32 的版本。不要把 appVersion 当成依赖约束，也不要用未加引号的 1.0，因为 YAML 解析器可能把它当作浮点数。

### 3.3 Chart 类型

- application 是默认类型，包含可以独立安装的 Kubernetes 资源。
- library 用于提供命名模板、标签、校验函数等公共能力，本身不可独立安装，通常不会直接生成资源。
- 应用 Chart 可以通过设置 type: library 转换为库 Chart；转换后，资源对象不会作为最终 manifest 输出。

## 4. Values 设计与覆盖规则

### 4.1 Values 的来源和优先级

Helm 按以下顺序合并值，后者优先级高于前者：

1. Chart 内置的 values.yaml；
2. 父 Chart 为子 Chart 提供的值；
3. 一个或多个 -f/--values 文件（多个文件从左到右合并，右侧覆盖左侧）；
4. --set、--set-string、--set-file 或 --set-json 参数。

例如：

~~~bash
helm upgrade --install myapp ./mychart \
  --namespace app-prod \
  --create-namespace \
  -f values.yaml \
  -f values-prod.yaml \
  --set image.tag=2.8.1 \
  --set-string service.annotations."example\.com/tier"=public
~~~

Map 通常按键递归合并；列表通常按整体替换处理。需要删除默认 Map 键时可以显式设置为 null，例如 --set livenessProbe.httpGet=null。--set-string 用于强制保留字符串类型，--set-file 读取文件内容，避免把多行证书或配置直接写入命令行。

升级时需要明确选择旧值策略：

- 默认情况下，helm upgrade 使用 Chart 的默认值与本次指定的覆盖值重新计算；
- --reuse-values 复用上一次 Release 的计算值，再叠加本次覆盖值；
- --reset-values 丢弃旧 Release 值，回到 Chart 默认值后再应用本次覆盖值。

生产流水线应显式提供版本化 values 文件，避免依赖本地 Shell 状态或隐式的旧值。

### 4.2 Values 设计原则

推荐让配置语义清晰、可验证、易于从 --set 覆盖：

~~~yaml
replicaCount: 2

image:
  repository: registry.example.com/myapp
  tag: "2.8.1"
  digest: ""
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 8080

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi

podAnnotations: {}
podLabels: {}

serviceAccount:
  create: true
  name: ""

ingress:
  enabled: false
  className: nginx
  hosts:
    - host: myapp.example.com
      paths:
        - path: /
          pathType: Prefix
~~~

建议：

- 字符串显式加引号；端口、副本数等 Kubernetes 数字字段保持数字类型；环境变量值即使是数字也应作为字符串。
- 对可以独立覆盖的配置使用浅层 Map；避免无必要的深层嵌套和难以维护的列表下标。
- 每一个公开值都在 values.yaml 中写注释，注释以参数名开头，例如 # replicaCount is the number of ...。
- 不要把环境、租户、区域等高维组合编码成大量互相覆盖的开关；优先使用结构化 Map 和明确的默认行为。
- 对镜像建议同时支持 tag 和 digest，生产环境优先使用不可变 digest。
- 不要在模板中为用户重新解释空字符串、false 和 null；用 Schema 明确契约。

### 4.3 values.schema.json 校验

Schema 使用 JSON Schema 描述 values 的类型、必填字段、枚举和范围。Helm 在 install、upgrade、lint 和 template 等流程中可以据此拒绝非法输入。

~~~json
{
  "$schema": "http://json-schema.org/schema#",
  "type": "object",
  "required": ["image", "service"],
  "properties": {
    "replicaCount": {
      "type": "integer",
      "minimum": 1,
      "maximum": 50
    },
    "image": {
      "type": "object",
      "required": ["repository", "tag"],
      "properties": {
        "repository": { "type": "string", "minLength": 1 },
        "tag": { "type": "string", "minLength": 1 },
        "digest": { "type": "string" }
      },
      "additionalProperties": false
    },
    "service": {
      "type": "object",
      "required": ["port"],
      "properties": {
        "type": {
          "type": "string",
          "enum": ["ClusterIP", "NodePort", "LoadBalancer"]
        },
        "port": { "type": "integer", "minimum": 1, "maximum": 65535 }
      },
      "additionalProperties": false
    }
  }
}
~~~

Schema 只能约束值的结构和类型，不能替代 Kubernetes API 校验、准入策略或运行时健康检查。需要兼容多个 Chart 版本时，应同步维护 Schema、README 和升级说明。

## 5. 模板引擎与模板编写

### 5.1 模板语法和内置对象

Helm 使用 Go text/template，并提供 Sprig 函数（出于安全原因不包含 env 和 expandenv）。模板动作使用双大括号包裹：

| 对象 | 作用 |
| --- | --- |
| .Values | 合并后的配置值 |
| .Release.Name | Release 名称 |
| .Release.Namespace | Release 所在命名空间 |
| .Release.IsInstall / .Release.IsUpgrade | 当前操作类型 |
| .Release.Service | 通常为 Helm |
| .Chart.Name / .Chart.Version / .Chart.AppVersion | Chart 元数据 |
| .Capabilities.KubeVersion | 目标集群 Kubernetes 版本 |
| .Capabilities.APIVersions.Has | 判断 API 或资源版本是否可用 |
| .Template.Name / .Template.BasePath | 当前模板信息 |
| .Files | 读取 Chart 内非模板文件 |

常用函数包括 include、required、default、coalesce、quote、toYaml、fromYaml、toJson、nindent、semverCompare、sha256sum、lookup 和 tpl。

### 5.2 作用域、管道和空白

with 和 range 会改变当前点号的作用域；$ 保存根作用域。跨作用域访问 Release 或 Values 时使用 $.Release.Name、$.Values.global。

~~~yaml
metadata:
  name: {{ include "myapp.fullname" . }}
  labels:
    {{- include "myapp.labels" . | nindent 4 }}
spec:
  template:
    metadata:
      labels:
        {{- include "myapp.selectorLabels" . | nindent 8 }}
    spec:
      containers:
        {{- range .Values.extraContainers }}
        - name: {{ .name | quote }}
          image: {{ .image | quote }}
        {{- end }}
~~~

模板输出最终必须是合法 YAML：

- 模板文件使用两个空格缩进，不使用 Tab；
- 多行 Map 使用 toYaml 与 nindent，不要手工拼接缩进；
- 字符串用 quote，资源数量和端口等数字不要无条件加引号；
- 使用左/右空白裁剪符控制边界空白，但要用 helm template 检查是否误删换行；
- 每个资源单独放在一个模板文件中，文件名使用短横线命名并体现资源类型；
- 模板内部注释使用 Go 模板注释；需要让用户在 --debug 输出中看到的说明才使用 YAML # 注释。

lookup 会向 Kubernetes API 查询现有对象，不能仅依赖离线 helm template 验证。使用 helm install/upgrade --dry-run=server 验证此类模板时，需要集群访问权限；不要让渲染结果依赖不可控的集群状态，除非已经定义好无对象时的行为。

### 5.3 命名与辅助模板

定义模板是全局可见的，父 Chart 和子 Chart 之间可能发生名称冲突，必须使用 Chart 名称命名空间化：

~~~gotemplate
{{/*
myapp.name returns the short application name.
*/}}
{{- define "myapp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
myapp.fullname returns a DNS-compatible resource name.
*/}}
{{- define "myapp.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "myapp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "myapp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "myapp.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | quote }}
{{ include "myapp.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}

{{- define "myapp.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "myapp.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
default
{{- end -}}
{{- end }}
~~~

include 返回字符串，可以继续进入管道，因此通常优于不能方便进入管道的 template 指令：

~~~yaml
labels:
  {{- include "myapp.labels" . | nindent 2 }}
~~~

required 用于尽早失败并给出明确错误：

~~~gotemplate
image: {{ required "image.repository must be set" .Values.image.repository | quote }}
~~~

tpl 会把 Values 中的字符串再次当作模板执行，适合受控的外部配置模板，但会扩大用户输入的执行能力。仅对可信来源启用 tpl，不要把任意用户输入直接传给 tpl。

### 5.4 资源模板示例

以下片段假设 Chart 同时包含 templates/configmap.yaml；如果没有该文件，应删除 checksum/config 这一行。

~~~yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "myapp.fullname" . }}
  labels:
    {{- include "myapp.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "myapp.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "myapp.selectorLabels" . | nindent 8 }}
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
    spec:
      serviceAccountName: {{ include "myapp.serviceAccountName" . }}
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: {{ .Values.service.port }}
              protocol: TCP
          readinessProbe:
            httpGet:
              path: /readyz
              port: http
          livenessProbe:
            httpGet:
              path: /healthz
              port: http
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
~~~

如果使用 digest，应把镜像拼接为 repository@digest，并避免同时生成容易造成歧义的 tag。Deployment 的 spec.selector 在创建后不可变，必须只包含稳定标签；版本、环境和其他可变标签放到 Pod template 或 metadata labels 中。

## 6. 依赖 Chart、子 Chart 与库 Chart

### 6.1 声明和构建依赖

依赖写在父 Chart 的 Chart.yaml 中：

~~~yaml
dependencies:
  - name: redis
    version: "~19.6.0"
    repository: "https://charts.example.com"
    condition: redis.enabled
    tags:
      - cache

  - name: common-library
    version: "1.x.x"
    repository: "oci://registry.example.com/helm"
    alias: primary-common
~~~

重要字段：

- name、version 和 repository 标识依赖及其来源；
- condition 指向父 Chart Values 中的布尔路径，适合开关可选依赖；
- tags 允许多个依赖共享一个功能开关；tags 必须位于父 Values 顶层；
- alias 允许同一个 Chart 以多个名称实例化；
- import-values 可把子 Chart 导出的部分值映射到父 Chart；
- OCI 依赖的 repository 写仓库路径，不包含依赖 Chart 名称，例如 oci://registry.example.com/helm。

常用命令：

~~~bash
helm dependency list ./mychart
helm dependency update ./mychart   # 解析版本并下载，更新 Chart.lock
helm dependency build ./mychart    # 按 Chart.lock 重建 charts/，适合 CI
~~~

update 会重新解析满足约束的最新版本；build 优先使用现有 Chart.lock。生产构建应提交 Chart.lock，将依赖解析结果固定到可审计的版本和摘要。依赖仓库优先使用 HTTPS；对于高风险供应链，进一步固定到可信 OCI Registry 的 digest 并在流水线中校验来源。

### 6.2 子 Chart 的 Values 边界

父 Chart 可以通过名称向子 Chart 传值：

~~~yaml
redis:
  enabled: true
  architecture: standalone

global:
  imageRegistry: registry.example.com
~~~

子 Chart 不能直接读取父 Chart 的任意私有 Values；它只能读取自己的配置和约定的 .Values.global。需要共享配置时，优先定义清晰的 global 契约，避免通过深层覆盖依赖内部实现。

### 6.3 Library Chart

库 Chart 用于集中实现：

- 标准命名和标签；
- Pod 安全上下文、探针、资源配置片段；
- 组织级注解和监控配置；
- 通用校验、渲染和合并函数。

库 Chart 不应偷偷创建命名空间级资源或依赖运行时状态。定义模板时使用命名空间化名称，并在父 Chart 中通过 include 显式调用。

## 7. CRD 的安装和生命周期

把 CustomResourceDefinition 文件放入 Chart 的 crds/ 目录：

~~~text
mychart/
└── crds/
    └── widgets.example.com.yaml
~~~

Helm 会在普通模板前安装 crds/ 中的声明；这些文件不经过模板渲染，因此不能使用 .Values。可用 --skip-crds 跳过安装。

必须注意：

- Helm 不负责通过 Chart 自动升级或删除 CRD；CRD 删除可能导致所有自定义资源和数据丢失；
- --dry-run 无法真实注册 CRD，因此不能完全验证“安装 CRD 后再创建自定义资源”的流程；
- 对需要独立权限、升级窗口和备份策略的 CRD，推荐拆分为“CRD 管理 Chart”和“自定义资源 Chart”；
- 升级 CRD 前应先阅读对应 Operator/控制器的兼容性说明，执行数据备份并验证旧版本资源；
- 模板中使用 CRD 对象前，应在文档中声明安装顺序和所需集群权限。

Helm 3 已移除 crd-install Hook，不能用旧版 Hook 方式替代 crds/ 目录。

## 8. Hook 与测试

### 8.1 Hook 生命周期

Hook 是带特殊注解的模板资源，用于在 Release 生命周期的特定阶段执行：

| 注解值 | 执行时机 |
| --- | --- |
| pre-install | 模板渲染后、普通资源创建前 |
| post-install | 普通资源创建后 |
| pre-upgrade | 模板渲染后、资源更新前 |
| post-upgrade | 资源更新后 |
| pre-rollback | 回滚资源前 |
| post-rollback | 回滚资源后 |
| pre-delete | 删除 Release 资源前 |
| post-delete | 删除 Release 资源后 |
| test | 执行 helm test 时 |

示例：

~~~yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "myapp.fullname" . }}-migration
  annotations:
    "helm.sh/hook": pre-upgrade,pre-install
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migration
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          command: ["/app/bin/migrate"]
~~~

Hook 执行顺序由 weight（从小到大）、资源类型和名称共同决定；weight 必须作为字符串写在注解中。hook-delete-policy 常用值为 before-hook-creation、hook-succeeded 和 hook-failed。

Hook 资源在完成后不会自动作为普通 Release 资源管理。若没有删除策略，Job 或 Pod 可能残留；若使用 helm.sh/resource-policy: keep，资源会成为孤儿对象，后续 Helm 不再管理它。Hook 必须幂等、可重试、带超时和清理策略，避免把不可逆的数据迁移放在无法回滚的 Hook 中。

### 8.2 Chart Test

测试资源通常放在 templates/tests/，使用 helm.sh/hook: test：

~~~yaml
apiVersion: v1
kind: Pod
metadata:
  name: {{ include "myapp.fullname" . }}-test-connection
  annotations:
    "helm.sh/hook": test
spec:
  restartPolicy: Never
  containers:
    - name: curl
      image: curlimages/curl:8.10.1
      command:
        - curl
        - --fail
        - --silent
        - http://{{ include "myapp.fullname" . }}:{{ .Values.service.port }}/healthz
~~~

执行：

~~~bash
helm test myapp --logs
~~~

测试至少应覆盖 Service 可达性、健康端点和关键依赖。测试镜像、网络策略和 RBAC 也属于 Chart 的运行前提，应在 README 中说明。
## 9. 常用命令与交付流程

### 9.1 创建、检查和渲染

~~~bash
helm create mychart
helm show chart ./mychart
helm show values ./mychart
helm lint ./mychart --strict
helm dependency build ./mychart
helm template myrelease ./mychart \
  --namespace app-prod \
  -f values-prod.yaml \
  --debug
helm template myrelease ./mychart \
  --kube-version 1.32.0 \
  --api-versions apps/v1 \
  --api-versions networking.k8s.io/v1
~~~

helm template 只在本地渲染，不会创建集群资源。应把渲染结果提交给 YAML 解析器、Kubernetes Schema 校验器和策略检查器做额外验证。必要时使用 --include-crds 把 CRD 一并输出。

### 9.2 安装和升级

~~~bash
helm install myapp ./mychart \
  --namespace app-prod \
  --create-namespace \
  -f values-prod.yaml \
  --wait \
  --timeout 10m

helm upgrade --install myapp ./mychart \
  --namespace app-prod \
  --create-namespace \
  -f values-prod.yaml \
  --atomic \
  --wait \
  --timeout 10m
~~~

常用参数：

- --namespace 明确 Release 所在命名空间；
- --create-namespace 在命名空间不存在时创建；
- --version 安装仓库或 OCI 中的指定 Chart 版本；
- --wait 等待工作负载和 Service 等资源达到就绪状态；
- --wait-for-jobs 同时等待相关 Job 完成；
- --timeout 限制 Kubernetes 操作和 Hook 等待时间；
- --atomic 失败时自动回滚；它隐含等待行为，但仍应显式配置超时；
- --dry-run=client 不访问集群，适合离线检查；
- --dry-run=server 访问 API Server，适合验证 lookup、准入和集群能力，但不会持久化资源；
- --debug 会输出计算值和 manifest，禁止在可能包含密钥的环境中公开日志。

### 9.3 查看、回滚和卸载

~~~bash
helm status myapp -n app-prod
helm history myapp -n app-prod
helm get values myapp -n app-prod --all
helm get manifest myapp -n app-prod
helm get all myapp -n app-prod

helm rollback myapp 3 -n app-prod --wait --timeout 10m

helm uninstall myapp -n app-prod
# 需要保留历史时：
helm uninstall myapp -n app-prod --keep-history
~~~

回滚的是整个 Release 修订，而不是仅回滚某一个 Deployment。数据库 Schema、外部 DNS、云资源和不可逆 Job 不会因为 Helm 回滚自动恢复，必须在应用层设计兼容和补偿流程。

### 9.4 打包和仓库操作

~~~bash
helm package ./mychart --destination dist
helm pull oci://registry.example.com/helm/myapp --version 1.4.0
helm repo add internal https://charts.example.com
helm repo update
helm search repo internal/myapp --versions
helm pull internal/myapp --version 1.4.0
~~~

helm lint 只检查 Chart 的静态问题；它不能证明 Kubernetes 资源在当前集群中一定能够创建。helm template 也不能替代集群准入、Admission Policy、运行时探针和端到端测试。

## 10. Chart 分发、OCI 和完整性校验

### 10.1 经典 Chart Repository

经典仓库以 index.yaml 索引一个或多个 Chart.tgz，常见流程是：

~~~bash
helm package ./mychart --destination dist
helm repo index dist --url https://charts.example.com
helm repo add internal https://charts.example.com
helm repo update
helm search repo internal
~~~

发布系统必须保证包文件、index.yaml 和版本元数据原子更新，并避免复用同名同版本包。Chart 版本一旦发布，最好视为不可变制品。

### 10.2 OCI Registry

Helm 推荐使用支持 OCI 的容器 Registry 分发 Chart：

~~~bash
helm registry login registry.example.com -u "$REGISTRY_USER"
helm package ./mychart --destination dist
helm push dist/myapp-1.4.0.tgz oci://registry.example.com/helm
helm pull oci://registry.example.com/helm/myapp --version 1.4.0
helm install myapp \
  oci://registry.example.com/helm/myapp \
  --version 1.4.0 \
  -n app-prod
~~~

推送时 OCI 地址必须带 oci://，但不写 Chart basename 和 tag；Helm 从包内 name 和 version 推导它们。拉取、安装和升级时需要写完整的 Chart 名称。对不可变发布，使用 digest 而不是可变 tag：

~~~bash
helm install myapp \
  oci://registry.example.com/helm/myapp@sha256:52ccaee6d4dd272e54bfccda77738b42e1edf0e4a20c27e23f0b6c15d01aef79 \
  -n app-prod
~~~

OCI Registry 还可以承载依赖、Provenance 和其他 OCI Artifact。访问 Registry 时应校验 TLS、仓库权限、镜像/Chart 保留策略和审计日志。

### 10.3 Provenance、签名和供应链

经典 Chart 可以用 GPG 生成 Provenance 文件：

~~~bash
helm package ./mychart \
  --sign \
  --key "Release Signing Key" \
  --keyring path/to/secring.gpg

helm verify myapp-1.4.0.tgz
helm install --generate-name --verify myapp-1.4.0.tgz
~~~

Provenance 文件通常为 myapp-1.4.0.tgz.prov，应与 Chart 包一起发布。签名只能证明制品来源和完整性，不能证明模板没有高风险权限或运行时逻辑；仍需审查模板、依赖、镜像和 RBAC。

OCI 场景可以采用 Sigstore 及其 Helm 插件进行签名和验证。无论使用 GPG 还是 Sigstore，都应在 CI 中固定可信公钥、身份或签名策略，拒绝未知来源的依赖。生产部署建议同时记录 Chart 版本、包 digest、镜像 digest、Git commit 和流水线构建号。

## 11. 生产级设计与安全基线

### 11.1 资源和标签

推荐使用 Kubernetes 通用标签：

- app.kubernetes.io/name
- app.kubernetes.io/instance
- app.kubernetes.io/managed-by
- app.kubernetes.io/version
- app.kubernetes.io/component
- app.kubernetes.io/part-of
- helm.sh/chart

其中 app.kubernetes.io/managed-by 通常为 .Release.Service，app.kubernetes.io/instance 为 .Release.Name。用于 Selector 的标签必须稳定，不能包含每次发布都会变化的 Chart 版本或 Git SHA。

为工作负载提供：

- 合理的 resources.requests/limits；
- readinessProbe、livenessProbe 和必要时的 startupProbe；
- PodDisruptionBudget、TopologySpreadConstraints 和反亲和性；
- HPA 与 Deployment 副本数的清晰职责；
- ConfigMap/Secret 变更触发 Pod 滚动的 checksum annotation；
- ServiceAccount、NetworkPolicy 和最小化 RBAC；
- Pod securityContext、非 root 用户、只读根文件系统、禁止新增 Linux capabilities 和 seccompProfile。

### 11.2 镜像、密钥和权限

- 默认使用完整 Registry 地址和固定版本；生产环境优先使用镜像 digest。
- 不要在 values.yaml、Git 仓库、Chart 包或 CI 日志中存储密码、Token、私钥和云凭据。
- Kubernetes Secret 只是编码后的对象，不等同于密文存储；结合 KMS、External Secrets、Vault 或云厂商密钥服务。
- --set password=... 可能进入 Shell 历史、进程列表和 CI 日志；敏感值应通过受控 Secret 注入。
- ServiceAccount 默认不应授予集群管理员权限；集群级资源和命名空间级资源应分离评审。
- 模板中的 tpl、lookup、Files.Get 和动态权限对象必须经过代码审查。
- 依赖 Chart、基础镜像和构建工具都属于供应链边界，应扫描漏洞、记录 SBOM 并锁定版本。

### 11.3 可重复、幂等和可观测

模板渲染应尽量是确定性的。升级时重新执行 randAlphaNum 等随机函数会产生变化并触发滚动；随机值必须持久化或由外部 Secret 管理。Hook 和迁移 Job 要求幂等，失败后可安全重试。

Chart 应在 NOTES 和 README 中输出可操作信息，例如访问地址、端口转发方式、下一步命令和已知限制；不要输出凭据或完整 Secret。对升级、回滚和删除操作记录审计事件，并保留可查询的 Release 历史。

## 12. CI/CD 与 GitOps 建议

一个最小的构建流水线可以分为静态检查、渲染校验、打包签名和发布部署四个阶段：

~~~bash
set -euo pipefail

helm dependency build ./mychart
helm lint ./mychart --strict

helm template myapp ./mychart \
  --namespace app-prod \
  --kube-version 1.32.0 \
  -f values-ci.yaml > rendered.yaml

# 可在这里运行 kubeconform、conftest、OPA 或组织策略检查
helm package ./mychart --destination dist

# 如果组织签名流程生成了 .prov，可在发布前校验
# helm verify dist/myapp-1.4.0.tgz

# 发布到 OCI Registry
helm push dist/myapp-1.4.0.tgz oci://registry.example.com/helm
~~~

交付规则建议：

1. 由 Git Tag 或发布流水线生成唯一 Chart 版本，禁止覆盖已发布的同名同版本包；
2. 提交 Chart.lock，使用干净环境和 helm dependency build；
3. 对每套环境只维护必要的 values 差异，禁止把生产 Secret 纳入仓库；
4. 在合并请求中保存渲染结果摘要、依赖版本、Chart digest 和镜像 digest；
5. 部署使用 --wait、合理的 --timeout 和失败回滚策略；
6. 对 CRD、数据库迁移、集群级 RBAC 等高风险变更设置人工审批；
7. GitOps 场景中让控制器负责持续对账，Chart 负责可复现的 manifest 生成，避免同一 Release 同时被多个控制器和人工 Helm 命令写入；
8. 升级前使用独立集群或临时命名空间运行 helm test 和回滚演练。

## 13. 常见问题排查

| 现象 | 常见原因 | 排查方式 |
| --- | --- | --- |
| nil pointer evaluating interface | Values 层级为空或访问路径不安全 | 用 default/required，补全默认 Map 和 Schema |
| YAML parse error | 缩进、引号、换行控制错误 | helm template --debug，检查 toYaml 与 nindent |
| no matches for kind | API 版本不支持或 CRD 尚未安装 | 检查 Capabilities、CRD 安装顺序和集群版本 |
| cannot patch immutable field | 修改了 Deployment Selector 等不可变字段 | 保持 Selector 稳定，必要时设计迁移或新资源名 |
| timed out waiting for the condition | 探针失败、资源不足、Hook 卡住或镜像拉取失败 | helm status、kubectl describe/events/logs，调整探针和 timeout |
| already exists / ownership error | 资源由其他 Release 或手工对象管理 | 检查 labels/annotations 和资源归属，不要强行接管 |
| Release 处于 pending-upgrade | Hook 超时、客户端中断或并发操作 | 查看 helm history、Hook Job 和事件，确认后回滚 |
| 配置更新但 Pod 未重启 | Deployment Pod template 没有变化 | 对 ConfigMap/Secret 内容添加 checksum annotation |
| 依赖下载到意外版本 | 使用 update 重新解析或版本约束过宽 | 提交 Chart.lock，CI 使用 dependency build |
| helm template 正常但集群失败 | 本地缺少 API discovery、准入策略或 CRD | 使用 server dry-run、目标版本渲染和集群策略校验 |
| Hook Job 残留 | 没有配置删除策略或 TTL | 增加 hook-delete-policy 和 ttlSecondsAfterFinished |
| 回滚后数据不一致 | 数据库迁移或外部资源不可逆 | 将数据迁移设计为向前兼容，单独制定恢复流程 |

建议的诊断命令：

~~~bash
helm status myapp -n app-prod
helm history myapp -n app-prod
helm get values myapp -n app-prod --all
helm get hooks myapp -n app-prod
kubectl get events -n app-prod --sort-by=.lastTimestamp
kubectl describe deployment -n app-prod myapp
kubectl logs -n app-prod deploy/myapp --all-containers
~~~

## 14. 最小可运行 Chart 示例

### 14.1 文件

~~~text
myapp/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── _helpers.tpl
    ├── deployment.yaml
    └── service.yaml
~~~

### 14.2 Chart.yaml

~~~yaml
apiVersion: v2
name: myapp
description: Minimal web service chart
type: application
version: 0.1.0
appVersion: "1.0.0"
~~~

### 14.3 values.yaml

~~~yaml
replicaCount: 2

image:
  repository: nginx
  tag: "1.27.1"
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80

resources: {}
~~~

### 14.4 templates/_helpers.tpl

~~~gotemplate
{{- define "myapp.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "myapp.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "myapp.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "myapp.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | quote }}
app.kubernetes.io/name: {{ include "myapp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
~~~

### 14.5 templates/deployment.yaml

~~~yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "myapp.fullname" . }}
  labels:
    {{- include "myapp.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app.kubernetes.io/name: {{ include "myapp.name" . }}
      app.kubernetes.io/instance: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: {{ include "myapp.name" . }}
        app.kubernetes.io/instance: {{ .Release.Name }}
    spec:
      containers:
        - name: nginx
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: 80
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
~~~

### 14.6 templates/service.yaml

~~~yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "myapp.fullname" . }}
  labels:
    {{- include "myapp.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  selector:
    app.kubernetes.io/name: {{ include "myapp.name" . }}
    app.kubernetes.io/instance: {{ .Release.Name }}
  ports:
    - name: http
      port: {{ .Values.service.port }}
      targetPort: http
      protocol: TCP
~~~

### 14.7 验证和部署

~~~bash
helm lint ./myapp --strict
helm template demo ./myapp --namespace demo
helm install demo ./myapp --namespace demo --create-namespace --wait
helm test demo --namespace demo
helm upgrade demo ./myapp --namespace demo --wait --timeout 5m
helm rollback demo 1 --namespace demo --wait
helm uninstall demo --namespace demo
~~~

## 15. 术语速查

- **Chart**：Helm 的可分发软件包。
- **Release**：Chart 在指定集群和命名空间中的部署实例。
- **Revision**：Release 的历史修订号。
- **Values**：传给模板的配置数据。
- **Manifest**：渲染后提交给 Kubernetes 的资源清单。
- **Subchart**：被父 Chart 作为依赖引入的 Chart。
- **Library Chart**：只提供模板能力、不直接安装资源的 Chart。
- **Hook**：在 Release 生命周期阶段执行的特殊资源。
- **CRD**：扩展 Kubernetes API 的 CustomResourceDefinition。
- **Provenance**：用于校验 Chart 来源和完整性的签名记录。
- **OCI Artifact**：使用 OCI Distribution 规范存储的 Chart 包及其相关层。

## 16. 参考资料

### Helm 官方与中文文档

- [Helm 官方文档](https://helm.sh/)
- [Charts：Chart 格式与依赖](https://helm.sh/docs/topics/charts/)
- [Helm 中文文档：Charts](https://helm.kubernetes.ac.cn/docs/topics/charts/)
- [Helm 中文文档镜像：Charts](https://whmzsu.github.io/helm-doc-zh-cn/chart/charts-zh_cn.html)

### 教程  

- https://www.cnblogs.com/mangolxh/p/19797526
- https://zhuanlan.zhihu.com/p/641877289
- https://bbs.huaweicloud.com/blogs/456356
- https://zhuanlan.zhihu.com/p/80821849
- https://developer.aliyun.com/article/1207395
- https://blog.csdn.net/yugongpeng/article/details/134945136
- https://cloud.tencent.com/developer/article/2504578
- https://cloud.tencent.com/developer/article/2400078
- https://dontla.blog.csdn.net/article/details/160217180  
- https://gitlab.cn/docs/jh/user/packages/helm_repository/

### 延伸阅读

- [Helm Chart 最佳实践：Values](https://helm.sh/docs/chart_best_practices/values/)
- [Helm Chart 最佳实践：Templates](https://helm.sh/docs/chart_best_practices/templates/)
- [Helm Chart 依赖](https://helm.sh/docs/topics/charts/#chart-dependencies)
- [Helm OCI Registry](https://helm.sh/docs/topics/registries/)
- [Helm Chart Hooks](https://helm.sh/docs/topics/charts_hooks/)
- [Kubernetes 通用标签](https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/)
- [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html)
