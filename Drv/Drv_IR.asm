; ╔══════════════════════════════════════════════════════════════════════╗
; ║  第1部分：文件名片                                                     ║
; ╠══════════════════════════════════════════════════════════════════════╣
; ║  文件名: Drv_IR.asm                                                   ║
; ║  层级:   Drv (驱动层)                                                 ║
; ║  功能:   红外遥控(NEC协议)的初始化和信号解码。通过测量相邻红外脉冲        ║
; ║          下降沿的时间间隔，解析出遥控器按键码。                          ║
; ║                                                                      ║
; ║  白话:   红外遥控器发出的是一串"光脉冲"——38kHz红外光快速闪烁代表"1"，   ║
; ║          不闪代表"0"，但单片机不是这样直接读的。                        ║
; ║          NEC协议的核心思想：用"两次下降沿之间的时长"来编码信息。         ║
; ║          - 13.5ms间隔 → START信号（"我要开始发数据了"）                ║
; ║          - 11.25ms间隔 → REPEAT信号（"刚才那个键还按着呢"）            ║
; ║          - 2.25ms间隔 → 数据位0                                       ║
; ║          - 1.125ms间隔 → 数据位1                                      ║
; ║          这个文件用Timer2充当"秒表"：每次下降沿来(INT0中断)，           ║
; ║          读Timer2的计数值→算间隔→判断是START/REPEAT/bit0/bit1。       ║
; ║          收齐32位后，验证反码(Data0 XOR Data1 = FFH)，通过后发布按键码。║
; ║                                                                      ║
; ║  硬件: P3.2(INT0引脚)接红外接收头(如HS0038)，下降沿触发中断             ║
; ║  中断: INT0下降沿 → 自动跳 ORG 0003H → IR_ISR                        ║
; ║                                                                      ║
; ║  调用者: Main.asm (IR_Init在初始化时调用)                              ║
; ║          CPU硬件 (红外脉冲的每个下降沿触发INT0中断)                    ║
; ║  被谁读: Protocol_IR.asm (读 IR_CmdReady/IR_Cmd)                      ║
; ╚══════════════════════════════════════════════════════════════════════╝
;
; ╔══════════════════════════════════════════════════════════════════════╗
; ║  第2部分：汇编指令速查表（本文件出现的所有指令）                        ║
; ╠══════════════════════════════════════════════════════════════════════╣
; ║  EQU  n        │ 给常数/地址取名 (T2CON_REG EQU 0C8H)                ║
; ║  BIT  n        │ 给"位地址"取名 (IR_EX0 BIT 0A8H)                    ║
; ║  RLC  A        │ 带CY的循环左移：A的每位+ CY一起往左挪一位，           ║
; ║               │ 最高位移入CY，原CY移入最低位。常用于逐位构建掩码       ║
; ║  XRL  A, 直接地址│ 按位异或(XOR)：相同=0，不同=1。用来验证反码        ║
; ║               │ 如果Data0 XOR Data1 = FFH，说明互为反码，数据正确     ║
; ║  NOP           │ 空操作（什么也不做，占1字节1周期）。这里占位用         ║
; ║  ------ 以下指令见此前文件，此处简记 ------                            ║
; ║  PUSH / POP / MOV / SETB / CLR / CLR C / SUBB / JZ / JNZ / DEC /    ║
; ║  CJNE / JC / JNC / INC / LJMP / SJMP / ORL / RET / RETI              ║
; ╚══════════════════════════════════════════════════════════════════════╝
;
; ╔══════════════════════════════════════════════════════════════════════╗
; ║  第3部分：特殊功能寄存器速查表（本文件涉及的SFR）                       ║
; ╠══════════════════════════════════════════════════════════════════════╣
; ║  T2CON │ C8H │ Timer2控制寄存器。TR2(bit2)=启动/停止                 ║
; ║  TH2   │ CDH │ Timer2计数初值高8位（可以做自动重装，此处用于计时）    ║
; ║  TL2   │ CCH │ Timer2计数初值低8位                                   ║
; ║  TCON  │ 88H │ IT0(bit0)=INT0触发方式：0=低电平, 1=下降沿            ║
; ║        │     │ IE0(bit1)=INT0中断标志（硬件自动清）                   ║
; ║  IE    │ A8H │ EX0(bit0)=INT0中断允许                                ║
; ╚══════════════════════════════════════════════════════════════════════╝

