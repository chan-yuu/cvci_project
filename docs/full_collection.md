# 全量数据采集说明

本文汇总本仓库（LEAD / `cvci_project`）全量 expert 采集的路线规模、采集器、环境、资源和操作方式。更细的传感器改装见 [data_generation.md](data_generation.md)，读数据见 [data_access.md](data_access.md)。

## 采集什么、用什么采

| 项目 | 内容 |
|---|---|
| 采集器 | LEAD **Expert**（特权规则专家，不是学习策略） |
| 入口 | `python -m lead --expert --routes <一条 XML>` |
| 集群入口 | `python scripts/slurm/collect_data.py`（默认扫全部 `data_routes`） |
| 模拟器 | **CARLA 0.9.16**（数据采集必须 0.9.16；0.9.15 只够评测） |
| Leaderboard | `3rd_party/leaderboard/expert/`（autopilot / 本地 evaluator） |
| 输出格式 | **py123d / 123D**，每种模态一个 `.arrow`，另有 `sync.arrow` |

Expert 在同步模式下开全传感器（6 路环视 RGB + depth + semantic + instance、双雷达/双 LiDAR、4 雷达、IMU/GPS/速度），并同时写一份扰动视角（`perturbated_view`）。

图像/点云仍是压缩载荷：RGB=JPEG，depth/semantic/instance=PNG，LiDAR=LAZ，状态和框是 Arrow 表。容器一律是 Arrow。

官方发布数据集约 **1 TB**、8,930 条路线。单机全量不现实，按集群并行设计。

## 路线规模

路线 XML 在 `src/lead/routes/data_routes/`。每个 XML 恰好 1 条 `<route>`，SLURM 一文件一作业。

`collect_data.py` 默认递归扫描该目录，并排除黑名单场景 `YieldToEmergencyVehicle`（`unused/`）。

| 集合 | 条数 | 说明 |
|---|---|---|
| `lead/` | 3,364 | 主集，覆盖 12 个城镇 |
| `50x38_Town12/` | 1,850 | 全部 Town12 |
| `50x36_Town13/` | 1,750 | 全部 Town13 |
| `leaderboard1/` | 2,780 | Town01–07、Town10HD |
| `unused/` | 100 | 急救车让行，**默认不采** |
| **默认全量（去掉 unused）** | **9,744** | 直接跑采集器就是这个数 |

README 对外写的是 **8,930 条 / 43 种场景 / 12 张地图**。和仓库 9,744 的差约 814 条，主要是 `lead/noScenarios`（806，含试采用的 `short_route.xml`）这类无场景路段；发布集做过过滤。场景文件夹名去重后是 43 种，和 README 一致。

`lead/` 按城镇大约：Town15 1028、Town12 582、Town13 487、Town06 305、Town05 230、Town03 185、Town04 178、Town10HD 143、Town07 136、Town01 54、Town02 29、Town11 7。

评测路线在 `src/lead/routes/benchmark_routes/`（Bench2Drive 220、Fail2Drive 200、Longest6 36、Town13 20），**不是采集集**。

## 本机环境（已配好）

| 项目 | 值 |
|---|---|
| 仓库 | `/vepfs-mlp2/xts001/400122/project/cvci_project` |
| Conda 环境名 | `cvci_project`（Python 3.10） |
| 关键包 | `lead`、`carla==0.9.16`、`torch==2.8.0+cu128`、`py123d` |
| CARLA | `3rd_party/CARLA/standard_0916`（含 Additional Maps / Town11–15） |
| 启动用户 | **必须普通用户 `cyun`**（Unreal 拒绝 root；`scripts/cli/start_carla` 会自动切过去） |
| 无头显示 | Xvfb `:1`（`DISPLAY=:1`） |
| 本机 GPU | 1× NVIDIA A100-SXM4-80GB |

`.env` 关键路径：

