<#
.SYNOPSIS
Универсальный скрипт для работы с видео:
1. Классификация видео по параметрам (разрешение, соотношение сторон, FPS) с фильтрацией.
2. Замена несжатых видео сжатыми (по имени).
#>

# ========== ОБЩИЕ НАСТРОЙКИ ==========
$videoExtensions = @(
    "*.mp4", "*.mkv", "*.avi", "*.mov", "*.wmv", "*.flv", "*.webm",
    "*.m4v", "*.mpg", "*.mpeg", "*.ts", "*.m2ts", "*.3gp", "*.hevc", "*.h265"
)

$colInfo = "Cyan"
$colSuccess = "Green"
$colWarn = "Yellow"
$colError = "Red"

function Write-Log {
    param([string]$Message, [string]$Color = "White", [string]$LogFile = "")
    Write-Host $Message -ForegroundColor $Color
    if ($LogFile -and $LogFile -ne "") {
        Add-Content -Path $LogFile -Value $Message
    }
}

# ========== 1. КЛАССИФИКАЦИЯ ВИДЕО ==========
function Start-VideoClassification {
    param(
        [string]$SourceFolder,
        [string]$OutputRoot,
        [string]$FfprobePath,
        [int]$MinBitrateKbps,
        [string]$ActionType,  # "Copy", "Move", "Shortcut"
        [hashtable]$Filters   # фильтры: fpsList, resList, arList, requireAudio
    )
    
    $rootSortedFolder = "Видео_Сортировано"
    $fullOutputRoot = Join-Path $OutputRoot $rootSortedFolder
    if (-not (Test-Path -LiteralPath $fullOutputRoot)) {
        New-Item -Path $fullOutputRoot -ItemType Directory -Force | Out-Null
    }

    # Получение информации о видео (ffprobe JSON)
    function Get-VideoInfo {
        param([string]$FilePath)
        if (-not (Test-Path -LiteralPath $FilePath)) { return $null }
        $argsList = @("-v", "error", "-select_streams", "v:0", "-show_entries", "stream=bit_rate,width,height,r_frame_rate", "-show_entries", "stream=codec_type", "-of", "json", "--", $FilePath)
        try {
            $output = & $FfprobePath $argsList 2>&1 | Out-String
            if ([string]::IsNullOrWhiteSpace($output)) { return $null }
            $json = $output | ConvertFrom-Json
            if (-not $json.streams -or $json.streams.Count -eq 0) { return $null }
            $stream = $json.streams[0]
            $bitrateRaw = $stream.bit_rate
            $bitrate = 0
            if ($bitrateRaw -and $bitrateRaw -ne "N/A") {
                if ($bitrateRaw -match '^\d+$') { $bitrate = [int]$bitrateRaw }
            }
            $width = $stream.width; $height = $stream.height
            if (-not $width -or -not $height -or $width -eq 0 -or $height -eq 0) { return $null }
            $fpsRaw = $stream.r_frame_rate
            $fps = 0.0
            if ($fpsRaw) {
                if ($fpsRaw -match '^(\d+)/(\d+)$') {
                    $num = [double]$matches[1]; $den = [double]$matches[2]
                    if ($den -ne 0) { $fps = $num / $den }
                } else { [double]::TryParse($fpsRaw, [ref]$fps) | Out-Null }
            }
            # Проверка наличия аудио
            $hasAudio = $false
            foreach ($s in $json.streams) {
                if ($s.codec_type -eq "audio") { $hasAudio = $true; break }
            }
            return @{ Bitrate = $bitrate; Width = $width; Height = $height; FPS = $fps; HasAudio = $hasAudio }
        } catch { return $null }
    }

    # Определение разрешения (по меньшей стороне)
    function Get-ResolutionCategory {
        param([int]$Width, [int]$Height)
        $pixels = if ($Width -ge $Height) { $Height } else { $Width }
        if ($pixels -ge 2160) { return "2160p" }
        elseif ($pixels -ge 1440) { return "1440p" }
        elseif ($pixels -ge 1080) { return "1080p" }
        elseif ($pixels -ge 720) { return "720p" }
        elseif ($pixels -ge 480) { return "480p" }
        elseif ($pixels -ge 360) { return "360p" }
        elseif ($pixels -ge 240) { return "240p" }
        else { return "SD" }
    }

    # Соотношение сторон
    function Get-AspectRatioCategory {
        param([int]$Width, [int]$Height)
        $ratio = $Width / $Height
        if ($Width -ge $Height) {
            if ([math]::Abs($ratio - 16.0/9.0) -le 0.02) { return "16x9" }
            elseif ([math]::Abs($ratio - 4.0/3.0) -le 0.02) { return "4x3" }
            elseif ([math]::Abs($ratio - 21.0/9.0) -le 0.02) { return "21x9" }
            else { return "other" }
        } else {
            $ratioInv = $Height / $Width
            if ([math]::Abs($ratioInv - 16.0/9.0) -le 0.02) { return "9x16" }
            elseif ([math]::Abs($ratioInv - 4.0/3.0) -le 0.02) { return "3x4" }
            else { return "other_vertical" }
        }
    }

    # Категория FPS
    function Get-FpsCategory {
        param([double]$Fps)
        if ($Fps -le 0) { return "unknown" }
        $standard = @(24, 25, 30, 48, 50, 60, 120, 240)
        $nearest = $standard | Sort-Object { [math]::Abs($_ - $Fps) } | Select-Object -First 1
        if ([math]::Abs($nearest - $Fps) -le 0.5) { return "$nearest" + "fps" }
        return ([math]::Round($Fps, 0)) + "fps"
    }

    function Convert-AspectToFolderName {
        param([string]$Aspect)
        switch ($Aspect) {
            "16x9" { return "16-9" }
            "4x3"  { return "4-3" }
            "21x9" { return "21-9" }
            "9x16" { return "9-16" }
            "3x4"  { return "3-4" }
            default { return $Aspect }
        }
    }

    function Get-DestinationFolderName {
        param([string]$Mode, [string]$AspectRaw, [string]$Resolution, [string]$FpsCat)
        if ($Mode -eq "FPSonly") {
            return $FpsCat
        } else {
            $aspectName = Convert-AspectToFolderName -Aspect $AspectRaw
            return "${aspectName}_${Resolution}_${FpsCat}"
        }
    }

    # Обработка дубликатов
    $script:usedNames = @{}
    $duplicatePolicy = "AutoRename"

    function Get-DestinationPathWithDuplicates {
        param(
            [string]$TargetFolder,
            [string]$BaseName,
            [string]$Extension,
            [string]$Policy,
            [object]$SourceFileForAsk,
            [string]$ActionType
        )
        $folderKey = $TargetFolder.ToLower()
        if (-not $script:usedNames.ContainsKey($folderKey)) {
            $script:usedNames[$folderKey] = @{}
        }
        $usedInFolder = $script:usedNames[$folderKey]
        
        $destExtension = if ($ActionType -eq "Shortcut") { ".lnk" } else { $Extension }
        $candidate = Join-Path $TargetFolder ($BaseName + $destExtension)
        
        if ((-not (Test-Path -LiteralPath $candidate)) -and (-not $usedInFolder.ContainsKey($BaseName))) {
            $usedInFolder[$BaseName] = $true
            return $candidate
        }
        
        Write-Host "`n⚠️ КОНФЛИКТ: файл '$BaseName$destExtension' уже существует или будет скопирован в папку:" -ForegroundColor $colWarn
        Write-Host "   $TargetFolder" -ForegroundColor $colWarn
        Write-Host "   Исходный файл: $($SourceFileForAsk.Name)" -ForegroundColor $colWarn
        
        if ($Policy -eq "Skip") {
            Write-Host "   ➤ Политика 'Пропускать': файл не будет обработан." -ForegroundColor $colWarn
            return $null
        }
        elseif ($Policy -eq "AutoRename") {
            $i = 1
            do {
                $newBase = $BaseName + "_$i"
                $candidate = Join-Path $TargetFolder ($newBase + $destExtension)
                $i++
            } while ((Test-Path -LiteralPath $candidate) -or $usedInFolder.ContainsKey($newBase))
            $usedInFolder[$newBase] = $true
            Write-Host "   ➤ Автоматическое переименование: '$newBase$destExtension'" -ForegroundColor $colSuccess
            return $candidate
        }
        elseif ($Policy -eq "Ask") {
            do {
                $answer = Read-Host "   Переименовать (R), Пропустить (S) ? [R/S]"
                if ($answer -eq 'R' -or $answer -eq 'r') {
                    $i = 1
                    do {
                        $newBase = $BaseName + "_$i"
                        $candidate = Join-Path $TargetFolder ($newBase + $destExtension)
                        $i++
                    } while ((Test-Path -LiteralPath $candidate) -or $usedInFolder.ContainsKey($newBase))
                    $usedInFolder[$newBase] = $true
                    Write-Host "   ➤ Переименован: '$newBase$destExtension'" -ForegroundColor $colSuccess
                    return $candidate
                } elseif ($answer -eq 'S' -or $answer -eq 's') {
                    Write-Host "   ➤ Файл пропущен." -ForegroundColor $colWarn
                    return $null
                } else {
                    Write-Host "   Неверный ввод. Введите R (переименовать) или S (пропустить)." -ForegroundColor $colError
                }
            } while ($true)
        }
        return $null
    }

    # ----- ВЫБОР РЕЖИМА СОРТИРОВКИ -----
    Write-Host "`n=== КЛАССИФИКАЦИЯ ВИДЕО ($ActionType) ===" -ForegroundColor $colInfo
    Write-Host "Выберите режим сортировки:" -ForegroundColor $colWarn
    Write-Host "  1 - Полная сортировка (16-9_2160p_25fps и т.п.)"
    Write-Host "  2 - Только по FPS (25fps, 30fps, ...)"
    $modeChoice = Read-Host "Ваш выбор (1 или 2)"
    while ($modeChoice -ne "1" -and $modeChoice -ne "2") {
        Write-Host "Ошибка: введите 1 или 2" -ForegroundColor $colError
        $modeChoice = Read-Host "Ваш выбор"
    }
    $sortMode = if ($modeChoice -eq "1") { "Full" } else { "FPSonly" }
    $modeDesc = if ($sortMode -eq "Full") { "Полная сортировка (aspect_resolution_fps)" } else { "Только по FPS" }
    Write-Host "Выбран режим: $modeDesc" -ForegroundColor $colSuccess

    # ----- СТРАТЕГИЯ ДУБЛИКАТОВ -----
    Write-Host "`nВыберите стратегию обработки дубликатов (файлы с одинаковыми именами в одной папке):" -ForegroundColor $colWarn
    Write-Host "  1 - Автоматически переименовывать (добавлять _1, _2 ...)"
    Write-Host "  2 - Пропускать (обработать только первый файл)"
    Write-Host "  3 - Спрашивать для каждого конфликта"
    $dupChoice = Read-Host "Ваш выбор (1, 2 или 3)"
    while ($dupChoice -ne "1" -and $dupChoice -ne "2" -and $dupChoice -ne "3") {
        Write-Host "Ошибка: введите 1, 2 или 3" -ForegroundColor $colError
        $dupChoice = Read-Host "Ваш выбор"
    }
    switch ($dupChoice) {
        "1" { $duplicatePolicy = "AutoRename"; $policyDesc = "автоматическое переименование" }
        "2" { $duplicatePolicy = "Skip"; $policyDesc = "пропуск дубликатов" }
        "3" { $duplicatePolicy = "Ask"; $policyDesc = "ручной выбор для каждого" }
    }
    Write-Host "Выбрана стратегия: $policyDesc" -ForegroundColor $colSuccess

    # ----- ОСНОВНОЙ БЛОК -----
    Write-Host "`nИсточник видео: $SourceFolder"
    Write-Host "Корневая папка для обработки: $fullOutputRoot" -ForegroundColor $colInfo
    if ($MinBitrateKbps -gt 0) { Write-Host "Минимальный битрейт: $MinBitrateKbps кбит/с" -ForegroundColor $colWarn }
    else { Write-Host "Фильтр по битрейту: отключён" }
    
    # Отображение дополнительных фильтров
    Write-Host "Дополнительные фильтры:" -ForegroundColor $colInfo
    if ($Filters.fpsList.Count -gt 0) { Write-Host "  - FPS: $($Filters.fpsList -join ', ')" -ForegroundColor $colWarn }
    else { Write-Host "  - FPS: без фильтра" }
    if ($Filters.resList.Count -gt 0) { Write-Host "  - Разрешение: $($Filters.resList -join ', ')" -ForegroundColor $colWarn }
    else { Write-Host "  - Разрешение: без фильтра" }
    if ($Filters.arList.Count -gt 0) { Write-Host "  - Соотношение сторон: $($Filters.arList -join ', ')" -ForegroundColor $colWarn }
    else { Write-Host "  - Соотношение сторон: без фильтра" }
    if ($Filters.requireAudio -eq $true) { Write-Host "  - Наличие звука: только видео со звуком" -ForegroundColor $colWarn }
    elseif ($Filters.requireAudio -eq $false) { Write-Host "  - Наличие звука: только видео без звука" -ForegroundColor $colWarn }
    else { Write-Host "  - Наличие звука: без фильтра" }

    $videoFiles = Get-ChildItem -Path $SourceFolder -Include $videoExtensions -Recurse -File -ErrorAction SilentlyContinue
    $total = $videoFiles.Count
    if ($total -eq 0) {
        Write-Host "Видеофайлы не найдены." -ForegroundColor $colError
        Read-Host "Нажмите Enter для выхода"
        return
    }
    Write-Host "Найдено видеофайлов: $total" -ForegroundColor $colInfo

    # ----- ПЕРВЫЙ ПРОХОД: анализ, фильтрация -----
    Write-Host "`nАнализ файлов и фильтрация...`n" -ForegroundColor $colInfo
    $selectedItems = @()
    $totalSizeBytes = 0
    $processed = 0
    $skippedBitrate = 0
    $skippedNoInfo = 0
    $skippedFilters = 0

    foreach ($file in $videoFiles) {
        $processed++
        $percent = [math]::Round(($processed / $total) * 100)
        Write-Progress -Activity "Анализ видео" -Status "$processed из $total ($percent%)" -PercentComplete $percent -CurrentOperation $file.Name

        $info = Get-VideoInfo -FilePath $file.FullName
        if (-not $info -or $info.Width -eq 0 -or $info.Height -eq 0) {
            Write-Host "  [ПРОПУСК] $($file.Name) - не удалось прочитать параметры" -ForegroundColor $colWarn
            $skippedNoInfo++
            continue
        }

        # Фильтр по битрейту
        if ($MinBitrateKbps -gt 0 -and $info.Bitrate -lt ($MinBitrateKbps * 1000)) {
            $bitrateKbps = [math]::Round($info.Bitrate / 1000, 0)
            Write-Host "  [ПРОПУСК] $($file.Name) - битрейт $bitrateKbps кбит/с < $MinBitrateKbps" -ForegroundColor $colWarn
            $skippedBitrate++
            continue
        }

        # Получение категорий для фильтрации
        $resolutionCat = Get-ResolutionCategory -Width $info.Width -Height $info.Height
        $aspectCat = Get-AspectRatioCategory -Width $info.Width -Height $info.Height
        $fpsCatRaw = Get-FpsCategory -Fps $info.FPS  # Например "30fps", "25fps"

        # Дополнительные фильтры (если заданы)
        $filterPass = $true
        # Фильтр по FPS (список разрешённых категорий)
        if ($Filters.fpsList.Count -gt 0) {
            if ($fpsCatRaw -notin $Filters.fpsList) { $filterPass = $false }
        }
        # Фильтр по разрешению
        if ($filterPass -and $Filters.resList.Count -gt 0) {
            if ($resolutionCat -notin $Filters.resList) { $filterPass = $false }
        }
        # Фильтр по соотношению сторон
        if ($filterPass -and $Filters.arList.Count -gt 0) {
            if ($aspectCat -notin $Filters.arList) { $filterPass = $false }
        }
        # Фильтр по наличию аудио
        if ($filterPass -and $null -ne $Filters.requireAudio) {
            if ($Filters.requireAudio -eq $true -and -not $info.HasAudio) { $filterPass = $false }
            if ($Filters.requireAudio -eq $false -and $info.HasAudio) { $filterPass = $false }
        }

        if (-not $filterPass) {
            Write-Host "  [ПРОПУСК] $($file.Name) - не проходит дополнительные фильтры" -ForegroundColor $colWarn
            $skippedFilters++
            continue
        }

        # Файл прошёл все фильтры
        $destFolderName = Get-DestinationFolderName -Mode $sortMode -AspectRaw $aspectCat -Resolution $resolutionCat -FpsCat $fpsCatRaw
        $destDir = Join-Path $fullOutputRoot $destFolderName

        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $extension = [System.IO.Path]::GetExtension($file.Name)
        
        $fileSize = $file.Length
        $totalSizeBytes += $fileSize
        $bitrateKbps = [math]::Round($info.Bitrate / 1000, 0)

        $selectedItems += [PSCustomObject]@{
            Source       = $file.FullName
            DestFolder   = $destDir
            BaseName     = $baseName
            Extension    = $extension
            SizeBytes    = $fileSize
            Name         = $file.Name
            CategoryName = $destFolderName
            Bitrate      = $bitrateKbps
        }

        Write-Host "  [ВКЛЮЧЁН] $($file.Name) -> $destFolderName | $( [math]::Round($fileSize/1MB, 2) ) MB, битрейт ${bitrateKbps}kbps" -ForegroundColor $colSuccess
    }

    Write-Progress -Activity "Анализ видео" -Completed

    $selectedCount = $selectedItems.Count
    $totalSizeGB = $totalSizeBytes / 1GB

    Write-Host "`n=== РЕЗУЛЬТАТЫ АНАЛИЗА ===" -ForegroundColor $colInfo
    Write-Host "Всего обработано:            $processed"
    Write-Host "Отобрано для обработки:      $selectedCount"
    Write-Host "Пропущено по битрейту:       $skippedBitrate"
    Write-Host "Пропущено по доп. фильтрам:  $skippedFilters"
    Write-Host "Не удалось прочитать:        $skippedNoInfo"
    Write-Host "ОБЩИЙ ОБЪЁМ ОТОБРАННЫХ ВИДЕО: $([math]::Round($totalSizeGB, 2)) ГБ" -ForegroundColor $colWarn

    if ($selectedCount -eq 0) {
        Write-Host "Нет видео, соответствующих критериям. Выход." -ForegroundColor $colError
        Read-Host "Нажмите Enter для выхода"
        return
    }

    # ----- ПОДТВЕРЖДЕНИЕ -----
    $actionVerb = if ($ActionType -eq "Copy") { "Копирование" } elseif ($ActionType -eq "Move") { "Перемещение" } else { "Создание ярлыков" }
    do {
        $confirm = Read-Host "`nВыполнить $actionVerb для отобранных файлов? (Y/N)"
        if ($confirm -eq 'Y' -or $confirm -eq 'y') { $proceed = $true; break }
        elseif ($confirm -eq 'N' -or $confirm -eq 'n') { Write-Host "Операция отменена." -ForegroundColor $colWarn; Read-Host "Нажмите Enter для выхода"; return }
        else { Write-Host "Пожалуйста, введите Y или N." -ForegroundColor $colError }
    } while ($true)

    # ----- ВТОРОЙ ПРОХОД: выполнение -----
    Write-Host "`n=== НАЧАЛО $actionVerb ===" -ForegroundColor $colInfo
    $successCount = 0
    $errors = 0
    $skippedDuplicates = 0
    $current = 0

    $script:usedNames = @{}
    $script:duplicatePolicy = $duplicatePolicy

    foreach ($item in $selectedItems) {
        $current++
        $percent = [math]::Round(($current / $selectedCount) * 100)
        Write-Progress -Activity "Обработка видео" -Status "$current из $selectedCount ($percent%)" -PercentComplete $percent -CurrentOperation $item.Name

        if (-not (Test-Path -LiteralPath $item.DestFolder)) {
            New-Item -ItemType Directory -Path $item.DestFolder -Force | Out-Null
        }

        $destPath = Get-DestinationPathWithDuplicates -TargetFolder $item.DestFolder -BaseName $item.BaseName -Extension $item.Extension -Policy $duplicatePolicy -SourceFileForAsk $item -ActionType $ActionType
        
        if (-not $destPath) {
            $skippedDuplicates++
            Write-Host "[$current/$selectedCount] ПРОПУЩЕН (дубликат): $($item.Name)" -ForegroundColor $colWarn
            continue
        }

        try {
            if ($ActionType -eq "Copy") {
                Copy-Item -Path $item.Source -Destination $destPath -Force -ErrorAction Stop
            } elseif ($ActionType -eq "Move") {
                Move-Item -Path $item.Source -Destination $destPath -Force -ErrorAction Stop
            } else { # Shortcut
                $shell = New-Object -ComObject WScript.Shell
                $shortcut = $shell.CreateShortcut($destPath)
                $shortcut.TargetPath = $item.Source
                $shortcut.Save()
            }
            Write-Host "[$current/$selectedCount] $actionVerb выполнен: $($item.Name) -> $destPath" -ForegroundColor $colSuccess
            $successCount++
        } catch {
            Write-Host "[$current/$selectedCount] ОШИБКА при $actionVerb $($item.Name): $_" -ForegroundColor $colError
            $errors++
        }
    }

    Write-Progress -Activity "Обработка видео" -Completed
    Write-Host "`n=== ИТОГО ===" -ForegroundColor $colInfo
    Write-Host "Отобрано файлов:           $selectedCount"
    Write-Host "Успешно $actionVerb :      $successCount"
    Write-Host "Пропущено из-за дубликатов: $skippedDuplicates"
    Write-Host "Ошибок:                    $errors"
    Write-Host "Общий объём обработанных данных: $([math]::Round($totalSizeGB, 2)) ГБ" -ForegroundColor $colSuccess
    Write-Host "Корневая папка: $fullOutputRoot" -ForegroundColor $colInfo

    Read-Host "`nНажмите Enter для продолжения"
}

