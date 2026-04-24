NAME    DRV_UART

PUBLIC  UART_Init
PUBLIC  UART_ISR
PUBLIC  UART_ReadByte

UART_FIFO_SIZE  EQU 64
; 类似 #define UART_FIFO_SIZE 64
UART_FIFO_MASK  EQU 3FH ; 0011 1111B = 63

UART_DATA   SEGMENT DATA
RSEG    UART_DATA
; 定义四个变量,每个变量占用一个字节
UART_Head:  DS  1 ; FIFO头指针
UART_Tail:  DS  1 ; FIFO尾指针
UART_Count: DS  1 ; FIFO中数据的数量
UART_RxTmp: DS  1 ; 临时变量，用于存储接收到的数据
/*
    DS(Define Storage) : 分配空间, DS 1 表示分配一个字节的空间
*/

UART_IDATA  SEGMENT IDATA ; 避开寄存器区, 使用IDATA区存储UART_Fifo数组,位置在80H以上
RSEG    UART_IDATA
UART_Fifo:  DS  UART_FIFO_SIZE

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

	MOV     UART_Head, #00H
	MOV     UART_Tail, #00H
	MOV     UART_Count, #00H

	POP     ACC
	RET

; UART_ISR
; Serial interrupt body, called from vector in Main.asm.
UART_ISR:
	PUSH    ACC
	PUSH    00H
	PUSH    01H
	PUSH    0D0H

	JNB     RI, UART_ISR_CheckTI
	CLR     RI
	
	; CPL     P1.7
	
	MOV     A, SBUF
	MOV     UART_RxTmp, A

	MOV     A, UART_Count
	CJNE    A, #UART_FIFO_SIZE, UART_ISR_Store
	SJMP    UART_ISR_CheckTI

UART_ISR_Store:
	MOV     A, UART_Head
	ADD     A, #UART_Fifo
	MOV     R0, A
	MOV     A, UART_RxTmp
	MOV     @R0, A

	INC     UART_Head
	MOV     A, UART_Head
	ANL     A, #UART_FIFO_MASK
	MOV     UART_Head, A

	INC     UART_Count

UART_ISR_CheckTI:
	JNB     TI, UART_ISR_Exit
	CLR     TI

UART_ISR_Exit:
	POP     0D0H
	POP     01H
	POP     00H
	POP     ACC
	RETI

; UART_ReadByte
; Return ACC=data, C=1 on success; ACC=00H, C=0 if FIFO empty.
UART_ReadByte:
	PUSH    00H
	PUSH    01H

	CLR     ES
	MOV     A, UART_Count
	JZ      UART_Read_Empty

	MOV     A, UART_Tail
	ADD     A, #UART_Fifo
	MOV     R0, A
	MOV     A, @R0
	MOV     R1, A       ; R1 暂存读到的正确数据

	INC     UART_Tail
	MOV     A, UART_Tail
	ANL     A, #UART_FIFO_MASK
	MOV     UART_Tail, A

	DEC     UART_Count
	SETB    ES

	MOV     A, R1       ; 把正确数据放回 A
	SETB    C           ; 进位标志置 1，表示有数据
	SJMP    UART_Read_Return

UART_Read_Empty:
	SETB    ES
	CLR     A
	CLR     C

UART_Read_Return:
	POP     01H
	POP     00H
	RET

END
