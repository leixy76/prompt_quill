@echo off


:: If you don't already have Git, download Git-SCM and install it here: https://git-scm.com/download/win
WHERE git >nul 2>nul
IF %ERRORLEVEL% NEQ 0 (
	ECHO:
	ECHO You will need to install git first before running this script. Please download it at https://git-scm.com/download/win
	ECHO:
	pause
	exit
)

cd /D "%~dp0"

set PATH=%PATH%;%SystemRoot%\system32

echo "%CD%"| findstr /C:" " >nul && echo This script relies on Miniconda which can not be silently installed under a path with spaces. && goto end

@rem Check for special characters in installation path
set "SPCHARMESSAGE="WARNING: Special characters were detected in the installation path!" "         This can cause the installation to fail!""
echo "%CD%"| findstr /R /C:"[!#\$%&()\*+,;<=>?@\[\]\^`{|}~]" >nul && (
	call :PrintBigMessage %SPCHARMESSAGE%
)
set SPCHARMESSAGE=

@rem fix failed install when installing to a separate drive
set TMP=%cd%\installer_files
set TEMP=%cd%\installer_files

@rem deactivate existing conda envs as needed to avoid conflicts
(call conda deactivate && call conda deactivate && call conda deactivate) 2>nul

@rem config
set BASE_DIR=%cd%
set INSTALL_DIR=%cd%\installer_files
set CACHE_DIR=%cd%\installer_cache
set CONDA_ROOT_PREFIX=%cd%\installer_files\conda
set INSTALL_ENV_DIR=%cd%\installer_files\env
set MINICONDA_DOWNLOAD_URL=https://repo.anaconda.com/miniconda/Miniconda3-py310_23.3.1-0-Windows-x86_64.exe
set conda_exists=F
set STATUS_FILE=%cd%\installer_files\status.txt

if not exist "%INSTALL_DIR%" (
	mkdir "%INSTALL_DIR%"
)


@rem figure out whether git and conda needs to be installed
call "%CONDA_ROOT_PREFIX%\_conda.exe" --version >nul 2>&1
if "%ERRORLEVEL%" EQU "0" set conda_exists=T

@rem (if necessary) install git and conda into a contained environment
@rem download conda
if "%conda_exists%" == "F" (
	echo Downloading Miniconda from %MINICONDA_DOWNLOAD_URL% to %INSTALL_DIR%\miniconda_installer.exe

	call curl -Lk "%MINICONDA_DOWNLOAD_URL%" > "%INSTALL_DIR%\miniconda_installer.exe" || ( echo. && echo Miniconda failed to download. && goto end )

	echo Installing Miniconda to %CONDA_ROOT_PREFIX%
	start /wait "" "%INSTALL_DIR%\miniconda_installer.exe" /InstallationType=JustMe /NoShortcuts=1 /AddToPath=0 /RegisterPython=0 /NoRegistry=1 /S /D=%CONDA_ROOT_PREFIX%

	@rem test the conda binary
	echo Miniconda version:
	call "%CONDA_ROOT_PREFIX%\_conda.exe" --version || ( echo. && echo Miniconda not found. && goto end )
)

@rem create the installer env
if not exist "%INSTALL_ENV_DIR%" (
	echo Packages to install: %PACKAGES_TO_INSTALL%
	call "%CONDA_ROOT_PREFIX%\_conda.exe" create --no-shortcuts -y -k --prefix "%INSTALL_ENV_DIR%" python=3.11 || ( echo. && echo Conda environment creation failed. && goto end )
)

@rem check if conda environment was actually created
if not exist "%INSTALL_ENV_DIR%\python.exe" ( echo. && echo Conda environment is empty. && goto end )


@rem environment isolation
set PYTHONNOUSERSITE=1
set PYTHONPATH=
set PYTHONHOME=
set "CUDA_PATH=%INSTALL_ENV_DIR%"
set "CUDA_HOME=%CUDA_PATH%"

@rem activate installer env
call "%CONDA_ROOT_PREFIX%\condabin\conda.bat" activate "%INSTALL_ENV_DIR%" || ( echo. && echo Miniconda hook not found. && goto end )

ECHO cleanup miniconda installer
del /f %INSTALL_DIR%\miniconda_installer.exe

call pip install requests

if exist "%INSTALL_DIR%/qdrant" (
    ECHO Startup Qdrant
    cd %INSTALL_DIR%/qdrant
    start "" "%INSTALL_DIR%/qdrant/qdrant.exe"

    cd %BASE_DIR%
    start /W "" python pq/check_qdrant_up.py

)

