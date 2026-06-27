要在单个实例中测试QQ运行情况，你可以通过手动创建一个临时容器来完成测试，无需修改现有代码。以下是具体步骤：

## 测试步骤

### 1. 启动临时测试容器

基于现有的 `wechat-on-cloud` 镜像启动一个临时容器，挂载本地目录用于数据持久化：

```bash
# 创建测试数据卷
docker volume create qq-test-data

# 启动临时容器
docker run -d \
  --name qq-test \
  -p 5900:3000 \
  -v qq-test-data:/config \
  -e LIBGL_ALWAYS_SOFTWARE=1 \
  ghcr.io/gloridust/wechat-on-cloud:latest
```

### 2. 安装QQ依赖

进入容器安装QQ需要的gtk2.0依赖：

```bash
docker exec -it qq-test bash
apt-get update
apt-get install -y libgtk2.0-0
exit
```

### 3. 下载并安装QQ

在容器内下载QQ Linux版（以amd64为例）：

```bash
docker exec -it qq-test bash
cd /config
# 下载QQ Linux版（示例URL，需替换为实际下载地址）
curl -LO https://dldir1.qq.com/qqfile/qq/QQNT/linuxqq_3.2.2-1311_x86_64.deb
# 安装QQ
dpkg -i linuxqq_3.2.2-1311_x86_64.deb
# 修复可能的依赖问题
apt-get -f install -y
exit
```

### 4. 修改启动脚本

由于QQ的二进制路径与微信不同，需要临时修改启动逻辑：

```bash
docker exec -it qq-test bash
# 查看QQ安装路径
which linuxqq
# 或者
find /opt -name linuxqq
# 假设找到路径为 /usr/bin/linuxqq
echo '/usr/bin/linuxqq' > /config/qq-bin
exit
```

### 5. 手动启动QQ

绕过autostart脚本，直接启动QQ：

```bash
docker exec -it qq-test bash
export DISPLAY=:1
export LIBGL_ALWAYS_SOFTWARE=1
/usr/bin/linuxqq
```

### 6. 通过VNC访问

在浏览器中访问 `http://<你的服务器IP>:5900`，应该能看到KasmVNC登录界面。使用默认凭据（通常是 `abc` / `abc`）登录，查看QQ是否能正常运行。

## 基于现有架构的更简单方法

如果你想利用项目的现有机制，可以：

### 1. 修改Dockerfile添加gtk2.0

