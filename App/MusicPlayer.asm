; ╔══════════════════════════════════════════════════════════════════════╗
; ║  第1部分：文件名片                                                   ║
; ╠══════════════════════════════════════════════════════════════════════╣
; ║  文件名: MusicPlayer.asm                                             ║
; ║  层级:   App (应用层)                                                ║
; ║  功能:   歌曲播放引擎。根据歌曲ID查表播放对应曲目的旋律。            ║
; ║                                                                      ║
; ║  注释:   这是电子琴的"自动演奏"功能。就像一个音乐盒的滚筒：          ║
; ║          1. 有一张"歌单表"（SongTable），存了10首歌的地址            ║
; ║          2. 每首歌的数据格式是"音符+时长"交替排列：                  ║
; ║             DB 1,25, 2,25, 3,25, ...  → 音符1(Do)唱250ms,            ║
; ║             音符2(Re)唱250ms, 音符3唱250ms...                        ║
; ║          3. 读到 0xFF 时就结束（等于"曲终"标记）                     ║
; ║          4. 播放过程中随时检测红外遥控，有人按遥控就立刻切歌/静音    ║
; ║          5. 每个音符之间加15ms停顿                                   ║
; ║                                                                      ║
; ║  曲目列表:                                                           ║
; ║  ID 0~3: 两只老虎 / 小星星 / 欢乐颂 / 生日快乐 (多音符旋律)          ║
; ║  ID 4~9: Do / Re / Mi / Fa / So / La 单音 (短按单键播放一个音即停)   ║
; ║                                                                      ║
; ║  调用者: Main.asm 的 Dispatch_Event（收到事件30~39时调用）           ║
; ║  依赖:   Bsp_Buzzer.asm (Buzzer_Play), Bsp_Led.asm (Led_ShowSpectrum)║
; ║         Lib/Delay.asm (Delay_ms), Drv_IR.asm (IR_CmdReady)           ║
; ╚══════════════════════════════════════════════════════════════════════╝
;
; ╔══════════════════════════════════════════════════════════════════════╗
; ║  第2部分：汇编指令速查表（本文件出现的所有指令）                     ║
; ╠══════════════════════════════════════════════════════════════════════╣
; ║  MUL  AB        │ 乘法：A × B → 结果低8位在A，高8位在B(F0H)          ║
; ║                │ 这里用来算 SongTable[A*2] 的偏移                    ║
; ║  ADD  A, 直接地址│ 加法：A = A + 地址的值。用于16位指针累加的低字节  ║
; ║  ADDC A, 直接地址│ 带进位加法：A = A + 值 + CY。用于16位累加的高字节 ║
; ║                │ 为什么需要ADDC？因为低字节加法可能溢出(>255)，      ║
; ║                │ 溢出的部分存在CY里，高字节必须用ADDC把它加进去。    ║
; ║  LCALL 标签     │ 长调用子函数（64KB范围内均可），自动把返回地址压栈 ║
; ║  DW   地址       │ 伪指令：Define Word，在ROM中存放一个16位地址      ║
; ║                │ A51的DW是"高字节在前"(MSB first)                    ║
; ║  ------ 以下指令见此前文件，此处简记 ------                          ║
; ║  PUSH / POP / MOV / CJNE / JNC / JZ / JNZ / DJNZ / SJMP /            ║
; ║  CLR A / INC / MOVC / RET                                            ║
; ╚══════════════════════════════════════════════════════════════════════╝
;
; ╔══════════════════════════════════════════════════════════════════════╗
; ║  第3部分：特殊功能寄存器速查表                                       ║
; ╠══════════════════════════════════════════════════════════════════════╣
; ║  本文件未直接操作SFR。（通过调用 Buzzer_Play/Led_ShowSpectrum/Delay_ms║
; ║  间接操作硬件，仅读取 IR_CmdReady 变量）                             ║
; ╚══════════════════════════════════════════════════════════════════════╝

NAME    MUSICPLAYER

PUBLIC  MusicPlayer_PlaySong

EXTRN   CODE (Buzzer_Play)
EXTRN   CODE (Led_ShowSpectrum)
EXTRN   CODE (DigiTube_ShowNumber)
EXTRN   CODE (DigiTube_Scan)
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
        PUSH    0F0H    ; B寄存器 (MUL指令的乘积高8位存在这里) 多用来协助A寄存器进行乘除法运算
        PUSH    82H     ; DPL
        PUSH    83H     ; DPH
        PUSH    07H     ; R7

        ; 范围检查：SongID >= 10？非法，直接退出
        CJNE    A, #10, $+3  ; $ 符号代表“当前这条指令的首地址”  如果A != 10 就跳三个字节,即刚好跳过该条指令正常向下执行,如果A == 10 还是继续执行下一条指令,目的只是为了产生CY
        JNC     Play_End_Direct ; CY=0说明A>=10

        ; --- 二级指针查表：先查SongTable(歌单)，再查实际歌曲数据 ---
        ; SongTable是个指针数组，每个元素是2字节(DW)，指向一首歌的数据
        ; 我们要读 SongTable[SongID] 中的2字节，作为目标歌曲的地址
        ;
        ; 计算: DPTR = SongTable + SongID * 2
        MOV     DPTR, #SongTable
        MOV     0F0H, #2       ; B = 2 (每个DW占2字节)
        MUL     AB             ; A*B → A=低8位, B(F0H)=高8位 前面的CJNE不会改变A的值，所以A里还是SongID，乘以2后得到偏移量
        ; 现在 (B,A) 组成16位偏移量。把偏移加到DPTR上：
        ADD     A, 82H         ; A + DPL → A
        MOV     82H, A         ; 更新DPL
        MOV     A, 0F0H        ; 取偏移高字节
        ADDC    A, 83H         ; A + DPH + CY (处理低字节加法可能的进位)
        MOV     83H, A         ; 更新DPH
        
        ; 现在DPTR指向SongTable[SongID]的第一个字节（DW的高字节）
        ; 读出2字节作为歌曲数据的真实地址：
        CLR     A
        MOVC    A, @A+DPTR     ; 读第0字节（DW的高字节 → A51 MSB first）
        MOV     0F0H, A        ; 暂存到B
        MOV     A, #1
        MOVC    A, @A+DPTR     ; 读第1字节（DW的低字节）
        MOV     82H, A         ; → DPL
        MOV     83H, 0F0H      ; 暂存的高字节 → DPH
        ; 现在DPTR指向了目标歌曲数据的首地址