echo install the vector store
if not exist "%INSTALL_DIR%/qdrant" (

    if not exist "%CACHE_DIR%/qdrant-x86_64-pc-windows-msvc.zip" (
        ECHO Download Qdrant Portable Version
        if exist %STATUS_FILE% del %STATUS_FILE%
        curl -L https://github.com/qdrant/qdrant/releases/download/v1.9.2/qdrant-x86_64-pc-windows-msvc.zip --output %INSTALL_DIR%/qdrant-x86_64-pc-windows-msvc.zip -w "%%{http_code}" > %STATUS_FILE%
        set /p HTTPCODE=<%STATUS_FILE%
        for /f %%i in ("%HTTPCODE%") do set HTTPCODE=%%i
        if "%HTTPCODE%" neq "200" (
            echo [101;93m Error: Failed to download qdrant-x86_64-pc-windows-msvc.zips HTTP Status Code: %HTTPCODE% [0m
            pause
            exit /b 1
        )
    ) else (
        xcopy %CACHE_DIR%\qdrant-x86_64-pc-windows-msvc.zip %INSTALL_DIR%
    )

    if not exist "%CACHE_DIR%/dist-qdrant.zip" (
        ECHO Download Qdrant Web UI
        if exist %STATUS_FILE% del %STATUS_FILE%
        curl -L https://github.com/qdrant/qdrant-web-ui/releases/download/v0.1.22/dist-qdrant.zip --output %INSTALL_DIR%/dist-qdrant.zip -w "%%{http_code}" > %STATUS_FILE%
        set /p HTTPCODE=<%STATUS_FILE%
        for /f %%i in ("%HTTPCODE%") do set HTTPCODE=%%i
        if "%HTTPCODE%" neq "200" (
         echo [101;93m Error: Failed to download dist-qdrant.zip HTTP Status Code: %HTTPCODE% [0m
         pause
         exit /b 1
        )
    ) else (
        xcopy %CACHE_DIR%\dist-qdrant.zip %INSTALL_DIR%
    )

    if not exist "%CACHE_DIR%/data.zip" (
        ECHO Download llama-index QDrant data
        if exist %STATUS_FILE% del %STATUS_FILE%
        curl -L https://civitai.com/api/download/models/567736 --output %INSTALL_DIR%/data.zip -w "%%{http_code}" > %STATUS_FILE%
        set /p HTTPCODE=<%STATUS_FILE%
        for /f %%i in ("%HTTPCODE%") do set HTTPCODE=%%i
        if "%HTTPCODE%" neq "200" (
         echo [101;93m Error: Failed to download Prompt Quill data HTTP Status Code: %HTTPCODE% [0m
         pause
         exit /b 1
        )
    ) else (
        xcopy %CACHE_DIR%\data.zip %INSTALL_DIR%
    )


    ECHO Extract Qdrant with unzip
    %INSTALL_DIR%/../../unzip/unzip.exe %INSTALL_DIR%/qdrant-x86_64-pc-windows-msvc.zip -d %INSTALL_DIR%/qdrant

    ECHO Extract Qdrant web UI with unzip
    %INSTALL_DIR%/../../unzip/unzip.exe %INSTALL_DIR%/dist-qdrant.zip -d %INSTALL_DIR%/qdrant

    ECHO rename the dist folder to static
    cd %INSTALL_DIR%/qdrant
    ren "dist" "static"

    cd %INSTALL_DIR%

    ECHO Extract Qdrant web UI with unzip
    %INSTALL_DIR%/../../unzip/unzip.exe %INSTALL_DIR%/data.zip -d %INSTALL_DIR%/delete_after_setup

    ECHO Startup Qdrant to upload the data
    cd %INSTALL_DIR%/qdrant
    start "" "%INSTALL_DIR%/qdrant/qdrant.exe" --disable-telemetry

    cd %BASE_DIR%
    REM we do this to give Qdrant some time to fire up
    start /W "" python pq/check_qdrant_up.py

    ECHO Load data into qdrant, please be patient, this may take a while
    curl -X POST "http://localhost:6333/collections/prompts_large_meta/snapshots/upload?priority=snapshot" -H "Content-Type:multipart/form-data" -H "api-key:" -F "snapshot=@%INSTALL_DIR%/delete_after_setup/prompts_ng_gte-2103298935062809-2024-06-12-06-41-21.snapshot"

    ECHO some cleanup
    del /f %INSTALL_DIR%\dist-qdrant.zip
    del /f %INSTALL_DIR%\qdrant-x86_64-pc-windows-msvc.zip
    del /f %INSTALL_DIR%\data.zip
    rmdir /s /q %INSTALL_DIR%\delete_after_setup
    rmdir /s /q %INSTALL_DIR%\qdrant\snapshots
)



cd %BASE_DIR%
call python one_click.py



:PrintBigMessage
echo. && echo.
echo *******************************************************************
for %%M in (%*) do echo * %%~M
echo *******************************************************************
echo. && echo.
pause
exit /b

:end
pause
exit