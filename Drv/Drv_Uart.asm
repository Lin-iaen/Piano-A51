; ╔══════════════════════════════════════════════════════════════════════╗
; ║  第1部分：文件名片                                                   ║
; ╠══════════════════════════════════════════════════════════════════════╣
; ║  文件名: Drv_Uart.asm                                                ║
; ║  层级:   Drv (驱动层)                                                ║
; ║  功能:   串口(UART)的初始化和中断接收。用8状态状态机逐字节接收数据帧 ║
; ║          完整收完一帧后通知主循环。                                  ║
; ║                                                                      ║
; ║  白话:   串口就是单片机与PC通信的"电话线"。PC发来一串字节，          ║
; ║          每一个字节到达都会触发UART中断，这个文件的ISR就像一个       ║
; ║          "邮局分拣员"，收到一个字节就根据当前状态决定：              ║
; ║          - 这是帧头吗？(等0x55→等0xAA)                               ║
; ║          - 这是版本号吗？(必须0x01)                                  ║
; ║          - 这是命令吗？→存起来                                       ║
; ║          - 这是长度吗？(不能超过8，防缓冲区溢出)                     ║
; ║          - 这是数据吗？→逐个存入Buf[]                                ║
; ║          - 这是校验码吗？→存CRC                                      ║
; ║          任何一步不匹配→立刻复位，重新等帧头("可丢一帧，不读错一帧") ║
; ║                                                                      ║
; ║  帧格式:| 0x55 | 0xAA | Ver(0x01) | Cmd | Len | Payload[0..7] | CRC |║
; ║  波特率: 9600bps @ 11.0592MHz (TH1=TL1=0xFD, SMOD=0)                 ║
; ║                                                                      ║
; ║  调用者: Main.asm (UART_Init在初始化时调用)                          ║
; ║          CPU硬件 (收到串口字节自动触发中断,跳 UART_ISR)              ║
; ║  被谁读: Protocol.asm (读 UART_RxReady/RxCmd/RxLen/RxBuf)            ║
; ╚══════════════════════════════════════════════════════════════════════╝
;
; ╔══════════════════════════════════════════════════════════════════════╗
; ║  第2部分：汇编指令速查表（本文件出现的所有指令）                     ║
; ╠══════════════════════════════════════════════════════════════════════╣
; ║  ANL 直接地址, #n│ 按位"与"清指定位。ANL PCON,#7FH = 清SMOD位        ║
; ║  ORL 直接地址, #n│ 按位"或"置指定位。ORL TMOD,#20H = Timer1模式2     ║
; ║  JNB  bit, 标签  │ Jump if Not Bit：bit=0就跳转。JNB RI=等接收中断   ║
; ║  JNC  标签       │ CY=0(无借位)跳转，也用于判断无符号数>=比较值      ║
; ║  ADD  A, #n      │ 加法：A = A + n                                   ║
; ║  MOV  @R0, A     │ 间接寻址：把A的值写入以R0为地址的内存位置。       ║
; ║                  │ 就像"按门牌号送快递"——R0里存着门牌号              ║
; ║  INC  直接地址   │ 加1                                               ║
; ║  LJMP 标签       │ 无条件长跳转（64KB范围内均可，占3字节）           ║
; ║                  │ 为什么这里大量用LJMP而不是SJMP？                  ║
; ║                  │ SJMP只能跳±128字节，ISR代码很长怕越界。           ║
; ║                  │ 用LJMP虽然占空间多但绝对安全。                    ║
; ║  RETI            │ 从中断返回（附加：重新开放同级/低级中断）         ║
; ║  ------ 以下指令见此前文件，此处简记 ------                          ║
; ║  PUSH / POP / MOV / SETB / CLR / JZ / JNZ / CJNE / SJMP / JC / RET   ║
; ╚══════════════════════════════════════════════════════════════════════╝
;
; ╔══════════════════════════════════════════════════════════════════════╗
; ║  第3部分：特殊功能寄存器速查表（本文件涉及的SFR）                    ║
; ╠══════════════════════════════════════════════════════════════════════╣
; ║  SCON │ 98H │ 串口控制寄存器。50H=模式1(8位UART,可变波特率),REN=1    ║
; ║  SBUF │ 99H │ 串口数据缓冲器。读SBUF=取收到的字节,写SBUF=发送字节    ║
; ║  TMOD │ 89H │ 定时器模式。高4位(Timer1)设20H=模式2(8位自动重装)      ║
; ║  TH1  │ 8DH │ Timer1初值高8位。0xFD → 9600bps@11.0592MHz             ║
; ║  TL1  │ 8BH │ Timer1初值低8位。模式2下TH1=TL1,溢出自动重装           ║
; ║  PCON │ 87H │ 电源控制。SMOD(bit7)=0时波特率不翻倍                   ║
; ║       │     │ 波特率公式: 模式1波特率 = (2^SMOD/32)×(f_osc/(12×(256-TH1))) ║
; ║  TCON │ 88H │ TR1(bit6)=Timer1运行控制, TI(bit1)=发送中断, RI(bit0)=接收中断 ║
; ║  IE   │ A8H │ ES(bit4)=UART中断开关, EA(bit7)=总中断                 ║
; ║  PSW  │ D0H │ 压栈保护(0D0H)                                         ║
; ╚══════════════════════════════════════════════════════════════════════╝