NAME    DRV_IR

PUBLIC  IR_Init
PUBLIC  IR_ISR
PUBLIC  IR_CmdReady
PUBLIC  IR_Cmd

; 直接地址定义——不依赖头文件，自己写死寄存器地址，兼容任何编译器
T2CON_REG   EQU 0C8H    ; Timer2控制寄存器地址
TL2_REG     EQU 0CCH    ; Timer2低8位
TH2_REG     EQU 0CDH    ; Timer2高8位

IR_IT0 BIT 088H         ; TCON.0 = INT0触发方式控制位
IR_EX0 BIT 0A8H         ; IE.0 = INT0中断允许位
IR_TR2 BIT 0CAH         ; T2CON.2 = Timer2运行控制位

IR_DATA SEGMENT DATA
RSEG    IR_DATA
IR_State:       DS 1    ; 0=空闲(等START), 1=等引导间隔, 2=接收32位数据
IR_BitCnt:      DS 1    ; 已收到的bit计数(0~31)
IR_Mask:        DS 1    ; 当前位的掩码(01H,02H,04H,08H,10H,20H,40H,80H)
IR_ByteIdx:     DS 1    ; 当前正在填充的字节序号(0=Data0,1=Data1,2=Data2,3=Data3)
IR_Data0:       DS 1    ; 接收数据的字节0（地址码低8位）
IR_Data1:       DS 1    ; 字节1（地址码高8位/反码）
IR_Data2:       DS 1    ; 字节2（命令码）——这是最终要用的按键码
IR_Data3:       DS 1    ; 字节3（命令反码）
IR_DeltaH:      DS 1    ; 两次下降沿间隔的Timer2计数值高字节
IR_DeltaL:      DS 1    ; 间隔低字节
IR_LastCmd:     DS 1    ; 上一次收到的命令码（用于REPEAT帧判断）
IR_CmdReady:    DS 1    ; 新命令就绪标志
IR_Cmd:         DS 1    ; 最终解码出的按键码

IR_CODE SEGMENT CODE
RSEG    IR_CODE

IR_Init:
        CLR     IR_EX0  ; 先关INT0中断
        CLR     IR_TR2  ; 先停Timer2

        MOV     T2CON_REG, #00H ; Timer2配置清零
        MOV     TH2_REG, #00H   ; 计数值从0开始
        MOV     TL2_REG, #00H

        MOV     IR_State, #0    ; 初始状态=空闲
        MOV     IR_BitCnt, #0
        MOV     IR_Mask, #01H   ; 掩码从最低位开始
        MOV     IR_ByteIdx, #0  ; 从字节0开始存
        MOV     IR_Data0, #0
        MOV     IR_Data1, #0
        MOV     IR_Data2, #0
        MOV     IR_Data3, #0
        MOV     IR_DeltaH, #0
        MOV     IR_DeltaL, #0
        MOV     IR_LastCmd, #0
        MOV     IR_CmdReady, #0
        MOV     IR_Cmd, #0

        SETB    IR_IT0  ; INT0触发方式=下降沿（红外接收头输出低电平时触发）
        SETB    IR_TR2  ; 启动Timer2计时
        SETB    IR_EX0  ; 开INT0中断
        RET

