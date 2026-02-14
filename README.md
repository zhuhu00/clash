# Clash

用于在容器或远程 Linux 环境中一键启动 Mihomo (Clash) 服务的脚本集合。适合在 AutoDL、云服务器等环境快速拉起代理。  
说明：`conf/config.yaml` 可以直接从本地 Clash 导出的配置复制过来使用。

## 环境准备
- 具备 bash 或 zsh 的 Linux 环境（脚本会自动适配两者）。
- 可访问外网的 Clash 订阅地址，或一份已经可用的 `config.yaml`。
- 推荐先安装 `lsof` 方便后续排查：

  ```bash
  sudo apt-get update
  sudo apt-get install -y lsof
  ```

## 快速开始
1. 克隆仓库并进入目录：

	```bash
	git clone https://github.com/zhuhu00/clash.git clash-for-linux
	cd clash-for-linux
	```

2. 配置订阅信息（可选）。脚本会优先尝试使用 `.env` 中的订阅地址自动下载配置：

	```bash
	cp .env.example .env
	vim .env
	```

	`.env` 示例：

	```dotenv
	export CLASH_URL='https://your-subscription-url'
	export CLASH_SECRET='自定义Dashboard口令，可留空自动生成'
	```

3. 准备配置文件：
	- 若 `.env` 中提供了订阅地址且该地址可访问，`start.sh` 会自动下载到 `conf/config.yaml`(不一定能成功, 推荐第下面的方案, 手动维护)。
	- 如果更倾向手动维护，直接把本地 Clash 导出的 `config.yaml` 复制到 `conf/` 目录即可（与提示中的 update 保持一致）。
  		![20251125161141](https://raw.githubusercontent.com/zhuhu00/img/master/uPic/20251125161141.png)

1. 运行启动脚本：

	```bash
	source ./start.sh
	```

### `start.sh` 做了什么？
- 清理历史遗留的代理函数，避免环境变量冲突。
- 自动检测 CPU 架构，下载匹配的 Mihomo 二进制文件和 `yq` 工具。
- 根据订阅或现有配置校验 `conf/config.yaml`，并在需要时尝试合并 `conf/template.yaml`。
- 启动 Mihomo，生成 `logs/mihomo.log`，并输出 Dashboard 地址（默认 `http://<server-ip>:9090/ui`）。
- 在 `~/.zshrc` 或 `~/.bashrc` 中注入一组便捷命令，并立即加载。
- 自动执行一次网络连通性测试，必要时临时开启代理。

## 自动注入的常用命令
这些函数写入到当前用户的 shell 配置中，可随时调用：
- `proxy_on`：导出 HTTP(S) 代理环境变量，默认指向 `127.0.0.1:<Clash端口>`。
- `proxy_off`：清除所有代理相关环境变量。
- `clash_on`：执行 `restart.sh`，平滑重启 Mihomo 服务。
- `clash_off`：终止当前 Mihomo 进程，并清空代理变量。
- `health_check`：调用 `health_check.sh`，验证外网访问。
- `clash_test`：调用 `tools/clash_test.sh`，并发测速所有节点并输出延迟最低的前 10。
- `clash_switch`：测速并交互式切换节点。默认测试日本/美国/新加坡节点，展示 top 10，输入编号即可通过 API 热切换，无需重启服务。
- `shutdown_system`：触发带双重确认的卸载流程，清理脚本、配置和日志。

首次运行后脚本会提示这些命令，可按需再次执行。若后续修改了配置文件，请运行 `clash_on` 或 `source ./restart.sh` 让新配置生效。

## 常见操作
- **查看监听端口**：`lsof -i -P -n | grep LISTEN | grep -E ':9090|:789[0-9]'`
- **健康检查**：`health_check` 或 `source ./health_check.sh`
- **查看日志**：`tail -f logs/mihomo.log`
- **访问 Dashboard**：浏览器打开 `http://<服务器IP>:9090/ui` 并使用 `.env` 中的 `CLASH_SECRET` 登录（留空则查看脚本输出）。
- **验证外网**：`curl -L google.com`

## 配置与节点管理
- 使用 Clash for Windows 获取订阅内容时，可右键 Profiles → Edit，然后把 `proxies`、`proxy-groups`、`rules` 段复制到 `conf/config.yaml`。需要图例可参考 `image/` 目录中的截图。
- **切换节点（推荐）**：运行 `clash_switch`，测速完成后输入编号即可热切换，无需重启服务：

  ```bash
  # 默认测速日本/美国/新加坡节点，展示 top 10
  clash_switch

  # 只测日本节点
  clash_switch -- --filter "日本"

  # 自定义排除
  clash_switch -- --exclude "香港|美国"
  ```

- 若希望同时保留模板配置，可在运行前导出 `ENABLE_TEMPLATE_MERGE=1`，脚本会用 `yq` 自动合并 `conf/template.yaml`。

## 排查建议
- 端口未打开：先确认 `conf/config.yaml` 中的端口（`mixed-port`、`port` 或 `socks-port`）配置正确，再查看 `logs/mihomo.log`。
- 订阅下载失败：检查 `.env` 中的 `CLASH_URL` 是否可在宿主机访问，必要时手动把配置文件放到 `conf/`。
- 函数未生效：确认 `~/.zshrc` 或 `~/.bashrc` 中已追加命令，重新 `source` 一次，或在新的 shell 会话中重试。

完成以上步骤后，即可在容器内开启代理，加速访问外网资源。根据需要可继续通过 VS Code 端口转发或其它工具实现本地访问。
