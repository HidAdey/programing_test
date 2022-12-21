#!/usr/bin/perl
use strict;
use warnings;
use Time::Local 'timelocal';

my $file = $ARGV[0];      ###監視ログファイル名
my $file_1 = $ARGV[1];    ###出力ファイル名（拡張子不要）
my $timeout = $ARGV[2];    ###パラメータN（連続タイムアウト数）

unless ($timeout =~ /^\d+/){
    print STDERR "Please input numerical value for number of timeouts \"N\"!\n";
    exit;
}

open(IN1, $file) or die "$!";
open(OUT,"> $file_1\_serverdown.txt") or die "$!";
open(OUT1,"> $file_1\_subnetdown.txt") or die "$!";

my %failure = ();
my %fail_num = ();

my %subnet = ();
my %server_name = ();
my %failure_subnet = ();
my %sub_fail_num = ();
my %sub_date = ();

while(<IN1>){
    chomp;
    my @lines = split(/,/,$_);
    my $date = $lines[0];
    my $server = $lines[1];
    my $ping = $lines[2];
    
    $server =~ /(^\d+\.\d+\.\d+)\./;
    my $sub = $1;

    if (! exists $subnet{$sub}){
        $subnet{$sub} = 1;
        $server_name{$server} = 1;
    }elsif (! exists $server_name{$server}){
        $subnet{$sub} ++;
        $server_name{$server} = 1;
    }

    if (exists $fail_num{$server}){
        if ($ping =~ /-/) {                ### タイムアウトが続いている場合
            $fail_num{$server} ++;         ### タイムアウトの回数をカウント
            #print "$ping\n";
            if (exists $sub_fail_num{$sub}){         ### サブサーバートータルのタイムアウトの回数をカウント
                $sub_fail_num{$sub} ++;
            }else{
                $sub_fail_num{$sub} = 1;
            }
        }elsif ($fail_num{$server} >= $timeout){            ### 一定回数以上タイムアウトしてから復旧した場合（故障期間の計算）
            my $time_fail_str = time_from_str($failure{$server});
            my $time_fail_end = time_from_str($date);
            my $recovery = time_to_sec($time_fail_end) - time_to_sec($time_fail_str);
            print OUT "$server,$failure{$server},$recovery\n";                ### サーバー名、障害の開始時間、障害の継続時間　の順で出力
            delete $fail_num{$server};
            #print "$ping\n";

            my $sub_timeout = $timeout * $subnet{$sub};                          ### タイムアウト数の閾値　×　サブネット内の全サーバーの数　＝　サブネット内の全サーバーのタイムアウト数の許容量
            if (! exists $sub_fail_num{$sub}){
                next;
            }elsif($sub_fail_num{$sub} >= $sub_timeout){
                my $time_fail_str_sub = time_from_str($failure_subnet{$sub});
                my $time_fail_end_sub = time_from_str($date);
                my $recovery_sub = time_to_sec($time_fail_end_sub) - time_to_sec($time_fail_str_sub);
                print OUT1 "$sub,$failure_subnet{$sub},$recovery_sub\n";                ### サーバー名、障害の開始時間、障害の継続時間　の順で出力
                delete $sub_fail_num{$sub};
                #print "$ping\n";
            }else{
                delete $sub_fail_num{$sub};
            }
        }else{                             ### 一定回数以内にタイムアウトから復旧した場合
            delete $fail_num{$server};
            delete $sub_fail_num{$sub};
        }
    }else{
        if ($ping =~ /-/){                 ### 今まで故障はないが、今回タイムアウトした場合
            $failure{$server} = $date;
            $fail_num{$server} = 1;
            if (exists $sub_fail_num{$sub}){
                $sub_fail_num{$sub} ++;
            }else{
                $sub_fail_num{$sub} = 1;
                $failure_subnet{$sub} = $date;
            }
            #print "$ping\n";
        }else{                             ### 今まで問題がなく、今回も正常な場合
            #print "$ping\n";
            if (exists $sub_fail_num{$sub}){
                delete $sub_fail_num{$sub};
            }
        }
    }

}

### ログの記録終了時にタイムアウトしているサーバーも出力する（故障期間は算出できないので、'failure'と記載）
foreach ( sort { $failure{$a} <=> $failure{$b} } keys  %failure){
    if (exists $fail_num{$_} && $fail_num{$_} >= $timeout) {
        print OUT "$_,$failure{$_},failure\n";
    }
}

foreach ( sort { $failure_subnet{$a} <=> $failure_subnet{$b} } keys  %failure_subnet){
    my $sub_timeout = $timeout * $subnet{$_};  
    if (exists $sub_fail_num{$_} && $sub_fail_num{$_} >= $sub_timeout) {
        print OUT1 "$_,$failure_subnet{$_},subnet_failure!\n";
    }
}

close (IN1);
close (OUT);



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
    }
    else {
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