; INT0 下降沿中断：通过相邻下降沿间隔进行 NEC 粗解码
IR_ISR:
        PUSH    ACC
        PUSH    0D0H    ; 保护PSW

        ; --- 读秒表：把Timer2当前计数值拿出来作为"时间间隔" ---
        ; Timer2一直在自动加1计数，两次下降沿之间的差值就是信号时长
        MOV     A, TH2_REG
        MOV     IR_DeltaH, A   ; 高字节
        MOV     A, TL2_REG
        MOV     IR_DeltaL, A   ; 低字节
        MOV     TH2_REG, #00H  ; 秒表归零，准备测下一个间隔
        MOV     TL2_REG, #00H

        ; --- 状态路由 ---
        MOV     A, IR_State
        JZ      IR_ISR_FromIdle    ; State=0: 第一次收到信号
        DEC     A
        JZ      IR_ISR_CheckLead   ; State=1: 判断START还是REPEAT
        LJMP    IR_ISR_DecodeBit    ; State=2: 解码数据位

IR_ISR_FromIdle:
        ; 啥也不管，先进入状态1（等引导脉冲的长度判断）
        MOV     IR_State, #1
        LJMP    IR_ISR_Exit

IR_ISR_CheckLead:
        ; --- 先判断是不是 REPEAT（重复帧）：约11.25ms → 高字节[24H,2CH) ---
        MOV     A, IR_DeltaH
        CLR     C
        SUBB    A, #024H       ; DeltaH - 24H
        JC      IR_ISR_CheckStart ; CY=1说明DeltaH<24H，太小不可能是REPEAT

        MOV     A, IR_DeltaH
        CLR     C
        SUBB    A, #02CH       ; DeltaH - 2CH
        JC      IR_ISR_RepeatFrame ; CY=1说明DeltaH<2CH，在[24H,2CH)区间→REPEAT！

IR_ISR_CheckStart:
        ; --- 判断是不是 START（起始帧）：约13.5ms → 高字节[2CH,37H) ---
        MOV     A, IR_DeltaH
        CLR     C
        SUBB    A, #02CH
        JNC     IR_ISR_CheckStart_Upper ; CY=0说明>=2CH，去检查上限
        LJMP    IR_ISR_ResetIdle        ; <2CH但也不是REPEAT→无效信号

IR_ISR_CheckStart_Upper:
        MOV     A, IR_DeltaH
        CLR     C
        SUBB    A, #037H
        JC      IR_ISR_StartFrame_Go    ; CY=1说明<37H，在[2CH,37H)区间→START！
        LJMP    IR_ISR_ResetIdle        ; >=37H→无效

IR_ISR_StartFrame_Go:
        LJMP    IR_ISR_StartFrame       ; 长跳转到START处理


IR_ISR_RepeatFrame:
        ; REPEAT帧：遥控器还在发送"按住不松"的信号
        ; 策略：不触发新事件（屏蔽连发），只记录有REPEAT来过。
        ; 如果不屏蔽，歌曲会不停重播导致"口吃"效果。
        MOV     A, IR_LastCmd
        JNZ     IR_ISR_RepeatFrame_Go   ; LastCmd!=0 说明有上一条命令
        LJMP    IR_ISR_ResetIdle        ; 没有上一条命令，忽略

IR_ISR_RepeatFrame_Go:
        MOV     IR_Cmd, A       ; 存命令（但IR_CmdReady不置1！注意区别）
        ; 下面这行被注释掉了，这就是屏蔽连发的关键：
        ; MOV     IR_CmdReady, #1 ; 被屏蔽——不通知主循环
        NOP
        NOP
        NOP
        LJMP    IR_ISR_ResetIdle

IR_ISR_StartFrame:
        ; START帧来了！准备接收后面的32位数据
        MOV     IR_State, #2   ; 进入"解码数据位"状态
        MOV     IR_BitCnt, #0
        MOV     IR_Mask, #01H  ; 从bit0开始
        MOV     IR_ByteIdx, #0 ; 从字节0开始
        MOV     IR_Data0, #0
        MOV     IR_Data1, #0
        MOV     IR_Data2, #0
        MOV     IR_Data3, #0
        LJMP    IR_ISR_Exit

