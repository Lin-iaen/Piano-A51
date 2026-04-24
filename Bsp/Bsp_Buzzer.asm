/*
 * File: Bsp_Buzzer.asm
 * Description: 本文件使用了特殊寄存器DPTR0来存储频率表的地址,注意正确PUSH/POP DPTR0的值以避免干扰其他代码
 */

NAME    BSP_BUZZER

PUBLIC  Buzzer_Play

EXTRN   DATA (Freq_TH0)
EXTRN   DATA (Freq_TL0)

BUZZER_CODE SEGMENT CODE
RSEG    BUZZER_CODE

; Buzzer_Play
; Input : ACC = 0(静音), 1,2,3,......21(音调索引)
; 作用: 根据输入的音调索引播放对应的音调,如果输入为0则静音
Buzzer_Play:
	PUSH    ACC
	PUSH    00H
	PUSH    82H ; DPTR0低字节
	PUSH    83H ; DPTR0高字节

	MOV     R0, A ; 累加器容易被修改,先把它的值保存到R0中,相当于定义一个temp变量
	JZ      Buzzer_Mute ; 如果输入为0,关闭蜂鸣器

	MOV     A, R0
	CLR     CY
	/*
	PSW寄存器的位分布如下:
		 D7  D6  D5  D4  D3  D2  D1   D0
		 |   |   |   |   |   |   |    |
	PSW  CY  Ac  F0 RS1 RS0  OV  未用  P

	CY可能被置1的其他途径:
	1. ADD/ADDC / SUBB 简单的计算指令
	2. 其他指令如RLC/RRC等位移指令
	3. 其他指令如ANL/ORL等逻辑指令
	4. CJNE 比较并跳转指令,如果CJNE A, #data 发现 $A < data$，内部减法产生了借位，也会把 CY 置 1
	*/
	SUBB    A, #22
	/*
		在8051中,SUBB是一种带借位的减法指令,上述指令执行的是A = A - 22 - CY
	*/
	
	JNC     Buzzer_Mute ; 如果CY没有被置1,说明A>=22,跳向蜂鸣器闭嘴函数

	MOV     A, R0 ; SUBB把A的值修改了,从R0中恢复原始输入值
	MOV     DPTR, #Note_TH0_Table
	MOVC    A, @A+DPTR
	MOV     Freq_TH0, A

	MOV     A, R0
	MOV     DPTR, #Note_TL0_Table
	MOVC    A, @A+DPTR
	MOV     Freq_TL0, A

	MOV     TH0, Freq_TH0
	MOV     TL0, Freq_TL0
	SETB    TR0
	SJMP    Buzzer_Exit

Buzzer_Mute:
	CLR     TR0 ; 停止定时器0
	SETB    P2.4 ; 关闭蜂鸣器

Buzzer_Exit:
	POP     83H
	POP     82H
	POP     00H
	POP     ACC
	RET

; 11.0592MHz crystal
; Timer tick = 12/11.0592MHz = 1.085us
; Reload = 65536 - round(460800 / f)
; Index: 0=rest, 1..7 low(C3..B3), 8..14 middle(C4..B4), 15..21 high(C5..B5)
; 初值计算公式 : (65536 - 初值) * 2f = 11.0592MHz / 12 = 921600

Note_TH0_Table:
	DB  00H
	DB  0F2H,0F3H,0F5H,0F5H,0F6H,0F7H,0F8H
	DB  0F9H,0F9H,0FAH,0FAH,0FBH,0FBH,0FCH
	DB  0FCH,0FCH,0FDH,0FDH,0FDH,0FDH,0FEH

Note_TL0_Table:
	DB  00H
	DB  042H,0C1H,017H,0B7H,0D1H,0D1H,0B6H
	DB  021H,0E1H,08CH,0D8H,068H,0E9H,05BH
	DB  08FH,0EFH,045H,06CH,0B4H,0F4H,02EH

END
