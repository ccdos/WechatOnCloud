# QQ Linux 测试实例 — 安装与启动文档

## 容器信息

| 项目 | 值 |
|------|-----|
| 容器名 | `qq-test` |
| 镜像 | `ghcr.io/gloridust/wechat-on-cloud:latest` |
| 主机端口 | `5901` → 容器内 `3000` |
| VNC 访问 | `http://into-wechat:5901/` |
| 启动脚本路径 | `/opt/QQ/start.sh` |

---

## 1. 下载地址（已验证可用）

> 官方 CDN（down.qq.com / dldir1.qq.com）已全部下线，仅以下地址有效：

```
https://qqdl.gtimg.cn/qqfile/QQNT/9.9.31/release/00e6a3e7/QQ_3.2.29_260528_amd64_01.deb
```

版本：QQ 3.2.29（2026-05-28 编译），AMD64 x86_64

---

## 2. 首次安装（全新容器）

```bash
# 创建容器
docker volume create qq-test-data
docker run -d \
  --name qq-test \
  -p 5901:3000 \
  -v qq-test-data:/config \
  -e LIBGL_ALWAYS_SOFTWARE=1 \
  ghcr.io/gloridust/wechat-on-cloud:latest

# 进入容器
docker exec -it qq-test bash

# 更新软件源并安装依赖
apt-get update -qq
apt-get install -y libgtk2.0-0 libnss3 libxss1 libgbm1 libasound2 libdrm2

# 下载 QQ 安装包（在容器内）
wget --no-check-certificate \
  "https://qqdl.gtimg.cn/qqfile/QQNT/9.9.31/release/00e6a3e7/QQ_3.2.29_260528_amd64_01.deb" \
  -O /tmp/QQ_3.2.29.deb

# 解压安装（绕过依赖检查，直接解压到系统）
dpkg --extract /tmp/QQ_3.2.29.deb /

# 启动 QQ（必须加 --no-sandbox --enable-unsafe-swiftshader）
export DISPLAY=:1
export LIBGL_ALWAYS_SOFTWARE=1
cd /opt/QQ
./qq --no-sandbox --enable-unsafe-swiftshader &
```

---

## 3. 启动 QQ（日常使用）

```bash
# 启动 QQ（在一行内执行，不要拆分）
ssh ccdos@into-wechat "docker exec qq-test bash -c 'export DISPLAY=:1 && export LIBGL_ALWAYS_SOFTWARE=1 && cd /opt/QQ && ./qq --no-sandbox --enable-unsafe-swiftshader &'"

# 或先进入容器再启动
docker exec -it qq-test bash
export DISPLAY=:1
export LIBGL_ALWAYS_SOFTWARE=1
cd /opt/QQ && ./qq --no-sandbox --enable-unsafe-swiftshader
```

---

## 4. 访问方法

1. 浏览器打开 `http://into-wechat:5901/`
2. 点击 **Connect** 按钮连接到 VNC 会话
3. 看到桌面后，QQ 已在后台运行

> 注意：首次需要点击 Connect 才能看到桌面内容（autoconnect 机制有延迟）。

---

## 5. 已知问题与解决

### 提示 "not mini app"
正常，QQ 桌面版启动时会出现此提示，不影响使用。

### D-Bus 错误
```
ERROR:dbus/bus.cc:408 Failed to connect to the bus
```
不影响桌面版 QQ 运行，可忽略。

### GPU 进程崩溃
```
ERROR:gpu/command_buffer/service/gles2_cmd_decoder_passthrough.cc:1095
Automatic fallback to software WebGL has been deprecated
```
加 `--enable-unsafe-swiftshader` 参数解决。

---

## 6. 开机自启动（可选）

如果需要 QQ 随容器自动启动，修改容器启动脚本或添加 s6 service。

---

## 7. 清理测试容器

```bash
ssh ccdos@into-wechat
docker rm -f qq-test
docker volume rm qq-test-data
```
