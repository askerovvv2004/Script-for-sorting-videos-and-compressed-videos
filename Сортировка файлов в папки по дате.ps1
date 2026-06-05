# =================================================================
# Сортировка файлов (фото, видео) по датам с возможностью группировки
# по годам, месяцам, дням или произвольному формату.
# =================================================================

# ---------------------- НАСТРОЙКИ (можно изменить) ----------------------
# Вопросы перед началом работы ($true - задать вопрос, $false - использовать значения по умолчанию)
$questionReName           = $true   # Переименовывать файлы?
$questionReNameDateOrPostfix = $true   # Добавлять дату или префикс?
$questionReNameAll        = $true   # Переименовывать полностью или добавить дату в начало?
$questionCopyOrRemove     = $true   # Копировать или перемещать?
$questionFolderFormat     = $true   # Запрашивать формат группировки папок (годы, месяцы, дни)

# Типы файлов, которые обрабатываются (добавлены видеоформаты)
$typeFiles = "*.jpg", "*.jpeg", "*.gif", "*.bmp", "*.png",
             "*.avi", "*.AVI", "*.mp4", "*.mkv", "*.mov", "*.wmv", "*.flv", "*.m4v"

# Формат создания папок по умолчанию (будет изменён, если включены вопросы)
$formatFolders   = "yyyy.MM"        # ГГГГ.ММ
$formatDateToName = "yyyy.MM.dd"    # Формат даты в имени файла (при переименовании)

# Настройки переименования (используются, если вопросы отключены)
$ReName               = $true       # Переименовывать файлы
$ReNameDateOrPostfix  = $true       # Добавлять дату (true) или префикс (false)
$ReNameAll            = $false      # true – полностью заменить имя на дату, false – добавить дату в начало
$ReNamePostfixNum     = $true       # Добавлять числовой постфикс при конфликте имён

# Копирование (true) или перемещение (false)
$CopyOrRemove = $true

# ---------------------------------------------------------------------
# Добавление сборки для работы с изображениями
Add-Type -AssemblyName System.Drawing

# ---------------------------------------------------------------------
# Функция: проверка, является ли файл изображением (по расширению)
function IsImageFile {
    param([string]$path)
    $imageExtensions = @(".jpg", ".jpeg", ".gif", ".bmp", ".png", ".tiff")
    $ext = [System.IO.Path]::GetExtension($path).ToLower()
    return $imageExtensions -contains $ext
}

# ---------------------------------------------------------------------
# Функция: формирование пути к папке (и создание, если её нет)
function Get-FolderPath {
    param(
        [int]$id,
        [string]$fileName,
        $selectDate,
        [array]$folgerCreatesPath
    )

    switch ($id) {
        { $_ -ge 1 -and $_ -le 3 } {
            $folderName = $selectDate.ToString($formatFolders)
            $dateString = $selectDate.ToString($formatDateToName)
        }
        4 {
            if ($selectDate -eq $null) {
                $folderName = "_файлы без даты съемки"
                $dateString = ""
            } else {
                $folderName = [datetime]::ParseExact($selectDate, "yyyy:MM:dd H:m:s`0", $null).ToString($formatFolders)
                $dateString = [datetime]::ParseExact($selectDate, "yyyy:MM:dd H:m:s`0", $null).ToString($formatDateToName)
            }
        }
        5 {
            if ([string]::IsNullOrEmpty($selectDate)) {
                $folderName = "_файлы без даты создания мультимедиа"
                $dateString = ""
            } else {
                $selectDate = $selectDate.Replace("$([char]8206)", "").Replace("$([char]8207)", "")
                $folderName = [datetime]::ParseExact($selectDate, "dd.MM.yyyy H:m", $null).ToString($formatFolders)
                $dateString = [datetime]::ParseExact($selectDate, "dd.MM.yyyy H:m", $null).ToString($formatDateToName)
            }
        }
    }

    $newFolderPath = Join-Path -Path $pathBase -ChildPath $folderName
    if (-not (Test-Path $newFolderPath)) {
        New-Item -Path $newFolderPath -ItemType Directory | Out-Null
        $folgerCreatesPath += $newFolderPath
    }
    return $newFolderPath, $folgerCreatesPath, $dateString
}

# ---------------------------------------------------------------------
# Функция: генерация имени файла с числовым постфиксом (если нужно)
function Get-NewNameWithPostfix {
    param(
        [string]$newNameFileTemplate,
        [string]$template,
        [string]$newFolderPath
    )
    $postfix = 1
    do {
        if ($postfix -eq 1) {
            $newPathFile = Join-Path -Path $newFolderPath -ChildPath $newNameFileTemplate.Replace($template, "_")
        } else {
            $newNameFile = $newNameFileTemplate.Replace(":", $postfix)
            $newPathFile = Join-Path -Path $newFolderPath -ChildPath $newNameFile
        }
        $exists = Test-Path $newPathFile
        $postfix++
    } while ($exists -eq $true)   # цикл, пока файл существует
    return $newPathFile
}

