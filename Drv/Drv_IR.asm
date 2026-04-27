NAME    DRV_IR

PUBLIC  IR_Init
PUBLIC  IR_ISR
PUBLIC  IR_CmdReady
PUBLIC  IR_Cmd

; 直接地址定义，避免不同器件头文件命名差异
T2CON_REG   EQU 0C8H
TL2_REG     EQU 0CCH
TH2_REG     EQU 0CDH

IR_IT0 BIT 088H
IR_EX0 BIT 0A8H
IR_TR2 BIT 0CAH

IR_DATA SEGMENT DATA
RSEG    IR_DATA
IR_State:       DS 1    ; 0=空闲, 1=等待引导间隔, 2=接收32位数据
IR_BitCnt:      DS 1
IR_Mask:        DS 1
IR_ByteIdx:     DS 1
IR_Data0:       DS 1
IR_Data1:       DS 1
IR_Data2:       DS 1
IR_Data3:       DS 1
IR_DeltaH:      DS 1
IR_DeltaL:      DS 1
IR_LastCmd:     DS 1
IR_CmdReady:    DS 1
IR_Cmd:         DS 1

IR_CODE SEGMENT CODE
RSEG    IR_CODE

IR_Init:
        CLR     IR_EX0
        CLR     IR_TR2

        MOV     T2CON_REG, #00H
        MOV     TH2_REG, #00H
        MOV     TL2_REG, #00H

        MOV     IR_State, #0
        MOV     IR_BitCnt, #0
        MOV     IR_Mask, #01H
        MOV     IR_ByteIdx, #0
        MOV     IR_Data0, #0
        MOV     IR_Data1, #0
        MOV     IR_Data2, #0
        MOV     IR_Data3, #0
        MOV     IR_DeltaH, #0
        MOV     IR_DeltaL, #0
        MOV     IR_LastCmd, #0
        MOV     IR_CmdReady, #0
        MOV     IR_Cmd, #0

        SETB    IR_IT0
        SETB    IR_TR2
        SETB    IR_EX0
        RET

; INT0 下降沿中断：通过相邻下降沿间隔进行 NEC 粗解码
IR_ISR:
        PUSH    ACC
        PUSH    0D0H

        MOV     A, TH2_REG
        MOV     IR_DeltaH, A
        MOV     A, TL2_REG
        MOV     IR_DeltaL, A
        MOV     TH2_REG, #00H
        MOV     TL2_REG, #00H

        MOV     A, IR_State
        JZ      IR_ISR_FromIdle
        DEC     A
        JZ      IR_ISR_CheckLead
        LJMP    IR_ISR_DecodeBit

IR_ISR_FromIdle:
        MOV     IR_State, #1
        LJMP    IR_ISR_Exit

IR_ISR_CheckLead:
        ; repeat: 约 11.25ms，计数高字节区间 [24H,2CH)
        MOV     A, IR_DeltaH
        CLR     C
        SUBB    A, #024H
        JC      IR_ISR_CheckStart

        MOV     A, IR_DeltaH
        CLR     C
        SUBB    A, #02CH
        JC      IR_ISR_RepeatFrame

IR_ISR_CheckStart:
        ; start: 约 13.5ms，计数高字节区间 [2CH,37H)
        MOV     A, IR_DeltaH
        CLR     C
        SUBB    A, #02CH
        JNC     IR_ISR_CheckStart_Upper  ; >= 2CH，不借位，跳去检查上限
        LJMP    IR_ISR_ResetIdle         ; < 2CH，错的，长跳转复位

IR_ISR_CheckStart_Upper:
        MOV     A, IR_DeltaH
        CLR     C
        SUBB    A, #037H
        JC      IR_ISR_StartFrame_Go     ; < 37H，借位了，说明在合法区间内！
        LJMP    IR_ISR_ResetIdle         ; >= 37H，错的，长跳转复位

IR_ISR_StartFrame_Go:                    ; 【新增中转标签】
        LJMP    IR_ISR_StartFrame        ; 安全地长跳转去启动帧处理


IR_ISR_RepeatFrame:
        MOV     A, IR_LastCmd
        JNZ     IR_ISR_RepeatFrame_Go    ; 【逻辑反转】：如果不为0，说明有上一条命令，跳去执行！
        LJMP    IR_ISR_ResetIdle         ; 如果为0，长跳转复位

IR_ISR_RepeatFrame_Go:                   ; 【新增中转标签】
        ; 屏蔽连发事件，防止歌曲或单音发生持续“口吃”重播
        MOV     IR_Cmd, A
        ; MOV     IR_CmdReady, #1 ; 被屏蔽
        NOP
        NOP
        NOP
        LJMP    IR_ISR_ResetIdle

IR_ISR_StartFrame:
        MOV     IR_State, #2
        MOV     IR_BitCnt, #0
        MOV     IR_Mask, #01H
        MOV     IR_ByteIdx, #0
        MOV     IR_Data0, #0
        MOV     IR_Data1, #0
        MOV     IR_Data2, #0
        MOV     IR_Data3, #0
        LJMP    IR_ISR_Exit

IR_ISR_DecodeBit:
        ; bit0: <6ms高字节阈值; bit1: <11ms高字节阈值
        MOV     A, IR_DeltaH
        CLR     C
        SUBB    A, #006H
        JC      IR_ISR_StoreBit0

        MOV     A, IR_DeltaH
        CLR     C
        SUBB    A, #00BH
        JC      IR_ISR_StoreBit1

        LJMP    IR_ISR_ResetIdle

IR_ISR_StoreBit0:
        SJMP    IR_ISR_AfterStoreBit

IR_ISR_StoreBit1:
        MOV     A, IR_ByteIdx
        JZ      IR_ISR_StoreByte0

        CJNE    A, #1, IR_ISR_CheckByte2
        MOV     A, IR_Mask
        ORL     IR_Data1, A
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
        ORL     IR_Data0, A

IR_ISR_AfterStoreBit:
        MOV     A, IR_Mask
        CLR     C
        RLC     A
        MOV     IR_Mask, A
        JNZ     IR_ISR_IncBitCnt

        MOV     IR_Mask, #01H
        INC     IR_ByteIdx

IR_ISR_IncBitCnt:
        INC     IR_BitCnt
        MOV     A, IR_BitCnt
        CJNE    A, #32, IR_ISR_Exit

        MOV     A, IR_Data0
        XRL     A, IR_Data1
        CJNE    A, #0FFH, IR_ISR_ResetIdle

        MOV     A, IR_Data2
        XRL     A, IR_Data3
        CJNE    A, #0FFH, IR_ISR_ResetIdle

        MOV     A, IR_Data2
        MOV     IR_Cmd, A
        MOV     IR_LastCmd, A
        MOV     IR_CmdReady, #1

IR_ISR_ResetIdle:
        MOV     IR_State, #0

IR_ISR_Exit:
        POP     0D0H
        POP     ACC
        RETI

END
