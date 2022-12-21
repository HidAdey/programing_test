#!/usr/bin/perl
use strict;
use warnings;
use Time::Local 'timelocal';

my $file = $ARGV[0];        ### 監視ログファイル名
my $file_1 = $ARGV[1];      ### 出力ファイル名（.txtファイルとして2種類出力）
my $timeout = $ARGV[2];     ### パラメータN（連続タイムアウト数）
my $m = $ARGV[3];    ### パラメータm（サーバーの応答時間を平均する回数）
my $t = $ARGV[4];    ### パラメータt（サーバーの反応時間の上限）


unless ($timeout =~ /^\d+/){
    print STDERR "Please input numerical value for Number of timeouts!\n";
    exit;
}
unless ($m =~ /^\d+/){
    print STDERR "Please input numerical value for number of time points to average \"m\"!\n";
    exit;
}
unless ($t =~ /^\d+/){
    print STDERR "Please input numerical value for overload condition time threshold \"t\"!\n";
    exit;
}


open(IN1, $file) or die "$!";
open(OUT1,"> $file_1\_failure.txt") or die "$!";
open(OUT2,"> $file_1\_overload.txt") or die "$!";

my %failure = ();
my %fail_num = ();

my %server_count = ();
my %server_check = ();
my %server_time = ();
my %overload = ();
my %load_num = ();

while(<IN1>){
    chomp;
    my @lines = split(/,/,$_);
    my $date = $lines[0];
    my $server = $lines[1];
    my $ping = $lines[2];

    unless (exists $server_count{$server}){
        $server_count{$server} = 0;
    }

    if (exists $fail_num{$server}){
        if ($ping =~ /-/) {                ### タイムアウトが続いている場合
            $fail_num{$server} ++;         ### タイムアウトの回数をカウント
            #print "$ping\n";
            next;
        }elsif ($fail_num{$server} >= $timeout){            ### 一定回数以上タイムアウトしてから復旧した場合（故障期間の計算）
            my $time_fail_str = time_from_str($failure{$server});
            my $time_fail_end = time_from_str($date);
            #print "$failure{$server}\n";
            #print "$date\n";
            my $recovery = time_to_sec($time_fail_end) - time_to_sec($time_fail_str);
            print OUT1 "$server,$failure{$server},$recovery\n";                 ### サーバー名、障害の開始時間、障害の継続時間　の順で出力
            delete $fail_num{$server};

            $server_count{$server} ++;                                          ### pingの計算用のハッシュ
            $server_check{$server}{$server_count{$server}} = $ping;
            $server_time{$server}{$server_count{$server}} = $date;
            #print "$ping\n";
        }else{                             ### 一定回数以内にタイムアウトから復旧した場合
            delete $fail_num{$server};

            $server_count{$server} ++;                                          ### pingの計算用のハッシュ
            $server_check{$server}{$server_count{$server}} = $ping;
            $server_time{$server}{$server_count{$server}} = $date;
        }
    }else{
        if ($ping =~ /-/){                 ### 今まで故障はないが、今回タイムアウトした場合
            $failure{$server} = $date;
            $fail_num{$server} = 1;
            #print "$ping\n";
            #print "$date,$ping\n";
            if (exists $load_num{$server}){                                              ### すでに過負荷だった場合
                my $time_overload_str = time_from_str($overload{$server});
                my $time_overload_end = time_from_str($date);
                my $recovery_load = time_to_sec($time_overload_end) - time_to_sec($time_overload_str);
                print OUT2 "$server,$overload{$server},$recovery_load\n";                ### 過負荷な情報を出力。サーバー名、障害の開始時間、障害の継続時間　の順で出力
                delete $load_num{$server};
                delete $server_count{$server};
                delete $server_check{$server};
                delete $server_time{$server};
                delete $overload{$server};
            }else{
                #print "$date,$ping\n";
                delete $server_count{$server};
                delete $server_check{$server};
                delete $server_time{$server};
                delete $overload{$server};
            }
        }elsif (exists $load_num{$server}){                             ### 今までタイムアウトがなく、今回もタイムアウトがない場合
            $server_count{$server} ++;
            $server_check{$server}{$server_count{$server}} = $ping;
            $server_time{$server}{$server_count{$server}} = $date;
            my $total_ping = 0;
            foreach my $key (keys %{$server_check{$server}}){
                $total_ping += $server_check{$server}{$key};
            }
            #print "$date,$total_ping,$ping\n";
            my $ping_ave = $total_ping / $m;
            if ($ping_ave > $t) {                                                       ### 過負荷状態が続いている場合
                delete $server_check{$server}{$server_count{$server} - $m +1};
            }else{                                                                      ### 過負荷状態が解消された場合
            my $time_overload_str = time_from_str($overload{$server});
            my $time_overload_end = time_from_str($date);
            my $recovery_load = time_to_sec($time_overload_end) - time_to_sec($time_overload_str);
            print OUT2 "$server,$overload{$server},$recovery_load\n";                ### サーバー名、障害の開始時間、障害の継続時間　の順で出力
            delete $load_num{$server};
            #print "$ping\n";
            }
        }else{
            $server_count{$server} ++;
            $server_check{$server}{$server_count{$server}} = $ping;
            $server_time{$server}{$server_count{$server}} = $date;
            if (exists $server_check{$server}{$server_count{$server} +1 - $m}){
                my $total_ping = 0;
                foreach my $key (keys %{$server_check{$server}}){
                    $total_ping += $server_check{$server}{$key}
                }
                #print "$date,$total_ping,$ping\n";
                my $ping_ave = $total_ping / $m;
                if ($ping_ave > $t) {
                    $overload{$server} = $server_time{$server}{$server_count{$server} +1 - $m};
                    #print "$date,$overload{$server},$ping\n";
                    $load_num{$server} = 1;
                    delete $server_check{$server}{$server_count{$server} +1 - $m};
                }else{
                    #print "$date,$ping\n";
                    delete $server_check{$server}{$server_count{$server} +1 - $m};
                }
            }
            
        }
    }

}
close (IN1);