# ---------------------------------------------------------------------
# Функция: копирование / перемещение файла с учётом переименования
function Action-File {
    param(
        [boolean]$ReName,
        [boolean]$ReNameDateOrPostfix,
        [boolean]$ReNameAll,
        [boolean]$ReNamePostfixNum,
        [string]$filePath,
        [string]$newFolderPath,
        [string]$NameFile,
        [string]$dateString,
        [array]$filesDuplicatesPath
    )

    if ($ReName) {
        if ($ReNameDateOrPostfix) {
            # Переименование на основе даты
            if ($ReNameAll) {
                # Полная замена имени файла на дату
                if ($ReNamePostfixNum) {
                    $extension = [System.IO.Path]::GetExtension($filePath)
                    $template = '-'+':'
                    $newNameFileTemplate = $dateString + $template + $extension
                    $newPathFile = Get-NewNameWithPostfix -newNameFileTemplate $newNameFileTemplate -template $template -newFolderPath $newFolderPath
                } else {
                    $newPathFile = Join-Path -Path $newFolderPath -ChildPath $dateString
                }
            } else {
                # Добавление даты в начало имени
                if ($ReNamePostfixNum) {
                    $template = '-'+':'+'_'
                    $newNameFileTemplate = $dateString + $template + $NameFile
                    $newPathFile = Get-NewNameWithPostfix -newNameFileTemplate $newNameFileTemplate -template $template -newFolderPath $newFolderPath
                } else {
                    $newPathFile = Join-Path -Path $newFolderPath -ChildPath ($dateString + "_" + $NameFile)
                }
            }
        } else {
            # Добавление постфикса к старому имени
            $template = '-'+':'
            $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($NameFile)
            $extension = [System.IO.Path]::GetExtension($NameFile)
            $newNameFileTemplate = $nameWithoutExt + $template + $extension
            $newPathFile = Get-NewNameWithPostfix -newNameFileTemplate $newNameFileTemplate -template $template -newFolderPath $newFolderPath
        }
    } else {
        $newPathFile = Join-Path -Path $newFolderPath -ChildPath $NameFile
    }

    if (Test-Path $newPathFile) {
        # Файл с таким именем уже существует – запоминаем как дубликат
        $filesDuplicatesPath += [PSCustomObject]@{
            FilePathOld = $filePath
            FilePathNew = $newPathFile
        }
    } else {
        if ($CopyOrRemove) {
            Copy-Item -LiteralPath $filePath -Destination $newPathFile
        } else {
            Move-Item -LiteralPath $filePath -Destination $newPathFile
        }
    }
    return $filesDuplicatesPath
}

# ---------------------- НАЧАЛО СКРИПТА ------------------------------
Write-Host @"

************************************************************
************************************************************
************************************************************
Макрос сортировки файлов в папки по одному из свойств:
  "создан", "изменен", "открыт", "дата съемки" или "дата создания мультимедиа".
Макрос ищет файлы с расширениями: $typeFiles
в папке, где находится скрипт, и во всех подпапках,
и копирует (или перемещает) файлы в новые папки в соответствии с выбранной датой.

Примечание:
Вы можете изменить поведение, отредактировав переменные в начале файла.
$true  - задавать вопрос;
$false - не задавать вопрос (использовать значения по умолчанию).

Настройка дополнительных вопросов:
1) `$questionReName`            - переименование файлов
2) `$questionReNameDateOrPostfix` - дата или префикс
3) `$questionReNameAll`         - полное переименование или добавление даты
4) `$questionCopyOrRemove`      - копирование или перемещение
5) `$questionFolderFormat`      - формат группировки папок (годы, месяцы, дни)

Настройка переменных формата:
- `$typeFiles`      - типы обрабатываемых файлов (можно добавлять любые расширения)
- `$formatFolders`  - формат имен создаваемых папок (по умолчанию "yyyy.MM")
- `$formatDateToName` - формат даты при переименовании файлов
"@

# ---------------------- ВЫБОР СВОЙСТВА ДАТЫ ------------------------
Write-Host @"

Для сортировки в зависимости от свойства введите цифру:
1 - дата создания файла;
2 - дата изменения файла;
3 - дата открытия файла;
4 - дата съемки (только для изображений);
5 - дата создания мультимедиа (рекомендуется для видео).
"@

