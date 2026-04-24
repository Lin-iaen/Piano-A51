NAME    PROTOCOL

PUBLIC  Task_ParseSerial

EXTRN   CODE (UART_ReadByte)
EXTRN   CODE (Buzzer_Play)
EXTRN   CODE (Led_ShowSpectrum)
// EXTRN   CODE (Delay_ms)    

PROTOCOL_CODE    SEGMENT CODE
RSEG    PROTOCOL_CODE

Task_ParseSerial:
	PUSH    ACC
	PUSH    00H

	LCALL   UART_ReadByte
	JNC     Task_ParseSerial_Exit   ; 如果缓冲区没数据，直接退出

	MOV     R0, A

	CJNE    A, #'0', Task_ParseSerial_CheckSpace
	CLR     A
	LCALL   Buzzer_Play
	LCALL   Led_ShowSpectrum
	SJMP    Task_ParseSerial_Exit  ; 【修改】查到休止符，跳转去延时

Task_ParseSerial_CheckSpace:
	CJNE    A, #' ', Task_ParseSerial_CheckMiddle
	CLR     A
	LCALL   Buzzer_Play
	LCALL   Led_ShowSpectrum
	SJMP    Task_ParseSerial_Exit  ; 【修改】查到休止符，跳转去延时

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
	LCALL   Buzzer_Play
	LCALL   Led_ShowSpectrum
	SJMP    Task_ParseSerial_Exit  ; 【修改】发声后，跳转去延时

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
	LCALL   Buzzer_Play
	LCALL   Led_ShowSpectrum
	SJMP    Task_ParseSerial_Exit  ; 【修改】发声后，跳转去延时

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
	LCALL   Buzzer_Play
	LCALL   Led_ShowSpectrum
	; 高音发声后，顺延进入下面的延时逻辑

; =======================================
; 【新增核心】音符节拍器与切分音处理
; =======================================
/*Task_ParseSerial_Delay:
	; 1. 让当前音符（或静音）保持 200 毫秒（相当于一拍）
	MOV     R7, #200
	LCALL   Delay_ms
	
	; 2. 极其关键的“切分音”：强制闭嘴 20 毫秒
	; 如果连续发送 "11"，没有这段静音，听起来就像是一个长长的 "1"
	CLR     A
	LCALL   Buzzer_Play
	MOV     R7, #20
	LCALL   Delay_ms*/

Task_ParseSerial_Exit:
	POP     00H
	POP     ACC
	RET

END