# OpenMIPS — 五级流水线 MIPS 处理器（Basys3 FPGA）

> **课程设计**：FPGA 模型机设计  
> **作者**：赵嘉阳，计科2303班，23041091  
> **目标板**：Basys3（Xilinx Artix-7 xc7a35tcpg236-1）

---

## 项目简介

本项目实现了一个兼容 MIPS32 指令集的五级流水线处理器，支持 **38+ 条 MIPS 指令**，并包含 CP0 协处理器、异常处理机制（Syscall / ERET）、HI/LO 乘除法寄存器、以及 LLbit 支持。  

完整流水线阶段：

```
IF → ID → EX → MEM → WB
  ↑      ↑     ↑      ↑
 PC    译码   执行   写回
```

顶层模块 `openmips_min_sopc` 集成了 CPU 内核、指令 ROM、数据 RAM 和 IO 外设模块，可直接在 Basys3 开发板上运行。

---

## 文件结构

```
github可复刻版/
├── README.md                         # 本文件
├── .gitignore                        # Git 忽略规则
├── 引脚.txt                          # 仿真引脚参考
│
├── src/                              # RTL 源码（22个 Verilog 模块）
│   ├── define.v                      # 全局宏定义（指令编码、ALU操作等）
│   ├── openmips.v                    # CPU 顶层模块（五级流水线连接）
│   ├── openmips_min_sopc.v           # 最小 SOPC 系统（CPU + ROM + RAM + IO）
│   ├── pc_reg.v                      # PC 程序计数器
│   ├── if_id.v                       # IF/ID 流水线寄存器
│   ├── id.v                          # ID 译码阶段
│   ├── id_ex.v                       # ID/EX 流水线寄存器
│   ├── ex.v                          # EX 执行阶段
│   ├── ex_mem.v                      # EX/MEM 流水线寄存器
│   ├── mem.v                         # MEM 访存阶段
│   ├── mem_wb.v                      # MEM/WB 流水线寄存器
│   ├── regfile.v                     # 通用寄存器文件（32×32bit）
│   ├── ctrl.v                        # 控制模块（流水线暂停/刷新）
│   ├── div.v                         # 除法器
│   ├── hilo_reg.v                    # HI/LO 寄存器
│   ├── LLbit_reg.v                   # LLbit 寄存器（LL/SC 指令支持）
│   ├── cp0_reg.v                     # CP0 协处理器寄存器
│   ├── inst_rom.v                    # 指令 ROM（含内置测试程序）
│   ├── data_ram.v                    # 数据 RAM
│   ├── io.v                          # IO 外设模块（开关/LED/数码管/按键）
│   ├── clk_div.v                     # 时钟分频
│   └── mioc.v                        # 存储器-IO 控制器（备用）
│
├── tb/                               # 仿真测试文件
│   ├── openmips_min_sopc_tb.v        # 基本仿真测试
│   ├── tb_hard.v                     # 下板测试（硬件仿真）
│   └── tb_hardv2.v                   # 下板测试 v2
│
├── constraints/                      # XDC 引脚约束
│   ├── basys3_constraints.xdc        # Basys3 完整约束（推荐使用）
│   └── opmipxdc.xdc                  # 备用约束文件
│
├── docs/                             # 课程设计文档
│   ├── 课设报告_计科2303班_23041091_赵嘉阳.docx
│   ├── FPGA汇报赵嘉阳.pptx
│   └── PPT大纲.docx
│
└── bitstream/                        # 生成的比特流
    └── Finally.bit                   # 可直接烧录到 Basys3 的 bit 文件
```

---

## 支持的指令集

### 算术/逻辑运算
`ADD, ADDU, SUB, SUBU, ADDI, ADDIU, AND, OR, XOR, NOR, ANDI, ORI, XORI, LUI, SLT, SLTU, SLTI, SLTIU, CLZ, CLO`

### 移位运算
`SLL, SLLV, SRL, SRLV, SRA, SRAV`

### 移动运算
`MOVZ, MOVN, MFHI, MTHI, MFLO, MTLO`

### 乘除法
`MULT, MULTU, MUL, MADD, MADDU, MSUB, MSUBU, DIV, DIVU`

