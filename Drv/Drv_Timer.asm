/*
 * File: Drv_Timer.asm
 * Description: 本文件实现了定时器0的初始化和中断服务程序,以及两个全局变量Freq_TH0和Freq_TL0用于存储定时器0的初值,以便在中断服务程序中使用.
*/

NAME    DRV_TIMER

PUBLIC  Timer0_Init
PUBLIC  Timer0_ISR
PUBLIC  Freq_TH0
PUBLIC  Freq_TL0

TIMER_DATA  SEGMENT DATA
RSEG    TIMER_DATA
Freq_TH0:   DS  1 ; 申请一个字节的空间
Freq_TL0:   DS  1

TIMER_CODE  SEGMENT CODE
RSEG    TIMER_CODE

Timer0_Init:
	; 此处使用ANL和ORL指令来设置定时器0,而不是直接使用MOV指令，因为MOV指令会覆盖整个寄存器的值, 可能会影响定时器1，而ANL和ORL指令可以只修改特定的位，保留其他位的值不变
	ANL     TMOD, #0F0H ; 使用ANL清除低4位，保留高4位
	ORL     TMOD, #01H ; 0000 0001B, 定时器0工作在模式1（16位定时器模式）
	CLR     TR0 ; 先停止定时器0
	CLR     TF0 ; 清除定时器0的溢出标志
	SETB    ET0 ; 使能定时器0中断
	SETB    EA ; 使能总中断
	RET

Timer0_ISR:
	MOV     TH0, Freq_TH0 ; 装载预设初值
	MOV     TL0, Freq_TL0
	CPL     P2.4 ; 翻转P2.4的状态
	RETI

END
