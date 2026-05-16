; ║  文件名: Main.asm
; ║  层级:   App (应用层) — 项目的"总指挥部"                              
; ║  功能:   1. 系统入口：上电后第一个执行的代码                         
; ║         2. 中断向量表：定义3个中断的跳转入口            
; ║         3. 系统初始化：串口、定时器、红外              
; ║         4. 主循环：轮询三路输入→转换为统一事件→分发给执行单元 
; ║               
; ║         这个文件是整个项目的"大脑"。                      
; ║                                                                      
; ║          【上电→初始化→死循环】                                        
; ║          1) 单片机一上电，硬件强制PC=0000H，第一条指令LJMP跳到MAIN_START
; ║             0000H~002BH是中断向量区，让开中断向量区       
; ║          2) MAIN_START做三件事：设堆栈指针→初始化三个外设→开总中断    
; ║          3) 进入死循环（嵌入式程序的正常状态）：                      
; ║             检测串口→有数据？解析→分发                            
; ║             检测红外→有命令？解析→分发                     
; ║             检测按键→有按下？翻译→分发                    
; ║             循环往复，永不停止。                              
; ║                                                                
; ║          【统一事件系统】是这个文件的核心设计：                       
; ║          三路输入（串口/红外/按键）各说各的语言，但都翻译成统一事件码   
; ║          (0~22~39)，Dispatch_Event 只管根据事件码决定干什么：         
; ║          0=跳过, 1~21=弹一个音, 22=静音, 30~39=播一首歌               
; ║          新增输入源只需要产生同样的事件码，不用改Dispatch_Event。        
; ║                                                                      
; ║  中断向量表 (硬件强制的固定入口):                                      
; ║  ORG 0000H: 复位         → LJMP MAIN_START                     
; ║  ORG 0003H: 外部中断0(IR) → LJMP IR_ISR                      
; ║  ORG 000BH: 定时器0溢出   → LJMP Timer0_ISR                        
; ║  ORG 0023H: 串口中断      → LJMP UART_ISR                   

; ║  第2部分：汇编指令速查表（本文件出现的所有指令）                    
; ╠═════════════════════════════════════════════════════════════════════
; ║  ORG  n        │ 伪指令：指定下一条代码放在ROM的地址n。                
; ║               │ 8051的中断入口是硬件固定的，必须用ORG精确放置跳转指令。 
; ║  LJMP 标签     │ 无条件长跳转(占3字节)，64KB范围内可达。               
; ║               │ 为什么中断向量区用LJMP？中断服务函数可能在            
; ║               │ 很远的位置，SJMP跳不到。                              
; ║  MOV  SP, #50H │ 设置堆栈指针。SP=50H(80)意味着堆栈从地址80开始，       
; ║               │ 远离寄存器区(00H~1FH)和位寻址区(20H~2FH)             
; ║  LCALL 标签    │ 长调用子函数（占3字节），自动把返回地址压栈            
; ║  SJMP 标签     │ 短跳转（占2字节）。主循环的 SJMP MAIN_LOOP 形成死循环  
; ║  ------ 以下指令见此前文件，此处简记 ------                            
; ║  SETB / PUSH / POP / JZ / CJNE / SUBB / JC / JNC / CLR A / CLR C /  
; ║  MOV / RET                                                           

;
; ╔══════════════════════════════════════════════════════════════════════
; ║  第3部分：特殊功能寄存器速查表（本文件涉及的SFR）                       
; ╠══════════════════════════════════════════════════════════════════════
; ║  SP │ 81H │ 堆栈指针。指向"最后压入的那个数据在RAM中的位置"+1          
; ║     │     │ 上电默认07H，这里改为50H。07H离寄存器区太近，嵌套调用      
; ║     │     │ 容易把R0~R7的数据踩坏（这就是"爆栈"）                    
; ║  IE │ A8H │ 中断允许。EA(bit7)=总中断总闸门，所有中断的"终极开关"     

NAME    MAIN

; ------------------ 声明外部函数和变量 ------------------
EXTRN   CODE (Timer0_Init)
EXTRN   CODE (UART_Init)
EXTRN   CODE (Timer0_ISR)
EXTRN   CODE (UART_ISR)
EXTRN   CODE (IR_Init)
EXTRN   CODE (IR_ISR)
EXTRN   CODE (Task_ParseSerial)
EXTRN   CODE (Task_ParseIR)
	
