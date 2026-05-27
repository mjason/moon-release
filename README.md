# Moon

针对 A 股的量化交易实盘管理程序。用 Elixir + Phoenix + Ash 监控 Python 策略进程，统一管理 fusion 选股 / 择时、rocket 实盘下单、QMT 实时行情。

本仓库**只发布二进制 release**和安装脚本；源码在私有仓库。

---

## 安装

目前仅支持 **macOS (Apple Silicon / Intel)**。

```bash
curl -fsSL https://raw.githubusercontent.com/mjason/moon-release/main/install.sh | bash
```

脚本会：

- 拉取最新 release，解压到 `~/.moon/`
- 首次运行时生成配置文件 `~/.moon/env`
- 生成启动脚本 `~/.moon/run`

> 默认安装目录是 `~/.moon`，可用环境变量 `MOON_INSTALL_DIR` 覆盖。

---

## 配置

### 1. 编辑 `~/.moon/env`

```bash
$EDITOR ~/.moon/env
```

| 字段 | 是否必填 | 说明 |
|---|---|---|
| `PYTHON_PROJECT_DIR` | **必填** | Python 项目根目录，必须含 `.venv`（fusion / rocket 等内核位置）|
| `DATABASE_PATH` | 默认 | Moon 自己的 SQLite 数据库（存所有 Ash 配置），升级时保留 |
| `SECRET_KEY_BASE` | 自动 | 首次安装自动生成，无需改动 |
| `PORT` | 默认 `4000` | Web UI 监听端口 |
| `PHX_HOST` | 默认 `localhost` | 主机名 |

### 2. 启动

```bash
~/.moon/run
```

