; ╔══════════════════════════════════════════════════════════════════════╗
; ║  第1部分：文件名片                                                   ║
; ╠══════════════════════════════════════════════════════════════════════╣
; ║  文件名: Protocol_IR.asm                                             ║
; ║  层级:   App (应用层)                                                ║
; ║  功能:   把红外驱动解码出的"遥控器原始按键码"翻译成"统一事件码"。    ║
; ║                                                                      ║
; ║  白话:   红外驱动会告诉代码按键的原始码 例如0CH。                    ║
; ║          这个文件像一个"翻译官"，拿着一本字典（CJNE链），            ║
; ║          把原始遥控码映射成系统能理解的统一事件：                    ║
; ║          - 遥控0~9 → 事件30~39（触发歌曲播放或单音）                 ║
; ║          - 遥控VOL- → 事件22（静音）                                 ║
; ║          不认识的按键码 → 忽略。                                     ║
; ║                                                                      ║
; ║  遥控器型号: 21键NEC小遥控                                           ║
; ║  调用者: Main.asm 主循环每轮调 Task_ParseIR                          ║
; ║  依赖:   Drv_IR.asm（读它的 IR_CmdReady / IR_Cmd）                   ║
; ╚══════════════════════════════════════════════════════════════════════╝
;
; ╔══════════════════════════════════════════════════════════════════════╗
; ║  第2部分：汇编指令速查表（本文件出现的所有指令）                     ║
; ╠══════════════════════════════════════════════════════════════════════╣
; ║  CJNE A, #n, 标签│ 比较跳转。这里用CJNE链实现"遥控码→事件码"查表     ║
; ║                 │ 技巧：一串CJNE像 if-else if-else 链                ║
; ║  其余指令: MOV / JZ / JNZ / SJMP / CLR A / RET / EQU                 ║
; ╚══════════════════════════════════════════════════════════════════════╝
;
; ╔══════════════════════════════════════════════════════════════════════╗
; ║  第3部分：特殊功能寄存器速查表                                       ║
; ╠══════════════════════════════════════════════════════════════════════╣
; ║  本文件未使用任何SFR。（纯数据转换，不操作硬件）                     ║
; ╚══════════════════════════════════════════════════════════════════════╝

NAME    PROTOCOL_IR

PUBLIC  Task_ParseIR

EXTRN   DATA (IR_CmdReady)
EXTRN   DATA (IR_Cmd)

NOTE_OFF_EVT    EQU 22

IR_CODE SEGMENT CODE
RSEG    IR_CODE

; Task_ParseIR
; 输出: A = 统一事件(0=无, 1..21=发音, 22=静音, 30~39=歌曲)
; 说明: 先适配常见 21 键 NEC 小遥控，后续只需改映射表即可。
Task_ParseIR:
        MOV     A, IR_CmdReady
        JZ      Task_ParseIR_None    ; 没有新遥控命令

        CLR     A
        MOV     IR_CmdReady, A       ; 消费就绪标志（防止重复处理）

        MOV     A, IR_Cmd            ; 取原始按键码

        ; ============ 遥控码 → 统一事件 映射表 ============
        ; 常见的 21-key NEC 小遥控：
        ;   0→16H, 1→0CH, 2→18H, 3→5EH, 4→08H
        ;   5→1CH, 6→5AH, 7→42H, 8→52H, 9→4AH
        ;   VOL-→07H
        ; 映射：0→30(歌曲0), 1→31(歌曲1), ..., 9→39(歌曲9)
        ;       VOL- → 22(静音)
        ; 
        ; 实现方式：一条CJNE链（等于手写 if-else if-else）
        ; 为什么不用查表(MOVC)？按键码是不连续的值(16H,0CH,18H...)，
        ; 没法用A做偏移直接查表，手写CJNE链更简单直接。
        
        CJNE    A, #016H, Task_ParseIR_CheckMute2
        MOV     A, #30            ; 遥控0 → 事件30
        SJMP    Task_ParseIR_Exit

Task_ParseIR_CheckMute2:
        CJNE    A, #007H, Task_ParseIR_Check1
        MOV     A, #NOTE_OFF_EVT  ; VOL- → 静音(22)
        SJMP    Task_ParseIR_Exit

Task_ParseIR_Check1:
        CJNE    A, #00CH, Task_ParseIR_Check2
        MOV     A, #31            ; 遥控1 → 事件31
        SJMP    Task_ParseIR_Exit

Task_ParseIR_Check2:
        CJNE    A, #018H, Task_ParseIR_Check3
        MOV     A, #32            ; 遥控2 → 事件32
        SJMP    Task_ParseIR_Exit

Task_ParseIR_Check3:
        CJNE    A, #05EH, Task_ParseIR_Check4
        MOV     A, #33            ; 遥控3 → 事件33
        SJMP    Task_ParseIR_Exit

Task_ParseIR_Check4:
        CJNE    A, #008H, Task_ParseIR_Check5
        MOV     A, #34            ; 遥控4 → 事件34
        SJMP    Task_ParseIR_Exit

Task_ParseIR_Check5:
        CJNE    A, #01CH, Task_ParseIR_Check6
        MOV     A, #35            ; 遥控5 → 事件35
        SJMP    Task_ParseIR_Exit

Task_ParseIR_Check6:
        CJNE    A, #05AH, Task_ParseIR_Check7
        MOV     A, #36            ; 遥控6 → 事件36
        SJMP    Task_ParseIR_Exit

Task_ParseIR_Check7:
        CJNE    A, #042H, Task_ParseIR_Check8
        MOV     A, #37            ; 遥控7 → 事件37
        SJMP    Task_ParseIR_Exit

Task_ParseIR_Check8:
        CJNE    A, #052H, Task_ParseIR_Check9
        MOV     A, #38            ; 遥控8 → 事件38
        SJMP    Task_ParseIR_Exit

Task_ParseIR_Check9:
        CJNE    A, #04AH, Task_ParseIR_None ; 不是遥控9也不认识→忽略
        MOV     A, #39            ; 遥控9 → 事件39
        SJMP    Task_ParseIR_Exit

Task_ParseIR_None:
        CLR     A                 ; 返回0=无事件

Task_ParseIR_Exit:
        RET

END
