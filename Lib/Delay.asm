/*
 * File: Delay.asm
 * Description: 本文件使用了R5,R6,R7三个寄存器来实现一个基于软件循环的延时函数Delay_ms,输入参数是R7寄存器中的延时时间,单位为毫秒.
*/

NAME    DELAY

PUBLIC  Delay_ms

DELAY_SEG   SEGMENT CODE
RSEG    DELAY_SEG

; Delay_ms
; Input : R7 = delay time in milliseconds
; Clock : 11.0592MHz (1 machine cycle = 12 / 11.0592MHz = 1.085us)
; Note  : 1ms loop is calibrated to about 1003.7us.
Delay_ms:
	PUSH    ACC
	PUSH    05H ;PUSH只能操作直接地址,不能写成PUSH R5, PUSH R6, PUSH R7
	PUSH    06H
	PUSH    07H

	MOV     A, R7
	JZ      Delay_ms_Exit ; JZ (Jump if Zero) 指令会检查 A 寄存器的值，且只会去检测累加器A
	/*
		if(A == 0){
			// 如果输入的延时是0ms，直接跳过循环，快速返回
			// 如果不做该处理,普通的 DJNZ 会先减 1 变成 255 (FFH)，然后循环 256 次，导致实际延时变成 256ms，远远超过预期的0ms。
			goto Delay_ms_Exit;
		}
	*/

Delay_ms_Loop:
	MOV     R5, #02H ; 1MC = 1.085us, 1ms = 1000us, 1000/1.085 ≈ 921.66

Delay_ms_L1:
	MOV     R6, #0E5H ; 2MC

Delay_ms_L2:
	DJNZ    R6, Delay_ms_L2 ; 内层循环，消耗 2MC * 229 = 458MC
	DJNZ    R5, Delay_ms_L1 ; 外层循环，消耗 2 * 458MC = 916MC , 搭配前面的PUSH和DJNZ指令的消耗(16MC)，调用LCALL和RET消耗4MC , MOV A和JZ = 1+2 = 3MC , 整个循环大约是 916 + 16 + 4 + 3 = 939MC，939 * 1.085us ≈ 1019.7us，大约是1ms的延时。
	DJNZ    R7, Delay_ms_Loop

Delay_ms_Exit:
	POP     07H
	POP     06H
	POP     05H
	POP     ACC
	RET

END
