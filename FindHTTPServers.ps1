# ローカルネットワーク内のHTTPサーバーを検出するPowerShellスクリプト

# スクリプト開始メッセージ
Write-Host "ローカルネットワーク内のHTTPサーバー検出を開始します..." -ForegroundColor Cyan

# 現在のネットワーク情報を取得
$networkInfo = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq "Up" }

if ($networkInfo -eq $null) {
    Write-Host "アクティブなネットワーク接続が見つかりませんでした。" -ForegroundColor Red
    exit
}

# IPアドレスとサブネットマスクを取得
$ipAddress = $networkInfo.IPv4Address.IPAddress
$prefixLength = $networkInfo.IPv4Address.PrefixLength

Write-Host "現在のIPアドレス: $ipAddress / $prefixLength" -ForegroundColor Green

# CIDRからネットワークアドレスを計算
$ipBytes = $ipAddress.Split('.')
$networkAddress = "$($ipBytes[0]).$($ipBytes[1]).$($ipBytes[2])"

Write-Host "ネットワークアドレス: $networkAddress.0/24" -ForegroundColor Green
Write-Host "スキャン範囲: $networkAddress.1 から $networkAddress.254" -ForegroundColor Green

# 結果を格納する配列
$httpServers = @()

# 進捗状況表示用の変数
$total = 254
$current = 0
$startTime = Get-Date

# 各IPアドレスをスキャン
1..254 | ForEach-Object {
    $ip = "$networkAddress.$_"
    $current++
    $percent = [math]::Round(($current / $total) * 100)
    
    # 進捗状況表示
    Write-Progress -Activity "ネットワークスキャン中" -Status "$ip をチェック中..." -PercentComplete $percent
    
    # アクティブなホストをチェック（ポート80に接続を試みる）
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $connection = $tcpClient.BeginConnect($ip, 80, $null, $null)
    $wait = $connection.AsyncWaitHandle.WaitOne(100)
    
    if ($wait) {
        try {
            $tcpClient.EndConnect($connection)
            
            Write-Host "HTTP応答を確認中: $ip" -ForegroundColor Yellow
            
            # HTTPリクエストを送信
            $client = New-Object System.Net.Sockets.TcpClient
            $client.Connect($ip, 80)
            $client.SendTimeout = 1000
            $client.ReceiveTimeout = 1000
            
            if ($client.Connected) {
                $stream = $client.GetStream()
                $writer = New-Object System.IO.StreamWriter($stream)
                $buffer = New-Object System.Byte[] 4096
                $encoding = New-Object System.Text.ASCIIEncoding
                
                # HTTPリクエスト送信
                $request = "GET / HTTP/1.1`r`nHost: $ip`r`nConnection: Close`r`n`r`n"
                $writer.Write($request)
                $writer.Flush()
                
                # レスポンス受信
                $response = ""
                $read = 0
                
                try {
                    while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                        $response += $encoding.GetString($buffer, 0, $read)
                        if ($response.Contains("`r`n`r`n")) { break }
                    }
                }
                catch {
                    # タイムアウトなどのエラーは無視
                }
                
                # レスポンスがあれば解析
                if ($response -ne "") {
                    $statusCode = if ($response -match "HTTP/\d\.\d (\d+)") { $matches[1] } else { "Unknown" }
                    $server = if ($response -match "Server: ([^\r\n]+)") { $matches[1] } else { "Unknown" }
                    $title = if ($response -match "<title[^>]*>([^<]+)</title>") { $matches[1].Trim() } else { "No Title" }
                    
                    # 結果を配列に追加
                    $httpServers += [PSCustomObject]@{
                        IPAddress = $ip
                        StatusCode = $statusCode
                        Server = $server
                        Title = $title
                    }
                    
                    Write-Host "HTTPサーバーを検出: $ip ($server)" -ForegroundColor Green
                }
                
                # 接続を閉じる
                $writer.Close()
                $stream.Close()
            }
            
            $client.Close()
        }
        catch {
            # エラーは無視
        }
    }
    
    $tcpClient.Close()
}

# スキャン完了
$endTime = Get-Date
$duration = $endTime - $startTime

Write-Progress -Activity "ネットワークスキャン中" -Completed
Write-Host "`nスキャン完了！所要時間: $($duration.TotalSeconds.ToString('0.00')) 秒" -ForegroundColor Cyan
Write-Host "検出されたHTTPサーバー: $($httpServers.Count)" -ForegroundColor Cyan

# 結果表示
if ($httpServers.Count -gt 0) {
    Write-Host "`n検出されたHTTPサーバー一覧:" -ForegroundColor Magenta
    $httpServers | Format-Table -AutoSize
    
    # 詳細表示
    foreach ($server in $httpServers) {
        Write-Host "`nIP: $($server.IPAddress)" -ForegroundColor White
        Write-Host "  ステータスコード: $($server.StatusCode)" -ForegroundColor White
        Write-Host "  サーバー情報: $($server.Server)" -ForegroundColor White
        Write-Host "  タイトル: $($server.Title)" -ForegroundColor White
    }
    
    # 結果をCSVファイルに保存
    $csvPath = "$env:USERPROFILE\Desktop\http_servers_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $httpServers | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    Write-Host "`n結果をCSVファイルに保存しました: $csvPath" -ForegroundColor Cyan
}
else {
    Write-Host "HTTPサーバーは検出されませんでした。" -ForegroundColor Yellow
}