# OpenMIPS — 五级流水线 MIPS32 处理器

> **FPGA 模型机课程设计**  
> **作者**：赵嘉阳 | 计科2303 班 | 23041091  
> **平台**：Basys3 开发板（Xilinx Artix-7 xc7a35tcpg236-1）  
> **开发环境**：Vivado（推荐 2019.1+）  
> **语言**：Verilog HDL  
> **联系**：3238924258@qq.com

---

## 目录

- [1. 项目简介](#1-项目简介)
- [2. 文件结构](#2-文件结构)
- [3. 架构设计](#3-架构设计)
- [4. 流水线详解](#4-流水线详解)
- [5. 指令集](#5-指令集)
- [6. CP0 协处理器与异常处理](#6-cp0-协处理器与异常处理)
- [7. 存储器映射](#7-存储器映射)
- [8. IO 外设](#8-io-外设)
- [9. 模块说明](#9-模块说明)
- [10. 内置测试程序](#10-内置测试程序)
- [11. 使用方法](#11-使用方法)
- [12. 设计亮点](#12-设计亮点)
- [13. 参考文献](#13-参考文献)

---

## 1. 项目简介

本项目从零实现了一款兼容 **MIPS32 指令集**的五级流水线处理器，支持 **38+ 条 MIPS 指令**（含整数运算、移位、乘除法、分支跳转、Load/Store、异常处理等），并集成了 **CP0 协处理器**、**HI/LO 乘除寄存器**、**LLbit 寄存器**（支持 LL/SC 原子操作），可在 Basys3 开发板上实际运行。

### 技术特性

| 特性 | 说明 |
|------|------|
| **流水线级数** | 5 级（IF → ID → EX → MEM → WB） |
| **指令集** | MIPS32 子集，38+ 条指令 |
| **通用寄存器** | 32 个 × 32 bit（\$0 恒为零） |
| **数据前推** | EX/MEM → ID，MEM/WB → ID |
| **流水线暂停** | Load 相关、乘除累加相关 |
| **分支处理** | 延迟槽机制（Delay Slot） |
| **异常处理** | 精确异常，支持 Syscall / Trap / ERET |
| **协处理器** | CP0（Count / Compare / Status / Cause / EPC / Config / PrId） |
| **乘除法** | 独立除法器（32 周期），MADD/MSUB 累加支持 |
| **IO 外设** | 16 路开关、5 按键、16 LED、4 位 8 段数码管 |
| **断步调试** | 支持单步执行，可实时查看寄存器和 HI/LO 值 |

---

## 2. 文件结构

```
github可复刻版/
├── README.md                              # 本文件（详细说明文档）
├── .gitignore                             # Git 忽略规则（Vivado/仿真临时文件）
├── 引脚.txt                               # 仿真波形引脚参考
│
├── src/                                   # RTL 源码（22 个模块）
│   ├── define.v                           # 全局宏定义（指令编码、ALU 操作码、数据宽度等）
│   ├── openmips.v                         # CPU 顶层模块（各阶段例化与互联）
│   ├── openmips_min_sopc.v                # 最小 SOPC 系统（CPU + ROM + RAM + IO）
│   ├── pc_reg.v                           # 程序计数器（PC）
│   ├── if_id.v                            # IF/ID 流水线寄存器
│   ├── id.v                               # 译码阶段（指令译码、寄存器读取、数据前推判断）
│   ├── id_ex.v                            # ID/EX 流水线寄存器
│   ├── ex.v                               # 执行阶段（ALU、乘除累加、Trap 判断）
│   ├── ex_mem.v                           # EX/MEM 流水线寄存器
│   ├── mem.v                              # 访存阶段（Load/Store 对齐、LL/SC、异常判断）
│   ├── mem_wb.v                           # MEM/WB 流水线寄存器
│   ├── regfile.v                          # 通用寄存器文件（32×32bit，\$0 硬连线为 0）
│   ├── ctrl.v                             # 流水线控制器（stall/flush/new_pc 生成）
│   ├── div.v                              # 独立除法器（32 周期迭代除法）
│   ├── hilo_reg.v                         # HI/LO 寄存器（乘除法结果存储）
│   ├── LLbit_reg.v                        # LLbit 寄存器（LL/SC 原子操作支持）
│   ├── cp0_reg.v                          # CP0 协处理器（Count/Compare/Status/Cause/EPC 等）
│   ├── inst_rom.v                         # 指令 ROM（含内置 MIPS 测试程序）
│   ├── data_ram.v                         # 数据 RAM（1024×32bit）
│   ├── io.v                               # IO 外设控制器（开关/LED/数码管/按键/时钟分频）
│   ├── clk_div.v                          # 时钟分频器
│   └── mioc.v                             # 存储器 IO 地址译码器（备用模块）
│
├── tb/                                    # 仿真测试平台（3 个）
│   ├── openmips_min_sopc_tb.v             # 基本功能仿真
│   ├── tb_hard.v                          # 硬件仿真（断步调试测试）
│   └── tb_hardv2.v                        # 硬件仿真 v2（简化版）
│
├── constraints/                           # XDC 约束文件（2 个）
│   ├── basys3_constraints.xdc             # Basys3 完整引脚约束 ★ 推荐使用
│   └── opmipxdc.xdc                       # 备用约束文件
│
├── docs/                                  # 课程设计文档（3 个）
│   ├── FPGA模型机课程设计_课设报告_计科2303班_23041091_赵嘉阳.docx   # 课程设计报告
│   ├── FPGA汇报赵嘉阳.pptx                # 汇报 PPT
│   └── PPT大纲.docx                       # PPT 大纲
│
└── bitstream/                             # 比特流文件
    └── Finally.bit                        # 最终生成的 FPGA 配置文件
```

---

## 3. 架构设计

### 3.1 顶层框图

```
                        ┌──────────────────────────────────────────────┐
                        │               openmips_min_sopc              │
                        │                                              │
   sys_clk ────────────►│  ┌─────────┐   ┌──────────┐   ┌──────────┐  │
   switch_in[15:0] ────►│  │   io    │   │ inst_rom │   │ data_ram │  │
   key_in[4:0] ────────►│  │ (外设)   │   │ (指令ROM) │   │ (数据RAM) │  │
                        │  └────┬────┘   └────┬─────┘   └────┬─────┘  │
   led_out[15:0] ◄──────│       │             │               │        │
   seg_out[7:0] ◄───────│       │    ┌────────┴───────────────┘        │
   dig_out[3:0] ◄───────│       │    │                                  │
                        │  ┌────┴────┴─────┐                           │
                        │  │   openmips    │                           │
                        │  │  (CPU 内核)    │                           │
                        │  └───────────────┘                           │
                        └──────────────────────────────────────────────┘
```

### 3.2 CPU 五级流水线

```
        ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
        │    IF    │     │    ID    │     │    EX    │     │   MEM    │     │    WB    │
        │   取指   │────▶│   译码   │────▶│   执行   │────▶│   访存   │────▶│   写回   │
        └──────────┘     └──────────┘     └──────────┘     └──────────┘     └──────────┘
             │                 │                 │                 │                 │
        ┌────┴────┐      ┌────┴────┐      ┌────┴────┐      ┌────┴────┐      ┌────┴────┐
        │ pc_reg  │      │regfile  │      │ ALU     │      │data_ram │      │regfile  │
        │ inst_rom│      │ CP0读   │      │ 除法器   │      │ LLbit   │      │hilo_reg │
        └─────────┘      │ 前推判断 │      │ 乘累加   │      │ 异常判断 │      │ CP0写   │
                         │ 分支计算 │      │ HI/LO   │      └─────────┘      │ LLbit写 │
                         └─────────┘      │ Trap    │                       └─────────┘
                                          └─────────┘
```

### 3.3 数据通路

数据在流水线各阶段间通过 **流水线寄存器** 传递：

```
IF ──▶ IF/ID ──▶ ID ──▶ ID/EX ──▶ EX ──▶ EX/MEM ──▶ MEM ──▶ MEM/WB ──▶ WB
        (if_id)        (id_ex)         (ex_mem)         (mem_wb)
```

每个流水线寄存器在时钟上升沿锁存当前阶段输出，传递给下一阶段。`stall` 信号控制流水线冻结，`flush` 信号控制流水线清空（用于异常处理）。

---

## 4. 流水线详解

### 4.1 IF（取指阶段）

**模块**：`pc_reg.v` + `inst_rom.v` + `if_id.v`

- **PC 更新**：正常顺序 `PC+4`；分支跳转 `PC = branch_target`；异常 `PC = new_pc`
- **指令 ROM**：131072×32bit 容量，地址 `addr[InstMemNumLog2+1:2]` 索引
- **CE 控制**：复位时 `ce=0`，指令输出为 0
- **Stall 支持**：`stall[0]=1` 冻结 PC

### 4.2 ID（译码阶段）

**模块**：`id.v`（本项目最复杂的模块，约 800 行）

**核心功能**：
1. **指令译码**：解析 `op[31:26]`、`op2[10:6]`、`op3[5:0]`、`op4[20:16]`
2. **寄存器读取**：生成 `reg1_addr`、`reg2_addr`、读使能信号
3. **立即数生成**：支持符号扩展、零扩展、LUI 高位加载
4. **数据前推判断**：
   - EX 阶段的 Load 指令 → 插入 stall（`stallreq_for_reg1_loadrelate`）
   - EX/MEM、MEM/WB 阶段的写寄存器数据 → 直接前推使用
5. **分支处理**：
   - BEQ/BNE/BGEZ/BGTZ/BLEZ/BLTZ 分支判断
   - J/JAL/JR/JALR 跳转目标地址计算
   - 延迟槽标记（`next_inst_in_delayslot_o`）
6. **异常识别**：Syscall、无效指令检测

### 4.3 EX（执行阶段）

**模块**：`ex.v`

**核心功能**：
1. **逻辑运算**：AND/OR/XOR/NOR（组合逻辑）
2. **移位运算**：SLL/SRL/SRA（桶形移位器）
3. **算术运算**：ADD/SUB/SLT/SLTU/CLZ/CLO
4. **乘累加**：MULT/MULTU/MUL/MADD/MSUB（多周期，通过 `stallreq_for_madd_msub` 暂停）
5. **除法启动**：向除法器发送 `div_start` 信号
6. **Trap 判断**：TEQ/TGE/TLT/TNE 等条件 trap
7. **IO 地址译码**：SW/LW 的高 16 位 `0x7000` 前缀识别为 IO 访问
8. **CP0 读写**：MFC0/MTC0 指令处理
9. **访存地址计算**：`mem_addr = reg1 + imm`

### 4.4 MEM（访存阶段）

**模块**：`mem.v`

**核心功能**：
1. **Load 操作**：LB/LBU/LH/LHU/LW/LWL/LWR/LL（字节/半字/字对齐，符号/零扩展）
2. **Store 操作**：SB/SH/SW/SWL/SWR/SC（字节使能 `mem_sel_o`）
3. **LL/SC 原子操作**：通过 LLbit 寄存器实现
4. **异常传递**：检查 CP0 Status 寄存器，决定是否触发异常
5. **CP0 写传递**：将 EX 阶段的 CP0 写请求传递到 MEM/WB

### 4.5 WB（写回阶段）

**模块**：`mem_wb.v` + `regfile.v` + `hilo_reg.v` + `LLbit_reg.v` + `cp0_reg.v`

**写回目标**：
- **通用寄存器**（`regfile.v`）：32×32bit，\$0 恒为零
- **HI/LO 寄存器**（`hilo_reg.v`）：乘除法和 MFHI/MFLO 结果
- **LLbit 寄存器**（`LLbit_reg.v`）：LL/SC 原子操作的状态位
- **CP0 寄存器**（`cp0_reg.v`）：Count/Compare/Status/Cause/EPC 等

### 4.6 流水线冒险处理

#### 数据冒险（RAW Hazard）

| 场景 | 处理方式 |
|------|----------|
| EX/MEM 阶段结果被 ID 阶段需要 | **数据前推**：直接将 EX/MEM 结果旁路到 ID 输入 |
| MEM/WB 阶段结果被 ID 阶段需要 | **数据前推**：直接将 MEM/WB 结果旁路到 ID 输入 |
| EX 阶段 Load 指令的结果被 ID 下一条需要 | **流水线暂停**（stall 1 周期），然后前推 |

**前推优先级**：EX 阶段结果 > MEM 阶段结果 > 寄存器文件输出

#### 控制冒险（Branch Hazard）

- **延迟槽**：分支/跳转指令后的下一条指令**始终执行**
- JR/JALR 的寄存器值若被前一条 Load 使用 → stall 直到 Load 完成
- 分支方向在 ID 阶段决策，减少分支惩罚为 1 个延迟槽

#### 结构冒险

- 除法器（`div.v`）和乘累加单元独立于 ALU，通过 stall 机制协调
- 单端口寄存器文件：读写通过 stall 协调

### 4.7 Stall 信号编码

`stall[5:0]` 6 位信号，每位控制一个阶段：

| 位 | 控制对象 | 含义 |
|----|----------|------|
| `stall[0]` | PC | PC 不变 |
| `stall[1]` | IF/ID | IF/ID 锁存 |
| `stall[2]` | ID/EX | ID/EX 清空（插入 NOP） |
| `stall[3]` | EX/MEM | EX/MEM 锁存 |
| `stall[4]` | MEM/WB | MEM/WB 锁存 |
| `stall[5]` | - | 保留 |

常见编码：
- `6'b000000`：正常流水
- `6'b000111`：ID 阶段 stall（Load 相关）
- `6'b001111`：EX 阶段 stall（乘除累加相关）

---

## 5. 指令集

### 5.1 算术/逻辑运算（寄存器-寄存器）

| 指令 | 编码 (op[31:26] / funct[5:0]) | 功能 | 说明 |
|------|-------------------------------|------|------|
| `ADD` | `000000 / 100000` | `rd = rs + rt` | 有符号，溢出时 trap |
| `ADDU` | `000000 / 100001` | `rd = rs + rt` | 无符号，不检测溢出 |
| `SUB` | `000000 / 100010` | `rd = rs - rt` | 有符号，溢出时 trap |
| `SUBU` | `000000 / 100011` | `rd = rs - rt` | 无符号，不检测溢出 |
| `AND` | `000000 / 100100` | `rd = rs & rt` | 按位与 |
| `OR` | `000000 / 100101` | `rd = rs \| rt` | 按位或 |
| `XOR` | `000000 / 100110` | `rd = rs ^ rt` | 按位异或 |
| `NOR` | `000000 / 100111` | `rd = ~(rs \| rt)` | 按位或非 |
| `SLT` | `000000 / 101010` | `rd = (rs < rt) ? 1 : 0` | 有符号比较 |
| `SLTU` | `000000 / 101011` | `rd = (rs < rt) ? 1 : 0` | 无符号比较 |
| `CLZ` | `011100 / 100000` | `rd = count_leading_zeros(rs)` | 前导零计数 |
| `CLO` | `011100 / 100001` | `rd = count_leading_ones(rs)` | 前导一计数 |

### 5.2 算术/逻辑运算（立即数）

| 指令 | 编码 (op[31:26]) | 功能 |
|------|-----------------|------|
| `ADDI` | `001000` | `rt = rs + sign_ext(imm16)` |
| `ADDIU` | `001001` | `rt = rs + sign_ext(imm16)`（不检测溢出） |
| `ANDI` | `001100` | `rt = rs & zero_ext(imm16)` |
| `ORI` | `001101` | `rt = rs \| zero_ext(imm16)` |
| `XORI` | `001110` | `rt = rs ^ zero_ext(imm16)` |
| `LUI` | `001111` | `rt = imm16 << 16` |
| `SLTI` | `001010` | `rt = (rs < sign_ext(imm16)) ? 1 : 0` |
| `SLTIU` | `001011` | `rt = (rs < sign_ext(imm16)) ? 1 : 0`（无符号） |

### 5.3 移位指令

| 指令 | 编码 | 功能 |
|------|------|------|
| `SLL` | `000000 / 000000` | `rd = rt << sa`（逻辑左移） |
| `SLLV` | `000000 / 000100` | `rd = rt << rs[4:0]`（可变左移） |
| `SRL` | `000000 / 000010` | `rd = rt >> sa`（逻辑右移） |
| `SRLV` | `000000 / 000110` | `rd = rt >> rs[4:0]` |
| `SRA` | `000000 / 000011` | `rd = rt >>> sa`（算术右移） |
| `SRAV` | `000000 / 000111` | `rd = rt >>> rs[4:0]` |

### 5.4 移动指令

| 指令 | 编码 | 功能 |
|------|------|------|
| `MFHI` | `000000 / 010000` | `rd = HI` |
| `MTHI` | `000000 / 010001` | `HI = rs` |
| `MFLO` | `000000 / 010010` | `rd = LO` |
| `MTLO` | `000000 / 010011` | `LO = rs` |
| `MOVZ` | `000000 / 001010` | `if rt==0 then rd = rs` |
| `MOVN` | `000000 / 001011` | `if rt!=0 then rd = rs` |

### 5.5 乘除法指令

| 指令 | 编码 | 功能 |
|------|------|------|
| `MULT` | `000000 / 011000` | `{HI, LO} = rs * rt`（有符号，64 位积） |
| `MULTU` | `000000 / 011001` | `{HI, LO} = rs * rt`（无符号） |
| `MUL` | `011100 / 000010` | `rd = rs * rt`（低 32 位） |
| `MADD` | `011100 / 000000` | `{HI, LO} += rs * rt`（有符号乘加） |
| `MADDU` | `011100 / 000001` | `{HI, LO} += rs * rt`（无符号乘加） |
| `MSUB` | `011100 / 000100` | `{HI, LO} -= rs * rt`（有符号乘减） |
| `MSUBU` | `011100 / 000101` | `{HI, LO} -= rs * rt`（无符号乘减） |
| `DIV` | `000000 / 011010` | `LO=rs/rt, HI=rs%rt`（有符号） |
| `DIVU` | `000000 / 011011` | `LO=rs/rt, HI=rs%rt`（无符号） |

### 5.6 分支与跳转指令

| 指令 | 编码 | 功能 |
|------|------|------|
| `J` | `000010` | `PC = {PC[31:28], target<<2}` |
| `JAL` | `000011` | `$31 = PC+8; PC = {PC[31:28], target<<2}` |
| `JR` | `000000 / 001000` | `PC = rs` |
| `JALR` | `000000 / 001001` | `rd = PC+8; PC = rs` |
| `BEQ` | `000100` | `if rs==rt then PC += offset<<2` |
| `BNE` | `000101` | `if rs!=rt then PC += offset<<2` |
| `BGEZ` | `000001 / 00001` | `if rs>=0 then PC += offset<<2` |
| `BGEZAL` | `000001 / 10001` | `$31=PC+8; if rs>=0 then PC += offset<<2` |
| `BGTZ` | `000111` | `if rs>0 then PC += offset<<2` |
| `BLEZ` | `000110` | `if rs<=0 then PC += offset<<2` |
| `BLTZ` | `000001 / 00000` | `if rs<0 then PC += offset<<2` |
| `BLTZAL` | `000001 / 10000` | `$31=PC+8; if rs<0 then PC += offset<<2` |

### 5.7 存取指令

| 指令 | 编码 | 功能 |
|------|------|------|
| `LB` | `100000` | `rt = sign_ext(M[rs+offset][7:0])` |
| `LBU` | `100100` | `rt = zero_ext(M[rs+offset][7:0])` |
| `LH` | `100001` | `rt = sign_ext(M[rs+offset][15:0])` |
| `LHU` | `100101` | `rt = zero_ext(M[rs+offset][15:0])` |
| `LW` | `100011` | `rt = M[rs+offset]` |
| `LWL` | `100010` | 左半字加载 |
| `LWR` | `100110` | 右半字加载 |
| `LL` | `110000` | Load Linked（原子操作） |
| `SB` | `101000` | `M[rs+offset][7:0] = rt[7:0]` |
| `SH` | `101001` | `M[rs+offset][15:0] = rt[15:0]` |
| `SW` | `101011` | `M[rs+offset] = rt` |
| `SWL` | `101010` | 左半字存储 |
| `SWR` | `101110` | 右半字存储 |
| `SC` | `111000` | Store Conditional（原子操作） |

### 5.8 异常/系统指令

| 指令 | 编码 | 功能 |
|------|------|------|
| `SYSCALL` | `000000 / 001100` | 系统调用异常 |
| `ERET` | `010000_1_000000000000000000_011000` | 异常返回 |
| `TEQ` | `000000 / 110100` | `if rs==rt then Trap` |
| `TGE` | `000000 / 110000` | `if rs>=rt then Trap` |
| `TGEU` | `000000 / 110001` | `if rs>=rt then Trap`（无符号） |
| `TLT` | `000000 / 110010` | `if rs<rt then Trap` |
| `TLTU` | `000000 / 110011` | `if rs<rt then Trap`（无符号） |
| `TNE` | `000000 / 110110` | `if rs!=rt then Trap` |

---

## 6. CP0 协处理器与异常处理

### 6.1 CP0 寄存器

| 寄存器号 | 名称 | 功能 |
|----------|------|------|
| `CP0_REG_COUNT` (9) | Count | 自增计数器，每个时钟周期 +1 |
| `CP0_REG_COMPARE` (11) | Compare | 与 Count 比较，相等时触发定时中断 |
| `CP0_REG_STATUS` (12) | Status | 中断使能（IE）、异常级别（EXL）等状态位 |
| `CP0_REG_CAUSE` (13) | Cause | 异常原因码（ExcCode）、中断引脚状态（IP） |
| `CP0_REG_EPC` (14) | EPC | 异常返回地址（Exception PC） |
| `CP0_REG_PrId` (15) | Processor ID | 处理器标识 |
| `CP0_REG_CONFIG` (16) | Config | 配置寄存器（Endianness、MMU 类型等） |

### 6.2 异常类型与入口

| 异常码 | 类型 | 入口地址 | 说明 |
|--------|------|----------|------|
| `0x00` | Interrupt | `0x00000190` | 外部中断（定时器） |
| `0x08` | Syscall | `0x00000190` | SYSCALL 指令触发 |
| `0x0A` | Reserved Inst | `0x00000190` | 无效指令 |
| `0x0C` | Overflow | `0x00000190` | 算术溢出 |
| `0x0D` | Trap | `0x00000190` | Trap 指令触发 |
| `0x0E` | ERET | cp0_epc | 异常返回 |

### 6.3 异常处理流程

```
1. 异常触发（Syscall/Trap/Overflow/Interrupt）
     │
2. MEM 阶段检测异常
     │  ├── 保存 EPC：当前指令地址或延迟槽地址
     │  ├── 设置 Cause.ExcCode
     │  └── 置 Status.EXL = 1
     │
3. CTRL 模块生成 flush + new_pc
     │  ├── flush = 1（清空流水线中异常指令后的所有指令）
     │  └── new_pc = 0x00000190（异常入口）
     │
4. 异常处理程序执行
     │  ├── 保存现场（GPR）
     │  ├── 处理异常
     │  └── ERET 返回
     │
5. ERET 指令
     ├── PC = EPC
     └── Status.EXL = 0
```

### 6.4 精确异常

支持延迟槽中的精确异常：
- 若异常发生在延迟槽中：`EPC = 分支指令地址 + 4`，`Cause.BD = 1`
- 若异常不在延迟槽中：`EPC = 当前指令地址`，`Cause.BD = 0`

---

## 7. 存储器映射

```
0x00000000 ──────────── 指令 ROM（inst_rom，内置测试程序）
     │                  131072 × 32bit，地址空间 [0x0000, 0x7FFFC]
     │
0x00008000 ──────────── 异常入口
     │                  0x00000190 → instmem[100]
     │
0x70000000 ──────────── IO 地址空间
     │                  SW/LW 的立即数高 16 位 = 0x7000 时识别为 IO 访问
     │
0x70000F00 ──────────── LED 输出地址
0x70000F0C ──────────── 数码管输出地址
     │
0x???????? ──────────── 数据 RAM（data_ram）
                         1024 × 32bit，CE 使能访问
```

---

## 8. IO 外设

### 8.1 板载资源映射（Basys3）

| 外设 | FPGA 端口 | 位宽 | 方向 | 功能 |
|------|-----------|------|------|------|
| 拨码开关 | `switch_in[15:0]` | 16 | 输入 | 系统控制 + 寄存器编号输入 |
| 按键 | `key_in[4:0]` | 5 | 输入 | 断步时钟 + 方向键 |
| LED | `led_out[15:0]` | 16 | 输出 | 显示 PC[17:2]（当前执行指令条数） |
| 数码管段选 | `seg_out[7:0]` | 8 | 输出 | 7 段 + 小数点（低电平点亮） |
| 数码管位选 | `dig_out[3:0]` | 4 | 输出 | 4 位扫描（低电平选通） |
| 系统时钟 | `sys_clk` | 1 | 输入 | 100MHz（引脚 W5） |

### 8.2 开关功能定义

| 开关位 | 功能 | 说明 |
|--------|------|------|
| **SW[15]** | 系统复位 | 高电平复位 CPU |
| **SW[14]** | Debug 模式 | 1 = 断步执行模式 |
| **SW[13]** | 数码管高低位 | 1 = 显示高 16 位，0 = 显示低 16 位 |
| **SW[12]** | HI 寄存器显示 | 与 SW[11] 异或为 1 时显示 HI/LO |
| **SW[11]** | LO 寄存器显示 | 与 SW[12] 异或为 1 时显示 HI/LO |
| **SW[4:0]** | 寄存器编号 | 选择数码管显示的通用寄存器 (\$0~\$31) |

### 8.3 数码管显示逻辑

- **通用寄存器模式**（SW[12]⊕SW[11]=0）：
  - SW[13]=0 → 显示寄存器低 16 位（4 位十六进制）
  - SW[13]=1 → 显示寄存器高 16 位
- **HI/LO 显示模式**（SW[12]⊕SW[11]=1）：
  - SW[12]=1 → 显示 HI 寄存器
  - SW[11]=1 → 显示 LO 寄存器

### 8.4 时钟系统

- **正常模式**（SW[14]=0）：使用 1Hz 时钟（100MHz 分频），便于观察
- **断步模式**（SW[14]=1）：按下 BTNC（key_in[0]）产生一个上升沿脉冲，CPU 执行一条指令

---

## 9. 模块说明

### 9.1 define.v — 全局宏定义

项目的"字典"，定义了所有指令编码、ALU 操作码、数据宽度等近 300 行宏定义。

**核心分类**：
- **常量**：`RstEnable`、`ZeroWord`、`WriteEnable` 等
- **指令操作码**：`EXE_AND`(6'b100100)、`EXE_OR`(6'b100101) 等 50+ 条
- **ALU 操作码**（ID→EX）：`EXE_AND_OP`(8'b00100100) 等 60+ 个 8 位编码
- **ALU 选择码**：`EXE_RES_LOGIC`(3'b001)、`EXE_RES_SHIFT`(3'b010) 等 8 类运算
- **带宽定义**：`InstAddrBus`(31:0)、`DataBus`(31:0)、`RegBus`(31:0) 等
- **CP0 寄存器地址**：`CP0_REG_COUNT`(5'b01001) 等

### 9.2 openmips.v — CPU 顶层

五级流水线 CPU 的顶层连接模块，约 660 行。主要完成：

- **流水线模块例化**：PC、IF/ID、ID、ID/EX、EX、EX/MEM、MEM、MEM/WB
- **功能单元例化**：regfile、hilo_reg、ctrl、div、LLbit_reg、cp0_reg
- **互联信号声明**：约 120 个 wire 信号在各阶段间传递数据和控制信息
- **IO 输出处理**：将 PC 值输出到 LED、将 HI/LO 选择输出到数码管

### 9.3 openmips_min_sopc.v — 最小 SOPC

片上系统集成顶层，例化 CPU + inst_rom + data_ram + io 模块。

### 9.4 id.v — 译码阶段（核心模块）

约 800 行，是项目**最复杂的模块**。功能包括：
- 指令译码（R/I/J 三种格式全覆盖）
- 寄存器地址生成
- 立即数扩展（符号/零/LUI）
- Load 相关检测与 stall 请求
- 数据前推路径选择
- 分支目标地址计算
- 延迟槽标记
- Syscall 与无效指令检测

### 9.5 ex.v — 执行阶段

约 450 行，实现所有 ALU 运算：
- **逻辑运算**（4 条）：AND/OR/XOR/NOR
- **移位运算**（3 条）：SLL/SRL/SRA
- **算术运算**（8 条）：ADD/SUB/SLT/SLTU/CLZ/CLO 等
- **算术溢出检测**：`ov_sum` 信号
- **Trap 判断**（8 条）：TEQ/TGE/TLT/TNE 等
- **乘累加控制**：MADD/MSUB 多周期状态机
- **IO 地址译码**：高 16 位 0x7000 前缀识别

### 9.6 mem.v — 访存阶段

约 330 行，实现 Load/Store 操作：
- **字节/半字/字**对齐访问
- **带符号扩展**：LB/LH（符号扩展）、LBU/LHU（零扩展）
- **非对齐访问**：LWL/LWR/SWL/SWR
- **LL/SC 原子操作**：通过 LLbit 寄存器实现
- **字节使能**：`mem_sel_o[3:0]` 逐字节控制写入
- **异常判断**：检查 CP0 Status.EXL

### 9.7 div.v — 独立除法器

32 周期迭代除法器，状态机包含 4 个状态：
- `DivFree`：空闲，等待启动
- `DivByZero`：除零错误
- `DivOn`：32 次迭代（每周期一次移位-减法）
- `DivEnd`：完成，输出商（LO）和余数（HI）

支持有符号/无符号除法，自动取补码。

### 9.8 cp0_reg.v — CP0 协处理器

管理 7 个 CP0 寄存器，处理 6 种异常类型的 EPC/Cause 设置，支持定时器中断（Count 与 Compare 相等触发）。

### 9.9 ctrl.v — 流水线控制器

根据 `excepttype_i`、`stallreq_from_id`、`stallreq_from_ex` 生成 `stall`、`flush`、`new_pc` 三个核心控制信号。

### 9.10 io.v — IO 外设控制器

- **时钟分频**：100MHz → 1Hz（正常模式）/ 按键脉冲（断步模式）
- **按键消抖**：BTNC 按键 20ms 消抖
- **数码管动态扫描**：4 位扫描显示（scan_cnt[15:14] 控制位选）
- **复位同步**：两级同步器消除 SW[15] 亚稳态

---

## 10. 内置测试程序

`inst_rom.v` 中内置了完整的 MIPS 测试程序（`instmem[0]~instmem[105]`），覆盖所有指令类型：

### 测试序列

| 地址范围 | 指令数 | 测试内容 |
|----------|--------|----------|
| `[0]~[5]` | 6 | 立即数算术/逻辑运算（ORI, ADDI, ANDI, XORI, SLTI, SLTIU） |
| `[6]~[11]` | 6 | 寄存器算术/逻辑运算（ADD, OR, SUB, AND, XOR, SLT） |
| `[12]~[17]` | 6 | 移位指令（SLL, SRL, LUI, SRA, SLTU） |
| `[18]~[23]` | 6 | 存取指令（SW→地址32, LW→读取验证） |
| `[24]~[27]` | 4 | 分支指令（BEQ 不跳转, BNE 跳转，含延迟槽验证） |
| `[28]~[29]` | 2 | 跳转指令（J 到 [30]，含延迟槽） |
| `[30]~[31]` | 2 | 乘除法（MULT: 32×5=160, DIV: 32÷5=6 余 2） |
| `[32]~[33]` | 2 | 乘除数据移动（MFHI=$2, MFLO=$6） |
| `[34]~[35]` | 2 | 系统调用（SYSCALL → 异常入口 [100]） |
| `[36]~[37]` | 2 | NOP 填充 |
| `[38]` | 1 | 回起始（J [0]，循环执行） |
| `[100]~[105]` | 6 | **异常处理程序**（保存 HI/LO，ERET 返回 [38]） |

### 预期结果

执行后可通过开关选择寄存器，在数码管上验证：
- `$1 = 32`, `$2 = 5`, `$3 = 1`, `$4 = 5`, `$5 = 3`, `$6 = 2`（HI 余数）, `$7 = 6`（LO 商）, `$8 = 2`（HI）, `$9 = 6`（LO）, `$10 = 0x26`

---

## 11. 使用方法

### 11.1 环境要求

| 软件 | 版本 | 用途 |
|------|------|------|
| **Vivado** | 2019.1 或更高 | 综合、实现、生成比特流、烧录 |
| **ModelSim / Vivado Sim** | 任意版本 | 仿真验证（可选） |
| **Git** | 任意版本 | 版本管理 |

### 11.2 快速开始（Vivado 工程搭建）

#### 步骤一：克隆仓库

```bash
git clone git@github.com:ZLAND1/OpenMIPS_ZLAND.git
cd OpenMIPS_ZLAND
```

#### 步骤二：创建 Vivado 工程

1. 打开 Vivado → **Create Project**
2. 设置工程名（如 `openmips`），选择工程路径
3. 选择 **RTL Project**，勾选 "Do not specify sources at this time"
4. 选择目标芯片：
   - **Family**: Artix-7
   - **Package**: cpg236
   - **Speed**: -1
   - **Part**: **xc7a35tcpg236-1**（Basys3）

#### 步骤三：添加源文件

**方法 A — Vivado GUI：**
1. 在 Flow Navigator → **Add Sources** → **Add or create design sources**
2. 添加 `src/` 目录下所有 `.v` 文件（22 个）
3. 在 **Add Constraints** 中添加 `constraints/basys3_constraints.xdc`

**方法 B — Tcl Console（推荐，更快捷）：**
```tcl
# 在 Vivado Tcl Console 中执行
cd [get_property DIRECTORY [current_project]]
add_files -norecurse src/*.v
add_files -fileset constrs_1 constraints/basys3_constraints.xdc
update_compile_order -fileset sources_1
```

#### 步骤四：添加仿真文件（可选）

```tcl
add_files -fileset sim_1 tb/*.v
# 设置 include 路径（仿真时需要 src/ 中的 define.v）
set_property include_dirs src [get_filesets sim_1]
```

#### 步骤五：综合、实现、生成比特流

```
Run Synthesis → Run Implementation → Generate Bitstream
```

或 Tcl：
```tcl
launch_runs synth_1
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1
```

### 11.3 烧录到 Basys3

1. 用 USB 线连接 Basys3 到电脑
2. **Open Hardware Manager** → **Open Target** → **Auto Connect**
3. **Program Device** → 选择生成的 `.bit` 文件（或直接使用 `bitstream/Finally.bit`）
4. 点击 **Program** 开始烧录

### 11.4 上板测试操作

1. **上电复位**：将 SW[15] 拨到高电平（复位），再拨回低电平
2. **正常全速运行**：SW[14] = 0，观察 LED[15:0] 显示 PC 变化
3. **断步调试**：SW[14] = 1，每次按下 BTNC 按键执行一条指令
4. **查看寄存器**：
   - 将 SW[12] 和 SW[11] 设为不同值（如 SW[12]=0, SW[11]=0）
   - SW[4:0] 选择寄存器编号（如 `5'b00010` 查看 \$2）
   - SW[13] = 0 显示低 16 位，SW[13] = 1 显示高 16 位
5. **查看 HI/LO**：SW[12]=1, SW[11]=0 → 显示 HI；SW[12]=0, SW[11]=1 → 显示 LO

### 11.5 仿真验证

```tcl
# Vivado Sim
launch_simulation
add_wave tb_openmips_min_sopc/*
run 10us
```

或使用 ModelSim：
```bash
vlog +incdir+src src/*.v tb/*.v
vsim -voptargs=+acc tb_openmips_min_sopc
add wave -recursive *
run 10us
```

---

## 12. 设计亮点

### 12.1 数据前推（Data Forwarding）

在 ID 阶段实现了完整的两级前推：
- **EX 级前推**：EX/MEM 阶段将要写回的数据直接旁路到 ID 阶段的寄存器读取
- **MEM 级前推**：MEM/WB 阶段将要写回的数据直接旁路到 ID 阶段的寄存器读取
- **优先级处理**：EX 阶段结果优先于 MEM 阶段结果（更新的数据更优先）

### 12.2 Load 相关检测与 Stall

通过 `pre_inst_is_load` 信号检测 EX 阶段是否为 Load 指令，若 ID 阶段的源寄存器与 Load 目标寄存器冲突，自动插入 1 周期 stall。

### 12.3 精确异常处理

支持延迟槽中的精确异常：
- 自动区分异常发生在正常指令还是延迟槽中
- EPC 指向正确的返回地址
- Cause.BD 位标记延迟槽异常

### 12.4 独立除法器

32 周期迭代除法器与主流水线并行运行：
- 除法执行期间不阻塞其他指令（非除法指令可继续流转）
- 仅在 MFHI/MFLO 读取结果时若除法未完成才 stall
- 支持有符号和无符号两种模式

### 12.5 断步调试功能

通过 SW[14]+BTNC 实现单步执行，配合数码管实时查看任意寄存器的值，极大方便了上板调试。

### 12.6 模块化设计

CPU 各阶段、各功能单元完全独立为模块，接口清晰，便于：
- 独立仿真验证每个模块
- 代码复用和修改
- 指令集扩展

---

## 13. 参考文献

1. **《计算机组成与设计：硬件/软件接口》**（原书第 5 版）— David A. Patterson, John L. Hennessy
2. **《MIPS32 Architecture For Programmers》**（Vol I, II, III）— MIPS Technologies
3. **《自己动手写 CPU》**— 雷思磊（OpenMIPS 项目参考）
4. **Basys3 Board Reference Manual** — Digilent Inc.
5. **Xilinx 7 Series FPGAs Data Sheet** (DS180)

---

## 许可证

本项目为**课程设计作品**，仅供学习与参考。如需引用或使用部分代码，请注明出处。

---

> **作者**：赵嘉阳 | 计科 2303 班 | 23041091  
> **联系方式**：3238924258@qq.com  
> **GitHub**：[github.com/ZLAND1/OpenMIPS_ZLAND](https://github.com/ZLAND1/OpenMIPS_ZLAND)
