# Windows 本地部署 FastGPT 完全教程（小白版）

> 本教程基于 Windows 11 专业版 + Docker Desktop 实际部署 FastGPT 的全过程编写。
> 即使你完全不懂 Docker，跟着做也能成功。

---

## 目录

1. [Docker 是什么？（概念篇）](#一docker-是什么概念篇)
2. [部署前需要了解的东西](#二部署前需要了解的东西)
3. [安装步骤（实操篇）](#三安装步骤实操篇)
4. [启动 FastGPT](#四启动-fastgpt)
5. [常见问题与解决方法](#五常见问题与解决方法)
6. [日常使用指南](#六日常使用指南)
7. [配置 AI 模型](#七配置-ai-模型)

---

## 一、Docker 是什么？（概念篇）

### 1.1 为什么需要 Docker？

想象一下你想装一套软件，它需要：
- 一个特定版本的数据库
- 一个特定版本的缓存服务
- 若干依赖库

传统安装方式就像在自己电脑上东拼西凑，装多了容易版本冲突，卸载不干净还留垃圾。

**Docker 的思路**：把每个软件连同它需要的**全部运行环境**打包成一个"集装箱"（容器），彼此隔离，互不干扰。

### 1.2 三个核心概念

| 概念 | 类比 | 说明 |
|------|------|------|
| **镜像（Image）** | 安装光盘 | 一个只读的模板，包含了运行软件所需的一切 |
| **容器（Container）** | 装好并开机的虚拟机 | 用镜像启动起来的运行实例，更轻量、启动更快 |
| **Docker Compose** | 一次性装整套系统 | 当一套系统需要多个容器协作时，用一个 YAML 文件编排，一条命令全部启动 |

### 1.3 FastGPT 需要哪些容器？

FastGPT 不是一个单独的软件，它需要多个服务协同工作：

```
FastGPT 主应用 (端口 3000)  ← 你访问的就是这个
    │
    ├── MongoDB      → 存储用户、对话记录、应用配置
    ├── PostgreSQL   → 存储知识库的向量数据
    ├── Redis        → 缓存、消息队列
    ├── MinIO        → 文件存储（上传的文档等）
    ├── AIProxy      → AI 模型调用代理
    ├── Code Sandbox → 代码执行沙盒
    ├── Plugin       → 插件服务
    └── 其他辅助服务
``+

所有这些都被 Docker 隔离在容器里。卸载时只需 `docker compose down -v` 就能干净移除，不留垃圾。

---

## 二、部署前需要了解的东西

### 2.1 系统要求

- Windows 10/11（专业版或家庭版均可）
- 至少 8GB 内存（推荐 16GB）
- BIOS 中开启了虚拟化（大部分电脑默认开启）
- 硬盘至少 10GB 可用空间

### 2.2 WSL2 是什么？

**WSL2（Windows Subsystem for Linux 2）** 是 Windows 内置的 Linux 兼容层。Docker Desktop 在 Windows 上需要它作为底层运行环境，所以安装 Docker 前必须先启用 WSL2。

好消息是：安装 Docker Desktop 时它会自动帮你处理 WSL2 的安装，你不需要单独去装。

### 2.3 网络问题

如果你在国内网络环境：
- Docker 官方下载源可能连接不稳定
- FastGPT 官方提供了国内镜像源（阿里云容器镜像仓库），本教程使用的就是国内源

---

## 三、安装步骤（实操篇）

### 第 1 步：启用 WSL2 功能

1. 以管理员身份打开 PowerShell（右键开始菜单 → "终端管理员"或搜索 PowerShell 后右键"以管理员身份运行"）
2. 运行：

```powershell
wsl --install --no-launch
```

3. 如果提示需要重启，先不用急着重启，继续下一步装完 Docker Desktop 后统一重启一次

如果 `wsl --install` 报错，也可以手动启用功能：

```powershell
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
```

### 第 2 步：安装 Docker Desktop

**方式 A：使用 winget（推荐，可自动绕过下载问题）**

```powershell
winget install --id Docker.DockerDesktop --accept-source-agreements --accept-package-agreements --silent
```

**方式 B：从官网下载**

访问 https://www.docker.com/products/docker-desktop/ 下载 Windows 版安装程序，双击运行即可。

> 如果官网下载失败（国内网络常见），优先用方式 A。

### 第 3 步：重启电脑

安装完成后**必须重启电脑**，WSL2 虚拟化功能才能生效。

### 第 4 步：验证 Docker 正常工作

重启后，在开始菜单搜索 **Docker Desktop**，点击启动。

等任务栏右下角出现 🐳 鲸鱼图标并且状态为 "Docker Desktop is running"（大约 1-2 分钟），打开 PowerShell 验证：

```powershell
docker --version
docker info
```

如果 `docker info` 能正常输出 Server Version 等信息（没有 ERROR），说明 Docker 引擎正常运行。

---

## 四、启动 FastGPT

### 第 1 步：准备 docker-compose.yml

在你的电脑上创建一个文件夹（比如 `fastgpt`），把下面的文件放进去。

> 完整的配置文件太长，建议直接从 FastGPT 官方仓库下载：
> https://raw.githubusercontent.com/labring/FastGPT/main/document/public/deploy/docker/main/cn/docker-compose.pg.yml
>
> 这个版本使用 PostgreSQL 存储向量数据 + 国内镜像源，最适合国内本地部署。

下载后**必须修改两个地方**：

**修改 1：设置前端访问地址**

找到 `x-fe-domain`，改为：

```yaml
x-fe-domain: &x-fe-domain 'http://localhost:3000'
```

**修改 2：设置 Agent Sandbox 地址（必须改，否则启动会报错！）**

找到以下两行，改为：

```yaml
x-agent-sandbox-proxy-url: &x-agent-sandbox-proxy-url 'ws://localhost:3006'
x-agent-sandbox-preview-proxy-url: &x-agent-sandbox-preview-proxy-url 'http://localhost:3006'
```

> ⚠️ 这是最容易踩的坑！默认值是空字符串，FastGPT v4.17+ 启动时会检查这两个变量，如果为空会反复重启。
>
> 注意 `AGENT_SANDBOX_PROXY_URL` 必须用 `ws://` 开头（WebSocket 格式），用 `http://` 会报 "Invalid environment variables"。

**修改 3（可选）：设置 root 密码**

```yaml
x-default-root-psw: &x-default-root-psw '你的密码'
```

### 第 2 步：启动所有服务

打开 PowerShell，进入配置文件所在目录，运行：

```powershell
cd "你的fastgpt文件夹路径"
docker compose up -d
```

第一次运行会下载 1-2GB 的镜像（从阿里云镜像仓库拉取），可能需要 5-15 分钟，耐心等待。

看到所有容器状态都显示 `Running` 或 `Healthy` 就说明启动成功了。

### 第 3 步：访问 FastGPT

打开浏览器，访问：

> **http://localhost:3000**

- 用户名：`root`
- 密码：你在配置文件里设置的密码（默认 `1234`）

---

## 五、常见问题与解决方法

### 问题 1：`docker compose up` 后 fastgpt-app 反复重启

**现象**：`docker ps` 显示 fastgpt-app 状态为 `Restarting`

**排查**：查看错误日志

```powershell
docker logs fastgpt-app --tail 50
```

**常见原因 A：Agent Sandbox 环境变量为空**

错误信息包含：`AGENT_SANDBOX_PROXY_URL, AGENT_SANDBOX_PREVIEW_PROXY_URL are required`

解决：按上文"修改 2"填写地址，然后 `docker compose up -d fastgpt-app` 重建。

**常见原因 B：AGENT_SANDBOX_PROXY_URL 格式错误**

错误信息包含：`Invalid environment variables. Please check: AGENT_SANDBOX_PROXY_URL`

解决：确认使用 `ws://localhost:3006`（不是 `http://`），然后重启。

### 问题 2：localhost 拒绝连接

**排查步骤**：

```powershell
# 看 Docker 引擎是否正常
docker info

# 看容器状态
docker ps -a

# 看应用日志
docker logs fastgpt-app --tail 30
```

- 如果 `docker info` 报错 → Docker Desktop 没启动好，打开 Docker Desktop 等鲸鱼图标变绿
- 如果 fastgpt-app 状态是 `Restarting` → 看日志定位原因
- 如果所有容器都正常但还是拒绝连接 → 确认浏览器访问的是 `http://localhost:3000`（注意 `http://`，不是 `https://`）

### 问题 3：Docker Desktop 装好了但 `docker` 命令找不到

重启电脑后重新打开 PowerShell。如果还不行，用完整路径：

```powershell
& "C:\Program Files\Docker\Docker\resources\bin\docker.exe" --version
```

### 问题 4：拉取镜像超时/失败

确认使用的是国内镜像源的配置文件（`registry.cn-hangzhou.aliyuncs.com` 开头的镜像地址）。本教程使用的配置文件已经默认走国内源。

### 问题 5：PowerShell 运行带引号的路径报错

```powershell
# ❌ 错误：缺少 & 调用符
"C:\Program Files\...\docker.exe" compose up -d

# ✅ 正确：加 &
& "C:\Program Files\...\docker.exe" compose up -d
```

或者重启电脑后 Docker 已加入系统 PATH，直接用 `docker` 命令即可。

---

## 六、日常使用指南

### 开机后怎么用？

1. 启动 Docker Desktop（鲸鱼图标变绿即就绪）
2. FastGPT 容器设置了 `restart: always`，Docker 启动后会自动拉起所有容器
3. 直接访问 http://localhost:3000

### 常用命令

```powershell
# 查看所有容器状态
docker ps -a

# 停止所有 FastGPT 服务
docker compose down

# 启动所有 FastGPT 服务
docker compose up -d

# 查看应用日志（实时跟踪）
docker compose logs -f fastgpt-app

# 修改配置后重启应用
docker compose up -d fastgpt-app
```

### 修改密码

FastGPT 的 root 密码没有在网页界面里改的入口，需要修改配置文件：

1. 编辑 `docker-compose.yml` 中的 `x-default-root-psw`
2. 重启：`docker compose up -d fastgpt-app`
3. 重启后密码会被强制重置为配置文件中的值

---

## 七、配置 AI 模型

FastGPT 部署好只是搭好了"骨架"，还需要接入一个 AI 大模型才能真正使用。

### 步骤

1. 用 root 登录 FastGPT
2. 进入「账户」→「模型」页面
3. 添加你的模型：
   - **模型名称**：自定义
   - **API 地址**：模型服务商提供的接口地址
   - **API Key**：模型服务商提供的密钥

### 支持的模型服务商

| 服务商 | 说明 |
|--------|------|
| OpenAI | GPT-4o 等 |
| DeepSeek | 国产，性价比高 |
| 通义千问 | 阿里云 |
| 智谱 GLM | 国产 |
| 其他兼容 OpenAI 格式的模型 | 任何提供 OpenAI 兼容接口的服务 |

配置好模型后，你就可以创建自己的 AI 应用和知识库了。

---

## 附录：完整部署检查清单

- [ ] Windows 10/11，虚拟化已开启
- [ ] WSL2 功能已启用（需重启生效）
- [ ] Docker Desktop 已安装并正常运行（鲸鱼图标 🐳）
- [ ] docker-compose.yml 已下载到本地文件夹
- [ ] `x-fe-domain` 已设置为 `http://localhost:3000`
- [ ] `x-agent-sandbox-proxy-url` 已设置为 `ws://localhost:3006`
- [ ] `x-agent-sandbox-preview-proxy-url` 已设置为 `http://localhost:3006`
- [ ] `x-default-root-psw` 已设置为你想用的密码
- [ ] `docker compose up -d` 已执行完成
- [ ] 所有容器状态为 Running/Healthy
- [ ] 浏览器能打开 http://localhost:3000
- [ ] 已用 root 登录并配置了 AI 模型

