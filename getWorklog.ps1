# Константы
$WORK_HOURS_PER_DAY = 8
$REPO_PATH = "C:\"  # Укажите здесь путь к вашему репозиторию
$START_DATE = "2000-01-01"  # Укажите здесь начальную дату в формате YYYY-MM-DD
$FILE_NAME = "worklog-$START_DATE"
$TASK_PATTERN = '([A-Z]{3,7}-\d+)' # паттерн названия задачи, пример: TEST-12345
$MESSAGE_MAX_LENGTH = 300 # максимальная длина сгруппированного сообщения с коммитами

# Настройка кодировки
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'

# Переходим в директорию репозитория
Set-Location -Path $REPO_PATH

# Получаем лог git
$log = git log --since=$START_DATE --pretty=format:'%ad||||%h||||%s||||%D' --date=format:'%Y-%m-%d' --numstat --no-merges --encoding=UTF-8

$logLines = $log -split "`n"

$commits = @()
$currentCommit = $null



foreach ($line in $logLines) {
    $line = $line.Trim() 
    
    if ($line -match $TASK_PATTERN) {
        $parts = $line -split '\|\|\|\|'
        if ($parts.Count -ge 3) {
            if ($currentCommit) {
                $commits += $currentCommit
            }
            $currentCommit = [PSCustomObject]@{
                Date       = $parts[0]
                Hash       = $parts[1]
                Message    = $parts[2]
                Refs       = if ($parts.Count -gt 3) { $parts[3] } else { "" }
                TaskNumber = if ($parts[2] -match $TASK_PATTERN) { $matches[1] } else { "No Task" }
                Added      = 0
                Deleted    = 0
            }
        }
        
    }
    elseif ($line -match '^(\d+)\s+(\d+)\s+(.+)$') {
        if ($currentCommit) {
            $currentCommit.Added += [int]$matches[1]
            $currentCommit.Deleted += [int]$matches[2]
        }
       
    }
   
}

if ($currentCommit) {
    $commits += $currentCommit
}

Write-Host "Total commits processed: $($commits.Count)"
if ($commits.Count -gt 0) {
    Write-Host "First commit:"
    $commits[0] | Format-List
    Write-Host "Last commit:"
    $commits[-1] | Format-List
}
else {
    Write-Host "No commits were processed. Check the git log output and date range."
}

$commits | Format-Table Date, Hash, TaskNumber, Added, Deleted, Message -AutoSize



# Группировка и подсчет часов
$results = $commits | Group-Object Date | ForEach-Object {
    $date = $_.Name
    $dayCommits = $_.Group

    $totalChangesForDay = ($dayCommits | Measure-Object -Property Added, Deleted -Sum | Select-Object -ExpandProperty Sum | Measure-Object -Sum).Sum

    $taskGroups = $dayCommits | Group-Object TaskNumber

    $taskGroups | ForEach-Object {
        $taskNumber = $_.Name
        $taskCommits = $_.Group
        $taskChanges = ($taskCommits | Measure-Object -Property Added, Deleted -Sum | Select-Object -ExpandProperty Sum | Measure-Object -Sum).Sum
        $percentage = if ($totalChangesForDay -gt 0) { [math]::Round(($taskChanges / $totalChangesForDay) * 100, 2) } else { 0 }
        $hours = [math]::Round(($percentage / 100) * $WORK_HOURS_PER_DAY, 2)

        
        $commitMessages = $taskCommits.Message -join ";"
        if ($commitMessages.Length -gt $MESSAGE_MAX_LENGTH) {
            $commitMessages = $commitMessages.Substring(0, $MESSAGE_MAX_LENGTH) + "..."  # Обрезаем сообщение коммита до максимальной длины
        }

        # Отладочный вывод TaskNumber
        Write-Host "Task Number: $taskNumber"  # Выводим номер задачи для проверки

        # Создаем объект для каждого коммита
        [PSCustomObject]@{
            Date            = $date
            TaskNumber      = $taskNumber  # Убедитесь, что здесь сохраняется знак #
            Percentage       = "$percentage%"
            Hours            = "$hours hrs"  # Добавление "hrs" к количеству часов
            CommitMessages   = $commitMessages
        }
    }
}

$results = $results | Sort-Object Date, {[double]$_.Percentage.TrimEnd('%')} -Descending

Write-Host "Grouped results:"

# Переменная для хранения предыдущей даты
$previousDate = ""

foreach ($result in $results) {
    # Проверка на изменение даты
    if ($previousDate -ne $result.Date) {
        if ($previousDate -ne "") {
            Write-Host "---------------------------------------"  # Разделитель между днями
        }
        Write-Host "Date: $($result.Date)"  # Вывод даты
        $previousDate = $result.Date
    }
    
    # Форматированный вывод данных без столбца даты
    Write-Host ("{0,-10} {1,8} {2,-50}" -f 
                 $result.TaskNumber, 
                 $result.Hours, 
                 $result.CommitMessages)
}

# Сохранение результатов в файл
$results | Export-Csv -Path "$PSScriptRoot\$FILE_NAME.csv" -NoTypeInformation -Encoding UTF8
Write-Host "Results saved to $PSScriptRoot\$FILE_NAME.csv"

# Возвращаемся в исходную директорию
Set-Location -Path $PSScriptRoot