NAME    DRV_UART

PUBLIC  UART_Init
PUBLIC  UART_ISR
PUBLIC  UART_RxState
PUBLIC  UART_RxCmd
PUBLIC  UART_RxLen
PUBLIC  UART_RxIndex
PUBLIC  UART_RxBuf
PUBLIC  UART_RxCrcL
PUBLIC  UART_RxCrcH
PUBLIC  UART_RxReady

UART_DATA   SEGMENT DATA
RSEG    UART_DATA
UART_RxState:   DS  1   ; 当前状态(0~7)
UART_RxCmd:     DS  1   ; 收到的命令字节
UART_RxLen:     DS  1   ; 载荷长度
UART_RxIndex:   DS  1   ; 当前正在存的载荷字节下标
UART_RxCrcL:    DS  1   ; CRC低字节
UART_RxCrcH:    DS  1   ; CRC高字节
UART_RxReady:   DS  1   ; 帧就绪标志：1=有新帧, 主循环处理完应清0
UART_RxTmp:     DS  1   ; 临时存放刚收到的字节
UART_RxBuf:     DS  8   ; 载荷缓冲区(最多8字节)


UART_CODE   SEGMENT CODE
RSEG    UART_CODE

; =========================================
; UART 初始化
; =========================================
UART_Init:
        PUSH    ACC 
        ; Timer1工作在模式2(8位自动重装)，作为波特率发生器
        ANL     TMOD, #0FH     ; 清TMOD高4位(Timer1)，保留低4位(Timer0不变)
        ORL     TMOD, #20H     ; 高4位=0010B: GATE=0,C/T=0,M1M0=10(模式2)
        ANL     PCON, #07FH    ; 清SMOD=0，波特率不翻倍
        ; TH1=TL1=0xFD(253), 计数到255溢出→每256-253=3个周期溢出一次
        MOV     TH1, #0FDH     ; 9600bps@11.0592MHz的理论计算值
        MOV     TL1, #0FDH
        MOV     SCON, #50H     ; 0101 0000B: 模式1, REN=1(允许接收)
        CLR     TI             ; 清发送中断标志
        CLR     RI             ; 清接收中断标志
        SETB    TR1            ; 启动Timer1（波特率时钟开始跑）
        SETB    ES             ; 允许串口中断
        SETB    EA             ; 开总中断
        MOV     UART_RxState, #00H ; 状态机从0开始（等第一个0x55）
        MOV     UART_RxReady, #00H ; 没有就绪的帧
        POP     ACC
        RET

; =========================================
; UART 中断服务函数与8状态帧接收机
; =========================================
UART_ISR:
        PUSH    ACC
        PUSH    00H     ; 保护R0 (00H是R0的地址，不能直接PUSH R0)
        PUSH    0D0H    ; 保护PSW (标志寄存器，0D0H是其地址)

        JNB     RI, UART_ISR_CheckTI_Jump ; 不是接收中断(RI=0)，去处理发送
        CLR     RI              ; 清接收标志，准备收下一个
        MOV     A, SBUF         ; 从串口缓冲区读取刚收到的字节
        MOV     UART_RxTmp, A   ; 暂存

        ; 防护：上一帧还没被主循环取走(UART_RxReady=1)？丢弃新字节
        MOV     A, UART_RxReady
        JNZ     UART_ISR_CheckTI_Jump

        ; --- 状态路由表 ---
        ; 根据当前状态(0~7)跳到对应的处理函数。
        ; 为什么不用 JMP @A+DPTR？因为A只有0~7，手写CJNE链更直观。
        ; 为什么大量用LJMP？SJMP只能在±128字节内跳，这个ISR太长必须用LJMP。
        MOV     A, UART_RxState
        CJNE    A, #00H, CHK_ST1
        LJMP    UART_RX_STATE0
CHK_ST1:
        CJNE    A, #01H, CHK_ST2
        LJMP    UART_RX_STATE1
CHK_ST2:
        CJNE    A, #02H, CHK_ST3
        LJMP    UART_RX_STATE2
CHK_ST3:
        CJNE    A, #03H, CHK_ST4
        LJMP    UART_RX_STATE3
CHK_ST4:
        CJNE    A, #04H, CHK_ST5
        LJMP    UART_RX_STATE4
CHK_ST5:
        CJNE    A, #05H, CHK_ST6
        LJMP    UART_RX_STATE5
CHK_ST6:
        CJNE    A, #06H, CHK_ST7
        LJMP    UART_RX_STATE6
CHK_ST7:
        CJNE    A, #07H, UART_RX_RESET_STATE ; 非法状态，复位
        LJMP    UART_RX_STATE7

