NAME    MAIN

EXTRN   CODE (Timer0_Init)
EXTRN   CODE (UART_Init)
EXTRN   CODE (Timer0_ISR)
EXTRN   CODE (UART_ISR)
EXTRN   CODE (Task_ParseSerial)
	
EXTRN   CODE (Key_Scan)
EXTRN   CODE (Buzzer_Play)
EXTRN   CODE (Led_ShowSpectrum)
	
EXTRN   CODE (Lcd_Init)
EXTRN   CODE (Lcd_WriteCmd)
EXTRN   CODE (Lcd_WriteData)
EXTRN   CODE (Lcd_LoadCustomChars)

CSEG

ORG     0000H
	LJMP    MAIN_START

ORG     000BH
	LJMP    Timer0_ISR

ORG     0023H
	LJMP    UART_ISR

ORG     0030H
MAIN_START:
	MOV     SP, #50H

	LCALL   Timer0_Init
	LCALL   UART_Init

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
	
	; 2. 巡视板子上的 S1 按键有没有被按下
	LCALL   Key_Scan
	JZ      MAIN_LOOP_END   ; 如果 ACC 是 0 (没按下)，跳过静音逻辑

	; 先处理“松手事件”(Key_Scan 返回 5)，避免被后续分支误改写
	CJNE    A, #5, CHECK_KEY_PRESS
	CLR     A
	LCALL   Buzzer_Play
	LCALL   Led_ShowSpectrum
	SJMP    MAIN_LOOP_END

CHECK_KEY_PRESS:
	
	; 3. 如果 ACC 是 1 (按下了S1)，执行强制静音！
	CJNE    A, #1, CHECK_KEY2
	CLR     A               ; 准备静音指令 (索引 0)
	LCALL   Buzzer_Play     ; 强制蜂鸣器闭嘴
	SJMP    MAIN_LOOP_END
CHECK_KEY2:
	CJNE	A, #2, CHECK_KEY3
	MOV A, #1
	LCALL   Buzzer_Play     ; 
	; 这里可以添加按下 S2 的特殊功能，例如切换显示模式
	SJMP    MAIN_LOOP_END
CHECK_KEY3:
        CJNE    A, #3, CHECK_KEY4
        ; 【如果按了 S3】：播放中音 Do (传递数字 8)
        MOV     A, #8
        LCALL   Buzzer_Play
        SJMP    MAIN_LOOP_END

CHECK_KEY4:
	CJNE    A, #4, MAIN_LOOP_END
        ; 【如果按了 S4】：播放高音 Do (传递数字 15)
        MOV     A, #15
        LCALL   Buzzer_Play
	SJMP    MAIN_LOOP_END

MAIN_LOOP_END:
	SJMP    MAIN_LOOP

END