$id = Read-Host "Ваш выбор"
while (($id -lt 1) -or ($id -gt 5)) {
    $id = Read-Host "Неверный ввод. Введите число от 1 до 5"
}
Write-Host ""

# ---------------------- ВЫБОР ФОРМАТА ПАПОК (группировка) -----------------
if ($questionFolderFormat) {
    Write-Host @"
Выберите формат группировки файлов по папкам:
1 - по годам (ГГГГ)
2 - по месяцам (ГГГГ.ММ)
3 - по дням (ГГГГ.ММ.ДД)
4 - свой формат (например, yyyy-MM-dd)
"@
    $fmtChoice = Read-Host "Введите номер"
    switch ($fmtChoice) {
        "1" { $formatFolders = "yyyy"; $formatDateToName = "yyyy.MM.dd" }  # дата в имени остаётся полной
        "2" { $formatFolders = "yyyy.MM"; $formatDateToName = "yyyy.MM.dd" }
        "3" { $formatFolders = "yyyy.MM.dd"; $formatDateToName = "yyyy.MM.dd" }
        "4" {
            $formatFolders   = Read-Host "Введите формат папок (например, yyyy-MM-dd)"
            $formatDateToName = Read-Host "Введите формат даты для имени файла (например, yyyy.MM.dd)"
        }
        default {
            Write-Host "Неверный выбор. Оставляем текущий формат: $formatFolders"
        }
    }
    Write-Host "Группировка будет выполнена в формате: $formatFolders`n"
}

# ---------------------- ВОПРОСЫ О ПЕРЕИМЕНОВАНИИ ----------------------
if ($questionReName) {
    Write-Host "Переименовывать файлы?"
    Write-Host "0 - нет`n1 - да"
    $answerReName = Read-Host "Ваш выбор"
    while (($answerReName -ne 0) -and ($answerReName -ne 1)) {
        $answerReName = Read-Host "Неверно. Введите 0 или 1"
    }
    $ReName = ($answerReName -eq 1)

    if ($ReName -and $questionReNameDateOrPostfix) {
        Write-Host "Переименовывать на основании даты или добавлять постфикс?"
        Write-Host "0 - на основании даты (формат: $formatDateToName)`n1 - добавлять постфикс в конце файла"
        $answerReNameDateOrPostfix = Read-Host "Ваш выбор"
        while (($answerReNameDateOrPostfix -ne 0) -and ($answerReNameDateOrPostfix -ne 1)) {
            $answerReNameDateOrPostfix = Read-Host "Неверно. Введите 0 или 1"
        }
        $ReNameDateOrPostfix = ($answerReNameDateOrPostfix -eq 0)

        if ($ReNameDateOrPostfix -and $questionReNameAll) {
            Write-Host "Переименовывать файл полностью или добавить дату в начало?"
            Write-Host "0 - полностью заменить имя на дату`n1 - добавить дату перед текущим именем"
            $answerReNameAll = Read-Host "Ваш выбор"
            while (($answerReNameAll -ne 0) -and ($answerReNameAll -ne 1)) {
                $answerReNameAll = Read-Host "Неверно. Введите 0 или 1"
            }
            $ReNameAll = ($answerReNameAll -eq 0)
        }
    }
}

# ---------------------- ВОПРОС О КОПИРОВАНИИ / ПЕРЕМЕЩЕНИИ -------------
if ($questionCopyOrRemove) {
    Write-Host @"
Копировать или перемещать файлы?
Внимание! Перемещение может привести к потере данных при сбое.
0 - копировать (рекомендуется)
1 - перемещать
"@
    $answerCopyOrRemove = Read-Host "Ваш выбор"
    while (($answerCopyOrRemove -ne 0) -and ($answerCopyOrRemove -ne 1)) {
        $answerCopyOrRemove = Read-Host "Неверно. Введите 0 или 1"
    }
    $CopyOrRemove = ($answerCopyOrRemove -eq 0)
}

# ---------------------- ОСНОВНАЯ ОБРАБОТКА ----------------------------
$folgerCreatesPath   = @()      # список созданных папок
$filesDuplicatesPath = @()      # файлы-дубликаты (не скопированы)
$pathsCuttentFolder  = @()      # уже обработанные папки (для вывода)
$pathBase = Split-Path -Parent $MyInvocation.MyCommand.Path

$typeFilesString = $typeFiles -join '|'

