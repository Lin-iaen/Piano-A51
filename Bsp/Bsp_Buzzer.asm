; ╔══════════════════════════════════════════════════════════════════════╗
; ║  第1部分：文件名片                                                     ║
; ╠══════════════════════════════════════════════════════════════════════╣
; ║  文件名: Bsp_Buzzer.asm                                               ║
; ║  层级:   Bsp (板级支持层)                                             ║
; ║  功能:   接收一个音符编号(0~21)，查表获取Timer0的初值，启动定时器让      ║
; ║          蜂鸣器发出对应音高的声音。0是静音。                            ║
; ║                                                                      ║
; ║  白话:   这是整个项目的"喇叭控制中心"。怎么发出不同音高？               ║
; ║          每个音高对应一个固定频率的方波，频率由Timer0从多少开始数到      ║
; ║          65535来决定。这里有张预先算好的"频率表"（TH0/TL0初值表），     ║
; ║          输入音符编号→查表→把初值写入Timer0→启动，蜂鸣器就开始叫了。    ║
; ║          输入0→关掉Timer0+把P2.4拉高=闭嘴。                           ║
; ║                                                                      ║
; ║          安全性：对输入做了范围检查，编号>=22非法的直接静音。            ║
; ║                                                                      ║
; ║  调用者: Main.asm 的 Dispatch_Event（按键/串口/红外最终都调这个）       ║
; ║         MusicPlayer.asm（播放歌曲每个音符也调）                        ║
; ║  依赖:   Drv_Timer.asm（它写的 Freq_TH0/TL0 和 TH0/TL0 在那定义）     ║
; ╚══════════════════════════════════════════════════════════════════════╝
;
; ╔══════════════════════════════════════════════════════════════════════╗
; ║  第2部分：汇编指令速查表（本文件出现的所有指令）                        ║
; ╠══════════════════════════════════════════════════════════════════════╣
; ║  PUSH 直接地址  │ 压入堆栈保存                                        ║
; ║  POP  直接地址  │ 从堆栈弹出恢复                                      ║
; ║  MOV  Rn, A    │ 把A的值复制给Rn（A→R0/R1/...）                      ║
; ║  JZ   标签      │ A=0就跳转                                          ║
; ║  CLR  CY       │ 把CY(进位/借位标志)清零——SUBB会用到它，不清就出错     ║
; ║  SUBB A, #n    │ 带借位减法：A = A - n - CY。配合CLR CY使用即A=A-n   ║
; ║               │ 结果>=0则CY=0(无借位)，结果<0则CY=1(有借位)           ║
; ║  JNC  标签      │ Jump if No Carry：CY=0就跳转（即"没有借位"时跳）     ║
; ║  MOV  DPTR, #n │ 16位地址赋值给DPTR                                  ║
; ║  MOVC A,@A+DPTR│ 从ROM查表：读取 A+DPTR 地址处的字节到A               ║
; ║  SETB bit      │ 把某个位置1。SETB TR0=启动定时器0                    ║
; ║  CLR  bit      │ 把某个位清零。CLR TR0=停止定时器0                    ║
; ║  SJMP 标签      │ 无条件短跳转（只在本文件内±128字节范围跳）           ║
; ║  DB   n        │ 伪指令：在ROM中存放一个字节的常数                     ║
; ║  RET           │ 返回调用者                                          ║
; ╚══════════════════════════════════════════════════════════════════════╝
;
; ╔══════════════════════════════════════════════════════════════════════╗
; ║  第3部分：特殊功能寄存器速查表（本文件涉及的SFR）                       ║
; ╠══════════════════════════════════════════════════════════════════════╣
; ║  PSW   │ D0H │ 程序状态字。CY(D7)=进位/借位标志，很多运算会改它。     ║
; ║        │     │ 为什么先CLR CY？因为SUBB是A-n-CY，不清CY=结果差1。     ║
; ║  TCON  │ 88H │ 定时器控制。TR0(bit4)=Timer0启停开关：1=跑, 0=停      ║
; ║  TH0   │ 8CH │ Timer0计数初值高8位                                   ║
; ║  TL0   │ 8AH │ Timer0计数初值低8位                                   ║
; ║  P2    │ A0H │ P2端口。P2.4连接蜂鸣器，输出方波驱动发声              ║
; ║  DPTR  │ 82H+83H │ 16位数据指针，详见Bsp_Led.asm中的说明              ║
; ╚══════════════════════════════════════════════════════════════════════╝

