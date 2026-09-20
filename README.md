<h1 align="center">
  <br>
  <a href="https://tryglance.app"><img src="glance/Assets.xcassets/appicon.imageset/appicon.png" alt="Glance" width="150"></a>
  <br>
  Glance
  <br>
</h1>

<h3 align="center">Face unlock for your Mac</h3>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-black.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-black.svg" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-black.svg" alt="Swift">
</p>

Glance brings the FaceID-like experience of your iPhone to a Mac near you. Unlock your Mac with a glance — no typing, no reaching for the TouchID key. Everything runs on-device using Apple's Vision
and Core ML frameworks, so your face data and your Mac password never touch the internet. The UI is built into your Macbook's notch with fluid dynamic island like animations.


https://github.com/user-attachments/assets/e2ba036a-db3d-4824-a3d8-336b239baca9

## 原作者与项目来源

本项目基于 **Jonathan Zhou（[@jonnyoo](https://github.com/jonnyoo)）** 开源的 Glance 修改。感谢原作者提供面部识别、锁屏解锁和刘海交互的基础实现。

- **原版官网：** [tryglance.app](https://www.tryglance.app/)
- **原作者 GitHub：** [@jonnyoo](https://github.com/jonnyoo)
- **原版仓库：** [jonnyoo/glance](https://github.com/jonnyoo/glance)

这是基于原版开发的修改分支，以下新增功能与修复由本分支提供，不代表原作者的官方发布。

## 与原版的差异

下表列出本分支相对于开发起点的主要改动；原版后续更新可能有所不同。

| 项目 | 本分支的新增或调整 |
|---|---|
| **自定义识别动画** | 接入 [ShaderCN](https://www.shadercn.run/) 的 33 种光球动画，通过原生 Metal 在本地渲染。识别中对应 **Thinking**，成功对应 **Speaking**，失败对应 **Idle**。保留原有动画样式。 |
| **动画设置** | 在设置中选择光球、预览状态、调整尺寸、颜色、驱动强度和各动画参数；各状态独立保存，支持重置和复制配置。 |
| **连续面部采集** | 改为缓慢转头一圈连续采集，无需单独拍摄或导入正脸照片。系统自动从摄像头帧中选择参考帧和各角度样本。 |
| **异步整理与补帧** | 采集后显示雾化背景和 Thinking 动画，继续采集 4 秒真实补充帧，再后台筛选清晰度、对齐质量和身份一致性。补采预算为 12 秒，模型处理可能增加耗时；不足的角度可单独补齐。 |
| **会话与安全存储修复** | 统一钥匙串存储查询，兼容旧存储；同步设置页的会话状态，处理配置完成后的密钥缺失、会话无法解锁问题。增加保留旧加密数据的重新配置入口，并持久保存当前存储区标识。 |
| **熄屏与唤醒识别** | 补齐显示器休眠、系统唤醒和屏保退出事件的处理，合并重复事件；增加锁屏状态就绪重试和摄像头预热等待，减少亮屏后漏触发识别。 |
| **中英文切换** | 新增 **设置 → 通用 → 语言**，支持简体中文和英文即时切换并保存选择，覆盖主要设置、采集提示和动画参数名称。 |
| **回归验证** | 增加采集、凭据、钥匙串存储选择、唤醒事件和多语言检查，运行方法见 [验证说明](tools/enrollment-tests.md)。 |

本分支仍使用普通摄像头与本地 Vision / Core ML 识别，不具备 Apple Face ID 的深度传感器能力。补帧来自真实摄像头画面，不生成虚构的面部样本。旧密钥确实丢失时，重新配置会保留旧数据，但无法解密或恢复旧数据。

代码已通过编译和逻辑回归检查；Touch ID、摄像头采集及熄屏解锁的完整流程仍需使用正常签名的版本进行实机验证。





---

> [!WARNING]
> ## Read before downloading
> ## Glance is not as secure as Apple's FaceID or TouchID
> 
> MacBooks don't come equipped with the depth sensors that make iPhone FaceID trustworthy and secure. An
> iPhone builds a 3D map of your face; a MacBook webcam sees a flat 2D image. That means:
> 
> - Glance defeats, with reasonable confidence, a printed photo and a photo on a phone screen (heavy liveness detection must be turned on)
> - Glance does not reliably defeat a video of you
> - macOS has no API that lets a third-party app authorize a login, so Glance unlocks by typing
>   your stored password on the lock screen
> 
> Glance is a convenience feature, not a security upgrade. Only continue if you accept the tradeoff.

## Installation

**Requirements:**

- macOS 15 Sequoia or later
- Apple Silicon or Intel Mac

**以下下载链接为原作者发布的官方版本，不包含本分支的上述改动。使用本分支请参照 [Building from source](#building-from-source) 自行构建。**

<a href="https://github.com/jonnyoo/glance/releases/latest/download/Glance.dmg" target="_self"><img width="200" src="https://github.com/user-attachments/assets/cdb8af97-1ee2-4669-b7cb-dcfb56c9dd61" alt="Download for Mac" /></a>

Open the `.dmg` file and drag Glance to `/Applications`, then open it.


## Permissions

| Permission | Why |
|---|---|
| **Camera** | To see your face. Frames are processed in memory and never written to disk. |
| **Accessibility** | To type your password into the lock screen. |
| **Touch ID** | Gates the key that encrypts your face data and password. |

## How it works

1. Launch the app and follow onboarding. After authenticating secure storage, slowly move your head in a circle; there is no separate front-photo step. Glance collects the eight surrounding angles continuously and automatically selects a reference frame. The capture view blurs and shows a Thinking orb while the camera continues acquiring real supplemental frames. A four-second refinement interval is followed by background quality ranking and targeted retries, with a twelve-second acquisition budget (model processing can add time). Any missing angles can be filled without repeating the whole turn. Only 512-number *embeddings* are saved; temporary camera images are discarded.
2. Enter your Mac password once, encrypted behind Touch ID.
3. When your Mac locks or wakes from sleep, the animation appears in the notch and starts searching for a face.
4. If it's you — and the liveness checks agree you're a real person — Glance types the
   password and you're in.

## Features

| Feature | Description |
|---|---|
| **Face unlock** | Triggers on wake, on lock, or on pressing space at the lock screen. Pick any combination. |
| **Multiple identities** | Enroll several people, or several versions of yourself — with glasses, a beard, different lighting. Toggle any of them off without deleting. |
| **Liveness checks** | Watches for the motion and reflections that separate a real face from a photo. *Light* or *Heavy* strictness, or off. |
| **Notch UI** | A closed pill that expands into a scan animation with success and failure states. Hover to retry — or turn animations off entirely and Glance stays invisible. |
| **Camera & display** | Choose which camera to use, including different cameras for the built-in display vs. an external monitor. |
| **Auto-locking sessions** | The Touch ID session re-locks itself after an idle period you choose, so an unattended Mac doesn't stay authorized forever. |
| **Trackpad haptics** | Hovering over the notch will trigger haptics |
| **Notchless Mac support** | Macs without a notch will be replaced with a pill-shape, dynamic island style design. |
| **Your data, your call** | Edit or delete your enrolment or stored password at any time. The encrypted files are removed immediately. |

---

# Privacy and Security

Glance is designed to keep biometric data and credentials on-device.

### Face data

Glance never stores camera images. During enrollment, each captured face is converted into a **512-dimensional embedding** using an ArcFace-based Core ML model. The original frame is then discarded.

Embeddings are stored locally and encrypted with **AES-GCM**.

### Credentials

Your Mac password is stored as encrypted data and is never written to disk in plaintext. The encryption key is a **256-bit AES key stored in the macOS Keychain**, protected by `userPresence` — requiring Touch ID or your device password.

The key is only held in memory while an authorized Glance session is active.

If an older encrypted store exists but its key is inaccessible (for example after a signing change), setup and locked Settings pages offer **Recover secure setup**. After explicit confirmation and system authentication, Glance selects a separate new storage namespace. Previous encrypted face files and Keychain items remain untouched; this does not recover the lost key or decrypt the old data. Keep the original signed app/key if you need the old enrollment. The active vault identifier is persisted alongside the encrypted face files. New Keychain items explicitly use the data-protection backend; queries also support legacy items.

Choose **General → Language** to switch immediately between **简体中文** and **English**. The selection persists across launches.

Display sleep, system wake and screensaver exit feed a coalesced wake trigger. Glance waits up to three seconds for authoritative lock/display readiness and gives the camera a separate warm-up budget before timing recognition. A session must already be authenticated and **On wake** enabled; Glance does not display authentication prompts on the lock screen.

### Unlock pipeline

Glance won't type your password simply because a face matches. An unlock requires all of the following:

1. A valid Glance session is authorized.
2. The Mac is actually at the lock screen.
3. An enabled identity matches above the configured similarity threshold.
4. Liveness checks accept the detected face.
5. Accessibility permission is available to enter the password.

Face recognition and liveness detection run independently and must both succeed before the password is entered. 

### Local by design

Face recognition, face enrollment, and liveness detection run entirely on-device using Vision and Core ML. Glance does not send face data, camera frames, or credentials to a server.


### How it tells a face from a photo

Five independent cues over a rolling ~2s window, in two roles:

- **Deny cues** are evidence of a spoof — screen glare, or a device-shaped rectangle framing the
face. Either one fails the scan outright and overrides anything else.
- **Confirm cues** are evidence of a real face — flat-vs-3D landmark geometry, nose parallax
across head turns, blinks. Any one is enough, and their absence is never a failure, since a
live person can sit still and not blink.

Light detection only include deny cues. Heavy detection includes both deny and confirm cues.

### Face Lab

Face Lab is a hidden debug console to test face recognition and liveness detection with real values.

**To open it:** Settings → About, then click the app icon 5 times. A
debug section should appear in the sidebar.

---


## Building from source

### Prerequisites

- macOS 15+
- Xcode 26+



### Installation

1. Download or clone **this repository** using its GitHub **Code** button, then open the directory containing `glance.xcodeproj`. Cloning `jonnyoo/glance` instead gives you the original upstream version, without this branch's changes.
2. Open in Xcode:
  ```bash
   open glance.xcodeproj
  ```
3. Run the project:
  - Click `run` or press `Cmd + R`.



## Contributing

Not currently accepting PRs. Feel free to fork this project.

App feedback goes to [tryglance.app/feedback](https://tryglance.app/feedback).

## Acknowledgements

- **Jonathan Zhou — [@jonnyoo](https://github.com/jonnyoo)** — original creator of [Glance](https://www.tryglance.app/), whose open-source work this branch builds on.
- **[ShaderCN](https://www.shadercn.run/) / XorDev** — the orb animations adapted for native Metal rendering; attribution and terms are preserved in [ShaderOrb-LICENSE.txt](glance/Resources/ShaderOrb-LICENSE.txt).
- **[The Boring Notch](https://github.com/TheBoredTeam/boring.notch)** — for the notch window
physics.
- **[InsightFace](https://github.com/deepinsight/insightface)** — the ArcFace model doing the
recognition.
- **[Alcove](https://tryalcove.com)** — big design inspiration.


## License

[MIT](LICENSE) © Jonathan Zhou

The bundled ShaderCN / XorDev shader assets have separate non-commercial, attribution-required terms. See [ShaderOrb-LICENSE.txt](glance/Resources/ShaderOrb-LICENSE.txt); the MIT license does not replace those asset-specific terms.
