NAME    PROTOCOL

PUBLIC  Task_ParseSerial

EXTRN   DATA (UART_RxReady)
EXTRN   DATA (UART_RxCmd)
EXTRN   DATA (UART_RxLen)
EXTRN   DATA (UART_RxBuf)  ; 【必须包含这行，用于引入接收缓冲区】

NOTE_OFF_EVT    EQU 22

PROTOCOL_CODE    SEGMENT CODE
RSEG    PROTOCOL_CODE

Task_ParseSerial:
        PUSH    00H
        PUSH    01H
        PUSH    02H

        MOV     A, UART_RxReady
        JZ      Task_ParseSerial_None

        ; 原子快照：先关串口中断，复制帧关键字段，再清 ready
        CLR     ES
        MOV     A, UART_RxCmd
        MOV     R1, A
        MOV     A, UART_RxLen
        MOV     R2, A
        JZ      Task_ParseSerial_NoPayloadCopy
        MOV     A, UART_RxBuf
        SJMP    Task_ParseSerial_PayloadCopied

Task_ParseSerial_NoPayloadCopy:
        CLR     A

Task_ParseSerial_PayloadCopied:
        MOV     R0, A

        CLR     A
        MOV     UART_RxReady, A
        SETB    ES

        ; --- 1. 检查指令类型 (Cmd == 0x02 才处理) ---
        MOV     A, R1
        CJNE    A, #02H, Task_ParseSerial_None

        ; --- 2. 检查是否有载荷数据 (Len > 0) ---
        MOV     A, R2
        JZ      Task_ParseSerial_None

        ; --- 3. 真实业务数据（payload[0]）已在 A 中 ---
        MOV     A, R0

        ; --- 4. 业务逻辑转换 ---
        JNZ     Task_ParseSerial_CheckRange 
        
        MOV     A, #NOTE_OFF_EVT
        SJMP    Task_ParseSerial_Exit

Task_ParseSerial_CheckRange:
        CLR     C
        SUBB    A, #01H
        JC      Task_ParseSerial_None

        MOV     A, R0
        CLR     C
        SUBB    A, #22      
        JNC     Task_ParseSerial_None

        MOV     A, R0
        SJMP    Task_ParseSerial_Exit

Task_ParseSerial_None:
        SETB    ES
        CLR     A

Task_ParseSerial_Exit:
        POP     02H
        POP     01H
        POP     00H
        RET

END