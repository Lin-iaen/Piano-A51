NAME    PROTOCOL

PUBLIC  Task_ParseSerial

EXTRN   DATA (UART_RxReady)
EXTRN   DATA (UART_RxCmd)

NOTE_OFF_EVT    EQU 22

PROTOCOL_CODE    SEGMENT CODE
RSEG    PROTOCOL_CODE

Task_ParseSerial:
	PUSH    00H

    MOV     A, UART_RxReady
	JZ      Task_ParseSerial_None

	CLR     A
	MOV     UART_RxReady, A
	MOV     A, UART_RxCmd
	JZ      Task_ParseSerial_None

	MOV     R0, A
	CJNE    A, #NOTE_OFF_EVT, Task_ParseSerial_CheckRange
	MOV     A, R0
	SJMP    Task_ParseSerial_Exit

Task_ParseSerial_CheckRange:
	CLR     C
	SUBB    A, #01H
	JC      Task_ParseSerial_None

	MOV     A, R0
	CLR     C
	SUBB    A, #NOTE_OFF_EVT
	JNC     Task_ParseSerial_None

	MOV     A, R0

Task_ParseSerial_Exit:
	POP     00H
	RET

END