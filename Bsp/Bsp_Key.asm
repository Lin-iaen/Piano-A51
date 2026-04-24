NAME    BSP_KEY
        PUBLIC  Key_Scan

        KEY_DATA SEGMENT DATA
        RSEG    KEY_DATA
Key_State:  DS  1       ; 0=等按下, 1=按下消抖, 2=等松开, 3=松开消抖
Key_Cnt:    DS  1       ; 快照延时计数器
Key_Temp:   DS  1       ; 暂存按键特征

        KEY_CODE SEGMENT CODE
        RSEG    KEY_CODE

; ========================================================
; 函数：Key_Scan (工业级快照消抖状态机)
; ========================================================
Key_Scan:
        MOV     A, P3
        CPL     A           
        ; P3.2(INT0) 已给红外使用，这里仅扫描 P3.3/P3.4/P3.5 三个按键
        ANL     A, #038H    
        MOV     R0, A       ; R0 暂存当前有效的按键特征

        ; --- 状态机路由 ---
        MOV     A, Key_State
        JZ      STATE_0
        DEC     A
        JZ      STATE_1
        DEC     A
        JZ      STATE_2
        SJMP    STATE_3

STATE_0: ; --- 状态 0：等待按下 ---
        MOV     A, R0
        JZ      KEY_RET_0       ; 没人按，直接退出
        
        MOV     Key_Temp, A     ; 记录第一次按下的特征
        MOV     Key_State, #1   ; 进入状态 1 (闭眼等)
        MOV     Key_Cnt, #0
        SJMP    KEY_RET_0

STATE_1: ; --- 状态 1：按下快照消抖 ---
        INC     Key_Cnt
        MOV     A, Key_Cnt
        CJNE    A, #250, KEY_RET_0 ; 闭眼等够约 15ms 之前，直接退出
        
        ; 睁开眼睛：时间到了！
        MOV     Key_State, #2   ; 无论结果如何，下一步强制进入等松开状态
        
        ; 【拍快照】：15ms 后的现在，引脚状态跟刚才一样吗？
        MOV     A, R0
        CJNE    A, Key_Temp, KEY_RET_0 ; 不一样！说明刚才是噪音，直接丢弃！
        
        ; 一模一样！确认为完美按下，返回键码
        CJNE    A, #00000100B, CHECK_K2
        MOV     A, #1
        RET
CHECK_K2:
        CJNE    A, #00001000B, CHECK_K3
        MOV     A, #2
        RET
CHECK_K3:
        CJNE    A, #00010000B, KEY_RET_0
        MOV     A, #3
        RET

STATE_2: ; --- 状态 2：等待松开 ---
        MOV     A, R0
        JNZ     KEY_RET_0       ; 只要 R0 还有值(按着)，就一直等
        
        ; 发现松开了！
        MOV     Key_State, #3   ; 进入状态 3 (闭眼等)
        MOV     Key_Cnt, #0
        SJMP    KEY_RET_0

STATE_3: ; --- 状态 3：松开快照消抖 ---
        INC     Key_Cnt
        MOV     A, Key_Cnt
        CJNE    A, #250, KEY_RET_0 ; 闭眼等够约 15ms
        
        ; 睁开眼睛：时间到了！
        MOV     Key_State, #0   ; 无论结果如何，循环回状态 0
        
        ; 【拍快照】：15ms 后的现在，真的全松开了吗？
        MOV     A, R0
        JNZ     KEY_RET_0       ; 居然又有值了(遇到电源纹波噪音)，果断忽略！
        
        ; 完美松开！发送 Note-Off 强制静音
        MOV     A, #5
        RET

KEY_RET_0:
        CLR     A
        RET

        END