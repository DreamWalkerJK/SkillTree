# <center>kafka 配置外部地址</center>  

### 配置要点

```text
namespace: zggg-fips-dev
StatefulSet: zggg-dev-component-kafka-broker
broker 数量: 3
k8s 可访问机器节点 IP: 188.2.102.222
旧 NodePort: 32093
新增 NodePort: 32100、32101、32102
外部监听容器端口: 9095
```

### 1. 确认 NodePort 未被占用

```powershell
kubectl get services --all-namespaces -o wide | grep <nodeport-number>
```

无输出表示端口未被占用。如果已被占用，需要换成三个 `30000～32767` 范围内的空闲端口，并同步修改后续所有配置。

### 2. 给三个 broker 创建独立 NodePort Service  

在 k8s 页面中选择应用 负载-> 服务 -> 新建 -> 编辑 YAML：

```yaml
apiVersion: v1
kind: Service
metadata:
  name: zggg-dev-component-kafka-broker-0-external
  namespace: zggg-fips-dev
spec:
  type: NodePort
  selector:
    statefulset.kubernetes.io/pod-name: zggg-dev-component-kafka-broker-0
  ports:
    - name: kafka-external
      protocol: TCP
      port: 9095
      targetPort: 9095
      nodePort: 32100
```

```yaml
apiVersion: v1
kind: Service
metadata:
  name: zggg-dev-component-kafka-broker-1-external
  namespace: zggg-fips-dev
spec:
  type: NodePort
  selector:
    statefulset.kubernetes.io/pod-name: zggg-dev-component-kafka-broker-1
  ports:
    - name: kafka-external
      protocol: TCP
      port: 9095
      targetPort: 9095
      nodePort: 32101
```
```yaml
apiVersion: v1
kind: Service
metadata:
  name: zggg-dev-component-kafka-broker-2-external
  namespace: zggg-fips-dev
spec:
  type: NodePort
  selector:
    statefulset.kubernetes.io/pod-name: zggg-dev-component-kafka-broker-2
  ports:
    - name: kafka-external
      protocol: TCP
      port: 9095
      targetPort: 9095
      nodePort: 32102
```

### 3. 修改 Kafka broker 配置 ConfigMap  

- ConfigMap 配置名称通常为：

```text
zggg-dev-component-kafka-broker-configuration
```

- 在 k8s 页面中选择配置->配置字典编辑：在 `data.server.properties` 中，将现有 listeners 末尾追加外部 listener：

```properties
listeners=CLIENT://:9092,INTERNAL://:9094,EXTERNAL://:9095
```

- 在原有安全协议映射末尾追加：

```properties
listener.security.protocol.map=CLIENT:PLAINTEXT,INTERNAL:SASL_PLAINTEXT,EXTERNAL:PLAINTEXT
```

- 必须保留部署中原来的 INTERNAL 协议，不能因为示例而强制改成其他协议。基础 ConfigMap 的这一行先不要手工添加 EXTERNAL，除非后续报错，因为现有 `kafka-init` 会按照 Pod ordinal 自动追加对应的外部广播地址。

```properties
advertised.listeners=CLIENT://advertised-address-placeholder:9092,INTERNAL://advertised-address-placeholder:9094
```

### 4. 修改 Kafka StatefulSet  

- 在 k8s 中选择 应用负载 -> 工作负载 -> 有状态副本集 -> 筛选项目，找到 zggg-dev-component-kafka-broker 编辑 YAML，在 `spec.template.spec.initContainers` 中找到 `name: kafka-init`，在其 `env` 下追加：

```yaml
- name: EXTERNAL_ACCESS_ENABLED
  value: "true"
- name: EXTERNAL_ACCESS_HOST
  value: "188.2.102.222"
- name: EXTERNAL_ACCESS_PORTS_LIST
  value: "32100,32101,32102"
```

注意：必须将这些变量放在 `kafka-init` 初始化容器中，而不是主 Kafka 容器中。

- 该初始化脚本会生成：

```text
broker-0 → EXTERNAL://188.2.102.222:32100
broker-1 → EXTERNAL://188.2.102.222:32101
broker-2 → EXTERNAL://188.2.102.222:32102
```

- 然后在主容器 `name: kafka` 的 `ports` 下追加：

```yaml
- name: external
  containerPort: 9095
  protocol: TCP
```

### 5. 滚动重启

```powershell
kubectl -n zggg-fips-dev rollout restart statefulset `
  zggg-dev-component-kafka-broker

kubectl -n zggg-fips-dev rollout status statefulset `
  zggg-dev-component-kafka-broker `
  --timeout=10m
```

不要手动删除三个 Kafka Pod，由 StatefulSet 逐个滚动更新。

### 6. 本机测试端口

```powershell
telnet 188.2.102.222 32100
telnet 188.2.102.222 32101
telnet 188.2.102.222 32102
```