# Разделение логики в зависимости от выбранного свойства даты
switch ($id) {
    # Обработка через стандартные свойства файла (1-3) и дату съемки (4) для изображений
    { $_ -ge 1 -and $_ -le 4 } {
        $files = Get-ChildItem -Include $typeFiles -Path $pathBase -Recurse -File
        foreach ($file in $files) {
            $dirCurName = $file.DirectoryName
            if (($pathsCuttentFolder -eq $dirCurName).Count -eq 0) {
                Write-Host -ForegroundColor Magenta "Обрабатываю папку: $dirCurName"
                $pathsCuttentFolder += $dirCurName
            }

            switch ($id) {
                1 { $selectDate = $file.CreationTime }
                2 { $selectDate = $file.LastWriteTime }
                3 { $selectDate = $file.LastAccessTime }
                4 {
                    # Для даты съемки используем только изображения
                    if (IsImageFile $file.FullName) {
                        try {
                            $filePic = New-Object System.Drawing.Bitmap($file.FullName)
                            $propId = $filePic.PropertyIdList
                            if ($propId -contains 36867) {
                                $selectDate = [System.Text.Encoding]::ASCII.GetString($filePic.GetPropertyItem(36867).Value)
                            } else {
                                $selectDate = $null
                            }
                            $filePic.Dispose()
                        } catch {
                            $selectDate = $null
                        }
                    } else {
                        $selectDate = $null   # не изображение – даты съемки нет
                    }
                }
            }

            $tmp = Get-FolderPath -id $id -fileName $file.Name -selectDate $selectDate -folgerCreatesPath $folgerCreatesPath
            $newFolderPath = $tmp[0]
            $folgerCreatesPath = $tmp[1]
            $dateString = $tmp[2]

            $filesDuplicatesPath = @(Action-File -ReName $ReName -ReNameDateOrPostfix $ReNameDateOrPostfix `
                -ReNameAll $ReNameAll -ReNamePostfixNum $ReNamePostfixNum -filePath $file.FullName `
                -newFolderPath $newFolderPath -NameFile $file.Name -dateString $dateString `
                -filesDuplicatesPath $filesDuplicatesPath)
        }
    }
    5 {
        # Использование Shell.Application для получения мультимедийных свойств (в т.ч. видео)
        $allFolders = @($pathBase) + (Get-ChildItem -Path $pathBase -Recurse -Directory).FullName
        foreach ($folder in $allFolders) {
            Write-Host -ForegroundColor Magenta "Обрабатываю папку: $folder"
            $pathsCuttentFolder += $folder

            $objShell = New-Object -ComObject Shell.Application
            $objFolder = $objShell.Namespace($folder)
            foreach ($item in $objFolder.Items()) {
                if (-not $item.IsFolder) {
                    $ext = [System.IO.Path]::GetExtension($item.Path).ToLower()
                    # Проверяем, подходит ли расширение по маске
                    $matched = $false
                    foreach ($mask in $typeFiles) {
                        if ($item.Path -like $mask) { $matched = $true; break }
                    }
                    if ($matched) {
                        $selectDate = $objFolder.GetDetailsOf($item, 197)   # 197 = "Дата создания мультимедиа"
                        $tmp = Get-FolderPath -id $id -selectDate $selectDate -folgerCreatesPath $folgerCreatesPath
                        $newFolderPath = $tmp[0]
                        $folgerCreatesPath = $tmp[1]
                        $dateString = $tmp[2]
                        $filesDuplicatesPath = @(Action-File -ReName $ReName -ReNameDateOrPostfix $ReNameDateOrPostfix `
                            -ReNameAll $ReNameAll -ReNamePostfixNum $ReNamePostfixNum -filePath $item.Path `
                            -newFolderPath $newFolderPath -NameFile $item.Name -dateString $dateString `
                            -filesDuplicatesPath $filesDuplicatesPath)
                    }
                }
            }
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($objShell) | Out-Null
        }
    }
}

# ---------------------- ВЫВОД РЕЗУЛЬТАТОВ ----------------------------
Write-Host "`n"
$folgerCreatesPathCount = $folgerCreatesPath.Count
if ($folgerCreatesPathCount -ge 1) {
    Write-Host -ForegroundColor Green "Таблица созданных папок. Создано папок: $folgerCreatesPathCount"
    Get-ItemProperty -LiteralPath $folgerCreatesPath | Format-Table -AutoSize -Wrap BaseName, FullName
} else {
    Write-Host -ForegroundColor Green "Создано папок: 0"
}

$filesDuplicatesCount = $filesDuplicatesPath.Count
if ($filesDuplicatesCount -ge 1) {
    Write-Host "`n"
    Write-Host -ForegroundColor Red "Файлы, не скопированные из-за конфликта имён в конечной папке. Всего: $filesDuplicatesCount"
    $filesDuplicatesPath | Format-Table -AutoSize FilePathOld, FilePathNew
}

Read-Host -Prompt "Нажмите Enter для выхода"