打开 [http://localhost:4000](http://localhost:4000)。

第一次进去先去 sidebar **数据中心 → 配置**填好下面这些。

---

## 数据中心配置详解

Moon 通过 sidebar **数据中心 → 配置** 接 Go exodia 数据中心，所有字段都从这一页填。

### 准备工作

数据中心目录的物理结构（自己提前建好）：

```
<数据目录>/                    # 你在 UI 里填的「数据目录」字段
├── code/
│   ├── exodia                # Go exodia 二进制（自己从 fhy/exodia 拿）
│   └── data/                 # 数据中心运行时数据，exodia 自动维护
│       ├── products-status.json
│       └── FuelBinStat.db    # 实时行情 SQLite（min_data / fuzzy）
├── stock-1h-trading-data-pro/   # 订阅的产品目录，exodia 增量更新
├── stock-trading-data-pro/
└── ...
```

把 Go exodia 二进制放到 `<数据目录>/code/exodia` 后，moon 就能调用它跑数据更新。

### 字段说明

| 字段 | 说明 | 怎么拿 |
|---|---|---|
| **HID** | 硬件 ID（数据源鉴权用）| 数据源服务商提供 |
| **API Key** | 数据 API 密钥 | 数据源服务商提供 |
| **数据目录** | 数据中心根目录（绝对路径） | 你自己创建，比如 `/Users/you/data_center` |
| **订阅产品** | 要下载的数据产品列表 | 保存 HID + API Key 后页面会拉远端 product list 让你勾选 |
| **QMT Proxy 地址** | 实时行情接入地址 | 若使用 min_data / min_data_fuzzy，部署 [qmt_proxy](https://github.com/quant-on-quest/qmt_proxy) 后填它的 HTTP 地址（如 `http://192.168.1.10:9011`）；不用实时行情可留空 |

保存后 moon 会做两件事：

1. 把字段写到 `<数据目录>/code/config.json`（Go exodia 启动时读它）
2. 异步触发一次 `exodia init` 让数据中心初始化产品状态

### 触发数据更新

保存配置后，sidebar **数据中心 → 数据更新** 页面：

- **启动**按钮：手动跑一次 `exodia all_data`（全量增量更新所有订阅产品）
- 实时日志看进度
- 自动调度由 **调度配置**控制（见下）

### QMT 实时数据（可选）

只有在 **QMT Proxy 地址**填好之后才能用。两个独立通道：

| 入口 | 命令 | 用途 |
|---|---|---|
| sidebar **数据中心 → 准确 QMT** | `exodia min_data` | 按 5 分钟 K 线对齐的增量行情，写 SQLite `min_data` 表 |
| sidebar **数据中心 → 模糊 QMT** | `exodia min_data_fuzzy` | 任意时刻全市场 tick 快照（含五档买卖盘），写 SQLite `min_data_fuzzy` 表 |

两者各有暂停/恢复自动调度的按钮，状态持久化。

### 实时数据仪表盘

sidebar **数据中心 → 实时数据**：展示两个通道的最近运行历史、最新数据样本、累计行数。数据 5 分钟刷新一次（事件驱动 + 60s 兜底）。

---

## Fusion 配置（选股 / 择时 / 回测）

sidebar **Fusion → 配置**：

| 字段 | 说明 |
|---|---|
| 起始日期 / 结束日期 | 回测起止 |
| 初始资金 | 回测仓位规模 |
| 数据路径 | 一般跟数据中心的「数据目录」一致 |
| 过滤北交所 / 科创板 / 创业板 | 选股池过滤开关 |
| 性能模式 | `MAX` / `EQUAL` / `ECONOMY`，控制 CPU 占用 |
| 策略代码 | Python 写的 strategies 配置（单 master + strategy_pool 结构）|

保存时 moon 会渲染出 `<PYTHON_PROJECT_DIR>/fusion/config.json` + `<PYTHON_PROJECT_DIR>/fusion/strategies.py`，供 fusion 内核读取。

---

## Rocket 配置（实盘下单）

sidebar **Rocket → 配置**：

| 字段 | 说明 |
|---|---|
| QMT Endpoint | QMT HTTP API 地址（下单用）|
| QMT Data Endpoint | QMT 数据 API 地址，留空则同 QMT Endpoint |
| 企业微信机器人 | info / warning / news 三档 webhook，可选 |
| Framework Root Path | fusion 框架根路径 |
| 委托次数限制 | 单股委托上限，默认 50 |
| 同消息间隔 | 重复消息冷却秒数 |
| 仓位控制 | 整体仓位比例 0~1 |
| 加载前缀时间 | 策略卖出前几分钟开始加载 |
| 逆回购保留 | 保留给打新的金额 |

保存时渲染 `<PYTHON_PROJECT_DIR>/rocket/config.json`。

---

## 调度配置

sidebar **其他配置 → 调度配置**，控制各任务自动启动时机：

| 字段 | 含义 |
|---|---|
| 实盘选股时间 | 一天多个时间点，每个时间到达且非交易日跳过 |
| Rocket 启动时间 | 每日一次 |
| 盘中择时开始时间 | 之后每 60s 检查触发 |
| 全局退出时间 | 到点 stop 所有运行中任务 |
| Exodia 下载时间 | 每日多个时间点（不限交易日），失败自动重试 3 次 |
| 准确 QMT 拉取间隔 | 分钟级（交易时段内） |
| 模糊 QMT 拉取间隔 | 分钟级（交易时段内） |
| 盘中择时自动调度 | 暂停按钮的持久状态 |

调度器每 30 秒 tick，按以上配置触发。

---

## 升级

重跑同样命令：

```bash
curl -fsSL https://raw.githubusercontent.com/mjason/moon-release/main/install.sh | bash
```

只替换 release 文件（`bin/` / `lib/` / `releases/` / `erts-*`），**保留** `env` 配置和 SQLite 数据库，可放心升级。

---

## 卸载 / 备份

```bash
# 备份配置和数据
tar czf moon-backup-$(date +%F).tar.gz -C ~/.moon env moon.db

# 卸载
rm -rf ~/.moon
```

---

## FAQ

**Q: PYTHON_PROJECT_DIR 是什么？**
A: 含 `.venv` 的 Python 项目根目录，里面要有 `fusion/`、`rocket/` 子目录和 `launcher.py`。Moon 通过它启动各 Python 内核。

**Q: 数据目录和 PYTHON_PROJECT_DIR 是同一个吗？**
A: 不是。数据目录是 exodia 数据落地的地方，PYTHON_PROJECT_DIR 是 fusion / rocket Python 源码所在。可以放在不同位置。

**Q: 启动报 "PYTHON_PROJECT_DIR environment variable is not set"？**
A: `~/.moon/env` 里这个字段必须填实际路径。

**Q: 实时行情拉不到数据？**
A: 检查 QMT Proxy 地址是否可达，且 qmt_proxy 服务确实连上了 QMT 客户端。盘中数据只在 9:30-11:30 / 13:00-15:00 内拉取。

**Q: 怎么暂停某个自动任务？**
A: 对应 home 页面顶部有「暂停自动调度」按钮，持久化保存（重启服务依然有效）。

---

## 兼容性

- macOS Apple Silicon (arm64) / Intel (x86_64)
- Erlang/OTP 27+（release 自带）
- 暂不支持 Linux / Windows