在 `docker/Dockerfile` 的依赖安装部分添加 `libgtk2.0-0` [1](#3-0) ：

```dockerfile
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libgtk2.0-0 \
        # 保留现有依赖...
```

### 2. 重新构建镜像

```bash
cd docker
docker build -t qq-test:latest .
```

### 3. 创建测试实例

参考 `panel/server/src/docker.ts` 中的 `runInstance` 函数 [2](#3-1) ，手动创建容器：

```bash
docker run -d \
  --name qq-test-instance \
  -v qq-test-data:/config \
  --network $(docker network ls | grep woc-panel | awk '{print $1}') \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=Asia/Shanghai \
  --security-opt seccomp=unconfined \
  --shm-size=1g \
  qq-test:latest
```

### 4. 手动下载安装QQ

```bash
docker exec -it qq-test-instance /woc/wechat-ctl.sh install
# 但这会安装微信，所以需要手动下载QQ
docker exec -it qq-test-instance bash
cd /config
# 下载并安装QQ（同上）
```

## 测试验证要点

1. **依赖完整性**：QQ是否能正常启动，是否有缺失库错误
2. **界面渲染**：KasmVNC是否能正确渲染QQ界面
3. **输入法**：中文输入是否正常（项目已配置IME模式） [3](#3-2) 
4. **剪贴板**：剪贴板双向同步是否正常 [4](#3-3) 
5. **稳定性**：长时间运行是否稳定，有无内存泄漏或崩溃

## 清理测试环境

测试完成后清理容器和数据卷：

```bash
docker stop qq-test
docker rm qq-test
docker volume rm qq-test-data
```

## Notes

建议使用第一种方法（临时容器）进行快速测试，因为：
- 不需要修改现有代码和镜像
- 可以快速验证QQ在容器环境中的基本运行情况
- 测试失败可以直接删除容器，不影响生产环境

如果测试成功，再考虑修改 `docker/Dockerfile`、`docker/autostart` 等文件进行正式集成 [5](#3-4) 。

Wiki pages you might want to explore:
- [Overview (Gloridust/WechatOnCloud)](/wiki/Gloridust/WechatOnCloud#1)
- [Architecture & Key Concepts (Gloridust/WechatOnCloud)](/wiki/Gloridust/WechatOnCloud#1.1)
- [Glossary (Gloridust/WechatOnCloud)](/wiki/Gloridust/WechatOnCloud#9)

### Citations

**File:** docker/Dockerfile (L24-51)
```text
# 微信运行时需要、但官方 deb 未声明的额外库（单独成层，避免动到上面缓存的安装层）。
# 微信原生版是 Qt 程序，依赖一组 xcb 平台库；libxcb-cursor0 由 Qt 动态 dlopen，ldd 查不到，需主动装。
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libatomic1 \
        libxdamage1 \
        libxkbcommon-x11-0 \
        libxcb-icccm4 \
        libxcb-image0 \
        libxcb-keysyms1 \
        libxcb-render-util0 \
        libxcb-xkb1 \
        libxcb-cursor0 \
        # WeChatAppEx 是 Chromium 内核，需 GTK3 全家桶 + 一组 X 扩展 + cups
        libgtk-3-0 \
        libatk1.0-0 \
        libatk-bridge2.0-0 \
        libatspi2.0-0 \
        libcups2 \
        libxcomposite1 \
        libxrandr2 \
        libxfixes3 \
        libxtst6 \
        libxshmfence1 \
        libdrm2; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*
```

**File:** docker/Dockerfile (L57-70)
```text
# 让 KasmVNC web 客户端默认开启 IME 输入模式：
# 用户用本地（客户端）输入法打中文，拼音联想在本地完成、只把成品汉字发进容器，无需容器内装 IME。
# 默认值仅在浏览器未存过该设置时生效，不会覆盖用户手动改过的偏好。
# 注意：实际加载的是 webpack 产物 dist/main.bundle.js（app/ui.js 是未打包源码、运行时不加载），故必须改 bundle。
# 末尾的 grep 作为断言：若 base 镜像换了打包结构、改不到任何文件，则构建直接失败而非静默放过。
RUN set -eux; \
    patched=0; \
    for f in /usr/share/kasmvnc/www/dist/*.bundle.js /usr/local/share/kasmvnc/www/dist/*.bundle.js; do \
        if [ -f "$f" ] && grep -q "initSetting('enable_ime', false)" "$f"; then \
            sed -i "s/initSetting('enable_ime', false)/initSetting('enable_ime', true)/g" "$f"; \
            patched=1; \
        fi; \
    done; \
    [ "$patched" = "1" ]
```

**File:** panel/server/src/docker.ts (L82-115)
```typescript
export async function runInstance(inst: Instance): Promise<void> {
  const net = await ensureNetwork();
  await ensureImage();
  try {
    const existing = docker.getContainer(inst.containerName);
    await existing.inspect();
    await existing.remove({ force: true });
  } catch {
    /* 不存在，正常 */
  }
  // 摄像头设备（探测不到则为空数组 → 仅摄像头不可用，音频/麦克风照常）
  const vids = videoDevices();
  const hostConfig: Docker.HostConfig = {
    Binds: [`${inst.volumeName}:/config`],
    NetworkMode: net || undefined,
    SecurityOpt: ['seccomp=unconfined'],
    ShmSize: SHM_SIZE,
    RestartPolicy: { Name: 'unless-stopped' },
  };
  if (vids.length) {
    hostConfig.Devices = vids.map((d) => ({ PathOnHost: d, PathInContainer: d, CgroupPermissions: 'rwm' }));
    hostConfig.GroupAdd = ['video']; // 让容器内 abc 用户能访问 /dev/videoN
    console.log(`[docker] 实例 ${inst.id} 挂载摄像头设备: ${vids.join(', ')}`);
  }
  const container = await docker.createContainer({
    name: inst.containerName,
    Image: WECHAT_IMAGE,
    Hostname: inst.containerName,
    Env: envList(inst),
    ExposedPorts: { '3000/tcp': {} },
    HostConfig: hostConfig,
  });
  await container.start();
}
```

**File:** docker/autostart (L8-8)
```text
WECHAT_BIN=/config/wechat/opt/wechat/wechat
```