EXTRN   CODE (Key_Scan)
EXTRN   CODE (Buzzer_Play)
EXTRN   CODE (Led_ShowSpectrum)
EXTRN   CODE (MusicPlayer_PlaySong)

EXTRN   CODE (DigiTube_Init)
EXTRN   CODE (DigiTube_Scan)
EXTRN   CODE (DigiTube_ShowNumber)

CSEG        ; 使用默认代码段

NOTE_OFF_EVT    EQU     22  ; 静音事件的统一编码

; ============================================
; 中断向量表 —— 8051硬件强制的固定入口地址
; ============================================
; 每个ORG之间只有8字节（如0000H→0003H有3字节，刚好放一条LJMP）
; 如果中断服务函数很短，8字节能塞下；长了就必须用LJMP跳出去
; 这就是为什么这里每条都是LJMP——服务函数全在别的文件里，很长

ORG     0000H
	; 复位向量：上电/复位后PC自动指向这里
	; 8051在0000H执行第一条指令，这里是跳到真正的main函数去
	LJMP    MAIN_START

ORG     0003H
	; 外部中断0 (INT0)：P3.2引脚下降沿触发 → 红外遥控
	LJMP    IR_ISR

ORG     000BH
	; 定时器0中断：Timer0计数溢出 → 蜂鸣器方波翻转
	LJMP    Timer0_ISR

ORG     0023H
	; 串口中断：收到/发出一个字节 → 串口帧接收机
	LJMP    UART_ISR

; ============================================
; 系统初始化（上电后只执行一次）
; ============================================
ORG     0030H
	; 主程序入口放在0030H，跳过前面所有中断向量区（到002BH为止）。
	; 0030H之后写代码不会踩到中断入口。
MAIN_START:
	MOV     SP, #50H       ; 堆栈指针设到80(50H)，远离寄存器区
	; 8051的RAM布局（低→高）：
	; 00H~07H: R0~R7 (寄存器组0，堆栈默认从07H开始)
	; 08H~1FH: 寄存器组1~3
	; 20H~2FH: 位寻址区
	; 30H~7FH: 用户RAM — 设SP=50H让堆栈从这里起步，有48字节空间

	LCALL   Timer0_Init    ; 初始化Timer0 (蜂鸣器音调发生器)
	LCALL   UART_Init      ; 初始化串口 (9600bps, 帧接收状态机)
	LCALL   IR_Init        ; 初始化红外 (INT0下降沿触发 + Timer2计时)
	LCALL   DigiTube_Init  ; 初始化数码管 (显示缓冲清空, 位选关闭)

        SETB    EA          ; 开启总中断
	; 在这之前初始化做的CLR/SETB不会触发中断，因为EA=0等于所有中断被拦截。
	; SETB EA之后三个外设的中断才开始真正生效（还用各自的ET0/ES/EX0做二级开关）
	
MAIN_LOOP:
	; 经示波器测量,main循环一轮大约100us
	; CLR     P1.7
	; ============ 数码管动态扫描 ============
	LCALL   DigiTube_Scan  ; 每次循环扫一位，4次完成一轮全刷

	; ============ 输入源1：串口 ============
	LCALL   Task_ParseSerial  ; 检查有没有新到的串口帧，有就解析出事件码
	LCALL   Dispatch_Event    ; 根据事件码执行对应动作（发音/静音/播歌）

	; ============ 输入源2：红外遥控 ============
	LCALL   Task_ParseIR      ; 检查红外有没有新命令，翻译成事件码
	LCALL   Dispatch_Event

	; ============ 输入源3：物理按键 ============
	LCALL   Key_Scan          ; 扫描按键（带消抖），返回按键码
	
	LCALL   Key_ToEvent       ; 按键码→事件码（K1=静音, K2=note1, K3=note8, K4=note15）
	LCALL   Dispatch_Event

	; SETB    P1.7

	SJMP    MAIN_LOOP         ; 死循环