IR_ISR_DecodeBit:
        ; 解码数据位：bit0间隔≈2.25ms→TH2高字节<06H
        ;            bit1间隔≈1.125ms→TH2高字节<0BH但>=06H
        ; 阈值取06H和0BH是经验值——在几MHz计数下这种间隔大概落在这些区间
        MOV     A, IR_DeltaH
        CLR     C
        SUBB    A, #006H       ; DeltaH - 6
        JC      IR_ISR_StoreBit0 ; DeltaH<6 → bit0！

        MOV     A, IR_DeltaH
        CLR     C
        SUBB    A, #00BH      ; DeltaH - 11
        JC      IR_ISR_StoreBit1 ; 6<=DeltaH<11 → bit1！

        LJMP    IR_ISR_ResetIdle ; DeltaH>=11 → 无效

IR_ISR_StoreBit0:
        ; bit0：对应位保持为0（初始就是0，什么也不用改）
        SJMP    IR_ISR_AfterStoreBit

IR_ISR_StoreBit1:
        ; bit1：用掩码把对应位置1
        MOV     A, IR_ByteIdx
        JZ      IR_ISR_StoreByte0   ; ByteIdx=0，正在填Data0

        CJNE    A, #1, IR_ISR_CheckByte2
        MOV     A, IR_Mask          ; 掩码：01H→02H→04H→...→80H
        ORL     IR_Data1, A         ; 把Data1的该位置1
        SJMP    IR_ISR_AfterStoreBit

IR_ISR_CheckByte2:
        CJNE    A, #2, IR_ISR_CheckByte3
        MOV     A, IR_Mask
        ORL     IR_Data2, A
        SJMP    IR_ISR_AfterStoreBit

IR_ISR_CheckByte3:
        CJNE    A, #3, IR_ISR_AfterStoreBit
        MOV     A, IR_Mask
        ORL     IR_Data3, A
        SJMP    IR_ISR_AfterStoreBit

IR_ISR_StoreByte0:
        MOV     A, IR_Mask
        ORL     IR_Data0, A         ; 把Data0的该位置1

IR_ISR_AfterStoreBit:
        ; --- 掩码左移一位（RLC），准备处理下一位 ---
        MOV     A, IR_Mask
        CLR     C
        RLC     A               ; 01H→02H→04H→08H→10H→20H→40H→80H
        MOV     IR_Mask, A
        JNZ     IR_ISR_IncBitCnt ; 掩码还没到0，说明当前字节还没满8位

        ; 掩码为0=当前字节的8位已收完，切到下一个字节
        MOV     IR_Mask, #01H   ; 掩码重置为最低位
        INC     IR_ByteIdx      ; 字节序号+1

IR_ISR_IncBitCnt:
        INC     IR_BitCnt       ; 总bit计数+1
        MOV     A, IR_BitCnt
        CJNE    A, #32, IR_ISR_Exit ; 还没收齐32位，继续等

        ; --- 32位收齐！验证反码 ---
        ; NEC协议：Data0 XOR Data1 应该 = FFH（地址+地址反码）
        MOV     A, IR_Data0
        XRL     A, IR_Data1     ; 异或：相同为0，不同为1
        CJNE    A, #0FFH, IR_ISR_ResetIdle ; 不是FFH=反码校验失败，丢弃

        MOV     A, IR_Data2
        XRL     A, IR_Data3     ; 命令+命令反码
        CJNE    A, #0FFH, IR_ISR_ResetIdle ; 失败，丢弃

        ; --- 校验通过！发布按键码 ---
        MOV     A, IR_Data2     ; Data2就是遥控器的按键码
        MOV     IR_Cmd, A       ; 发布
        MOV     IR_LastCmd, A   ; 记录下一次REPEAT备用
        MOV     IR_CmdReady, #1 ; 通知主循环：有新遥控命令！

IR_ISR_ResetIdle:
        MOV     IR_State, #0    ; 状态归零，等下一轮START

IR_ISR_Exit:
        POP     0D0H    ; 恢复PSW
        POP     ACC     ; 恢复ACC
        RETI

END
