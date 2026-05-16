; ╔══════════════════════════════════════════════════════════════════════╗
; ║  第1部分：文件名片                                                     ║
; ╠══════════════════════════════════════════════════════════════════════╣
; ║  文件名: Drv_DigiTube.asm                                              ║
; ║  层级:   Drv (驱动层)                                                   ║
; ║  功能:   4位共阳数码管动态扫描驱动。                                      ║
; ║          · 段选：P0→74HC573(片选常使能, LE=P2.5)→8段(a~g+dp)              ║
; ║          · 位选：P2.0~P2.3 经PNP三极管驱动4位共阳端(0=选中, 1=关闭)       ║
; ║          · 扫描：主循环每次调用扫一位，4次完成一轮全刷                      ║
; ║                                                                        ║
; ║  白话:   数码管怎么显示数字？4个数码管其实是轮流亮的：                     ║
; ║          1. 先关掉所有位（防"鬼影"——上一个数字的残影会短暂出现在下一位）  ║
; ║          2. P0送出第N位的段码→P2.5给一个正脉冲→数据锁进74HC573            ║
; ║          3. 打开P2.0~P2.3中对应第N位的那根线→该位数码管亮                 ║
; ║          4. 下次调用扫下一位，循环。人眼有"视觉暂留"，轮流亮看起来像同时亮 ║
; ║                                                                        ║
; ║          74HC573是什么？8位透明锁存器。LE=1时输出=输入（透明模式），       ║
; ║          LE=下降沿时锁住当前数据。所以P0可以先后给段码、给位码，            ║
; ║          而段码被573"记住"不会丢。OE始终接地(使能)，芯片永不关闭输出。     ║
; ║                                                                        ║
; ║  调用者: Main.asm (初始化 DigiTube_Init, 主循环 DigiTube_Scan)           ║
; ║         Bsp_DigiTube.asm (通过 DigiTube_SetNum 写缓冲, DigiTube_Clear)   ║
; ║         MusicPlayer.asm (播放中调用 DigiTube_Scan 维持扫描)              ║
; ║  依赖:   无（不调用其他模块，只操作SFR）                                  ║
; ╚══════════════════════════════════════════════════════════════════════╝
;
; ╔══════════════════════════════════════════════════════════════════════╗
; ║  第2部分：汇编指令速查表（本文件出现的所有指令）                        ║
; ╠══════════════════════════════════════════════════════════════════════╣
; ║  MOV  P0, A     │ 把A写给P0端口。P0是开漏输出，写1=弱上拉，写0=强下拉     ║
; ║  SETB bit       │ 把位寻址区的某位置1                                     ║
; ║  CLR  bit       │ 把位寻址区的某位清0                                     ║
; ║  ADD  A, 直接地址│ 加法，用于计算 DigiTube_Buf + Pos 的地址                ║
; ║  MOV  A, @R0    │ 间接寻址：以R0中的值为地址读取数据                       ║
; ║  MOV  @R0, A    │ 间接寻址：把A写入R0指向的地址                            ║
; ║  CJNE A, #n, 标 │ 比较不相等则跳转（同时影响CY标志）                       ║
; ║  JNC  标签       │ CY=0则跳转（即A >= 比较值）                              ║
; ║  INC  直接地址   │ 自增1                                                    ║
; ║  ------ 以下指令见此前文件，此处简记 ------                                ║
; ║  PUSH / POP / MOV / MOVC / DIV / JZ / SJMP / RET / NOP / DJNZ          ║
; ╚══════════════════════════════════════════════════════════════════════╝
;
; ╔══════════════════════════════════════════════════════════════════════╗
; ║  第3部分：特殊功能寄存器速查表（本文件涉及的SFR）                       ║
; ╠══════════════════════════════════════════════════════════════════════╣
; ║  P0   │ 80H │ P0端口，8位开漏I/O。这里用作数码管段码数据输出口。         ║
; ║       │     │ 写1=内部弱上拉，写0=强下拉。驱动74HC573的8个数据输入端。    ║
; ║  P2   │ A0H │ P2端口，8位准双向I/O。可位寻址。                          ║
; ║       │     │ P2.0~P2.3: 位选线，0=选中该位(经PNP三极管→共阳端)         ║
; ║       │     │ P2.5: 74HC573锁存使能(LE)，上升沿锁存数据                  ║
; ║       │     │ P2.4: 蜂鸣器(Timer0 ISR中使用CPL翻转)，本模块不碰           ║
; ╚══════════════════════════════════════════════════════════════════════╝