### 跳转与分支
`J, JAL, JALR, JR, BEQ, BNE, BGEZ, BGEZAL, BGTZ, BLEZ, BLTZ, BLTZAL`

### 存取指令
`LB, LBU, LH, LHU, LL, LW, LWL, LWR, SB, SC, SH, SW, SWL, SWR`

### 异常/系统
`SYSCALL, ERET, TEQ, TGE, TGEU, TLT, TLTU, TNE`

---

## 如何使用

### 1. 创建 Vivado 工程

1. 打开 **Vivado**（推荐 2019.1 或更新版本）
2. 新建工程，选择目标芯片：**xc7a35tcpg236-1**（Basys3）
3. 将 `src/` 目录下所有 `.v` 文件添加为设计源文件
4. 将 `constraints/basys3_constraints.xdc` 添加为约束文件
5. 将 `tb/` 目录下的文件添加为仿真源文件（可选）

### 2. 综合与实现

```
Run Synthesis → Run Implementation → Generate Bitstream
```

或直接使用 Tcl 命令：
```tcl
add_files -norecurse src/*.v
add_files -fileset constrs_1 constraints/basys3_constraints.xdc
launch_runs impl_1 -to_step write_bitstream
```

### 3. 烧录到 Basys3

将 `bitstream/Finally.bit`（或新生成的 bit 文件）通过 Vivado Hardware Manager 烧录到 Basys3 开发板。

---

## 板载外设映射

| 外设 | 位宽 | 功能说明 |
|------|------|----------|
| **SW[15]** | 1 bit | 系统复位（高电平有效） |
| **SW[14]** | 1 bit | Debug 断步模式（1=断步，按键逐步执行） |
| **SW[13]** | 1 bit | 数码管高/低位选择（1=高位，0=低位） |
| **SW[12:11]** | 2 bit | HI/LO 寄存器显示使能 |
| **SW[4:0]** | 5 bit | 选择要查看的寄存器号 |
| **KEY[4:0]** | 5 bit | 按键（BTNC/BTNU/BTNL/BTNR/BTND） |
| **LED[15:0]** | 16 bit | 显示当前 PC[17:2]（指令执行条数） |
| **数码管** | 4位8段 | 显示寄存器值或 HI/LO 值 |

---

## 内置测试程序

`inst_rom.v` 中内置了一组 MIPS 指令测试序列，覆盖：

1. 立即数算术/逻辑运算（ORI, ADDI, ANDI, XORI, SLTI, SLTIU）
2. 寄存器算术/逻辑运算（ADD, OR, SUB, AND, XOR, SLT）
3. 移位指令（SLL, SRL, LUI, SRA, SLTU）
4. 存取指令（SW, LW）
5. 分支指令（BEQ, BNE）含延迟槽
6. 跳转指令（J）含延迟槽
7. 乘除法指令（MULT, DIV）
8. 乘除数据移动（MFHI, MFLO）
9. 异常处理（Syscall → ERET）

---

## 流水线架构

```
         ┌──────────────────────────────────────────┐
         │              数据前推 (Forwarding)         │
         │  EX/MEM → ID     MEM/WB → ID              │
         ▼                                          ▼
  ┌──────┐   ┌──────┐   ┌──────┐   ┌──────┐   ┌──────┐
  │  IF  │──▶│  ID  │──▶│  EX  │──▶│ MEM  │──▶│  WB  │
  │ 取指 │   │ 译码 │   │ 执行 │   │ 访存 │   │ 写回 │
  └──────┘   └──────┘   └──────┘   └──────┘   └──────┘
       │          │          │          │          │
       ▼          ▼          ▼          ▼          ▼
   PC_REG    REGFILE     HI/LO      DATA_RAM    REGFILE
              CP0         除法器     LLbit
```

- **数据前推**：EX/MEM 和 MEM/WB 阶段结果前推到 ID 阶段
- **流水线暂停**：解决数据相关（RAW hazard）
- **延迟槽**：分支/跳转指令的下一条指令始终执行
- **异常处理**：精确异常，支持 Syscall 和 ERET

---

## 许可证

本项目为课程设计作品，仅供学习参考。
