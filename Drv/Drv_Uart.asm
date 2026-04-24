NAME    DRV_UART

PUBLIC  UART_Init
PUBLIC  UART_ISR
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
UART_RxBuf:     DS  8


UART_CODE   SEGMENT CODE
RSEG    UART_CODE

; =========================================
; UART 初始化
; =========================================
UART_Init:
        PUSH    ACC
        ANL     TMOD, #0FH
        ORL     TMOD, #20H
        ANL     PCON, #07FH
        MOV     TH1, #0FDH
        MOV     TL1, #0FDH
        MOV     SCON, #50H
        CLR     TI
        CLR     RI
        SETB    TR1
        SETB    ES
        SETB    EA
        MOV     UART_RxState, #00H
        MOV     UART_RxReady, #00H
        POP     ACC
        RET

; =========================================
; UART 中断服务函数与状态机
; =========================================
UART_ISR:
        PUSH    ACC
        PUSH    00H
        PUSH    0D0H

        JNB     RI, UART_ISR_CheckTI_Jump ; 如果不是接收中断，去查发送
        CLR     RI
        MOV     A, SBUF
        MOV     UART_RxTmp, A

        MOV     A, UART_RxReady
        JNZ     UART_ISR_CheckTI_Jump ; 如果上一帧还没处理完，丢弃新数据

        ; --- 绝对跳转路由表 (彻底解决 Out of Range) ---
        MOV     A, UART_RxState
        CJNE    A, #00H, CHK_ST1
        LJMP    UART_RX_STATE0
CHK_ST1:
        CJNE    A, #01H, CHK_ST2
        LJMP    UART_RX_STATE1
CHK_ST2:
        CJNE    A, #02H, CHK_ST3
        LJMP    UART_RX_STATE2
CHK_ST3:
        CJNE    A, #03H, CHK_ST4
        LJMP    UART_RX_STATE3
CHK_ST4:
        CJNE    A, #04H, CHK_ST5
        LJMP    UART_RX_STATE4
CHK_ST5:
        CJNE    A, #05H, CHK_ST6
        LJMP    UART_RX_STATE5
CHK_ST6:
        CJNE    A, #06H, CHK_ST7
        LJMP    UART_RX_STATE6
CHK_ST7:
        CJNE    A, #07H, UART_RX_RESET_STATE
        LJMP    UART_RX_STATE7

; 中转跳板：为了让上面的 JNB 等相对跳转能安全跳到底部
UART_ISR_CheckTI_Jump:
        LJMP    UART_ISR_CheckTI

; --- 状态 0：等 0x55 ---
UART_RX_STATE0:
        MOV     A, UART_RxTmp
        CJNE    A, #055H, ST0_EXIT
        MOV     UART_RxState, #01H
ST0_EXIT:
        LJMP    UART_ISR_CheckTI

; --- 状态 1：等 0xAA ---
UART_RX_STATE1:
        MOV     A, UART_RxTmp
        CJNE    A, #0AAH, UART_RX_RESET_STATE
        MOV     UART_RxState, #02H
        LJMP    UART_ISR_CheckTI

; --- 状态 2：等版本号 0x01 ---
UART_RX_STATE2:
        MOV     A, UART_RxTmp
        CJNE    A, #001H, UART_RX_RESET_STATE
        MOV     UART_RxState, #03H
        LJMP    UART_ISR_CheckTI

; --- 状态 3：存命令 CMD ---
UART_RX_STATE3:
        MOV     A, UART_RxTmp
        MOV     UART_RxCmd, A
        MOV     UART_RxState, #04H
        LJMP    UART_ISR_CheckTI

; --- 状态 4：存长度 LEN 并防溢出 ---
UART_RX_STATE4:
        MOV     A, UART_RxTmp
        MOV     UART_RxLen, A
        CJNE    A, #009H, ST4_CHK_LEN
        LJMP    UART_RX_RESET_STATE ; ==9，超载防爆
ST4_CHK_LEN:
        JNC     UART_RX_RESET_STATE ; >9，超载防爆
        MOV     A, UART_RxLen
        JZ      ST4_LEN_ZERO        ; 长度为0
        MOV     UART_RxIndex, #00H
        MOV     UART_RxState, #05H
        LJMP    UART_ISR_CheckTI
ST4_LEN_ZERO:
        MOV     UART_RxState, #06H
        LJMP    UART_ISR_CheckTI

; --- 状态 5：收载荷 Payload 存入缓冲区 ---
UART_RX_STATE5:
        MOV     A, UART_RxIndex
        ADD     A, #UART_RxBuf
        MOV     R0, A
        MOV     A, UART_RxTmp
        MOV     @R0, A
        INC     UART_RxIndex
        MOV     A, UART_RxIndex
        CJNE    A, UART_RxLen, ST5_EXIT
        MOV     UART_RxState, #06H
ST5_EXIT:
        LJMP    UART_ISR_CheckTI

; --- 状态 6：存 CRC 低字节 ---
UART_RX_STATE6:
        MOV     A, UART_RxTmp
        MOV     UART_RxCrcL, A
        MOV     UART_RxState, #07H
        LJMP    UART_ISR_CheckTI

; --- 状态 7：存 CRC 高字节，并通知主程序 ---
UART_RX_STATE7:
        MOV     A, UART_RxTmp
        MOV     UART_RxCrcH, A
        MOV     UART_RxReady, #01H   ; 组包完成！
        MOV     UART_RxState, #00H
        LJMP    UART_ISR_CheckTI

; --- 状态复位 ---
UART_RX_RESET_STATE:
        MOV     UART_RxState, #00H
        LJMP    UART_ISR_CheckTI

; --- 检查 TI 标志 ---
UART_ISR_CheckTI:
        JNB     TI, UART_ISR_Exit
        CLR     TI

UART_ISR_Exit:
        POP     0D0H
        POP     00H
        POP     ACC
        RETI

END