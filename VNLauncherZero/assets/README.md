# App Icon Assets

- `VNLauncherZero.icns` 会在执行 `scripts/generate_app_icon.sh` 时自动生成。
- `scripts/build_release_app.sh` 会在打包时自动尝试生成并注入图标。
- 如果你想用自己的图片作为 App Logo，请保存为 `assets/custom-logo.png`（建议 1024x1024 PNG）。

如果你想自定义图标：
1. 准备一个 `1024x1024` 的 PNG
2. 保存为 `assets/custom-logo.png`
3. 运行 `./scripts/build_release_app.sh`（会自动生成并注入 `.icns`）