Play_Loop:
        ; --- 第一件事：检查是否被红外打断 ---
        MOV     A, IR_CmdReady
        JNZ     Play_End       ; IR_CmdReady=1说明有红外事件，立即结束当前播放

        ; --- 读取一个音符 ---
        CLR     A
        MOVC    A, @A+DPTR     ; 从歌曲数据中读一个字节
        INC     DPTR           ; 指针后移
        
        ; 读到 0xFF？= 歌曲结束
        CJNE    A, #0FFH, Play_Continue

Play_End:
        ; 歌曲结束→静音
        CLR     A
        LCALL   Buzzer_Play    ; 音符0=静音
        LCALL   Led_ShowSpectrum ; 关LED
        LCALL   DigiTube_ShowNumber ; 关数码管
Play_End_Direct:
        POP     07H
        POP     83H
        POP     82H
        POP     0F0H
        POP     ACC
        RET

Play_Continue:
        ; 播放当前音符
        LCALL   Buzzer_Play    ; Buzzer_Play内部会PUSH/POP保护ACC
        LCALL   Led_ShowSpectrum
        LCALL   DigiTube_ShowNumber ; 数码管同步显示音符编号

        ; --- 读取延时参数（单位：10ms） ---
        CLR     A
        MOVC    A, @A+DPTR     ; 读时长数据
        INC     DPTR           ; 指针后移
        
        MOV     R7, A           ; R7 = 延时次数
        JZ      Play_Gap        ; 延时=0，跳过

Delay_Loop:
        ; 每次外层循环消耗10ms，循环R7次就是 R7×10ms
        ; 在每个10ms间隔都检查红外打断，保证流畅响应
        MOV     A, IR_CmdReady
        JNZ     Play_End

        LCALL   DigiTube_Scan ; 维持数码管扫描（防闪灭）
        PUSH    07H             ; 保护外层计数器R7
        MOV     R7, #10         ; 每次延时10ms
        LCALL   Delay_ms
        POP     07H             ; 恢复外层计数器
        DJNZ    R7, Delay_Loop  ; R7减1，不为0继续等

Play_Gap:
        ; 音符间短暂停顿→产生"颗粒感"
        CLR     A
        LCALL   Buzzer_Play     ; 短暂静音
        LCALL   DigiTube_Scan   ; 维持扫描
        MOV     R7, #15         ; 停15ms
        LCALL   Delay_ms

        SJMP    Play_Loop       ; 继续下一个音符


; ====== 查表区 ======
; SongTable：歌单——10个指针，每个指向一首歌的数据
SongTable:
        DW  Song_Tigers     ; 0 (红外键 '0')
        DW  Song_Star       ; 1 (红外键 '1')
        DW  Song_Joy        ; 2 (红外键 '2')
        DW  Song_Birthday   ; 3 (红外键 '3')
        DW  Note_Do         ; 4 (红外键 '4')
        DW  Note_Re         ; 5 (红外键 '5')
        DW  Note_Mi         ; 6 (红外键 '6')
        DW  Note_Fa         ; 7 (红外键 '7')
        DW  Note_So         ; 8 (红外键 '8')
        DW  Note_La         ; 9 (红外键 '9')

; 歌曲数据格式: DB 音符(0=静音, 1~21=发音), 持续时间(单位: 10ms)
; 结束标志: DB 0xFF
; 举例: DB 1,25  → 音符1(Do)唱 25×10ms = 250ms

Song_Tigers: ; 两只老虎
        DB 1,50, 2,25, 3,25, 1,25
        DB 1,50, 2,25, 3,25, 1,25
        DB 3,50, 4,25, 5,50
        DB 3,50, 4,25, 5,50
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

; 单音预设：短按一键播放一个音符，然后自动停止
; 时长20 (200ms)
Note_Do:    DB 1, 20, 0FFH
Note_Re:    DB 2, 20, 0FFH
Note_Mi:    DB 3, 20, 0FFH
Note_Fa:    DB 4, 20, 0FFH
Note_So:    DB 5, 20, 0FFH
Note_La:    DB 6, 20, 0FFH

        END