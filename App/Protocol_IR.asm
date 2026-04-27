NAME    PROTOCOL_IR

PUBLIC  Task_ParseIR

EXTRN   DATA (IR_CmdReady)
EXTRN   DATA (IR_Cmd)

NOTE_OFF_EVT    EQU 22

IR_CODE SEGMENT CODE
RSEG    IR_CODE

; Task_ParseIR
; 输出: A = 统一事件(0=无, 1..21=发音, 22=静音)
; 说明: 先适配常见 21 键 NEC 小遥控，后续只需改映射表即可。
Task_ParseIR:
        MOV     A, IR_CmdReady
        JZ      Task_ParseIR_None

        CLR     A
        MOV     IR_CmdReady, A

        MOV     A, IR_Cmd

        ; 常见 21-key NEC 遥控按键码:
        ; 0 -> 16H, 1 -> 0CH, 2 -> 18H, 3 -> 5EH
        ; 4 -> 08H, 5 -> 1CH, 6 -> 5AH, 7 -> 42H, 8 -> 52H, 9 -> 4AH
        ; VOL- -> 07H (作为静音)
        ; 我们将按键 0~9 映射到 统一事件的 30~39 (供 MusicPlayer 播放特定歌曲或延时音符)
        CJNE    A, #016H, Task_ParseIR_CheckMute2
        MOV     A, #30
        SJMP    Task_ParseIR_Exit

Task_ParseIR_CheckMute2:
        CJNE    A, #007H, Task_ParseIR_Check1
        MOV     A, #NOTE_OFF_EVT
        SJMP    Task_ParseIR_Exit

Task_ParseIR_Check1:
        CJNE    A, #00CH, Task_ParseIR_Check2
        MOV     A, #31
        SJMP    Task_ParseIR_Exit

Task_ParseIR_Check2:
        CJNE    A, #018H, Task_ParseIR_Check3
        MOV     A, #32
        SJMP    Task_ParseIR_Exit

Task_ParseIR_Check3:
        CJNE    A, #05EH, Task_ParseIR_Check4
        MOV     A, #33
        SJMP    Task_ParseIR_Exit

Task_ParseIR_Check4:
        CJNE    A, #008H, Task_ParseIR_Check5
        MOV     A, #34
        SJMP    Task_ParseIR_Exit

Task_ParseIR_Check5:
        CJNE    A, #01CH, Task_ParseIR_Check6
        MOV     A, #35
        SJMP    Task_ParseIR_Exit

Task_ParseIR_Check6:
        CJNE    A, #05AH, Task_ParseIR_Check7
        MOV     A, #36
        SJMP    Task_ParseIR_Exit

Task_ParseIR_Check7:
        CJNE    A, #042H, Task_ParseIR_Check8
        MOV     A, #37
        SJMP    Task_ParseIR_Exit

Task_ParseIR_Check8:
        CJNE    A, #052H, Task_ParseIR_Check9
        MOV     A, #38
        SJMP    Task_ParseIR_Exit

Task_ParseIR_Check9:
        CJNE    A, #04AH, Task_ParseIR_None
        MOV     A, #39
        SJMP    Task_ParseIR_Exit

Task_ParseIR_None:
        CLR     A

Task_ParseIR_Exit:
        RET

END