```
CARLA_ROOT=.../3rd_party/CARLA/standard_0916
PY123D_DATA_ROOT=.../data/lead/123D
LEAD_OUTPUT_DIR_ROOT=.../outputs
LEADERBOARD_ROOT=.../3rd_party/leaderboard/expert/leaderboard
SCENARIO_RUNNER_ROOT=.../3rd_party/leaderboard/expert/scenario_runner
```

共享的 `project/.envrc` 里可能还写着旧项目的 `CARLA_ROOT`（0.9.15）。采本仓库数据时以本仓库 `.env` 为准，或先 `unset CARLA_ROOT`。`start_carla` 已强制读本仓库 `.env`。

Fail2Drive 专用 0.9.15 模拟器未安装；不影响 0.9.16 采集和 Bench2Drive / Town13 / Longest6 评测。

## 资源需求

官方单条作业（`.env` 默认，面向他们的 1080 Ti 集群）：

| 项 | 默认 | 说明 |
|---|---|---|
| GPU | `gpu:1080ti:1` | 一条路线一台 CARLA，占一张卡 |
| CPU | 2 | `COLLECT_DATA_CPUS_PER_TASK` |
| 内存 | 40 GB | `COLLECT_DATA_MEM` |
| 墙钟 | 300 分钟 | `COLLECT_DATA_TIMEOUT`（单条上限） |
| 并行作业 | 80 | `COLLECT_DATA_MAX_NUM_PARALLEL_JOBS` |
| 失败重试 | 2 | `COLLECT_DATA_MAX_NUM_ATTEMPTS` |
| CARLA 启动 | 60s × 5 次 | 端口冲突会换端口重试 |

官方说法：全量在 **64× GTX 1080 Ti** 上不到一天。Expert 在 1080 Ti + 2 CPU 上大约 **10 steps/s**。

本机只有 **1× A100**。试采 `short_route.xml`（Town01，两个路点）约 37s 墙钟、~100 步、12 MB。真实场景路线通常数分钟到十几分钟。按 9,744 条、平均 3–8 分钟粗算：

- 1 张卡：大约 **20–50 天**
- 存储：官方全集约 1 TB；本机全量同量级，另加 perturbated 视角

单卡适合抽样。要尽快采完 `lead/` 的 3364 条，见下面「8 卡加速采集」。

## 输出布局

```
data/lead/123D/                  # PY123D_DATA_ROOT
├── logs/
│   ├── normal_view/<ScenarioType>/<log_name>/*.arrow
│   └── perturbated_view/<ScenarioType>/<log_name>/*.arrow
├── maps/carla/carla_<town>.arrow
└── results/<ScenarioType>/<stem>_result.json
```

`log_name` 形如 `Town01_Rep-1_short_route_route0_08_25_15_24_00`。

已完成判定：对应 result JSON 里 run 已结束且 `score_route > 0`。再跑 `collect_data.py` 只会补缺。

试采样例：

```
data/lead/123D/logs/normal_view/noScenarios/Town01_Rep-1_short_route_route0_08_25_15_24_00/
```

## 怎么跑

### 1. 本机单条（调试 / 抽样）

用 **cyun** 登录，不要 root 直接跑 `CarlaUE4.sh`。

```bash
conda activate cvci_project
cd /vepfs-mlp2/xts001/400122/project/cvci_project

# 终端 1：启动 CARLA（已在跑可跳过）
scripts/cli/start_carla          # 默认端口 2000

# 终端 2：采一条
unset CARLA_ROOT                 # 避免 .envrc 里的 0.9.15 覆盖
python -m lead --expert \
  --routes src/lead/routes/data_routes/lead/Accident/route_001761.xml \
  --port 2000 \
  --timeout 600
```

最短冒烟：

```bash
python -m lead --expert \
  --routes src/lead/routes/data_routes/lead/noScenarios/short_route.xml \
  --port 2000
```

停 CARLA：`scripts/cli/clean_carla`。

### 2. 子集（推荐本机）

不要扫整个 `data_routes`。例如只采主集或一种场景：

