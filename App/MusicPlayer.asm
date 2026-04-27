NAME    MUSICPLAYER

PUBLIC  MusicPlayer_PlaySong

EXTRN   CODE (Buzzer_Play)
EXTRN   CODE (Led_ShowSpectrum)
EXTRN   CODE (Delay_ms)
EXTRN   DATA (IR_CmdReady) ; 允许红外按键打断当前播放

PLAYER_CODE SEGMENT CODE
RSEG    PLAYER_CODE

; ========================================================
; 函数：MusicPlayer_PlaySong
; 输入：A = Song ID (0..9)
; 描述：根据 ID 查表播放对应的乐曲或单音。支持红外打断。
; ========================================================
MusicPlayer_PlaySong:
        PUSH    ACC
        PUSH    0F0H
        PUSH    82H
        PUSH    83H
        PUSH    07H

        ; 限制 A 的范围 (0..9)
        CJNE    A, #10, $+3
        JNC     Play_End_Direct     ; A >= 10 则退出

        ; 计算 DPTR = SongTable + A * 2
        MOV     DPTR, #SongTable
        MOV     0F0H, #2
        MUL     AB
        ADD     A, 82H
        MOV     82H, A
        MOV     A, 0F0H
        ADDC    A, 83H
        MOV     83H, A
        
        ; 从 SongTable 取出目标歌曲的真实首地址到 DPL, DPH
        ; A51的 DW 是高字节在前？低字节在后？
        ; 我们直接顺序读出两字节：先高字节，后低字节。
        CLR     A
        MOVC    A, @A+DPTR
        MOV     0F0H, A     ; 保存高字节(或者低字节)到 B
        MOV     A, #1
        MOVC    A, @A+DPTR
        MOV     82H, A      ; 放入 DPL 
        MOV     83H, 0F0H   ; 放入 DPH (假设 DW 高字节在前；如果不对，查表读高低可能要反过来，标准的 A51 DW 确实是 MSB first)

Play_Loop:
        ; --- 检查是否被新的红外键打断 ---
        MOV     A, IR_CmdReady
        JNZ     Play_End    ; 如果有新红外命令，直接退出

        ; --- 读取音符 ---
        CLR     A
        MOVC    A, @A+DPTR
        INC     DPTR
        
        ; 检查结束标志 0xFF
        CJNE    A, #0FFH, Play_Continue

Play_End:
        ; 歌曲结束，静音
        CLR     A
        LCALL   Buzzer_Play
        LCALL   Led_ShowSpectrum
Play_End_Direct:
        POP     07H
        POP     83H
        POP     82H
        POP     0F0H
        POP     ACC
        RET

Play_Continue:
        ; 播放当前音符 (Buzzer_Play和Led_ShowSpectrum内部会保护ACC)
        LCALL   Buzzer_Play
        LCALL   Led_ShowSpectrum

        ; --- 读取延时参数 (以10ms为单位) ---
        CLR     A
        MOVC    A, @A+DPTR
        INC     DPTR
        
        MOV     R7, A       ; 延时次数
        JZ      Play_Gap    ; 如果延时是 0，防错直接跳过

Delay_Loop:
        ; 在延时循环中也检查红外打断，实现秒切
        MOV     A, IR_CmdReady
        JNZ     Play_End

        PUSH    07H
        MOV     R7, #10     ; 每次延时 10ms
        LCALL   Delay_ms
        POP     07H
        DJNZ    R7, Delay_Loop

Play_Gap:
        ; 音符间短暂停顿，产生敲击的颗粒感
        CLR     A
        LCALL   Buzzer_Play
        MOV     R7, #15     ; 停顿15ms
        LCALL   Delay_ms

        SJMP    Play_Loop


; ====== 查表区 ======
SongTable:
        DW  Song_Tigers     ; 0 (红外键 '0'，实际使用自行映射)
        DW  Song_Star       ; 1 (红外键 '1')
        DW  Song_Joy        ; 2 (红外键 '2')
        DW  Song_Birthday   ; 3 (红外键 '3')
        DW  Note_Do         ; 4 (红外键 '4')
        DW  Note_Re         ; 5 (红外键 '5')
        DW  Note_Mi         ; 6 (红外键 '6')
        DW  Note_Fa         ; 7 (红外键 '7')
        DW  Note_So         ; 8 (红外键 '8')
        DW  Note_La         ; 9 (红外键 '9')

; 歌曲数据格式: DB 音符(0静音, 1~21发音), 持续时间(单位: 10ms)
; 结束标志: DB 0xFF

Song_Tigers: ; 两只老虎
        DB 1,25, 2,25, 3,25, 1,25
        DB 1,25, 2,25, 3,25, 1,25
        DB 3,25, 4,25, 5,50
        DB 3,25, 4,25, 5,50
        DB 0FFH

Song_Star:   ; 小星星
        DB 1,25, 1,25, 5,25, 5,25, 6,25, 6,25, 5,50
        DB 4,25, 4,25, 3,25, 3,25, 2,25, 2,25, 1,50
        DB 0FFH

Song_Joy:    ; 欢乐颂
        DB 3,25, 3,25, 4,25, 5,25, 5,25, 4,25, 3,25, 2,25
        DB 1,25, 1,25, 2,25, 3,25, 3,35, 2,15, 2,50
        DB 0FFH

Song_Birthday: ; 生日快乐
        DB 5,12, 5,12, 6,25, 5,25, 8,25, 7,50
        DB 5,12, 5,12, 6,25, 5,25, 9,25, 8,50
        DB 0FFH

; 单音 (用于修复红外遥控单键长响，现在短按一个音符自动停止)
Note_Do:    DB 1, 20, 0FFH
Note_Re:    DB 2, 20, 0FFH
Note_Mi:    DB 3, 20, 0FFH
Note_Fa:    DB 4, 20, 0FFH
Note_So:    DB 5, 20, 0FFH
Note_La:    DB 6, 20, 0FFH

        END