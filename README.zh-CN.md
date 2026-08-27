# DeskPet for DeepSeek Harness

为 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 提供的原生 macOS 桌面宠物。宠物悬浮在整个系统桌面层，能够拖动、响应鼠标动作、显示快捷语，并跟随 Harness 的运行、等待、完成和失败状态播放动画。

[English](README.md)

## 功能

- 在 DeepSeek Harness 的“设置”中增加独立的“桌面宠物”栏目。
- 在 macOS 全局桌面显示透明、可拖动、置顶的宠物窗口。
- 双击宠物时聚焦已打开的 Harness 标签页，不刷新、不重复打开。
- 单击随机播放动作并显示可编辑的宠物快捷语。
- 任务运行或等待确认时，在宠物上方显示当前任务。
- 大小、位置、显示状态、当前宠物和快捷语均会保存。
- 中文与英文界面跟随 DeepSeek Harness 当前语言。
- 支持 Codex v1（1536×1872）和 v2（1536×2288）宠物图集。
- 可从 Awesome Codex Pet、Codex Pets、PetDex、SpriteYard、AgentBro、OpenPets 和 Codex Anime Pets 查找、下载、更新与删除宠物。
- 商店采用滚动到底自动加载；损坏的预览图保持空白，不显示裂图。

## 默认宠物

默认宠物为 BongoCat。

宠物素材不自动继承本仓库的 MIT 代码许可证。来源和使用限制见 [THIRD_PARTY_PETS.md](THIRD_PARTY_PETS.md)。包含第三方角色素材的仓库建议先保持私有；公开发布前请确认每个素材的再分发权限。

## 环境要求

- macOS 13 或更高版本
- Apple Silicon 或能够运行 Swift/AppKit 的 Mac
- 已安装 Node.js、pnpm 和 DeepSeek Harness 源码
- DeepSeek Harness 已能通过 `pnpm dsh web` 正常启动

## 安装

```bash
git clone https://github.com/yihanz0107/deskpet-for-deepseek-harness.git
cd deskpet-for-deepseek-harness
./install.sh
```

安装器会通过环境变量、保存的配置、常用目录和 Spotlight 自动查找 `deepseek-harness`。

如果没有自动找到，可以明确指定：

```bash
./install.sh --harness /你的路径/deepseek-harness
```

安装器会：

1. 编译并安装 `~/Applications/DeepSS Pet.app`。
2. 将 Web 设置扩展安装到 Harness 的 `apps/web/public/`。
3. 在 Harness 设置页入口中加载桌宠扩展。
4. 重新构建 Harness Web 前端。
5. 安装 `deepsshpet` 命令并保存 Harness 路径。

如只想安装而暂不重新构建 Web：

```bash
./install.sh --harness /你的路径/deepseek-harness --no-build-web
```

## 启动

```bash
deepsshpet
```

该命令不是只启动宠物：它会启动桌宠和 DeepSeek Harness。若 Harness 已经在运行，则直接聚焦现有页面，不会重复启动服务。

也可以临时指定位置：

```bash
DEEPSEEK_HARNESS_HOME=/你的路径/deepseek-harness deepsshpet
```

## 使用

打开 DeepSeek Harness → 设置 → 桌面宠物：

- “我的宠物”用于切换或删除已经安装的宠物。
- “找找新宠物”打开全屏宠物商店。
- “宠物大小”支持 0.2–1.5 倍，默认 0.5。
- “宠物快捷语”每行一句，保存后单击宠物会随机显示。
- 动画状态默认为自动跟随任务，也可以手动固定。

桌面操作：

- 鼠标移入：挥手。
- 单击：随机动作和快捷语。
- 拖动：移动宠物，左右方向动画保持固定帧率。
- 双击：返回已经打开的 Harness 页面。
- 右键：挥手、隐藏或退出桌宠。

## 目录

```text
app/                 原生 AppKit 桌宠源码和随包宠物
bin/deepsshpet       Harness + 桌宠启动命令
web/deepss-pet.js    Harness 设置与宠物商店扩展
build.sh             构建原生应用
install.sh           自动定位并安装到 Harness
```

用户下载的宠物保存在：

```text
~/Library/Application Support/DeepSS Pet/pets/
```

Harness 路径保存在：

```text
~/.config/deepsshpet/harness-path
```

## 开发验证

```bash
node --check web/deepss-pet.js
swiftc -typecheck app/Sources/main.swift \
  -framework AppKit -framework CoreGraphics \
  -framework ImageIO -framework Network
./build.sh
```

## 许可证

本项目代码采用 MIT License。第三方宠物图像、人物和商标仍属于各自权利人，详见 [THIRD_PARTY_PETS.md](THIRD_PARTY_PETS.md)。

## 宠物来源与感谢

特别感谢 [ayangweb/bongocat](https://github.com/ayangweb/bongocat) 以及 BongoCat 的创作者与贡献者。之所以有这个项目，是因为我很喜欢他们做的这只猫猫，所以希望它不只出现在原来的应用中，也能在使用 DeepSeek Harness 时更多地陪伴自己。BongoCat 是 DeskPet 的默认宠物，也是这个项目的起点。

感谢以下开源项目、宠物市场、素材社区以及所有宠物创作者。没有这些项目对格式、素材和社区生态的贡献，DeskPet 的宠物商店无法实现：

- [Awesome Codex Pet](https://github.com/legeling/awesome-codex-pet)
- [Codex Pets](https://codex-pets.net/)
- [PetDex](https://petdex.dev/)
- [SpriteYard](https://www.spriteyard.com/)
- [AgentBro Pet Market](https://www.agentbro.net/pets)
- [OpenPets](https://openpets.dev/gallery)
- [Codex Anime Pets](https://github.com/chenxin-dlut/codex-anime-pets)

特别感谢每位上传、绘制、维护和分享宠物的创作者。DeskPet 只提供技术兼容和本地加载能力，宠物素材的版权、许可和商标归原作者及相关权利人所有。
