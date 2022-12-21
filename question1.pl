#!/usr/bin/perl
use strict;
use warnings;
use Time::Local 'timelocal';

my $file = $ARGV[0];      ###監視ログファイル名
my $file_1 = $ARGV[1];    ###出力ファイル名（拡張子不要）


open(IN1, $file) or die "$!";
open(OUT,"> $file_1.txt") or die "$!";

my %failure = ();
my %fail_num = ();

while(<IN1>){
    chomp;
    my @lines = split(/,/,$_);
    my $date = $lines[0];
    my $server = $lines[1];
    my $ping = $lines[2];

    if (exists $fail_num{$server}){
        if ($ping =~ /-/) {                ### 故障が続いている場合
            #print "$ping\n";
            next;
        }else{                             ### 復旧した場合（故障期間の計算）
            my $time_fail_str = time_from_str($failure{$server});
            my $time_fail_end = time_from_str($date);
            my $recovery = time_to_sec($time_fail_end) - time_to_sec($time_fail_str);
            print OUT "$server,$failure{$server},$recovery\n";                ### サーバー名、障害の開始時間、障害の継続時間　の順で出力
            delete $fail_num{$server};
            #print "$ping\n";
        }
    }else{
        if ($ping =~ /-/){                 ### 今まで故障はないが、今回故障した場合
            $failure{$server} = $date;
            $fail_num{$server} = 1;
            #print "$ping\n";
        }else{                             ### 今まで問題がなく、今回も正常な場合
            #print "$ping\n";
            next;
        }
    }

}
close (IN1);


### ログの記録終了時にタイムアウトしているサーバーも出力する（故障期間は算出できないので、'failure'と記載）
foreach ( sort { $failure{$a} <=> $failure{$b} } keys  %failure){
    if (exists $fail_num{$_}) {
        print OUT "$_,$failure{$_},failure\n";
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
