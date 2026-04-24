NAME    PROTOCOL

PUBLIC  Task_ParseSerial

EXTRN   CODE (UART_ReadByte)

NOTE_OFF_EVT    EQU 22

PROTOCOL_CODE    SEGMENT CODE
RSEG    PROTOCOL_CODE

Task_ParseSerial:
	PUSH    00H

	LCALL   UART_ReadByte
	JNC     Task_ParseSerial_None   ; 如果缓冲区没数据，直接退出

	MOV     R0, A

	CJNE    A, #'0', Task_ParseSerial_CheckSpace
	MOV     A, #NOTE_OFF_EVT
	SJMP    Task_ParseSerial_Exit

Task_ParseSerial_CheckSpace:
	CJNE    A, #' ', Task_ParseSerial_CheckMiddle
	MOV     A, #NOTE_OFF_EVT
	SJMP    Task_ParseSerial_Exit

Task_ParseSerial_CheckMiddle:
	MOV     A, R0
	CLR     C
	SUBB    A, #'1'
	JC      Task_ParseSerial_CheckLow
	CJNE    A, #07, Task_ParseSerial_MiddleRange
	SJMP    Task_ParseSerial_CheckLow

Task_ParseSerial_MiddleRange:
	JNC     Task_ParseSerial_CheckLow
	ADD     A, #08
	SJMP    Task_ParseSerial_Exit

Task_ParseSerial_CheckLow:
	MOV     A, R0
	CLR     C
	SUBB    A, #'a'
	JC      Task_ParseSerial_CheckHigh
	CJNE    A, #07, Task_ParseSerial_LowRange
	SJMP    Task_ParseSerial_CheckHigh

Task_ParseSerial_LowRange:
	JNC     Task_ParseSerial_CheckHigh
	INC     A
	SJMP    Task_ParseSerial_Exit

Task_ParseSerial_CheckHigh:
	MOV     A, R0
	CLR     C
	SUBB    A, #'A'
	JC      Task_ParseSerial_Exit
	CJNE    A, #07, Task_ParseSerial_HighRange
	SJMP    Task_ParseSerial_Exit

Task_ParseSerial_HighRange:
	JNC     Task_ParseSerial_Exit
	ADD     A, #15
	SJMP    Task_ParseSerial_Exit

Task_ParseSerial_None:
	CLR     A

Task_ParseSerial_Exit:
	POP     00H
	RET

END