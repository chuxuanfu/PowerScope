# PowerScope

本地原生 macOS 功率监测应用。无网络请求、无第三方运行时、无需管理员密码。适用于 Apple Silicon Mac，最低 macOS 14；本次在当前这台 Mac 上构建和验证。

## 使用

双击 `PowerScope.app`。菜单栏直接显示整机实时功率（如 `18.6 W`），无需点击。详细窗口展示实时功率、供电流向、历史曲线和累计耗电。关闭详细窗口后仍在菜单栏监测，退出应用才停止。可以将应用拖入“应用程序”文件夹，但无需安装后台服务。

点击“显示设置”，分别选择每个指标的读数卡片和曲线是否显示，也可以隐藏电源流向、趋势图、累计用电，选择在菜单栏整机瓦数后附加一个指标，并设置 1 / 2 / 5 / 10 秒读取间隔。首次启动或从旧版升级后默认每秒采样一次。设置自动保存在本机。曲线支持最近 1 / 5 / 15 / 60 分钟和悬停查看；导出按钮输出已记录的功率历史 CSV。

## 每个数字是什么

| 指标 | 数据来源和边界 |
| --- | --- |
| 整机功率 | 优先读取 AppleSMC 的 PSTR（W）。该通道不可用时读取 AppleSmartBattery 的 SystemLoad（mW 换算成 W）。整机功率反映机内负载，包含内置屏幕等，不含充电器外部损耗，也不含给电池充电的功率。 |
| 充电器输入 | SystemPowerIn，进入 Mac 的实际直流输入功率；不是适配器标称瓦数，也不是插座电表读数。 |
| 电池供电 / 充电 | BatteryPower 的负向 / 正向部分，正确处理无符号 64 位值编码的负数；零和不可用严格区分。 |
| 芯片热功率估算 | SMC PHPC，SoC 散热模型估算。不是 CPU 单独功率，也不是已验证的完整芯片电源轨功率。 |
| CPU / GPU / ANE | 可用时由 IOReport 能量计数器差分得到的功率估计；缺失或已知不更新的通道不显示为零。 |
| 屏幕背光 | SMC PDBR / PBwo 背光通道。它不代表完整显示子系统，不用“整机减芯片”冒充屏幕功耗。 |

供电关系为：充电器输入 + 电池供电 ≈ 整机功率 + 电池充电。不同传感器和模型可能有不同采样区间；不可将芯片热功率、CPU、GPU、背光等重复相加，也不保证这些局部项目能完整分解整机读数。

硬件接口不是 Apple 稳定的公开功耗 API。不同 Mac 和 macOS 版本的传感器、语义与可用性可能不同。不可用显示“—”，不生成演示数据或填零。应用每次采样都重新读取 PSTR。备用的 SystemLoad、充电器输入和电池功率取自较慢的电池遥测，同一读数可能持续数十秒。

## 累计耗电

W 表示当前功率；Wh 表示累计能量。应用对有效功率采样使用梯形积分，同时单独累计整机耗电、充电器输入、电池放电和电池充电。充放电跨越零点时分别积分，避免相互抵消或重复计算。

只统计实际监测覆盖的时间：暂停、睡眠、退出和超过 30 秒的断采不补算。固件两次刷新之间，按最近的有效功率读数近似积分；电池遥测超过 120 秒未更新时暂停使用该来源，有效的 PSTR 读数仍计入整机耗电。重新打开后保留此前累计值，并从新的采样区间开始。累计数据是基于内部遥测的估计，不能作为插座电量或电费计量依据。

历史和设置保存在 `~/Library/Application Support/PowerScope/state.json`。历史保留最近 24 小时、最多 18,000 个样本；累计能量保留至手动重置。重置只清除累计账本，历史曲线仍保留。应用没有网络功能、开机启动项或常驻特权服务。

## 从源码构建

需要已安装 Xcode 或兼容的 Apple Swift 工具链。运行：

```sh
zsh build.sh /Applications/PowerScope.app
```

产物使用本机 ad-hoc 签名，仅供本机使用，未作 Apple 开发者公证。源码包含完整原生界面、传感器读取器和独立能量积分测试。

运行计算测试：

```sh
xcrun swiftc -module-cache-path .build/module-cache Sources/EnergyAccounting.swift Tests/EnergyAccountingTests.swift -o .build/EnergyTests
.build/EnergyTests
```

## 传感器定义参考

源代码和传感器名称的参考：

- [Asahi Linux macsmc hwmon 驱动：PHPC 的热功率估算含义](https://github.com/AsahiLinux/linux/blob/asahi/drivers/hwmon/macsmc-hwmon.c)
- [Asahi 笔记本传感器定义](https://github.com/AsahiLinux/linux/blob/asahi/arch/arm64/boot/dts/apple/hwmon-laptop.dtsi)
- [Stats 传感器名称](https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift)
- [macpow 背光通道实现](https://github.com/k06a/macpow/blob/main/src/metrics.rs)

这些参考不构成 Apple 对私有传感器接口的准确度或兼容性承诺。
