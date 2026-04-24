NAME    DRV_UART

PUBLIC  UART_Init
PUBLIC  UART_ISR
PUBLIC  UART_ReadByte
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
UART_RxState:   DS  1
UART_RxCmd:     DS  1
UART_RxLen:     DS  1
UART_RxIndex:   DS  1
UART_RxCrcL:    DS  1
UART_RxCrcH:    DS  1
UART_RxReady:   DS  1
UART_RxTmp:     DS  1

UART_IDATA  SEGMENT IDATA
RSEG    UART_IDATA
UART_RxBuf:     DS  8

UART_CODE   SEGMENT CODE
RSEG    UART_CODE

; UART_Init
; 11.0592MHz crystal, Timer1 mode2 auto-reload, 9600 baud.
UART_Init:
	PUSH    ACC

	ANL     TMOD, #0FH ; 使用ANL清除高4位，保留低4位
	ORL     TMOD, #20H ; 0010 0000B, 定时器1工作在模式2（8位自动重载模式）

	ANL     PCON, #07FH ; SMOD位清0，波特率不加倍
	MOV     TH1, #0FDH ; 重装载值
	MOV     TL1, #0FDH ; 预装载值

	MOV     SCON, #50H

	CLR     TI
	CLR     RI
	SETB    TR1
	SETB    ES
	SETB    EA

	MOV     UART_RxState, #00H
	MOV     UART_RxCmd, #00H
	MOV     UART_RxLen, #00H
	MOV     UART_RxIndex, #00H
	MOV     UART_RxCrcL, #00H
	MOV     UART_RxCrcH, #00H
	MOV     UART_RxReady, #00H
	MOV     UART_RxTmp, #00H

	POP     ACC
	RET

; UART_ISR
; Serial interrupt body, called from vector in Main.asm.
UART_ISR:
	PUSH    ACC
	PUSH    00H
	PUSH    0D0H

	JNB     RI, UART_ISR_CheckTI
	CLR     RI
	MOV     A, SBUF
	MOV     UART_RxTmp, A

	MOV     A, UART_RxReady
	JNZ     UART_ISR_CheckTI

	MOV     A, UART_RxState
	JZ      UART_RX_STATE0
	DEC     A
	JZ      UART_RX_STATE1
	DEC     A
	JZ      UART_RX_STATE2
	DEC     A
	JZ      UART_RX_STATE3
	DEC     A
	JZ      UART_RX_STATE4
	DEC     A
	JZ      UART_RX_STATE5
	DEC     A
	JZ      UART_RX_STATE6
	SJMP    UART_RX_STATE7

UART_RX_STATE0:
	MOV     A, UART_RxTmp
	CJNE    A, #055H, UART_RX_STATE0_EXIT
	MOV     UART_RxState, #01H

UART_RX_STATE0_EXIT:
	SJMP    UART_ISR_CheckTI

UART_RX_STATE1:
	MOV     A, UART_RxTmp
	CJNE    A, #0AAH, UART_RX_RESET_STATE
	MOV     UART_RxState, #02H
	SJMP    UART_ISR_CheckTI

UART_RX_STATE2:
	MOV     A, UART_RxTmp
	CJNE    A, #001H, UART_RX_RESET_STATE
	MOV     UART_RxState, #03H
	SJMP    UART_ISR_CheckTI

UART_RX_STATE3:
	MOV     A, UART_RxTmp
	MOV     UART_RxCmd, A
	MOV     UART_RxState, #04H
	SJMP    UART_ISR_CheckTI

UART_RX_STATE4:
	MOV     A, UART_RxTmp
	MOV     UART_RxLen, A
	CJNE    A, #009H, UART_RX_STATE4_LEN_CHECK
	SJMP    UART_RX_RESET_STATE

UART_RX_STATE4_LEN_CHECK:
	JNC     UART_RX_RESET_STATE
	MOV     A, UART_RxLen
	JZ      UART_RX_STATE4_LEN_ZERO
	MOV     UART_RxIndex, #00H
	MOV     UART_RxState, #05H
	SJMP    UART_ISR_CheckTI

UART_RX_STATE4_LEN_ZERO:
	MOV     UART_RxState, #06H
	SJMP    UART_ISR_CheckTI

UART_RX_STATE5:
	MOV     A, UART_RxIndex
	ADD     A, #UART_RxBuf
	MOV     R0, A
	MOV     A, UART_RxTmp
	MOV     @R0, A

	INC     UART_RxIndex
	MOV     A, UART_RxIndex
	CJNE    A, UART_RxLen, UART_RX_STATE5_EXIT
	MOV     UART_RxState, #06H

UART_RX_STATE5_EXIT:
	SJMP    UART_ISR_CheckTI

UART_RX_STATE6:
	MOV     A, UART_RxTmp
	MOV     UART_RxCrcL, A
	MOV     UART_RxState, #07H
	SJMP    UART_ISR_CheckTI

UART_RX_STATE7:
	MOV     A, UART_RxTmp
	MOV     UART_RxCrcH, A
	MOV     UART_RxIndex, #0FFH
	MOV     UART_RxReady, #01H
	MOV     UART_RxState, #00H
	SJMP    UART_ISR_CheckTI

UART_RX_RESET_STATE:
	MOV     UART_RxState, #00H
	SJMP    UART_ISR_CheckTI

UART_ISR_CheckTI:
	JNB     TI, UART_ISR_Exit
	CLR     TI

UART_ISR_Exit:
	POP     0D0H
	POP     00H
	POP     ACC
	RETI

; UART_ReadByte
; Return frame stream: first CMD, then Payload bytes.
; ACC=data, C=1 on success; ACC=00H, C=0 if no completed frame is available.
UART_ReadByte:
	PUSH    00H
	MOV     A, UART_RxReady
	JZ      UART_Read_Empty

	MOV     A, UART_RxIndex
	CJNE    A, #0FFH, UART_Read_Payload

	MOV     A, UART_RxCmd
	MOV     UART_RxIndex, #00H
	MOV     A, UART_RxLen
	JZ      UART_Read_CommandDone
	SETB    C
	SJMP    UART_Read_Return

UART_Read_CommandDone:
	CLR     A
	MOV     UART_RxReady, A
	CLR     C
	SJMP    UART_Read_Return

UART_Read_Payload:
	MOV     A, UART_RxIndex
	CJNE    A, UART_RxLen, UART_Read_PayloadCheck
	SJMP    UART_Read_EmptyAndClear

UART_Read_PayloadCheck:
	JNC     UART_Read_EmptyAndClear
	ADD     A, #UART_RxBuf
	MOV     R0, A
	MOV     A, @R0
	INC     UART_RxIndex
	MOV     A, UART_RxIndex
	CJNE    A, UART_RxLen, UART_Read_PayloadDone
	CLR     A
	MOV     UART_RxReady, A
	MOV     UART_RxIndex, A
	SETB    C
	SJMP    UART_Read_Return

UART_Read_PayloadDone:
	SETB    C
	SJMP    UART_Read_Return

UART_Read_EmptyAndClear:
	CLR     A
	MOV     UART_RxReady, A
	MOV     UART_RxIndex, A
	CLR     C

UART_Read_Empty:
	CLR     A
	CLR     C

UART_Read_Return:
	POP     00H
	RET

END
