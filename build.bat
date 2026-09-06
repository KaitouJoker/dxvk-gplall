@echo off
setlocal enabledelayedexpansion
title DXVK-GPLALL One-Click Builder [v2.6.9]
chcp 65001 >nul
cd /d "%~dp0"

echo =======================================================================
echo     DXVK-GPLALL v2.6.9 One-Click Builder [KartRider Low-Latency]
echo =======================================================================
echo.

:: 1. Visual Studio DevCmd 탐색
set "VS_PATH="
set "VS_DEVCMD="

set "VSWHERE_PATH=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "!VSWHERE_PATH!" set "VSWHERE_PATH=%ProgramFiles%\Microsoft Visual Studio\Installer\vswhere.exe"

if exist "!VSWHERE_PATH!" (
    for /f "usebackq tokens=*" %%i in (`"!VSWHERE_PATH!" -latest -property installationPath`) do set "VS_PATH=%%i"
)

:: 알려진 기본 설치 경로 대체 확인
if not defined VS_PATH if exist "D:\Microsoft Visual Studio\18\Community" set "VS_PATH=D:\Microsoft Visual Studio\18\Community"
if not defined VS_PATH if exist "C:\Program Files\Microsoft Visual Studio\2022\Community" set "VS_PATH=C:\Program Files\Microsoft Visual Studio\2022\Community"
if not defined VS_PATH if exist "C:\Program Files\Microsoft Visual Studio\2022\Professional" set "VS_PATH=C:\Program Files\Microsoft Visual Studio\2022\Professional"
if not defined VS_PATH if exist "C:\Program Files\Microsoft Visual Studio\2022\Enterprise" set "VS_PATH=C:\Program Files\Microsoft Visual Studio\2022\Enterprise"
if not defined VS_PATH if exist "C:\Program Files\Microsoft Visual Studio\2022\BuildTools" set "VS_PATH=C:\Program Files\Microsoft Visual Studio\2022\BuildTools"

if defined VS_PATH if exist "!VS_PATH!\Common7\Tools\VsDevCmd.bat" (
    set "VS_DEVCMD=!VS_PATH!\Common7\Tools\VsDevCmd.bat"
)

if not defined VS_DEVCMD (
    echo [ERROR] Visual Studio C++ 빌드 환경 [VsDevCmd.bat]을 찾을 수 없습니다.
    echo         Visual Studio 2022 이상과 "C++를 사용한 데스크톱 개발"을 설치해 주세요.
    echo.
    pause
    exit /b 1
)

echo [*] Visual Studio 감지됨: "!VS_PATH!"

:: 2. 필수 빌드 도구 검사
where meson.exe >nul 2>nul
if %ERRORLEVEL% neq 0 (
    where meson >nul 2>nul
    if %ERRORLEVEL% neq 0 (
        echo [ERROR] 'meson' 명령어를 찾을 수 없습니다. [pip install meson]
        pause
        exit /b 1
    )
)

where ninja.exe >nul 2>nul
if %ERRORLEVEL% neq 0 (
    where ninja >nul 2>nul
    if %ERRORLEVEL% neq 0 (
        echo [ERROR] 'ninja' 명령어를 찾을 수 없습니다. [pip install ninja]
        pause
        exit /b 1
    )
)

where glslangValidator.exe >nul 2>nul
if %ERRORLEVEL% neq 0 (
    where glslangValidator >nul 2>nul
    if %ERRORLEVEL% neq 0 (
        if exist "%~dp0glslangValidator.exe" (
            set "PATH=%~dp0;!PATH!"
        ) else (
            echo [*] glslangValidator.exe가 없어 자동 다운로드를 진행합니다...
            curl.exe -sLo "%~dp0glslangValidator.exe" "https://raw.githubusercontent.com/HansKristian-Work/vkd3d-proton-ci/main/glslangValidator.exe"
            if exist "%~dp0glslangValidator.exe" (
                set "PATH=%~dp0;!PATH!"
                echo [*] glslangValidator.exe 다운로드 완료.
            ) else (
                echo [ERROR] glslangValidator.exe 다운로드에 실패했습니다.
                pause
                exit /b 1
            )
        )
    )
)

:: 3. 명령줄 인수 처리
if /i "%1"=="x86" goto build_x86_only
if /i "%1"=="32" goto build_x86_only
if /i "%1"=="x32" goto build_x86_only
if /i "%1"=="x64" goto build_x64_only
if /i "%1"=="64" goto build_x64_only
if /i "%1"=="clean" goto do_clean
if /i "%1"=="all" goto build_both

:: 4. 대화형 메뉴 [더블 클릭 시 5초 후 자동 1번 선택]
echo.
echo -----------------------------------------------------------------------
echo  [빌드 모드를 선택하세요]
echo    1. 전체 빌드 [x32 + x64] - 기본값 [5초 후 자동 시작]
echo    2. 카트라이더용 32-bit [x86] 빌드
echo    3. 64-bit [x64] 빌드
echo    4. 빌드 임시 폴더 정리 [Clean]
echo -----------------------------------------------------------------------
echo.