; --------------------------------------------------------
; Key_ToEvent — 按键码 → 统一事件码
; 输入: A = Key_Scan 返回值(0=无按键, 1/2/3=键码, 5=松开)
; 输出: A = 统一事件(0=无, 1..21=发音, 22=静音)
; 
; 映射规则:
;   K1(键码1) → 静音(22)
;   K2(键码2) → 音符1 (Do)
;   K3(键码3) → 音符8 (中音区Do)
;   K4(键码4) → 音符15(低音区Do)
;   键码5(松开) → 静音(22) —— 松手自动闭嘴
; --------------------------------------------------------
Key_ToEvent:
	JZ      Key_ToEvent_None     ; A=0 → 无事件

	CJNE    A, #5, Key_ToEvent_CheckK1  ; 键码5（松开确认）?
	MOV     A, #NOTE_OFF_EVT      ; → 静音
	RET

Key_ToEvent_CheckK1:
	CJNE    A, #1, Key_ToEvent_CheckK2  ; 键码1（K1）?
	MOV     A, #NOTE_OFF_EVT      ; K1 → 静音
	RET

Key_ToEvent_CheckK2:
	CJNE    A, #2, Key_ToEvent_CheckK3  ; 键码2（K2）?
	MOV     A, #1                 ; K2 → 音符1 (Do)
	RET

Key_ToEvent_CheckK3:
	CJNE    A, #3, Key_ToEvent_CheckK4  ; 键码3（K3）?
	MOV     A, #8                 ; K3 → 音符8
	RET

Key_ToEvent_CheckK4:
	CJNE    A, #4, Key_ToEvent_None     ; 键码4（K4）? 不是就只能忽略了
	MOV     A, #15                ; K4 → 音符15
	RET

Key_ToEvent_None:
	CLR     A                     ; 返回0=无事件
	RET

; --------------------------------------------------------
; Dispatch_Event — 统一事件分发器（项目的"调度中心"）
; 输入: A = 统一事件
;       0        → 无操作
;       1~21     → 播放单个音符（Buzzer_Play + Led_ShowSpectrum）
;       22       → 静音（关蜂鸣器 + 关LED）
;       23~29    → （非法/预留，超过22的都是噪音，忽略）
;       30~39    → 播放歌曲（MusicPlayer_PlaySong，自动播完整曲）
; 
; 设计原则：新增输入源只需产生约定的事件码，不用改这里。
; --------------------------------------------------------
Dispatch_Event:
	PUSH    07H             ; 保护R7（此函数内部用R7暂存事件码）

	JZ      Dispatch_Event_Exit ; A=0 → 无事件，直接退出

	; --- 是静音事件吗？ ---
	CJNE    A, #NOTE_OFF_EVT, Dispatch_Event_CheckSong
	CLR     A               ; 音符0=静音
	LCALL   Buzzer_Play
	LCALL   Led_ShowSpectrum
	LCALL   DigiTube_ShowNumber ; 熄灭数码管
	SJMP    Dispatch_Event_Exit

Dispatch_Event_CheckSong:
	; --- 区分"单音符"(1~21) 和 "歌曲"(30~39) ---
	MOV     R7, A           ; 暂存原始事件码
	CLR     C
	SUBB    A, #30          ; A = 事件码 - 30
	JC      Dispatch_Event_Play ; CY=1说明事件码<30（即1~21或非法值23~29）
	
	; 事件码 >= 30 → 歌曲播放
	; A此时=歌曲ID（30→0, 31→1, ... 39→9）
	LCALL   MusicPlayer_PlaySong
	SJMP    Dispatch_Event_Exit

Dispatch_Event_Play:
	; 事件码 1~21 → 检查是否合法（排除23~29的非法值）
	MOV     A, R7           ; 恢复原始事件码
	CLR     C
	SUBB    A, #NOTE_OFF_EVT ; A = 事件码 - 22
	JNC     Dispatch_Event_Exit ; CY=0说明>=22（可能是23~29非法值），忽略

	; 合法！1~21之间的音符
	MOV     A, R7
	LCALL   Buzzer_Play     ; 播放音符
	LCALL   Led_ShowSpectrum ; 点亮对应LED
	LCALL   DigiTube_ShowNumber ; 数码管显示音符编号

Dispatch_Event_Exit:
	POP     07H             ; 恢复R7
	RET

END
