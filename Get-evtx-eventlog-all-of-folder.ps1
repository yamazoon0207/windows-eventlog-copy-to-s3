<#
・処理概要
C:\Windows\System32\winevt\Logs 配下のログファイルを全て S3 バケットの日付つきフォルダに送信して保存する
S3 ではライフサイクルポリシーを 2年に設定しておき 2年間保管する

保存イメージ
    s3://BuckekName/20210914/Application.evtx
    s3://BuckekName/20210914/Security.evtx
    s3://BuckekName/20210914/System.evtx
    s3://BuckekName/20210914/HardwareEvents.evtx
    ・・・略。一般的に 300 ログ程度 存在するログファイル全て・・・・
    s3://BuckekName/20210915/Application.evtx
    s3://BuckekName/20210915/Security.evtx
    s3://BuckekName/20210915/System.evtx
    s3://BuckekName/20210915/HardwareEvents.evtx
    ・・・略。一般的に 300 ログ程度 存在するログファイル全て・・・・
    ・・・・ 2 年分保存・・・・
制約
S3 にアップロードできるオブジェクトのサイズは 5GB である
そのため ログファイルのサイズが 5GB を超えている場合はアップロードに失敗する
aws cli が必要

処理詳細
1. イベントログの保存先となる S3 バケット内のパスを設定する ※Windows-Logs/accountid=<アカウント番号>/region=<リージョン>/<インスタンスID>/<yyyy-MMdd-HHmm_ss形式の現在時刻>
2. C:\Windows\System32\winevt\Logs 配下のファイルを指定した S3 バケットの 1のパスに送信する
※途中で処理に失敗した場合はイベントログにエラー内容を出力し処理を中断する

・利用方法
「変数定義」 内の 変数を記載し実行してください

・処理詳細
1. イベントログ(Applicationログ)に開始メッセージを出力する
2. $s3bucketname 変数に指定している S3 バケット の 下記パスを保存先に設定する
  保存先：Windows-Logs/accountid=<アカウント番号>/region=<リージョン>/<インスタンスID>/<yyyy-MMdd-HHmm_ss形式の現在時刻>
  ※<>内の情報は処理中に取得する
3. 設定した保存先の情報についてイベントログ(Applicationログ)にメッセージを出力する
4. C:\Windows\System32\winevt\Logs のログファイルを すべて S3 に送信する
5. C:\Windows\System32\winevt\Logs のログファイルを すべて S3 に送信したことについてイベントログ(Applicationログ)にメッセージを出力する
6. イベントログ(Applicationログ)に終了メッセージを出力する
処理に失敗した場合はイベントログにエラー内容を出力し終了する
#>


# 変数定義
# イベントログの送信先 S3 バケット名
$s3bucketname = "01-recieve"

# 処理実行
try {
    # 開始メッセージ出力
        # Application ログ に 本処理の ソース がない場合に追加
        $eventlogsource = "s3-copy-script"
        if ([System.Diagnostics.EventLog]::SourceExists($eventlogsource) -eq $false){ New-EventLog -LogName "Application" -Source $eventlogsource }

        # 開始メッセージ出力
        $startmessage =  "イベントログ の S3 への送信を開始します"
        Write-EventLog -LogName "Application" -EntryType Information -Source $eventlogsource -EventId 0 -Message "$startmessage"


    # S3 バケットのパス設定
        # インスタンスメタデータから情報を取得するための token を取得
        $token = Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token-ttl-seconds" = "21600"} -Method PUT –Uri http://169.254.169.254/latest/api/token

        # アカウント番号を取得
          # 右記 IAM 権限が必要 :AmazonSSMManagedInstanceCore
        $accountid = (Get-STSCallerIdentity).Account

        # インスタンスメタデータからリージョン情報を取得
        $region = Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token" = $token} -Method GET -Uri http://169.254.169.254/latest/meta-data/placement/region

        # インスタンスメタデータからインスタンスIDを取得
        $instanceid = Invoke-RestMethod -Headers @{"X-aws-ec2-metadata-token" = $token} -Method GET -Uri http://169.254.169.254/latest/meta-data/instance-id

        # 日付を取得
        $date = Get-Date -Format "yyyy-MMdd-HHmm_ss"

        # S3バケットのパスのみ変数格納
        $s3bucketpath = "Windows-Logs/accountid=$accountid/region=$region/$instanceid/$date"

        # S3バケットを設定
        $s3bucketfullpath = "s3://$s3bucketname/$s3bucketpath"

        # パス情報をメッセージ出力
        $s3pathmessage =  "イベントログの送信先は $s3bucketfullpath/ です"
        Write-EventLog -LogName "Application" -EntryType Information -Source $eventlogsource -EventId 0 -Message "$s3pathmessage"


    # S3 バケットに送信
        # 送信
          # S3 への put 権限が必要
          aws s3 sync "C:\Windows\System32\winevt\Logs" $s3bucketfullpath

        # 送信後メッセージ出力
        $s3message =  "イベントログ の S3 への送信が成功しました 送信先： $s3bucketfullpath"
        Write-EventLog -LogName "Application" -EntryType Information -Source $eventlogsource -EventId 0 -Message "$s3message"


    # 終了メッセージ出力
        # 終了メッセージ出力
        $endmessage =  "イベントログ の S3 への送信を終了します"
        Write-EventLog -LogName "Application" -EntryType Information -Source $eventlogsource -EventId 0 -Message "$endmessage"

} catch {
    # 異常メッセージ出力
        # 異常メッセージ出力
        $Failuremessage =  "イベントログ の S3 への送信が異常終了しました"
        Write-EventLog -LogName "Application" -EntryType Error -Source $eventlogsource -EventId 0 -Message "$Failuremessage $error"

        # 処理中断
        throw "イベントログ の S3 への送信が異常終了しました $error"
}
