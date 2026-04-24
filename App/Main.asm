NAME    MAIN

EXTRN   CODE (Timer0_Init)
EXTRN   CODE (UART_Init)
EXTRN   CODE (Timer0_ISR)
EXTRN   CODE (UART_ISR)
EXTRN   CODE (IR_Init)
EXTRN   CODE (IR_ISR)
EXTRN   CODE (Task_ParseSerial)
EXTRN   CODE (Task_ParseIR)
	
EXTRN   CODE (Key_Scan)
EXTRN   CODE (Buzzer_Play)
EXTRN   CODE (Led_ShowSpectrum)
	
EXTRN   CODE (Lcd_Init)
EXTRN   CODE (Lcd_WriteCmd)
EXTRN   CODE (Lcd_WriteData)
EXTRN   CODE (Lcd_LoadCustomChars)

CSEG

NOTE_OFF_EVT    EQU     22

ORG     0000H
	LJMP    MAIN_START

ORG     0003H
	LJMP    IR_ISR

ORG     000BH
	LJMP    Timer0_ISR

ORG     0023H
	LJMP    UART_ISR

ORG     0030H
MAIN_START:
	MOV     SP, #50H

	LCALL   Timer0_Init
	LCALL   UART_Init
	LCALL   IR_Init

	LCALL   Lcd_Init
        
        ; 【新增】：把阴阳码加载到屏幕的显存里！
        LCALL   Lcd_LoadCustomChars 
        
        ; --- 设置光标到第一行开头 ---
        MOV     A, #80H
        LCALL   Lcd_WriteCmd
        
        ; 【见证奇迹】：召唤第 0 个自定义字符 (也就是我们的阴阳码 1)
        ; 注意这里不能写 #'1'，必须写 #00H！
        MOV     A, #00H     
        LCALL   Lcd_WriteData

        SETB    EA              ; 开启总中断
	
	; CLR     P1.0

MAIN_LOOP:
	LCALL   Task_ParseSerial
	LCALL   Dispatch_Event

	LCALL   Task_ParseIR
	LCALL   Dispatch_Event

	LCALL   Key_Scan
	LCALL   Key_ToEvent
	LCALL   Dispatch_Event

	SJMP    MAIN_LOOP

; --------------------------------------------------------
; Key_ToEvent
; 输入: A = Key_Scan 返回值(0/1/2/3/4/5)
; 输出: A = 统一事件(0=无, 1..21=发音, 22=静音)
; --------------------------------------------------------
Key_ToEvent:
	JZ      Key_ToEvent_None

	CJNE    A, #5, Key_ToEvent_CheckK1
	MOV     A, #NOTE_OFF_EVT
	RET

Key_ToEvent_CheckK1:
	CJNE    A, #1, Key_ToEvent_CheckK2
	MOV     A, #NOTE_OFF_EVT
	RET

Key_ToEvent_CheckK2:
	CJNE    A, #2, Key_ToEvent_CheckK3
	MOV     A, #1
	RET

Key_ToEvent_CheckK3:
	CJNE    A, #3, Key_ToEvent_CheckK4
	MOV     A, #8
	RET

Key_ToEvent_CheckK4:
	CJNE    A, #4, Key_ToEvent_None
	MOV     A, #15
	RET

Key_ToEvent_None:
	CLR     A
	RET

; --------------------------------------------------------
; Dispatch_Event
; 输入: A = 统一事件(0=无, 1..21=发音, 22=静音)
; --------------------------------------------------------
Dispatch_Event:
	PUSH    07H

	JZ      Dispatch_Event_Exit

	CJNE    A, #NOTE_OFF_EVT, Dispatch_Event_Play
	CLR     A
	LCALL   Buzzer_Play
	LCALL   Led_ShowSpectrum
	SJMP    Dispatch_Event_Exit

Dispatch_Event_Play:
	MOV     R7, A
	CLR     C
	SUBB    A, #NOTE_OFF_EVT
	JNC     Dispatch_Event_Exit

	MOV     A, R7
	LCALL   Buzzer_Play
	LCALL   Led_ShowSpectrum

Dispatch_Event_Exit:
	POP     07H
	RET

END