; 中转跳板：JNB是2字节短跳转(±128字节)，跳不到文件底部的ISR_CheckTI，
; 先跳到这个标签再用LJMP长跳。这是8051汇编处理"长代码"的标准技巧。
UART_ISR_CheckTI_Jump:
        LJMP    UART_ISR_CheckTI

; --- 状态 0：等帧头第一个字节 0x55 ---
UART_RX_STATE0:
        MOV     A, UART_RxTmp
        CJNE    A, #055H, ST0_EXIT   ; 不是0x55，不理
        MOV     UART_RxState, #01H    ; 是0x55！进入状态1（等0xAA）
ST0_EXIT:
        LJMP    UART_ISR_CheckTI

; --- 状态 1：等帧头第二个字节 0xAA ---
UART_RX_STATE1:
        MOV     A, UART_RxTmp
        CJNE    A, #0AAH, UART_RX_RESET_STATE ; 不是0xAA，整帧作废回状态0
        MOV     UART_RxState, #02H            ; 是0xAA！进入状态2
        LJMP    UART_ISR_CheckTI

; --- 状态 2：等版本号 0x01 ---
UART_RX_STATE2:
        MOV     A, UART_RxTmp
        CJNE    A, #001H, UART_RX_RESET_STATE ; 不是0x01=版本不匹配，废帧
        MOV     UART_RxState, #03H
        LJMP    UART_ISR_CheckTI

; --- 状态 3：存储命令字节 CMD ---
UART_RX_STATE3:
        MOV     A, UART_RxTmp
        MOV     UART_RxCmd, A       ; 存命令
        MOV     UART_RxState, #04H  ; 下一个：等长度
        LJMP    UART_ISR_CheckTI

; --- 状态 4：存储长度 LEN 并防溢出 >8 ---
UART_RX_STATE4:
        MOV     A, UART_RxTmp
        MOV     UART_RxLen, A       ; 存长度
        CJNE    A, #009H, ST4_CHK_LEN ; LEN==9?
        LJMP    UART_RX_RESET_STATE ; 等于9，超限！废帧（缓冲区只有8字节）
ST4_CHK_LEN:
        JNC     UART_RX_RESET_STATE ; LEN>9（CJNE后CY=0说明A>9），同样超限
        MOV     A, UART_RxLen
        JZ      ST4_LEN_ZERO        ; LEN=0，没有载荷，直接跳到收CRC
        MOV     UART_RxIndex, #00H  ; 准备从buf[0]开始存
        MOV     UART_RxState, #05H  ; 进入收载荷状态
        LJMP    UART_ISR_CheckTI
ST4_LEN_ZERO:
        MOV     UART_RxState, #06H  ; 跳过收载荷，直接去收CRC
        LJMP    UART_ISR_CheckTI

; --- 状态 5：收载荷 Payload，逐字节存入缓冲区 ---
UART_RX_STATE5:
        MOV     A, UART_RxIndex
        ADD     A, #UART_RxBuf      ; 计算存到哪里：buf的基地址+当前下标
        MOV     R0, A               ; R0 = 目标地址
        MOV     A, UART_RxTmp
        MOV     @R0, A              ; 把收到的字节写入 buf[R0]
        INC     UART_RxIndex        ; 下标+1
        MOV     A, UART_RxIndex
        CJNE    A, UART_RxLen, ST5_EXIT ; 收够Len个了吗？没够继续
        MOV     UART_RxState, #06H  ; 收够了，进入收CRC
ST5_EXIT:
        LJMP    UART_ISR_CheckTI

; --- 状态 6：存 CRC 低字节 ---
UART_RX_STATE6:
        MOV     A, UART_RxTmp
        MOV     UART_RxCrcL, A
        MOV     UART_RxState, #07H  ; 下一个：CRC高字节
        LJMP    UART_ISR_CheckTI

; --- 状态 7：存 CRC 高字节，帧接收完成！--- 
UART_RX_STATE7:
        MOV     A, UART_RxTmp
        MOV     UART_RxCrcH, A
        MOV     UART_RxReady, #01H  ; 立"就绪"标志！主循环的Task_ParseSerial会来取
        MOV     UART_RxState, #00H  ; 状态归零，准备收下一帧
        LJMP    UART_ISR_CheckTI

; --- 状态复位：任何字段不匹配都跳到这里，丢弃当前帧 ---
UART_RX_RESET_STATE:
        MOV     UART_RxState, #00H  ; 回到状态0，重新等0x55
        LJMP    UART_ISR_CheckTI 

; --- 检查 TI (发送中断) 标志 ---
; 当前项目不使用串口发送，但这里留了处理位，为以后扩展保留
UART_ISR_CheckTI:
        JNB     TI, UART_ISR_Exit   ; TI=0（没触发发送中断），直接退出
        CLR     TI                  ; 清发送中断标志

UART_ISR_Exit:
        POP     0D0H    ; 恢复PSW
        POP     00H     ; 恢复R0
        POP     ACC     ; 恢复ACC
        RETI

END