```bash
# 只列出某场景
ls src/lead/routes/data_routes/lead/Accident/*.xml | wc -l   # 97

# 循环采（CARLA 保持一个进程即可）
for r in src/lead/routes/data_routes/lead/Accident/*.xml; do
  python -m lead --expert --routes "$r" --port 2000 --timeout 600
done
```

改 `collect_data.py` 的 `town_white_list` / `scenario_white_lists` / `--route_folder` 也能限制范围，例如：

```bash
python scripts/slurm/collect_data.py \
  --route_folder src/lead/routes/data_routes/lead/Accident
```

本机没有可用的 SLURM 队列时，不要按官方 `gpu:1080ti` 去提交。

### 3. 集群全量

1. 把 `.env` 里 `COLLECT_DATA_PARTITION` / `COLLECT_DATA_GRES` 改成集群真实分区和 GPU 型号。
2. `conda activate cvci_project`
3. `python scripts/slurm/collect_data.py`

每条 XML 一个作业、私有 CARLA 实例。并行数由 `COLLECT_DATA_MAX_NUM_PARALLEL_JOBS` 控制。失败会按 `COLLECT_DATA_MAX_NUM_ATTEMPTS` 重试；已成功的 result 会跳过。

## 传感器与配置落盘

默认六路 384×384 FOV 60° 环视、双 LiDAR、四雷达。改 rig 见 `src/lead/config/expert/sensor_rig_config.py`，或：

```bash
export LEAD_CONFIG="expert.sensor_rig.use_radars=false"
```

训练会读 `<PY123D_DATA_ROOT>/config.yaml`。SLURM 采集器会自动写；本机批量采完后应自行落盘（见 [data_generation.md](data_generation.md)）。

## 8 卡加速采完 `lead/`（3364 条）

目标：尽快采完主集。本机当前 `nvidia-smi` 只看到 **1× A100**；最多可申请 **8× 80GB**。这台环境 **没有 SLURM**（无 `sbatch`），官方 `collect_data.py` 不能直接提交，需要本地多卡调度。

### 单条多重、总时间

试采短路线：墙钟约 37s，CARLA 显存约 **6–7 GB**（Town01 + 全传感器）。  
`lead/` XML 大多只有 2 个路点，expert 会插成上千个点，时间主要看场景和换图。

| 类型 | 粗估墙钟（含起 CARLA） |
|---|---|
| `noScenarios` / 很短路 | 1–2 分钟 |
| 路口、事故、施工等（大多数） | 3–8 分钟 |
| Town12/13/15 + 复杂流量 | 8–15 分钟 |

按 **平均 5 分钟/条**（每条重启 CARLA）：

`3364 × 5 min ≈ 280 小时 ≈ 11.7 天`（1 卡串行）

A100 80GB 远大于 CARLA 所需（Town15 估 8–15 GB）。瓶颈是 GPU 时间和稳定性，不是显存装不下。官方按 **一路线一 CARLA 一卡**（1080 Ti 11GB）设计。

### 怎么加卡

| 方案 | 并行 | 估时（5 min/条） | 风险 |
|---|---|---|---|
| **A. 一卡一个 CARLA（推荐先跑）** | 8 | **约 35 小时（1.5 天）** | 低 |
| B. 一卡两个 CARLA | 16 | 纸面 ~18 小时，实际常 22–28 小时 | 中：抢 GPU、Vulkan 偶发挂 |
| C. 一卡三个及以上 | 24+ | 收益变小 | 高：大图更容易 OOM/卡死 |

两个实例打同一张卡，帧率会掉，总吞吐往往到不了 2 倍。

**尽快采完：申请 8 卡节点，先按方案 A。** 跑稳 50–100 条（含 Town12/13/15）后再考虑每卡 2 个。