# ========== 2. ЗАМЕНА НЕСЖАТЫХ ВИДЕО СЖАТЫМИ ==========
function Start-VideoReplacement {
    param(
        [string]$SourceFolder,
        [string]$TargetFolder
    )
    
    $logFile = Join-Path $PSScriptRoot "Replacement.log"
    
    Clear-Host
    Write-Log "══════════════════════════════════════════════════════════════" "Cyan" $logFile
    Write-Log "       ЗАМЕНА НЕСЖАТЫХ ВИДЕО СЖАТЫМИ" "Cyan" $logFile
    Write-Log "══════════════════════════════════════════════════════════════" "Cyan" $logFile

    # Выбор режима (копировать или переместить)
    do {
        Write-Host ""
        Write-Host "Выберите действие:" -ForegroundColor Yellow
        Write-Host "  1 - КОПИРОВАТЬ (сжатый остаётся, несжатый перезаписывается)"
        Write-Host "  2 - ПЕРЕМЕСТИТЬ (сжатый удаляется после замены)"
        $choice = Read-Host "Введите 1 или 2"
        if ($choice -eq "1") {
            $operationMode = "Copy"
            $actionDesc = "КОПИРОВАНИЕ"
            break
        } elseif ($choice -eq "2") {
            $operationMode = "Move"
            $actionDesc = "ПЕРЕМЕЩЕНИЕ"
            break
        } else {
            Write-Host "Ошибка: введите 1 или 2." -ForegroundColor Red
        }
    } while ($true)
    
    Write-Host ""
    Write-Host "ВЫ ВЫБРАЛИ: $actionDesc" -ForegroundColor Cyan
    Write-Host "Источник (сжатые): $SourceFolder"
    Write-Host "Цель (несжатые):   $TargetFolder"
    Write-Host "РЕЖИМ: $operationMode" -ForegroundColor Yellow
    $confirm = Read-Host "`nВы уверены, что хотите выполнить замену? (Y/N)"
    if ($confirm -ne "Y" -and $confirm -ne "y") {
        Write-Host "Операция отменена." -ForegroundColor Red
        Read-Host "Нажмите Enter для выхода"
        return
    }
    
    # Проверка папок
    if (-not (Test-Path $SourceFolder)) { Write-Host "ОШИБКА: Папка с источниками не найдена: $SourceFolder" -ForegroundColor Red; return }
    if (-not (Test-Path $TargetFolder)) { Write-Host "ОШИБКА: Целевая папка не найдена: $TargetFolder" -ForegroundColor Red; return }
    
    Clear-Host
    Write-Log "══════════════════════════════════════════════════════════════" "Cyan" $logFile
    Write-Log "       ЗАМЕНА НЕСЖАТЫХ ВИДЕО СЖАТЫМИ ($operationMode)" "Cyan" $logFile
    Write-Log "══════════════════════════════════════════════════════════════" "Cyan" $logFile
    Write-Log "Источник (сжатые):     $SourceFolder" "White" $logFile
    Write-Log "Цель (несжатые):       $TargetFolder" "White" $logFile
    Write-Log "Режим:                 $operationMode" "White" $logFile
    Write-Log "Лог-файл:              $logFile" "White" $logFile
    Write-Log "══════════════════════════════════════════════════════════════`n" "Cyan" $logFile
    
    # Сканирование сжатых файлов
    Write-Log "🔍 Сканирование сжатых файлов..." "Yellow" $logFile
    $compressedFiles = Get-ChildItem -Path $SourceFolder -Include $videoExtensions -Recurse
    $totalCompressed = $compressedFiles.Count
    Write-Log "✅ Найдено сжатых видеофайлов: $totalCompressed`n" "Green" $logFile
    
    if ($totalCompressed -eq 0) { Write-Log "Нет файлов для обработки. Завершение." "Red" $logFile; Read-Host "Нажмите Enter для выхода"; return }
    
    $processed = 0
    $copied = 0
    $failed = 0
    $notFound = 0
    $totalSizeBytes = 0
    $results = @()
    
    foreach ($compressed in $compressedFiles) {
        $processed++
        $percent = [math]::Round(($processed / $totalCompressed) * 100, 0)
        Write-Progress -Activity "Обработка файлов" -Status "$processed из $totalCompressed ($percent%)" -PercentComplete $percent -CurrentOperation $compressed.Name
        
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($compressed.Name)
        $uncompressed = Get-ChildItem -Path $TargetFolder -Filter "$baseName.*" -Recurse | Select-Object -First 1
        
        if (-not $uncompressed) {
            Write-Log "❌ [НЕ НАЙДЕН] '$($compressed.Name)' → нет соответствия в целевой папке" "DarkYellow" $logFile
            $results += [PSCustomObject]@{
                СжатыйФайл = $compressed.FullName
                ЦелевойФайл = "Не найден"
                Статус = "Пропущен (нет цели)"
                РазмерМБ = 0
            }
            $notFound++
            continue
        }
        
        $action = if ($operationMode -eq "Copy") { "Копирование" } else { "Перемещение" }
        $success = $false
        $errorMsg = ""
        
        try {
            if ($operationMode -eq "Copy") {
                Copy-Item -Path $compressed.FullName -Destination $uncompressed.FullName -Force -ErrorAction Stop
            } else {
                Move-Item -Path $compressed.FullName -Destination $uncompressed.FullName -Force -ErrorAction Stop
            }
            $success = $true
            $copied++
            $totalSizeBytes += $compressed.Length
            $statusColor = "Green"
            $statusText = "УСПЕШНО"
        } catch {
            $success = $false
            $failed++
            $errorMsg = $_.Exception.Message
            $statusColor = "Red"
            $statusText = "ОШИБКА"
        }
        
        $sourceShort = $compressed.FullName.Replace($SourceFolder, "[источник]")
        $targetShort = $uncompressed.FullName.Replace($TargetFolder, "[цель]")
        
        Write-Log "────────────────────────────────────────────────────────" "DarkGray" $logFile
        Write-Log "📹 $($compressed.Name)" "White" $logFile
        Write-Log "   $action из: $sourceShort" "Gray" $logFile
        Write-Log "          в: $targetShort" "Gray" $logFile
        if ($success) {
            Write-Log "   ✅ $statusText" $statusColor $logFile
        } else {
            Write-Log "   ❌ $statusText : $errorMsg" $statusColor $logFile
        }
        
        $results += [PSCustomObject]@{
            СжатыйФайл = $compressed.FullName
            ЦелевойФайл = $uncompressed.FullName
            Статус = if ($success) { "Успешно ($operationMode)" } else { "Ошибка: $errorMsg" }
            РазмерМБ = [math]::Round($compressed.Length / 1MB, 2)
        }
    }
    
    Write-Progress -Activity "Обработка файлов" -Completed
    
    $totalSizeGB = $totalSizeBytes / 1GB
    Write-Log "`n══════════════════════════════════════════════════════════════" "Cyan" $logFile
    Write-Log "                       РЕЗУЛЬТАТЫ" "Cyan" $logFile
    Write-Log "══════════════════════════════════════════════════════════════" "Cyan" $logFile
    Write-Log "📊 СТАТИСТИКА:" "Yellow" $logFile
    Write-Log "   Всего сжатых файлов обработано: $totalCompressed" "White" $logFile
    Write-Log "   ✅ УСПЕШНО ЗАМЕНЕНО:             $copied" -Color Green
    Write-Log "   ❌ ОШИБОК ПРИ ЗАМЕНЕ:            $failed" -Color Red
    Write-Log "   🔍 НЕ НАЙДЕНО ЦЕЛЕЙ:             $notFound" -Color DarkYellow
    Write-Log ""
    if ($copied -gt 0) {
        Write-Log "   💾 Общий объём обработанных данных: $([math]::Round($totalSizeGB, 2)) ГБ ($([math]::Round($totalSizeBytes/1MB,2)) МБ)" -Color Green
    }
    Write-Log "══════════════════════════════════════════════════════════════" "Cyan" $logFile
    
    if ($results.Count -gt 0) {
        Write-Log "`n📋 ПОДРОБНЫЙ СПИСОК (первые 30 записей):" "Yellow" $logFile
        $displayResults = $results | Select-Object -First 30 | ForEach-Object {
            [PSCustomObject]@{
                Файл = Split-Path $_.СжатыйФайл -Leaf
                Цель = if ($_.ЦелевойФайл -ne "Не найден") { Split-Path $_.ЦелевойФайл -Leaf } else { "Не найден" }
                Статус = $_.Статус
                РазмерМБ = "$($_.РазмерМБ) МБ"
            }
        }
        $displayResults | Format-Table -AutoSize | Out-String | Write-Log -LogFile $logFile
        if ($results.Count -gt 30) {
            Write-Log "... и еще $($results.Count - 30) записей (см. полный лог-файл)" "DarkGray" $logFile
        }
    }
    
    Write-Log "`n📄 Полный лог сохранён в: $logFile" "Cyan" $logFile
    Write-Log "══════════════════════════════════════════════════════════════" "Cyan" $logFile
    
    Write-Host "`n✅ Работа завершена. Нажмите Enter для продолжения..." -ForegroundColor Cyan
    $null = Read-Host
}

