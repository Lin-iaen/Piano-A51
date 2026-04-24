NAME    PROTOCOL

PUBLIC  Task_ParseSerial

EXTRN   DATA (UART_RxReady)
EXTRN   DATA (UART_RxCmd)
EXTRN   DATA (UART_RxLen)
EXTRN   IDATA (UART_RxBuf)  ; 【新增】必须引入缓冲区的地址才能读真实数据！

NOTE_OFF_EVT    EQU 22

PROTOCOL_CODE    SEGMENT CODE
RSEG    PROTOCOL_CODE

Task_ParseSerial:
        PUSH    00H

        MOV     A, UART_RxReady
        JZ      Task_ParseSerial_None

        ; 收到完整数据帧，立刻清除标志位，让中断可以接收下一帧
        CLR     A
        MOV     UART_RxReady, A
        
        ; --- 1. 检查指令类型 (Cmd == 0x02 才处理) ---
        MOV     A, UART_RxCmd
        CJNE    A, #02H, Task_ParseSerial_None

        ; --- 2. 检查是否有载荷数据 (Len > 0) ---
        MOV     A, UART_RxLen
        JZ      Task_ParseSerial_None

        ; --- 3. 提取包裹里的真实数据：UART_RxBuf[0] ---
        MOV     R0, #UART_RxBuf
        MOV     A, @R0

        ; --- 4. 业务逻辑转换 ---
        JNZ     Task_ParseSerial_CheckRange ; 如果不是 0，去检查 1~21 的范围
        
        ; 如果上位机发来的是 0，代表松手静音，转换为 NOTE_OFF_EVT (22)
        MOV     A, #NOTE_OFF_EVT
        SJMP    Task_ParseSerial_Exit

Task_ParseSerial_CheckRange:
        ; 检查是否小于 1
        CLR     C
        SUBB    A, #01H
        JC      Task_ParseSerial_None

        MOV     A, @R0      ; 恢复刚刚取出的音符值
        
        ; 检查是否大于 21
        CLR     C
        SUBB    A, #22      ; 如果 A >= 22，进位标志 C 会被清零
        JNC     Task_ParseSerial_None

        MOV     A, @R0      ; 完美合法！A = 真实音符 (1~21)
        SJMP    Task_ParseSerial_Exit

Task_ParseSerial_None:
        CLR     A

Task_ParseSerial_Exit:
        POP     00H
        RET

END