| 可用卡数 | 并行（一卡一实例） | 大约墙钟 |
|---|---|---|
| 1 | 1 | ~12 天 |
| 4 | 4 | ~3 天 |
| **8** | **8** | **~1.5 天** |
| 8（每卡 2 个，理想） | 16 | ~18–24 小时 |

若平均其实是 8 分钟，8 卡大约 **2.5 天**。同城复用 CARLA 可能再快 20–30%，但换城必须重启。

单卡配套（8 并行合计）：

- CPU：每实例 2–4 核 → 一共 16–32 核
- 内存：每实例 16–40 GB → 一共 128–320 GB
- 磁盘：`lead/` 大约全集的 1/3，预留 **300–500 GB**
- 端口：每个 CARLA 要 world + streaming + Traffic Manager，必须随机端口

### 失败自动 resume / 重启 CARLA

官方 `collect_data.py` 已有这些逻辑，本地调度应对齐：

1. **按路线 resume**：`results/<场景>/<stem>_result.json` 里 run 完成且 `score_route > 0` 就跳过。调度器挂了再拉起来只扫 result，接着跑（幂等）。
2. **必须重跑的状态**：`Started`、`Failed`、`Failed - Agent couldn't be set up`、`Failed - Simulation crashed`、`Failed - Agent crashed`，或 `score_route ≈ 0`。
3. **CARLA 启动失败**：换端口重试，最多 5 次（`COLLECT_DATA_CARLA_BOOT_ATTEMPTS`）。
4. **整条作业失败**：最多再提 2 次（`COLLECT_DATA_MAX_NUM_ATTEMPTS`）。
5. **每条单独起/杀 CARLA**（官方 e2e 也是这样），避免上一张大图把下一张弄脏。

本地 8 卡调度应做成：

- 8 个 worker，各绑一张卡（`CUDA_VISIBLE_DEVICES` + `-graphicsadapter=0`）
- 队列是 3364 个 XML；已有成功 result 的跳过
- 每条：起 CARLA → 等 RPC → 跑 expert → 杀掉 CARLA
- 起不来或中途断连：杀进程、换端口、重试 2–3 次
- 路线失败（超时、分数为 0）：重入队，上限 2 次

当前没有 SLURM，**不要**用 `collect_data.py` 直接 `sbatch`。需要一个本机多进程脚本实现上面这条循环。

### Expert 靠不靠得住

Expert 是特权规则专家（看真值：他车、红绿灯、路线），官方 8,930 条发布数据就是它采的，**大多数路线能跑完**。本机 `short_route` 已是 RouteCompletion 100%。

但不是 3364 条都保证一次成功：

- CARLA / Vulkan / 换大图会偶发崩，这是模拟器问题，不是专家逻辑坏了。
- 复杂流量（Town12/13/15、对向两车、汇入）会有超时、堵死、极低 `score_route`。
- 官方才要 result 检查和最多 2 次重提。
- `YieldToEmergencyVehicle` 被黑名单，就是专家/场景不稳定。
- 少数 XML 路点数为 0，可能更脆。

预期：**大部分一次过，一小部分要靠 resume 重试，极少数两次仍失败可先跳过再人工看。**  
不要假设 3364 条零失败；调度必须按 result 补采，否则无法「尽快采完」。

## 单卡 4×CARLA 实测（2026-08-25）

探测输出在 `outputs/density_probe/`，**不进**正式 `data/lead/123D/`。看进度（不必干等）：

```bash
watch -n 5 scripts/local/probe_status.sh
# 或只盯一路
tail -f outputs/density_probe/town15_s_stagger_w0.log | grep Step
```