NAME    DRV_DIGITUBE

; ---------- 公开接口 ----------
PUBLIC  DigiTube_Init
PUBLIC  DigiTube_Scan
PUBLIC  DigiTube_SetNum
PUBLIC  DigiTube_Clear
PUBLIC  DigiTube_Buf

; ---------- 数据段 ----------
DIGITUBE_DATA SEGMENT DATA
RSEG    DIGITUBE_DATA
DigiTube_Buf:   DS  4   ; 4字节段码缓冲：[0]千位 [1]百位 [2]十位 [3]个位
DigiTube_Pos:   DS  1   ; 当前扫描位位置 (0~3)

; ---------- 代码段 ----------
DIGITUBE_CODE SEGMENT CODE
RSEG    DIGITUBE_CODE

; ========================================================
; DigiTube_Init — 初始化数码管
; 破坏: ACC
; ========================================================
DigiTube_Init:
    ; P2.0~P2.3上电默认是准双向口(输出1=弱上拉)，PNP基极高电平→三极管截止→数码管灭
    ; 确保所有位都关闭：
    SETB    P2.0
    SETB    P2.1
    SETB    P2.2
    SETB    P2.3

    ; P2.5(LE)初始化为低，74HC573处于锁存状态（输出保持上一次的数据）
    CLR     P2.5

    ; 清空显示缓冲（全1=共阳数码管全灭）
    MOV     DigiTube_Buf+0, #0FFH
    MOV     DigiTube_Buf+1, #0FFH
    MOV     DigiTube_Buf+2, #0FFH
    MOV     DigiTube_Buf+3, #0FFH

    ; 扫描位置从0开始
    MOV     DigiTube_Pos, #0
    RET

; ========================================================
; DigiTube_Scan — 动态扫描一位（每次调用扫一个数码管位置）
; 调用频率: 主循环每次迭代调用一次（约50~200μs间隔）
; 破坏: ACC
; ========================================================
DigiTube_Scan:
    ; ---- 第1步：关闭所有位（消影 —— 防止段码残留导致"鬼影"） ----
    SETB    P2.0
    SETB    P2.1
    SETB    P2.2
    SETB    P2.3

    ; ---- 第2步：取出当前位的段码 ----
    ; 根据 DigiTube_Pos 直接读取对应的缓冲字节
    MOV     A, DigiTube_Pos
    CJNE    A, #0, Scan_Read1
    MOV     A, DigiTube_Buf+0
    SJMP    Scan_Output
Scan_Read1:
    CJNE    A, #1, Scan_Read2
    MOV     A, DigiTube_Buf+1
    SJMP    Scan_Output
Scan_Read2:
    CJNE    A, #2, Scan_Read3
    MOV     A, DigiTube_Buf+2
    SJMP    Scan_Output
Scan_Read3:
    MOV     A, DigiTube_Buf+3
Scan_Output:

    ; ---- 第3步：段码输出到P0，并锁存到74HC573 ----
    MOV     P0, A           ; P0输出段码
    SETB    P2.5            ; LE=1 → 74HC573进入透明模式（输出=输入）
    NOP                     ; 等待数据稳定（至少需>20ns，一个NOP在40MHz下=0.3μs足够）
    NOP
    CLR     P2.5            ; LE=0 → 下降沿锁存, 74HC573输出冻结

    ; ---- 第4步：打开当前位（对应的P2.x置0 → PNP导通 → 共阳端得电） ----
    ; 根据 DigiTube_Pos 选择对应的位选线：
    MOV     A, DigiTube_Pos
    CJNE    A, #0, Scan_Pos1
    CLR     P2.0            ; 位0亮
    SJMP    Scan_Next
Scan_Pos1:
    CJNE    A, #1, Scan_Pos2
    CLR     P2.1            ; 位1亮
    SJMP    Scan_Next
Scan_Pos2:
    CJNE    A, #2, Scan_Pos3
    CLR     P2.2            ; 位2亮
    SJMP    Scan_Next
Scan_Pos3:
    CLR     P2.3            ; 位3亮

