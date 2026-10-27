# xboot

Dock app：每行一个 target，点 Run 就在模拟器或本机跑起来，不打开 Xcode。

```sh
make test && make   # 构建 + 测试
```

## 约束

- 不写入被运行项目的目录。`mobilebuildmcp setup` 会写 `.mobilebuildmcp/config.yaml`，禁止调用。
- 不引入 `.xcodeproj`；构建链就是 Makefile + clang。

## 发版

1. 改 `Resources/Info.plist` 的 `CFBundleShortVersionString` 和 `CFBundleVersion`（必须与 tag 一致）。
2. `make test && make`。
3. 提交 → `git tag -a vX.Y.Z -m "xboot X.Y.Z"` → push 两者。
4. 等 CI，下载产物验证：`spctl -a -vvv --type exec xboot.app` 必须 `accepted`；`codesign -dv` 必须有 `Developer ID` 和 `runtime`。

## 禁止

- 不重打已发布的 tag（SHA256 会变）。要修就发新 patch 版本。
- 不删 CI 的 `Verify signature` 步骤；`staple` 失败必须致命。
- CI 是 Xcode 16.4，本机是 27——别用只有新 SDK 才有的 API。