### ログの記録終了時にタイムアウトしているサーバーも出力する（故障期間は算出できないので、'failure'と記載）
foreach ( sort { $failure{$a} <=> $failure{$b} } keys  %failure){
    if (exists $fail_num{$_} && $fail_num{$_} >= $timeout) {
        print OUT1 "$_,$failure{$_},failure\n";
    }
}

### ログの記録終了時に過負荷状態にあるサーバーも出力する（過負荷期間は算出できないので、'failure'と記載）
foreach my $key(keys(%overload)){
    if (exists $load_num{$key}) {
        print OUT2 "$key,$overload{$key},overload\n";
    }
}




# 時刻の文字列を時刻情報のハッシュに変換する関数
sub time_from_str {
    my $time_str = shift;
    return unless $time_str;
  
    my $time = {};
  
    # 日付を含む時刻の書式にマッチさせてハッシュを作成
    if ($time_str =~ /(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})/) {
    @{$time}{qw/year mon mday hour min sec/}
      = ($1, $2, $3, $4, $5, $6);
    
    $time->{year} -= 1900;
    $time->{mon} -= 1;
    
    return wantarray ? %$time : $time;
    }
    return;
}


# 時刻を秒に変換する関数
sub time_to_sec {
    my $time;
    if (ref $_[0] eq 'HASH') {
        $time = shift;
        #print "$time\n";
    }else {
        %$time = @_;
        #print "$time\n";
    }
  
    return unless defined $time->{sec};
    return unless defined $time->{min};
    return unless defined $time->{hour};
    return unless defined $time->{mday};
    return unless defined $time->{mon};
    return unless defined $time->{year};
  
    # Time::Localモジュールを使用して秒に変換
    require Time::Local;
    my $sec = Time::Local::timelocal(
        $time->{sec},
        $time->{min},
        $time->{hour},
        $time->{mday},
        $time->{mon},
        $time->{year},
    );
    return $sec;
}