Scan_Next:
    ; ---- 第5步：推到下一位（0→1→2→3→0 循环） ----
    INC     DigiTube_Pos
    MOV     A, DigiTube_Pos
    CJNE    A, #4, Scan_Ret
    MOV     DigiTube_Pos, #0    ; 超出3则归零
Scan_Ret:
    RET

; ========================================================
; DigiTube_Clear — 清空所有位（熄灭数码管）
; 破坏: 无
; ========================================================
DigiTube_Clear:
    PUSH    ACC
    MOV     DigiTube_Buf+0, #0FFH
    MOV     DigiTube_Buf+1, #0FFH
    MOV     DigiTube_Buf+2, #0FFH
    MOV     DigiTube_Buf+3, #0FFH
    POP     ACC
    RET

; ========================================================
; DigiTube_SetNum — 将数字写入显示缓冲（0~99，左对齐）
; 入口: ACC = 要显示的数字 (0~99)
;       0 = 显示"0   "（最左位显示0）
;       1~9 = 显示"X   "（最左位显示数字）
;       10~99 = 显示"XX  "（左两位显示数字）
;       >=100 = 忽略（清空显示）
; 破坏: ACC, B, DPTR, R0, R1
; ========================================================
DigiTube_SetNum:
    MOV     R0, A               ; R0 = 输入数字

    ; 先全部清空
    MOV     DigiTube_Buf+0, #0FFH
    MOV     DigiTube_Buf+1, #0FFH
    MOV     DigiTube_Buf+2, #0FFH
    MOV     DigiTube_Buf+3, #0FFH

    ; 范围检查：>=100 就不处理
    MOV     A, R0
    CLR     C
    SUBB    A, #100
    JNC     SetNum_Exit         ; CY=0 → A>=100 → 越界，返回（全灭）

    MOV     A, R0
    JZ      SetNum_Zero         ; A=0 → 跳去显示"0"

    ; ---- 拆分为十位和个位 ----
    ; DIV AB: A/B → A=商(十位), B=余数(个位)
    MOV     B, #10
    MOV     A, R0
    DIV     AB
    MOV     R1, B               ; R1 = 个位数

    ; 如果十位为0，只有个位，放在最左边
    JZ      SetNum_OnesOnly

    ; 有十位：十位→Buf[0]
    MOV     DPTR, #SEG_TABLE
    MOVC    A, @A+DPTR
    MOV     DigiTube_Buf+0, A   ; 十位→最左位

    ; 个位→Buf[1]
    MOV     A, R1
    MOV     DPTR, #SEG_TABLE
    MOVC    A, @A+DPTR
    MOV     DigiTube_Buf+1, A   ; 个位→第二左位
    SJMP    SetNum_Exit

SetNum_OnesOnly:
    ; 只有个位→Buf[0]
    MOV     A, R1
    MOV     DPTR, #SEG_TABLE
    MOVC    A, @A+DPTR
    MOV     DigiTube_Buf+0, A   ; 个位→最左位
    SJMP    SetNum_Exit

SetNum_Zero:
    ; 显示 "0" 在最左位
    MOV     DPTR, #SEG_TABLE
    CLR     A
    MOVC    A, @A+DPTR
    MOV     DigiTube_Buf+0, A

SetNum_Exit:
    RET

; ========================================================
; 共阳数码管段码表 (0=段ON, 1=段OFF)
; 位定义: BIT7=dp, BIT6=g, BIT5=f, BIT4=e, BIT3=d, BIT2=c, BIT1=b, BIT0=a
;
;     a
;    ---
;  f| g |b
;    ---
;  e|   |c
;    --- .dp
;     d
; ========================================================
SEG_TABLE:
    DB  0C0H   ; '0' = abcdef on      → 1100 0000
    DB  0F9H   ; '1' = bc on            → 1111 1001
    DB  0A4H   ; '2' = abdeg on         → 1010 0100
    DB  0B0H   ; '3' = abcdg on         → 1011 0000
    DB  099H   ; '4' = bcfg on          → 1001 1001
    DB  092H   ; '5' = acdfg on         → 1001 0010
    DB  082H   ; '6' = acdefg on        → 1000 0010
    DB  0F8H   ; '7' = abc on           → 1111 1000
    DB  080H   ; '8' = abcdefg on       → 1000 0000
    DB  090H   ; '9' = abcdfg on        → 1001 0000

    END
