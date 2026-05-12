@echo off
REM Launcher for write_run_hashes.ps1 when execution policy blocks local scripts.
REM Usage (from project root):  scripts\write_run_hashes.cmd -RunId v1-dw-20260510-freeze
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0write_run_hashes.ps1" %*
