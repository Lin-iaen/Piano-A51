; ╔══════════════════════════════════════════════════════════════════════╗
; ║  第1部分：文件名片                                                     ║
; ╠══════════════════════════════════════════════════════════════════════╣
; ║  文件名: Protocol.asm                                                 ║
; ║  层级:   App (应用层)                                                 ║
; ║  功能:   解析串口接收到的数据帧，从中提取音符编号，转换为统一事件码。    ║
; ║                                                                      ║
; ║  白话:   串口就像一条数据"水管"，PC上位机会通过它发送音乐控制指令。      ║
; ║          这个文件负责"拆包裹"：                                       ║
; ║          1. 检查有没有新到的完整数据帧（UART_RxReady是否为1）          ║
; ║          2. 用"原子快照"安全地把数据从中断共享区复制出来               ║
; ║             （关中断→复制→清ready→开中断，避免复制到一半被新数据覆盖）  ║
; ║          3. 校验：Cmd必须是0x02，payload[0]必须在0~21之间              ║
; ║          4. 把payload[0]转成统一事件码（0→静音22, 1~21→直接发音）     ║
; ║                                                                      ║
; ║  调用者: Main.asm 主循环每轮调 Task_ParseSerial                       ║
; ║  依赖:   Drv_Uart.asm（读取它发布的 UART_RxReady/RxCmd/RxLen/RxBuf）  ║
; ║  曾出过Bug: 详见 Issue_Review_2026-04-24——UART中断与主循环并发读写    ║
; ║             导致读到半帧数据。原子快照就是为此加的修复。                ║
; ╚══════════════════════════════════════════════════════════════════════╝
;
; ╔══════════════════════════════════════════════════════════════════════╗
; ║  第2部分：汇编指令速查表（本文件出现的所有指令）                        ║
; ╠══════════════════════════════════════════════════════════════════════╣
; ║  EQU  n        │ 伪指令：给常数n取个名字（NOTE_OFF_EVT EQU 22）       ║
; ║  PUSH 直接地址  │ 压栈保存                                            ║
; ║  POP  直接地址  │ 弹栈恢复                                            ║
; ║  MOV  A, 直接地址│ 从内存地址读取值到A                                  ║
; ║  JZ   标签      │ A=0跳转                                             ║
; ║  JNZ  标签      │ A≠0跳转                                             ║
; ║  CLR  ES       │ 关串口中断。ES是IE寄存器的bit4（禁止UART中断）        ║
; ║  SETB ES       │ 开串口中断                                           ║
; ║  CJNE A, #n, 标签│ 比较跳转                                            ║
; ║  CLR  C        │ 清CY（SUBB之前的必备操作）                            ║
; ║  SUBB A, #n    │ 带借位减法，配合JNC/JC做范围判断                      ║
; ║  JC   标签      │ CY=1就跳转（即"有借位"时跳）                         ║
; ║  JNC  标签      │ CY=0就跳转（即"无借位/够减"时跳）                    ║
; ║  SJMP 标签      │ 无条件短跳转                                        ║
; ║  CLR  A        │ A清零（返回0=无事件）                                 ║
; ║  RET           │ 返回调用者                                          ║
; ╚══════════════════════════════════════════════════════════════════════╝
;
; ╔══════════════════════════════════════════════════════════════════════╗
; ║  第3部分：特殊功能寄存器速查表（本文件涉及的SFR）                       ║
; ╠══════════════════════════════════════════════════════════════════════╣
; ║  IE │ A8H │ 中断允许寄存器。ES(bit4)=串口中断开关：SETB=允许, CLR=禁止║
; ║     │     │ 原子快照的核心：CLR ES 暂时禁止串口中断，防止复制数据时   ║
; ║     │     │ 新的接收字节破坏正在读取的帧                             ║
; ╚══════════════════════════════════════════════════════════════════════╝

NAME    PROTOCOL

PUBLIC  Task_ParseSerial

EXTRN   DATA (UART_RxReady)
EXTRN   DATA (UART_RxCmd)
EXTRN   DATA (UART_RxLen)
EXTRN   DATA (UART_RxBuf)  ; 引入接收缓冲区

NOTE_OFF_EVT    EQU 22      ; 静音事件的统一编码

PROTOCOL_CODE    SEGMENT CODE
RSEG    PROTOCOL_CODE

Task_ParseSerial:
        PUSH    00H         ; R0的地址是00H
        PUSH    01H         ; R1
        PUSH    02H         ; R2

        ; 检查是否有新帧
        MOV     A, UART_RxReady
        JZ      Task_ParseSerial_None   ; 没有，直接返回0

        ; ==========================================
        ; 原子快照：解决"中断与主循环并发读写"的Bug
        ; 问题场景：主循环读到一半，UART中断又收到新字节，
        ;          导致读到的帧是"拼凑"的，数据错乱。
        ; 解决方案：关中断→快速复制→开中断，中间极短，
        ;          不会丢数据（8051的UART有缓冲）。
        ; ==========================================
        CLR     ES              ; ① 关串口中断（禁止UART ISR执行）
        
        MOV     A, UART_RxCmd   ; ② 快照Cmd
        MOV     R1, A
        MOV     A, UART_RxLen   ; ③ 快照Len
        MOV     R2, A
        JZ      Task_ParseSerial_NoPayloadCopy ; Len=0，没有Payload
        MOV     A, UART_RxBuf   ; ④ 快照Payload[0]
        SJMP    Task_ParseSerial_PayloadCopied

Task_ParseSerial_NoPayloadCopy:
        CLR     A               ; Len=0时Payload视为0

Task_ParseSerial_PayloadCopied:
        MOV     R0, A           ; R0 = Payload[0]

        CLR     A
        MOV     UART_RxReady, A ; ⑤ 清Ready标志——这帧我们已经取走了
        SETB    ES              ; ⑥ 重新打开串口中断

        ; --- 1. 检查指令类型 (Cmd == 0x02 才是音符控制) ---
        MOV     A, R1
        CJNE    A, #02H, Task_ParseSerial_None ; 不是0x02，忽略此帧

        ; --- 2. 检查是否有载荷数据 (Len > 0) ---
        MOV     A, R2
        JZ      Task_ParseSerial_None ; Len=0，没有有效数据

        ; --- 3. payload[0]的值在R0中 ---
        MOV     A, R0

        ; --- 4. 业务逻辑转换 ---
        JNZ     Task_ParseSerial_CheckRange ; payload[0]!=0，继续检查
        
        MOV     A, #NOTE_OFF_EVT  ; payload[0]==0 → 静音事件(22)
        SJMP    Task_ParseSerial_Exit

Task_ParseSerial_CheckRange:
        ; 检查是否在合法范围 1~21
        ; 方法：先看是否 < 1（即=0或负数），再看是否 >= 22
        CLR     C               ; 清借位标志（SUBB必须）
        SUBB    A, #01H         ; A = payload - 1
        JC      Task_ParseSerial_None ; CY=1说明payload<1（即0或负数），非法

        MOV     A, R0           ; 恢复原始值
        CLR     C
        SUBB    A, #22          ; A = payload - 22
        JNC     Task_ParseSerial_None ; CY=0说明payload>=22，非法

        ; 合法！直接返回payload值（1~21），它就是事件码
        MOV     A, R0
        SJMP    Task_ParseSerial_Exit

Task_ParseSerial_None:
        SETB    ES              ; 确保中断是开的
        CLR     A               ; 返回0=无事件

Task_ParseSerial_Exit:
        POP     02H
        POP     01H
        POP     00H
        RET

END