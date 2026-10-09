此版本使用 ad-hoc 签名，未经过 Apple 公证。

- Apple Silicon（M 系列芯片）请选择 `arm64-local.dmg`。
- Intel Mac 请选择 `x86_64-local.dmg`。
- `SHA256SUMS` 提供下载文件的 SHA-256 校验值。

打开 DMG，将 KeyCount 拖到“应用程序”，推出 DMG 后再启动。
首次因无法验证开发者或未公证而被拦截时，可在
“系统设置 → 隐私与安全性 → 仍要打开”确认，然后在弹窗中点击“打开”。
无需关闭 Gatekeeper。

辅助功能和输入监控权限需按应用内提示授予；更新后可能需要重新添加权限条目。
