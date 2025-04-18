@echo off
setlocal enabledelayedexpansion



set /p "choice=是否已连接调试设备，输入Y跳过连接直接执行，输入N连接设备: "
if /i "%choice%"=="Y" goto continue
if /i "%choice%"=="N" (
     set /p "ip=请输入IP地址: "
     set /p "port=请输入端口: "
     hdc tconn %ip%:%port%
)

:continue
echo 已连接设备，执行下一条命令...

:: 记录开始时间并处理前导零
for /f "tokens=1-4 delims=:., " %%a in ("%TIME%") do (
    set /a "start_h=1%%a-100, start_m=1%%b-100, start_s=1%%c-100, start_cs=1%%d-100"
)
echo 开始时间：!start_h!:!start_m!:!start_s!.!start_cs!

:: 提示用户输入项目根目录
:input_path
set /p "PROJECT_ROOT=请输入项目根目录（例如 D:\harmony\ColorPicker）: "
if "%PROJECT_ROOT%"=="" (
    echo 错误：输入不能为空！
    goto input_path
)

set HAP_PATH=%PROJECT_ROOT%\entry\build\default\outputs\default\entry-default-signed.hap
set TIMESTAMP=%DATE:~5,2%%DATE:~8,2%_%TIME:~0,2%%TIME:~3,2%
set DEVICE_DIR=data/local/tmp/%TIMESTAMP%

:: 关键修改1：强制同步执行
:clean_project
echo [STEP 1] 正在清理工程...
(
    cd /d "%PROJECT_ROOT%" || exit /b 1
    call hvigorw clean --no-daemon --console=plain
) >clean.log 2>&1

:: 关键修改2：不检查错误直接继续（如需要容错可移除exit）
if errorlevel 1 (
    echo [警告] 清理失败，尝试继续构建...
)

:: 关键修改3：添加进程状态验证
tasklist /fi "IMAGENAME eq node.exe" | findstr /i "node.exe" >nul
if errorlevel 0 (
    echo [强制终止] 发现残留Node进程...
    taskkill /f /im node.exe >nul 2>&1
)

:build_hap
echo [STEP 2] 正在构建HAP...
(
    cd /d "%PROJECT_ROOT%"
    call hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon --console=plain
) >build.log 2>&1

if exist "%HAP_PATH%" (
    echo 构建成功！HAP路径：%HAP_PATH%
) else (
    echo 错误：HAP文件未生成！
    type build.log
    exit /b 1
)

:: 3. 创建设备临时目录
echo [STEP 3] Creating device directory: %DEVICE_DIR%
hdc shell mkdir -p %DEVICE_DIR%

:: 4. 推送 HAP 到设备
echo [STEP 4] Pushing HAP to device...
hdc file send "%HAP_PATH%" "%DEVICE_DIR%"

:: 5. 安装 HAP
echo [STEP 5] Installing HAP...
hdc shell bm install -p %DEVICE_DIR%

:: 6. 清理设备临时文件（可选）
echo [STEP 6] Cleaning device temp files...
hdc shell rm -rf %DEVICE_DIR%

:: 记录结束时间并处理前导零
for /f "tokens=1-4 delims=:., " %%a in ("%TIME%") do (
    set /a "end_h=1%%a-100, end_m=1%%b-100, end_s=1%%c-100, end_cs=1%%d-100"
)
echo 结束时间：!end_h!:!end_m!:!end_s!.!end_cs!

:: 计算耗时差值
set /a "start_total=(start_h*3600 + start_m*60 + start_s)*100 + start_cs"
set /a "end_total=(end_h*3600 + end_m*60 + end_s)*100 + end_cs"
set /a "diff_total=end_total - start_total"

:: 处理跨天情况（如23:00到01:00）
if %diff_total% lss 0 set /a diff_total+=8640000

:: 转换为可读格式
set /a "hours=diff_total/360000, remaining=diff_total%%360000"
set /a "minutes=remaining/6000, remaining%%=6000"
set /a "seconds=remaining/100, cs=remaining%%100"

:: 输出结果
echo 所有操作完成！耗时：%hours%小时%minutes%分%seconds%秒

pause