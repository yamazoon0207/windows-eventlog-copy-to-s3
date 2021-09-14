<#
・処理概要
指定日数分のイベントログ (対象は Application , System , Security のみ) を evtx 形式にして出力し S3 バケットの日付つきフォルダに保存する
S3 ではライフサイクルポリシーを 2年に設定しておき 2年間保管する

保存イメージ
    s3://BuckekName/20210914/Application_2021-0914-0446-30.evtx
    s3://BuckekName/20210914/Security_2021-0914-0446-30.evtx
    s3://BuckekName/20210914/System_2021-0914-0446-30.evtx
    s3://BuckekName/20210915/Application_2021-0915-0446-31.evtx
    s3://BuckekName/20210915/Security_2021-0915-0446-31.evtx
    s3://BuckekName/20210915/System_2021-0915-0446-31.evtx
    ・・・・ 2 年分保存・・・・

1. イベントログの保存先となる S3 バケット内のパスを設定する ※Windows-Logs/accountid=<アカウント番号>/region=<リージョン>/<インスタンスID>/<yyyy-MMdd-HHmm_ss形式の現在時刻>
2. 指定した期間のイベントログ(Application , System , Security) を抽出し evtx 形式にてEC2のローカルに一時保存する
3. 2 のファイルを指定した S3 バケットの 1のパスに送信する
4. 1 の一時保存ファイルを削除する
※途中で処理に失敗した場合はイベントログにエラー内容を出力し処理を中断する

・利用方法
「変数定義」 内の 変数を記載し実行してください

・処理詳細
1. イベントログ(Applicationログ)に開始メッセージを出力する
2. $s3bucketname 変数に指定している S3 バケット の 下記パスを保存先に設定する
  保存先：Windows-Logs/accountid=<アカウント番号>/region=<リージョン>/<インスタンスID>/<yyyy-MMdd-HHmm_ss形式の現在時刻>
  ※<>内の情報は処理中に取得する
3. 設定した保存先の情報についてイベントログ(Applicationログ)にメッセージを出力する
4. $logcategory 変数に指定したログ種別のイベントログを $period 変数に指定した分のみ抽出し $eventlogtempfolder 変数に指定した一時保存用フォルダに保存する (evtx形式)
5. 一時保存用フォルダに保存したことについてイベントログ(Applicationログ)にメッセージを出力する
6. S3 に送信する
7. 一時保存用フォルダに保存した対象のログを削除する
8. 一時保存用フォルダに保存した対象のログを削除したことについてイベントログ(Applicationログ)にメッセージを出力する
9. イベントログ(Applicationログ)に終了メッセージを出力する
処理に失敗した場合はイベントログにエラー内容を出力し終了する
#>


# 変数定義
# イベントログの送信先 S3 バケット名
$s3bucketname = "01-recieve"

# 取得対象イベントログ (Application , System , Security)
$logcategorylist = "Application","System","Security"

# 抽出する期間 (処理開始時間を起点に過去 xx 日分)
$period = 3 # 3日分

# S3 バケットに送信する一日分のイベントログを一時保存する場所 ※無い場合はこのスクリプトで作成しますのでこのままで構いません
$eventlogtempfolder = "C:\eventlog-for-s3-copy"


# イベントログ出力関数を定義
# 引数1：ログ種別(System,Application など)  引数2:出力先フォルダ(C:¥evtxlog など)
function get-evtxlog ($logname,$outpath) {

# 開始日付(100日前)と終了日付(今日)を取得し、
# イベントログの選択に使用するクエリ(XPATH形式)に格納する
        # 開始日付指定(100日前を指定する場合、100と記述する)
        $fromDay = $period

        # 開始日付
        $startTime = (Get-Date).AddDays(-$fromDay)

        # 終了日付(今日)
        $endTime   = (Get-Date)

        # イベントログの選択に使用するクエリ(XPATH形式)に渡すため、システム時刻(UTC)に変換する
        $startUtcTime = [System.TimeZoneInfo]::ConvertTimeToUtc($startTime).ToString("yyyy-MM-ddTHH:mm:ssZ")
        $endUtcTime   = [System.TimeZoneInfo]::ConvertTimeToUtc($endTime).ToString("yyyy-MM-ddTHH:mm:ssZ")

        # イベントログの選択に使用するクエリ(XPATH形式)
        $filter = @"
Event/System/TimeCreated[@SystemTime>='$startUtcTime'] and
Event/System/TimeCreated[@SystemTime<'$endUtcTime']
"@

# 出力ファイル名を作成しておく
        # yyyy-MMdd-HHmm-ss形式の今日日付(出力ファイルの名前用)
        $YYYYMMDD = $endTime.ToString("yyyy-MMdd-HHmm-ss")

        # 出力ファイル（ログ種別_yyyy-MMdd-HHmm-ss）
        $outfile = "${outpath}\${logname}_${YYYYMMDD}.evtx"

        # 出力ファイル（ログ種別_yyyy-MMdd-HHmm-ss） 名前のみ
        $outfilename = "${logname}_${YYYYMMDD}.evtx"

# .Netクラスのメソッドを使って出力
        # System.Diagnostics.Eventing.Reader.EventLogSession クラスをオブジェクト化
        $evsession = New-Object -TypeName System.Diagnostics.Eventing.Reader.EventLogSession

        # ExportLog メソッドを実行 
        # 引数は、ログ種別、"LogName"(FilePathかLogName)、クエリ、出力ファイル
        $evsession.ExportLog($logname,"LogName",$filter,$outfile)

        # 出力情報をメッセージ出力
        $geteventlogmessage =  "イベントログの一時保存ファイルは $eventlogtempfolder/$outfilename です"
        Write-EventLog -LogName "Application" -EntryType Information -Source $eventlogsource -EventId 0 -Message "$geteventlogmessage"

        # 出力ファイル名(パスなし) を返す
        return $outfilename
}

# S3 に送信する関数
function put-to-s3 ($outfilename) {
    # S3 バケットに送信
        # 送信
          # S3 への put 権限が必要
        Write-S3Object -BucketName $s3bucketname -Key "$s3bucketpath/$outfilename" -File $eventlogtempfolder/$outfilename

        # 送信後メッセージ出力
        $s3message =  "イベントログ の S3 への送信が成功しました 送信先： $s3bucketfullpath/$outfilename"
        Write-EventLog -LogName "Application" -EntryType Information -Source $eventlogsource -EventId 0 -Message "$s3message"

    # 一時保存ファイルを削除
        # 削除
        Remove-Item -Path $eventlogtempfolder/$outfilename -Force

        # 一時保存ファイルの削除後メッセージ出力
        $delmessage =  "一時保存ファイルを削除しました 対象： $eventlogtempfolder/$outfilename"
        Write-EventLog -LogName "Application" -EntryType Information -Source $eventlogsource -EventId 0 -Message "$delmessage"
}

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


    # 各種イベントログを抽出し一時保存先に出力
        # 出力先が無い場合は作成
        if ( -not (Test-Path $eventlogtempfolder) ) { mkdir $eventlogtempfolder }

        # S3 バケットに送信するためのファイルリストを作成
        $filelist = @()
        # 各種イベントログを抽出し一時保存先に出力しファイルリストに追加
        $logcategorylist |%{$filelist += get-evtxlog $_ $eventlogtempfolder}


    #  S3 バケットに送信
        # ファイルリスト内のファイルを S3 に送信
        $filelist |%{put-to-s3 $_}


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