NAME    BSP_BUZZER

PUBLIC  Buzzer_Play

EXTRN   DATA (Freq_TH0) ; 声明这两个变量在别的文件里定义（Drv_Timer.asm）
EXTRN   DATA (Freq_TL0)

BUZZER_CODE SEGMENT CODE
RSEG    BUZZER_CODE

; Buzzer_Play
; Input : ACC = 0(静音), 1,2,3,......21(音调索引)
; 作用: 根据输入的音调索引播放对应的音调,如果输入为0则静音
Buzzer_Play:
	PUSH    ACC
	PUSH    00H     ; R0的地址是00H。8051的R0~R7在内部RAM的00H~07H
	PUSH    82H     ; DPL (DPTR低字节)
	PUSH    83H     ; DPH (DPTR高字节)

	MOV     R0, A   ; 保存音符编号到R0（A随时会被SUBB/MOVC改掉）
	JZ      Buzzer_Mute ; 输入0 = 静音，直接跳去关蜂鸣器

	; --- 范围检查：编号>=22的一律视为非法，跳去静音 ---
	MOV     A, R0   ; 恢复原始输入值
	CLR     CY      ; 先清空借位标志！SUBB= A - n - CY，不清CY会导致差1
	; 
	; 重要陷阱：CJNE也会悄悄改CY！如果代码里前面有CJNE比较，后面的SUBB
	; 必须先CLR CY，否则减法结果会多减1（因为CY可能是1）。
	;
	SUBB    A, #22  ; A = A - 22 - CY（此时CY=0，所以就是A-22）
	; SUBB后：A>=22 → CY=0,  A<22 → CY=1
	JNC     Buzzer_Mute ; CY=0说明A>=22，非法编号跳去静音

	; --- 查表获取TH0初值 ---
	MOV     A, R0   ; 恢复音符编号（SUBB把A改掉了）
	MOV     DPTR, #Note_TH0_Table ; DPTR指向TH0初值表
	MOVC    A, @A+DPTR ; 查表：从ROM中取 Note_TH0_Table[A] 的值
	MOV     Freq_TH0, A ; 存到全局变量（Timer0_ISR会从这里读取）

	; --- 查表获取TL0初值 ---
	MOV     A, R0
	MOV     DPTR, #Note_TL0_Table
	MOVC    A, @A+DPTR
	MOV     Freq_TL0, A

	; --- 装填初值 + 启动定时器 ---
	; 直接写TH0/TL0（不是Freq_TH0/TL0），因为这是第一次启动，
	; 之后的中断才从Freq_TH0/TL0重载。不写初值的话第一次溢出会异常。
	MOV     TH0, Freq_TH0
	MOV     TL0, Freq_TL0
	SETB    TR0     ; 启动Timer0！蜂鸣器开始发声
	SJMP    Buzzer_Exit

Buzzer_Mute:
	CLR     TR0     ; 停止定时器0——方波停，蜂鸣器不再发声
	SETB    P2.4    ; 把P2.4拉高。蜂鸣器是低电平驱动，高电平=彻底闭嘴

Buzzer_Exit:
	POP     83H     ; 恢复DPH
	POP     82H     ; 恢复DPL
	POP     00H     ; 恢复R0
	POP     ACC     ; 恢复ACC
	RET

; 11.0592MHz crystal
; Timer tick = 12/11.0592MHz = 1.085us
; Reload = 65536 - round(460800 / f)
; Index: 0=rest, 1..7 low(C3..B3), 8..14 middle(C4..B4), 15..21 high(C5..B5)
; 初值计算公式 : (65536 - 初值) * 2f = 11.0592MHz / 12 = 921600

Note_TH0_Table:
	DB  00H
	DB  0F2H,0F3H,0F5H,0F5H,0F6H,0F7H,0F8H
	DB  0F9H,0F9H,0FAH,0FAH,0FBH,0FBH,0FCH
	DB  0FCH,0FCH,0FDH,0FDH,0FDH,0FDH,0FEH

Note_TL0_Table:
	DB  00H
	DB  042H,0C1H,017H,0B7H,0D1H,0D1H,0B6H
	DB  021H,0E1H,08CH,0D8H,068H,0E9H,05BH
	DB  08FH,0EFH,045H,06CH,0B4H,0F4H,02EH

END
