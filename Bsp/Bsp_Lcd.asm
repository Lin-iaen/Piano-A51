NAME    BSP_LCD1602

        PUBLIC  Lcd_Init
        PUBLIC  Lcd_WriteCmd
        PUBLIC  Lcd_WriteData
		PUBLIC  Lcd_LoadCustomChars ;

        EXTRN   CODE (Delay_ms) ; 借用我们之前写好的延时库

        ; === 硬件引脚映射 (完全对应你的原理图) ===
        LCD_RS  BIT P2.6
        LCD_RW  BIT P3.6
        LCD_EN  BIT P2.7
        LCD_DAT EQU P0          ; P0 口作为 8 位数据总线

        LCD_CODE SEGMENT CODE
        RSEG    LCD_CODE

; ========================================================
; 函数：Lcd_WriteCmd (写指令)
; 入口：ACC (存放要发送的指令，例如 0x01 清屏)
; ========================================================
Lcd_WriteCmd:
        CLR     LCD_RS          ; RS=0，大堂经理说：这是指令！
        CLR     LCD_RW          ; RW=0，只写不读
        MOV     LCD_DAT, A      ; 把 ACC 里的指令铺到 P0 数据线上
        
        ; --- 制造一个 EN 的下降沿“拍”进去 ---
        SETB    LCD_EN          ; EN 拉高
        NOP                     ; 等待信号稳定
        NOP
        CLR     LCD_EN          ; EN 拉低，完成“盖章”
        
        MOV     R7, #2          ; 给屏幕一点消化指令的时间 (2ms)
        LCALL   Delay_ms
        RET

; ========================================================
; 函数：Lcd_WriteData (写数据)
; 入口：ACC (存放要显示的 ASCII 码，例如 'A')
; ========================================================
Lcd_WriteData:
        SETB    LCD_RS          ; RS=1，大堂经理说：这是要显示的字符！
        CLR     LCD_RW          
        MOV     LCD_DAT, A      ; 把字符的 ASCII 码铺到数据线
        
        ; --- 同样的“盖章”动作 ---
        SETB    LCD_EN
        NOP
        NOP
        CLR     LCD_EN
        
        MOV     R7, #1          ; 字符写入比较快，延时 1ms
        LCALL   Delay_ms
        RET

; ========================================================
; 函数：Lcd_Init (LCD开机初始化)
; 说明：消除屏幕上的黑点，设置工作模式
; ========================================================
Lcd_Init:
        ; 1. 告诉屏幕我们的硬件配置：8位数据线，双行显示，5x7点阵
        MOV     A, #38H
        LCALL   Lcd_WriteCmd
        
        ; 2. 屏幕开关配置：开显示屏，关掉丑陋的闪烁光标
        MOV     A, #0CH
        LCALL   Lcd_WriteCmd
        
        ; 3. 写入新数据后，光标自动右移一格
        MOV     A, #06H
        LCALL   Lcd_WriteCmd
        
        ; 4. 终极清屏指令：把那些密密麻麻的黑点全部抹掉！
        MOV     A, #01H
        LCALL   Lcd_WriteCmd
        MOV     R7, #10         ; 清屏极其耗时，强制多等 10ms
        LCALL   Delay_ms
        
        RET
		
Lcd_LoadCustomChars:
        PUSH    ACC
        PUSH    07H
        PUSH    82H
        PUSH    83H

        ; 1. 发送指令：设置 CGRAM 地址为 0x40 (对应第 0 个自定义字符的开头)
        MOV     A, #40H
        LCALL   Lcd_WriteCmd

        ; 2. 准备查表，把 8 个字节的字模写进去
        MOV     DPTR, #INV_CHAR_1
        MOV     R7, #8          ; 循环 8 次

Load_Loop:
        CLR     A
        MOVC    A, @A+DPTR      ; 抓取阴阳码字节
        PUSH    07H             ; 把当前循环的次数（R7）压入堆栈保护起来
        LCALL   Lcd_WriteData   ; 去写数据（随便它怎么破坏 R7，我们不怕了）
        POP     07H
        INC     DPTR
        DJNZ    R7, Load_Loop

        POP     83H
        POP     82H
        POP     07H
        POP     ACC
        RET

; === 阴阳码字模区 ===
INV_CHAR_1:
        DB  1BH, 13H, 1BH, 1BH, 1BH, 1BH, 11H, 1FH
; 在 INV_CHAR_1 下面增加一个“向上平移两像素”的 1
INV_CHAR_1_UP:
        DB  1BH, 1BH, 13H, 1BH, 1BH, 1BH, 1BH, 11H ; 整体上移后的数据

        END