choice /c 1234 /t 5 /d 1 /m "선택 [1/2/3/4]: "
set "MENU_CHOICE=%ERRORLEVEL%"
echo.

if "%MENU_CHOICE%"=="4" goto do_clean
if "%MENU_CHOICE%"=="2" goto build_x86_only
if "%MENU_CHOICE%"=="3" goto build_x64_only
goto build_both

:build_both
call :compile_arch x86 x32
if %ERRORLEVEL% neq 0 goto build_fail
call :compile_arch x64 x64
if %ERRORLEVEL% neq 0 goto build_fail
goto build_success

:build_x86_only
call :compile_arch x86 x32
if %ERRORLEVEL% neq 0 goto build_fail
goto build_success

:build_x64_only
call :compile_arch x64 x64
if %ERRORLEVEL% neq 0 goto build_fail
goto build_success

:compile_arch
set "ARCH=%~1"
set "OUT_SUBDIR=%~2"
set "BUILD_DIR=build-msvc-%ARCH%"

echo.
echo =======================================================================
echo   [%ARCH%] 컴파일 시작 [Target: Release\%OUT_SUBDIR%\]
echo =======================================================================

if not exist "%BUILD_DIR%\build.ninja" (
    cmd /c call "%VS_DEVCMD%" -arch=%ARCH% -host_arch=x64 -no_logo ^&^& meson setup "%BUILD_DIR%" --buildtype release -Db_ndebug=if-release -Denable_d3d8=false
) else (
    cmd /c call "%VS_DEVCMD%" -arch=%ARCH% -host_arch=x64 -no_logo ^&^& meson setup "%BUILD_DIR%" --reconfigure
)
if %ERRORLEVEL% neq 0 (
    echo [ERROR] %ARCH% meson 설정 중 오류가 발생했습니다.
    exit /b 1
)

cmd /c call "%VS_DEVCMD%" -arch=%ARCH% -host_arch=x64 -no_logo ^&^& ninja -C "%BUILD_DIR%" src/d3d9/d3d9.dll src/dxgi/dxgi.dll
if %ERRORLEVEL% neq 0 (
    echo [ERROR] %ARCH% ninja 빌드 중 오류가 발생했습니다.
    exit /b 1
)

if not exist "Release\%OUT_SUBDIR%" mkdir "Release\%OUT_SUBDIR%"

if exist "%BUILD_DIR%\src\d3d9\d3d9.dll" (
    copy /y "%BUILD_DIR%\src\d3d9\d3d9.dll" "Release\%OUT_SUBDIR%\d3d9.dll" >nul
    echo [+] Release\%OUT_SUBDIR%\d3d9.dll 배포 완료
)

if exist "%BUILD_DIR%\src\dxgi\dxgi.dll" (
    copy /y "%BUILD_DIR%\src\dxgi\dxgi.dll" "Release\%OUT_SUBDIR%\dxgi.dll" >nul
    echo [+] Release\%OUT_SUBDIR%\dxgi.dll 배포 완료
)

exit /b 0

:do_clean
echo.
echo [*] 빌드 임시 디렉토리를 정리합니다...
if exist "build-msvc-x86" rmdir /s /q "build-msvc-x86"
if exist "build-msvc-x64" rmdir /s /q "build-msvc-x64"
if exist "subprojects\.wraplock" del /f /q "subprojects\.wraplock"
if exist "glslangValidator.exe" del /f /q "glslangValidator.exe"
echo [*] 정리가 완료되었습니다.
if "%1"=="" pause
exit /b 0

:build_fail
echo.
echo =======================================================================
echo   [FAILED] 빌드 도중 오류가 발생했습니다. 로그를 확인해 주세요.
echo =======================================================================
echo.
pause
exit /b 1

:build_success
echo.
echo =======================================================================
echo   [SUCCESS] 빌드 및 Release 폴더 배포가 성공적으로 완료되었습니다!
echo =======================================================================
echo.
echo [결과물 확인]
if exist "Release\x32\d3d9.dll" (
    for %%A in ("Release\x32\d3d9.dll") do echo   - Release\x32\d3d9.dll [%%~zA bytes]  ^<- 카트라이더용
)
if exist "Release\x32\dxgi.dll" (
    for %%A in ("Release\x32\dxgi.dll") do echo   - Release\x32\dxgi.dll [%%~zA bytes]
)
if exist "Release\x64\d3d9.dll" (
    for %%A in ("Release\x64\d3d9.dll") do echo   - Release\x64\d3d9.dll [%%~zA bytes]
)
if exist "Release\x64\dxgi.dll" (
    for %%A in ("Release\x64\dxgi.dll") do echo   - Release\x64\dxgi.dll [%%~zA bytes]
)
echo.
echo 카트라이더 적용: Release\x32\d3d9.dll 파일을 카트라이더 실행 폴더에 복사하세요.
echo.
if "%1"=="" pause
exit /b 0
