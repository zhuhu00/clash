# Clash in Container
服务器一般都是容器, 容器中进行更好的科研. 

## 下载项目

下载项目

```bash
git clone -b clash-in-container https://github.com/zhuhu00/clash-for-linux.git
```

进入到项目目录，编辑`.env`文件，修改变量`CLASH_URL`的值。

```bash
cd clash-for-linux
mv conf/template_raw.yaml conf/template.yaml
cp .env.example .env
vim .env
```

<!-- ![3.png](./image/3.jpg) -->

CLASH_URL填写订阅地址，CLASH_SECRET可自行填写（例如“123456”）。填写后按“:wq”退出。

<br>

## 启动程序

直接运行脚本文件`start.sh`

- 进入项目目录

```bash
cd clash-for-linux
```

安装lsof

```bash
apt-get update
apt-get install lsof
```


- 运行启动脚本

```bash
source ./start.sh
```

在“是否要在 .bashrc 中自动添加 proxy_on 命令？(y/n): ”后填y。

- 检查服务端口

```bash
lsof -i -P -n | grep LISTEN | grep -E ':9090|:789[0-9]'
```

![1.jpg](./image/1.jpg)

这时发现并没有端口出现。

<br>

## 修改配置文件

- 打开Windows中配置文件

打开电脑中Clash for Windows，点击Profiles。在自己的订阅右键并点击Edit。

![2.jpg](./image/2.jpg)

- 复制

选中**proxies，proxy-groups，rules**并复制到本地的**clash-for-linux/conf/config.yaml**中。

![3.jpg](./image/3.jpg)

![4.jpg](./image/4.jpg)

从**“proxies:”开始覆盖**。

- 修改

在config.yaml第一行添加：

<!-- ```bash
port: 7890 # HTTP代理端口
socks-port: 7892 # SOCKS5代理端口
``` -->
<!-- 
注释：

```bash
# mixed-port: 7890
``` -->
<!-- 
修改：

```bash
external-controller: '127.0.0.1:9090' -> external-controller: '127.0.0.1:6006'
``` -->

将config.yaml的内容复制到template.yaml，使其一致。

- 重启

```bash
source ./restart.sh
```

![5.jpg](./image/5.jpg)

显示重启失败为正常情况。

命令行输入：

```bash
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
```

- 验证

```bash
source ./health_check.sh
```

![6.jpg](./image/6.jpg)

验证是否能进入谷歌

```bash
curl -L google.com
```

![11.jpg](./image/11.jpg)

此时已经成功配置。

## 更换节点

- vscode 的端口转发, 可以

- 方法一 （本人暂时连接失败）



根据 https://www.autodl.com/docs/ssh_proxy/ 下载图形化工具。


![7.png](./image/7.png)

后进入Dashboard。

![8.jpg](./image/8.jpg)

这里我填的是.env文件中的链接和密码，一直显示失败。。下面展示另一种

- 方法二

在config.yaml的proxy-groups中将希望使用的节点排在列表第一个。

![9.jpg](./image/9.jpg)

这里使用“新加坡 08”节点。

重启

```bash
source ./restart.sh
```

检查clash-for-AutoDL/logs/mihomo.log

![10.jpg](./image/10.jpg)

日志中显示希望更换的节点即成功。

