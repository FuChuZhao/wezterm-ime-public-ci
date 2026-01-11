# wezterm-ime-public-ci

这个仓库用于**公开**保存 GitHub Actions 构建工作流；真正的源码放在**私有**仓库里。工作流会通过 SSH 拉取私有源码仓库并在 `windows-2022` 上构建，然后上传 `zip` 产物到 Actions Artifacts。

## 你需要准备什么

### 1) 私有源码仓库

- 在 GitHub 创建一个私有仓库（例如：`FuChuZhao/wezterm-ime-private`）
- 将源码推送到该私有仓库（推荐 `main` 分支）

### 2) SSH Deploy Key（推荐只读）

在本地生成一对 key：

```bash
ssh-keygen -t ed25519 -C "github-actions" -f wezterm-ime-build-key
```

然后：

- 将 `wezterm-ime-build-key.pub` 添加到**私有源码仓库**：`Settings` → `Deploy keys` → `Add deploy key`（建议只勾选 read-only）
- 将 `wezterm-ime-build-key`（私钥全文）添加到**本公共仓库**：`Settings` → `Secrets and variables` → `Actions` → `New repository secret`
  - 名称：`SSH_PRIVATE_KEY`

### 3) 配置仓库 Secrets/Variables

在本公共仓库中配置：

- `SSH_PRIVATE_KEY`：上一步的私钥全文
- `SOURCE_REPO`：私有源码仓库的 `owner/repo`（例如：`FuChuZhao/wezterm-ime-private`）

## 触发构建

- 手动：`Actions` → `build-windows` → `Run workflow`，可输入要构建的 `ref`（branch/tag/SHA）
- 自动：向本公共仓库的 `main` 分支 push 会触发一次构建（默认构建私有源码仓库的 `main`）

## 构建产物

工作流会上传一个 `wezterm-ime-windows-<SOURCE_SHA>.zip`，其中包含：

- `wezterm.exe`
- `wezterm-gui.exe`
- `wezterm-mux-server.exe`
- `strip-ansi-escapes.exe`