# ========== ГЛАВНОЕ МЕНЮ ==========
Clear-Host
Write-Host "══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "                 УНИВЕРСАЛЬНЫЙ СКРИПТ ДЛЯ ВИДЕО" -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "Выберите режим работы:" -ForegroundColor Yellow
Write-Host "  1 - Классификация видео (сортировка по параметрам)"
Write-Host "  2 - Замена несжатых видео сжатыми (по имени)"
Write-Host "  0 - Выход"
$mainChoice = Read-Host "Ваш выбор"

if ($mainChoice -eq "0") {
    Write-Host "Выход." -ForegroundColor Magenta
    exit
} elseif ($mainChoice -eq "1") {
    # ----- РЕЖИМ КЛАССИФИКАЦИИ -----
    Clear-Host
    Write-Host "=== КЛАССИФИКАЦИЯ ВИДЕО ===" -ForegroundColor Cyan
    
    # Ввод исходной папки
    $defaultSource = (Get-Location).Path
    $srcInput = Read-Host "Введите путь к папке с видео (Enter = $defaultSource)"
    $SourceFolder = if ($srcInput -eq "") { $defaultSource } else { $srcInput }
    if (-not (Test-Path $SourceFolder)) {
        Write-Host "ОШИБКА: Папка не существует!" -ForegroundColor Red
        Read-Host "Нажмите Enter для выхода"
        exit
    }
    
    # Ввод папки для сортировки
    $defaultOutput = (Get-Location).Path
    $outInput = Read-Host "Введите целевую папку для сортировки (Enter = $defaultOutput)"
    $OutputFolder = if ($outInput -eq "") { $defaultOutput } else { $outInput }
    if (-not (Test-Path $OutputFolder)) {
        Write-Host "Папка не существует. Будет создана." -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    }
    
    # Ввод пути к ffprobe
    $defaultFfprobe = "C:\ffmpeg\bin\ffprobe.exe"
    $ffInput = Read-Host "Введите путь к ffprobe.exe (Enter = $defaultFfprobe)"
    $FfprobePath = if ($ffInput -eq "") { $defaultFfprobe } else { $ffInput }
    if (-not (Test-Path $FfprobePath)) {
        Write-Host "ОШИБКА: ffprobe.exe не найден!" -ForegroundColor Red
        Read-Host "Нажмите Enter для выхода"
        exit
    }
    
    # Ввод минимального битрейта
    $bitrateInput = Read-Host "Введите минимальный битрейт (кбит/с) [Enter = 20000]"
    if ($bitrateInput -match '^\d+$') {
        $MinBitrateKbps = [int]$bitrateInput
    } elseif ($bitrateInput -eq "") {
        $MinBitrateKbps = 20000
    } else {
        Write-Host "Неверный ввод, оставлено значение по умолчанию 20000 кбит/с" -ForegroundColor Yellow
        $MinBitrateKbps = 20000
    }
    
    # --- Настройка дополнительных фильтров ---
    $filters = @{ fpsList = @(); resList = @(); arList = @(); requireAudio = $null }
    Write-Host "`n=== НАСТРОЙКА ДОПОЛНИТЕЛЬНЫХ ФИЛЬТРОВ ===" -ForegroundColor Cyan
    Write-Host "Вы можете ограничить выборку по FPS, разрешению, соотношению сторон и наличию звука."
    Write-Host "По умолчанию все фильтры отключены (не ограничивают)." -ForegroundColor Yellow
    
    # Фильтр по FPS
    $fpsChoice = Read-Host "`nПрименить фильтр по FPS? (Y/N) [N]"
    if ($fpsChoice -eq 'Y' -or $fpsChoice -eq 'y') {
        Write-Host "Доступные значения FPS: 24, 25, 30, 48, 50, 60, 120, 240" -ForegroundColor Green
        Write-Host "Введите нужные через запятую (например: 24,30,60). Для завершения введите пустую строку."
        while ($true) {
            $val = Read-Host "> "
            if ($val -eq "") { break }
            $vals = $val -split ',' | ForEach-Object { $_.Trim() }
            foreach ($v in $vals) {
                if ($v -match '^\d+$') { $filters.fpsList += "$($v)fps" }
                else { Write-Host "Неверный формат: $v. Пропущено." -ForegroundColor Red }
            }
            Write-Host "Текущий список: $($filters.fpsList -join ', ')" -ForegroundColor Cyan
        }
    }
    
    # Фильтр по разрешению
    $resChoice = Read-Host "`nПрименить фильтр по разрешению? (Y/N) [N]"
    if ($resChoice -eq 'Y' -or $resChoice -eq 'y') {
        Write-Host "Доступные разрешения: 2160p, 1440p, 1080p, 720p, 480p, 360p, 240p, SD" -ForegroundColor Green
        Write-Host "Введите нужные через запятую (например: 1080p,720p)."
        while ($true) {
            $val = Read-Host "> "
            if ($val -eq "") { break }
            $vals = $val -split ',' | ForEach-Object { $_.Trim() }
            foreach ($v in $vals) {
                if ($v -match '^(2160p|1440p|1080p|720p|480p|360p|240p|SD)$') { $filters.resList += $v }
                else { Write-Host "Неверный формат: $v. Пропущено." -ForegroundColor Red }
            }
            Write-Host "Текущий список: $($filters.resList -join ', ')" -ForegroundColor Cyan
        }
    }
    
    # Фильтр по соотношению сторон
    $arChoice = Read-Host "`nПрименить фильтр по соотношению сторон? (Y/N) [N]"
    if ($arChoice -eq 'Y' -or $arChoice -eq 'y') {
        Write-Host "Доступные соотношения: 16x9, 9x16, 4x3, 3x4, 21x9, other, other_vertical" -ForegroundColor Green
        Write-Host "Введите нужные через запятую (например: 16x9,9x16)."
        while ($true) {
            $val = Read-Host "> "
            if ($val -eq "") { break }
            $vals = $val -split ',' | ForEach-Object { $_.Trim() }
            foreach ($v in $vals) {
                if ($v -match '^(16x9|9x16|4x3|3x4|21x9|other|other_vertical)$') { $filters.arList += $v }
                else { Write-Host "Неверный формат: $v. Пропущено." -ForegroundColor Red }
            }
            Write-Host "Текущий список: $($filters.arList -join ', ')" -ForegroundColor Cyan
        }
    }
    
    # Фильтр по наличию звука
    $audioChoice = Read-Host "`nПрименить фильтр по наличию звука? (Y/N) [N]"
    if ($audioChoice -eq 'Y' -or $audioChoice -eq 'y') {
        Write-Host "  1 - Только видео со звуком"
        Write-Host "  2 - Только видео без звука"
        $audOpt = Read-Host "Ваш выбор (1 или 2)"
        if ($audOpt -eq "1") { $filters.requireAudio = $true }
        elseif ($audOpt -eq "2") { $filters.requireAudio = $false }
        else { Write-Host "Неверный выбор, фильтр по звуку отключён." -ForegroundColor Red }
    }
    
    # Выбор действия
    Write-Host "`nВыберите действие с файлами:" -ForegroundColor Yellow
    Write-Host "  1 - Копировать (исходные файлы остаются)"
    Write-Host "  2 - Переместить (исходные файлы удаляются)"
    Write-Host "  3 - Создать ярлыки (ссылки на исходные файлы)"
    $actChoice = Read-Host "Ваш выбор (1,2,3)"
    while ($actChoice -ne "1" -and $actChoice -ne "2" -and $actChoice -ne "3") {
        Write-Host "Ошибка: введите 1, 2 или 3" -ForegroundColor Red
        $actChoice = Read-Host "Ваш выбор"
    }
    $ActionType = switch ($actChoice) {
        "1" { "Copy" }
        "2" { "Move" }
        "3" { "Shortcut" }
    }
    
    Start-VideoClassification -SourceFolder $SourceFolder -OutputRoot $OutputFolder -FfprobePath $FfprobePath -MinBitrateKbps $MinBitrateKbps -ActionType $ActionType -Filters $filters
    
} elseif ($mainChoice -eq "2") {
    # ----- РЕЖИМ ЗАМЕНЫ -----
    Clear-Host
    Write-Host "=== ЗАМЕНА НЕСЖАТЫХ ВИДЕО СЖАТЫМИ ===" -ForegroundColor Cyan
    
    # Папка со сжатыми – по умолчанию подпапка "Сжатые" в папке скрипта
    $defaultSource = Join-Path $PSScriptRoot "Сжатые"
    $srcInput = Read-Host "Введите путь к папке со сжатыми видео (Enter = $defaultSource)"
    $sourceFolder = if ($srcInput -eq "") { $defaultSource } else { $srcInput }
    if (-not (Test-Path $sourceFolder)) {
        Write-Host "ОШИБКА: Папка не существует! Будет создана?" -ForegroundColor Red
        $create = Read-Host "Создать папку? (Y/N)"
        if ($create -eq 'Y' -or $create -eq 'y') { New-Item -ItemType Directory -Path $sourceFolder -Force | Out-Null }
        else { Write-Host "Операция отменена."; Read-Host "Нажмите Enter"; exit }
    }
    
    # Папка с несжатыми – по умолчанию подпапка "Несжатые" в папке скрипта
    $defaultTarget = Join-Path $PSScriptRoot "Несжатые"
    $tgtInput = Read-Host "Введите путь к папке с несжатыми видео (Enter = $defaultTarget)"
    $targetFolder = if ($tgtInput -eq "") { $defaultTarget } else { $tgtInput }
    if (-not (Test-Path $targetFolder)) {
        Write-Host "ОШИБКА: Папка не существует! Будет создана?" -ForegroundColor Red
        $create = Read-Host "Создать папку? (Y/N)"
        if ($create -eq 'Y' -or $create -eq 'y') { New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null }
        else { Write-Host "Операция отменена."; Read-Host "Нажмите Enter"; exit }
    }
    
    Start-VideoReplacement -SourceFolder $sourceFolder -TargetFolder $targetFolder
    
} else {
    Write-Host "Неверный выбор. Выход." -ForegroundColor Red
    Read-Host "Нажмите Enter"
    exit
}