| 路线 | 1 卡 1 CARLA | 1 卡 4 CARLA 同时采同一条 | 说明 |
|---|---|---|---|
| Town01 `short_route` | 试采 **37s** 墙钟 / 约 100 步 / 12 MB | 成功的 worker **33–38s** 墙钟（游戏时间 4.9–5.3s） | 太短，4 路几乎不比 1 路慢；吞吐≈成功路数倍 |
| Town05 Accident `route_001761` | 本机未单独再跑 1 路对照 | 成功 2 路：**6.0–6.2 min** 墙钟 / 游戏 38s / 约 110 MB | 另 1 路 TM 端口冲突没启动，1 路 RPC 超时 |
| Town15 `route_000643` | 未跑 1 路对照 | **4/4 完成**，墙钟 **8.2–8.5 min**（游戏 57–61s），RouteCompletion 100% | 约 1135–1221 步；数据在 `outputs/density_probe/data/town15_s_stagger_w*` |

4 路同时采时，单步大约 **200–300 ms**（官方 1080 Ti 约 100 ms/step）。短路的墙钟被启动开销吃掉，看不出变慢；Town05 这种真实路线，4 路并行的墙钟仍是分钟级，但一次出 2–4 份。

**数据在哪**

```
outputs/density_probe/data/<wave>_w<0-3>/logs/{normal,perturbated}_view/...
outputs/density_probe/<wave>_w<0-3>.log          # 每步 Step / Time per step
outputs/density_probe/gpu_samples.csv
```

目录体积在涨就说明在采。`RouteCompletionTest 100%` 出现在对应 `.log` 末尾即该路完成。

**资源（4 个 CARLA + 4 个 expert）**

| 项 | 实测 | 机器上限 | 结论 |
|---|---|---|---|
| GPU 显存 | 空载 4 实例 **~25 GB**，采集中 **23–28 GB** | 80 GB | 远没用满，显存不是瓶颈 |
| GPU 利用率 | 采集中常见 **15–60%**，尖峰 ~80% | 100% | 也没打满 |
| 功耗 | **90–140 W** | 400 W | 很空 |
| CPU | load **~60 / 112 核** | 112 | 比 GPU 更忙，但仍有余量 |
| 内存 | 机器 1.8T | — | 不是瓶颈 |

4 路能起来、能同时写 Town15，但 **GPU 远没吃满**。限制是 CARLA 同步 tick / Traffic Manager 端口，不是 80GB 装不下。正式调度必须给每路独立 `--traffic-manager-port`（evaluator 已改为尊重该参数）；4 路同时 `find_free_port` 会撞端口。

## 单卡 1 路 vs 8 路（2026-08-26 对照）

同一张 A100，先单独采，再 8 个 CARLA 同时采同一条。8/8 全部 RouteCompletion 100%。空载 8 实例显存约 **47 GB**，采完后约 **51 GB**。

| 路线 | 1 个 CARLA | 8 个同时（每路 System Time） | 8 路一批墙钟 | 相对 1 路 |
|---|---|---|---|---|
| Town01 `short_route` | **27s**（游戏 4.9s） | **96–104s** | ~3.0 min | 单份慢约 3.7 倍；一批出 8 份，吞吐约 **2 倍** |
| Town05 Accident | **279s / 4.7 min**（游戏 39s） | **803–889s / 13.4–14.8 min** | ~15.6 min | 单份慢约 3.1 倍；一批出 8 份，吞吐约 **2.4 倍** |

主日志：`outputs/density_probe/master.log`。

## 建议

1. 链路已用 `short_route` 验证通过。
2. 要尽快采完 `lead/`：申请 **8×80GB**，一卡一 CARLA，本地队列 + result resume + CARLA 崩溃重启。
3. 先用 50–100 条（含 Town12/13/15）测真实平均时长和挂掉率，再决定要不要每卡 2 个。
4. `lead/` 磁盘预留 **300–500 GB**；若继续采 Town12/13 全集再按 1 TB 打算。
5. 始终用 `cyun` + `cvci_project` + CARLA 0.9.16。
6. 不要采 `unused/YieldToEmergencyVehicle`。
7. 单卡 8 个 CARLA 能同时采完且全成功，但单条会慢 3 倍左右，吞吐大约只有 2–2.5 倍；正式采集更稳的是一卡一路，单卡多开只是在卡不够时的加速手段。



