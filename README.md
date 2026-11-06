# 合盖不休眠 · LidAwake

一个常驻菜单栏的小工具：**不接外接显示器，合上盖子也让 Mac 继续跑任务**。
效果等价于在终端执行 `sudo pmset -a disablesleep 1`（关闭时恢复 `0`），但不用记命令、不用每次开终端、退出时还会自动帮你改回去。

![面板](Docs/panel-on.png)

## 用法

1. 把 `Dist/LidAwake.app` 拖进「应用程序」文件夹，双击运行。
   首次打开若提示「无法验证开发者」，右键点 App → 打开，或在「系统设置 → 隐私与安全性」里点「仍要打开」。
2. 菜单栏出现笔记本图标，点它弹出面板。
3. 拨动顶部开关：
   - **开启** → 合盖后系统不睡眠，继续跑编译 / 下载 / 渲染；
   - **关闭** → 恢复系统默认（合盖即睡眠）。
4. 第一次切换会弹系统管理员授权框（支持触控 ID）。如果不想每次都输密码，点面板里的「**授权**」，写入一条**只允许这两条命令**的免密规则：

   ```
   <你的用户名> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
   ```

   规则写在 `/etc/sudoers.d/lidawake`，只放行 `pmset -a disablesleep 0|1`，**不会**给出整机 root 权限。随时点「移除」即可删掉。

## 面板上的信息

| 项目 | 含义 |
| --- | --- |
| 电源 | 当前是电源适配器还是电池、电量、是否在充电 |
| 机盖 | 从 IOKit 读取的实时开合状态 |
| 已持续 | 本次开启已运行多久 |
| 切换方式 | 「免密」＝已装规则；「需密码」＝每次弹授权框 |
| 电池提醒 | 用电池时合盖运行会明显掉电、机身发热，建议插电 |

两个偏好开关：

- **退出时恢复默认休眠**（默认开）：退出 App 时自动 `disablesleep 0`，避免忘关后整夜耗电。若没装免密规则，退出时会问你是「恢复并退出 / 保持开启退出 / 取消」。
- **登录时自动启动**：开机后直接在菜单栏待命（走 `SMAppService`，需要 App 在「应用程序」里）。

## 构建

```bash
cd LidAwake
./build.sh            # Release 构建，产物在 Dist/LidAwake.app
```

或者用 Xcode 直接打开 `LidAwake.xcodeproj` 运行。要求 macOS 14+、Xcode 15+（本机在 macOS 27.2 / Xcode 27.2 上验证通过）。

## 目录结构

```
LidAwake/
├── LidAwake.xcodeproj/
├── Sources/
│   ├── App/         LidAwakeApp（MenuBarExtra + 退出恢复）、AppModel（状态机）、CommandLineSupport（--probe/--snapshot）
│   ├── Core/        Shell（子进程）、Privileged（sudo / osascript 双通道 + sudoers 安装）、SystemStatus（pmset 与 IOKit 读取）
│   ├── Views/       PanelView（368pt 面板 + 自绘开关）
│   └── Resources/   Assets.xcassets（AppIcon）
├── scripts/make_icon.swift   生成 App 图标（改配色/图形后重跑）
├── Docs/                     面板截图
└── build.sh
```

## 原理

- 开关写的是 `pmset -a disablesleep`（macOS 的大杀器：全系统禁用睡眠，合盖也不睡）。
- 提权两条通道：装过免密规则就走 `sudo -n`（静默）；否则走 `osascript ... with administrator privileges` 弹系统授权框。
- sudoers 安装流程：写临时文件 → `visudo -cf` 校验 → `mv -f` 原子替换，避免写坏 `/etc/sudoers` 把 sudo 弄坏。
- 需要 root 的操作都不在主线程，面板上会显示「处理中」。

## 调试用命令行

```bash
Dist/LidAwake.app/Contents/MacOS/LidAwake --probe           # 打印系统状态与 pmset 原文
Dist/LidAwake.app/Contents/MacOS/LidAwake --status          # 自检：菜单栏图标是否创建成功
Dist/LidAwake.app/Contents/MacOS/LidAwake --print-script    # 打印免密规则 / 安装脚本 / AppleScript 源码，可自行审计
Dist/LidAwake.app/Contents/MacOS/LidAwake --snapshot out.png --state on --battery
```

## 注意

- App 用 ad-hoc 签名（本机没有开发者证书），所以分发到别的 Mac 需要对方手动放行；拷到新机器前建议自己重签一次。
- `disablesleep=1` 期间电脑不会自动睡，**请务必接电源**；忘记关会一直耗电。
- 系统大版本升级后 `pmset` 行为若有变化，面板里的「无法读取系统休眠设置」会提示你。
