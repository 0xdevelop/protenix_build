# protenix_build

第一阶段骨架：`build_srcs` 下以 submodule 接入上游源码。

- `build_srcs/protenix` → `git@github.com:bytedance/Protenix.git`
- `build_srcs/pxdesign` → `git@github.com:bytedance/PXDesign.git`

```bash
git submodule update --init --recursive
```
