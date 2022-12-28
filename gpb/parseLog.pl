#!C:/Users/ashefer/AllFilesRepos/WorkFiles/Perl/bin/perl
package ParseLog;
my $version = '1.0.0';

use strict;
use lib "./lib";
use utf8;

use DBI;
use DBD::SQLite;
use File::Basename;

my ($sth_m, $sth_l, $sth_t);

my $path_of_this_module = File::Basename::dirname( eval { ( caller() )[1] } );
my $pathToCfg = $path_of_this_module.'/conf/config.txt';

my $params = getConfig($pathToCfg);
unless (keys %{$params}) { 
    die "\nThe confinguration  wasn't read. '$pathToCfg'\n";
}

my $db_con = getDBConnection($params);
my $rslt   = createTbl($db_con);
parseLog($params, $db_con, $path_of_this_module);

moveToBackup($params, $path_of_this_module);

# Disconnect from the database.
$db_con->disconnect();

############################################
# get db_con
############################################
sub getDBConnection(){
    our $db_con;
    $params = shift;
    
    if($db_con){ return $db_con; }
    else
    {
      my $database = $params->{"db_name"};
      my $hostname = $params->{"db_host_ip"};
      my $port     = $params->{"db_port"};
      my $user     = $params->{"db_usr_name"};
      my $password = $params->{"db_usr_pswd"};

      my $dsn = "DBI:mysql:database=$database;host=$hostname;port=$port";
      $db_con = DBI->connect($dsn, $user, $password);
    }
    if(!$db_con){
        die "\n\nFailed to connect to MySQL database: ".DBI->errstr();
    }

  return $db_con;
}

############################################
# Create tables: message / log
############################################
sub createTbl($$){
my $dbh  = shift;
my $rslt->{"table"} = [];

my $create_tbl_message = <<CREATE_TBL_MESSAGE
CREATE TABLE message (
created   TIMESTAMP(0)  NOT NULL,
id        VARCHAR(100)  NOT NULL,
int_id    CHAR(16)      NOT NULL,
str       VARCHAR(2000) NOT NULL,
status    BOOL,
sort_sign TINYINT,
CONSTRAINT message_int_id_pk PRIMARY KEY(int_id)
)
CREATE_TBL_MESSAGE
;
my $create_idx_message = <<CREATE_IDX_MESSAGE
CREATE INDEX message_created_idx ON message (created)
CREATE_IDX_MESSAGE
;
my $create_idx_int_id  = <<CREATE_IDX_INT_ID
CREATE INDEX message_int_id_idx ON message (int_id)
CREATE_IDX_INT_ID
;
my $create_tbl_log     = <<CREATE_TBL_LOG
CREATE TABLE log (
created   TIMESTAMP(0) NOT NULL,
int_id    CHAR(16)     NOT NULL,
str       VARCHAR(2000),
address   VARCHAR(255),
sort_sign TINYINT
)
CREATE_TBL_LOG
;
my $create_idx_address = <<CREATE_IDX_ADDRESS
CREATE INDEX log_address_idx USING HASH ON log (address)
CREATE_IDX_ADDRESS
;
# --- 'tech_log' is used to write an err_msg by inserting data ---
my $create_tech_log = <<CREATE_TECH_LOG
CREATE TABLE tech_log (
created TIMESTAMP(0) NOT NULL,
file    VARCHAR(25)  NOT NULL,
form    VARCHAR(25)  NOT NULL,
action  VARCHAR(25)  NOT NULL,
cause   VARCHAR(2000)
)
CREATE_TECH_LOG
;
    my ($err, $tblName) = checkTableInDB($dbh, 'message');
    unless ( $tblName->{numrows} ){
        ($err, $rslt) = getSetDataSQL($dbh, $create_tbl_message, 'non-select');
        if(!$err){ 
            ($err, $rslt) = getSetDataSQL($dbh, $create_idx_message, 'non-select');
            if (!$err){
                ($err, $rslt) = getSetDataSQL($dbh, $create_idx_int_id,  'non-select');
                if (!$err){
                    push @{$rslt->{"table"}}, 'message';
    }    }    }    }
    if ($err){ die $err};

    ($err, $tblName) = checkTableInDB($dbh, 'log');
    unless ( $tblName->{numrows} ){
        ($err, $rslt) = getSetDataSQL($dbh, $create_tbl_log, 'non-select');
        if (!$err){
            ($err, $rslt) = getSetDataSQL($dbh, $create_idx_address, 'non-select');
            if (!$err){
                push @{$rslt->{"table"}}, 'log';
    }    }    }
    if ($err){ die $err};
    
    ($err, $tblName) = checkTableInDB($dbh, 'tech_log');
    unless ( $tblName->{numrows} ){
        ($err, $rslt) = getSetDataSQL($dbh, $create_tech_log, 'non-select');
    }
    if ($err){ die $err};
    
    return 'OK';
}

sub getListOfFiles($$){
    my $path    = shift;
    my $relPath = shift;
    
    $path =~ s/[\.]+//;
    my $ok = opendir my $dir_handle, $relPath.$path;
    my @listOfFiles = ();
    
    while (my $file_name = readdir $dir_handle) {
       if ($file_name ne '.' && $file_name ne '..') {
           
           $file_name = $params->{"inputFolder"}.'/'.$file_name;
           push @listOfFiles, $file_name if -f $file_name;
       }
    }
    $ok = closedir $dir_handle;
    
    return \@listOfFiles;
}

sub moveToBackup($$){
    my $prm  = shift;
    my $path = shift;
    
    my $cmd = '';
    my $dst = $prm->{"backupFolder"};
    $dst    =~ s/[\.]+//;
    
    my $src = $prm->{"inputFolder"};
    $src    =~ s/[\.]+//;
    
    if( !(-d $path.$dst) ){ mkdir $path.$dst; }
    run_command('echo %OS%');
    
    if($_ =~ m/Windows/){
        $src =~ s!\/!\\!g;
        $dst =~ s!\/!\\!g;
        $cmd = 'move /Y '
                . $path.$src .'\*.* '
                . $path.$dst;
    }
    else{
        $cmd = 'scp -r '
              . $path.$src .'/* '
              . $path.$dst
        ;
    }
    run_command($cmd);
}

################################################################################
#Execute external command. All output messages can be read
################################################################################
sub run_command {
	my $p_commandline = shift;
	my $err = shift;

	$_     = qx{$p_commandline 2>&1};
	$$err .= $_;

	return $?;
}

############################################
# parseLog
############################################
sub parseLog($$){
    my ($params, $dbh, $relPath) = @_;
    
    if($params->{"inputFolder"}){
        my @listOfFiles = @{ getListOfFiles($params->{"inputFolder"}, $relPath) };
        
        my $pttrn_flag  = '([><=*-]+)';
        my $pttrn_mail  = '((?:[\w._-]+)@[\w._-]+\..+)';
        my $pttrn_id_xx = '(?:.+id=)(.+)(?:\b)';
        if (scalar @listOfFiles){
            foreach my $fln (@listOfFiles){

                if(!open(FLH, "<", $fln))
                {     print "\nFile '$fln' can't be open: $!\n";
                    next;
                }
                my $line = 0;
                while(<FLH>)
                {   my %entry = ();
                    my @line = split " ", $_;
                    if (scalar @line > 3){
                        $entry{"date"}      = join ' ', @line[0,1];
                        $entry{"int_id"}    = $line[2];
                        $entry{"str"}       = join ' ', @line[2..$#line];
                        $entry{"str"}       =~ s/'/\\'/g;
                        
                        if ($line[3] ne 'Completed'){
                            $entry{"sort_sign"} = 1;}
                        else {
                            $entry{"sort_sign"} = 2;}
                        
                        if ( my ($flag) = $line[3] =~ m/$pttrn_flag/){
                            $entry{"flag"} = $flag;
                            
                            if ($entry{"flag"} eq '<='){
                                ($entry{"id"}) = $_ =~ m/$pttrn_id_xx/;
                                 $entry{"id"} ||= '';
                                 $entry{"sort_sign"} = 0;
                            }
                            else {
                                if( $line[4] =~ m/$pttrn_mail/ || $line[4] eq '<>' ) {
                                    $entry{"address"} = $line[4];
                                }
                                elsif($line[4] eq ':blackhole:'){
                                    ($entry{"address"}) = $line[5] =~ m/<$pttrn_mail>/;
                                }
                                else { $entry{"address"} = ''; }
                            }
                        }
                    }
                    putDataIntoDB($dbh, \%entry, ++$line, $fln =~ m/([^\/\\]+)$/);
                }
                 close(FLH);
            }
        }
        else {
            print "\nThe given folder is empty or not exist: '".$params->{"inputFolder"}."'\n";
        }
    }
    
}

######################################
# each line will be inserted into db
# duplicates will be inserted into 'tech_log'
######################################
sub putDataIntoDB($$;$){
    my ($dbh, $value, $line, $file) = @_;
    
my $insrt_message = <<INSRT_MESSAGE
insert into message (created, id, int_id, str, sort_sign)
select * from (
    select ? as created
         , ? as id
         , ? as int_id
         , ? as str
         , ? as sort_sign
    ) as new_message
where not exists( 
    select int_id 
    from message
    where int_id  = ?
)
INSRT_MESSAGE
;

my $insrt_log = <<INSRT_LOG
insert into log (created, int_id, str, address, sort_sign)
select * from (
    select ? as created
         , ? as int_id
         , ? as str
         , IFNULL(?,'') as address
         , ? as sort_sign
    ) as new_log
where not exists (
    select int_id
    from log
    where created   = ?
      and int_id    = ?
      and str       = ?
      and address   = ?
      and sort_sign = ?
)
INSRT_LOG
;
my $insrt_tech_log = <<INSRT_TECH_LOG
insert into tech_log (created, file, form, action, cause) values (?, ?, ?, ?, ?)
INSRT_TECH_LOG
;
    my $flag = $value->{"flag"};
    if ($value->{"flag"} && $value->{"flag"} eq '<='){
        
        unless ($sth_m){$sth_m = $dbh->prepare($insrt_message);}
        my $ref->{numrows} = $sth_m->execute(
                $value->{"date"}, $value->{"id"}, $value->{"int_id"}, $value->{"str"}, $value->{"sort_sign"}, $value->{"int_id"}
        );
        if ($ref->{numrows} eq '0E0'){
            $ref->{numrows} = 0;
            
            unless ($sth_t){$sth_t = $dbh->prepare($insrt_tech_log);}
            my $ref->{numrows} = $sth_t->execute(
                    localtime_to_char('YYYY-MM-DD HH:MI:SS', time(), ':', '-'),
                    $file, 'message', 'insert',
                    'Duplicate, line#: '.$line.'; '.$value->{"date"}.' '.$value->{"str"}
            );
            if($dbh->err){ die $dbh->err; }
        }
    }
    else {
        unless ($sth_l){$sth_l = $dbh->prepare($insrt_log);}
        my $ref->{numrows} = $sth_l->execute(
                $value->{"date"}, $value->{"int_id"}, $value->{"str"}, $value->{"address"}, $value->{"sort_sign"},
                $value->{"date"}, $value->{"int_id"}, $value->{"str"}, $value->{"address"}, $value->{"sort_sign"}
        );
        if ($ref->{numrows} eq '0E0'){
            $ref->{numrows} = 0;
            
            unless ($sth_t){$sth_t = $dbh->prepare($insrt_tech_log);}
            my $ref->{numrows} = $sth_t->execute(
                    localtime_to_char('YYYY-MM-DD HH:MI:SS', time(), ':', '-'),
                    $file, 'log', 'insert',
                    'Duplicate, line#: '.$line.'; '.$value->{"date"}.' '.$value->{"str"}
            );
            if($dbh->err){ die $dbh->err; }
        }
    }

    return 'OK';
}

############################################
# Converting a character date into seconds
############################################
sub dateToSec($$$){
    my ($in_date, $delimDate, $delimTime) = @_;
    my @partOfDate = split " ", $in_date;
    
    if(scalar @partOfDate > 1){
        my ($year, $mon, $day) = split $delimDate, $partOfDate[0];
        my ($hour, $min, $sec) = split $delimTime, $partOfDate[1];
        
        my $unixTime = timelocal($sec, $min, $hour, $day, $mon-1, $year);
        return $unixTime > 0 ? $unixTime : $in_date;
    }
    return $in_date;
}

############################################
# getConfig
############################################
sub getConfig($){
  my ($fln)     = @_;
  my $pattern   = '^(?!#)(\w+)\s+=\s+(.+)';
  my %cfgParams = ();
  
  if(!open(FLH, "<", $fln))
  { print "\nFile $fln can't be open: $!\n";
    return undef;
  }
    
  while(<FLH>)
  {
    my($key, $value) = $_ =~ m/$pattern/;
    if($key){
        $cfgParams{$key} = $value;
    }
  }
  close(FLH);
  
  return \%cfgParams;
}

############################################
# check if a table already exits in DB
# if a table exits it returns the table_name.
# If not then empty string ""
############################################
sub checkTableInDB($$){
    my $dbh     = shift;
    my $tmpName = shift;

my $stmt_check_tbl_in_db = <<STMT_CHECK_TBL_IN_DB
SELECT table_name
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE='BASE TABLE'
  AND TABLE_NAME='$tmpName'
STMT_CHECK_TBL_IN_DB
;
    my ($err, $rslt) = getSetDataSQL($dbh, $stmt_check_tbl_in_db, 'select');
    return ($err, $rslt);
}

############################################
# run an query that can be select or non-select
#
# $dbh - conn to db; 
# $sql - select/non-select;
# $typeOfQuery - 'select'/'non-select'
#
# retrun ref to {numrows} and {affected_rows}
############################################
sub getSetDataSQL($$$){
    my ($dbh, $sql, $typeOfQuery) = @_;
        
    my $sth            = $dbh->prepare($sql);
    my $ref->{numrows} = $sth->execute();    # get number of rows
    $ref->{numrows}    = 0 if $ref->{numrows} eq '0E0';
    
    if ($typeOfQuery eq 'select'){
        $ref->{affected_rows} = $sth->fetchall_arrayref();     # get all rows and cols
        my ($slctdFileds)     = $sql =~ m/^select[\s]+(.+?)[\s]+from/i; 
        $ref->{fieldNames}    = [split ",", $slctdFileds];
    }
    # if($dbh->err){
        # die "\n\nFailed to retrieve data: ".$dbh->err;
    # }
    return ($dbh->errstr, $ref);
}

################################################################################
#
# Getting character date from timestamp
#
################################################################################
sub localtime_to_char(;$$$$)
{   # localtime_to_char('YYYY.MM.DD HH:MI:SS', time(), ':', '.')
    
    my $datetime_char    = '';
    my $format_date_time = shift || 'YYYYMMDDHHMISS';
    my $_timestamp_      = shift || time();
    my $tm_dlm           = shift || ':';
    my $dt_dlm           = shift || '.';
        
    # aktuelles Zeitstempel ermittelt
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($_timestamp_);
    $year  += 1900;
    $mon   = "0$mon"  if ((++$mon) < 10);
    $mday  = "0$mday" if ($mday    < 10);
    $hour  = "0$hour" if ($hour    < 10);
    $min   = "0$min"  if ($min     < 10);
    $sec   = "0$sec"  if ($sec     < 10);
    
    if ( $format_date_time   eq 'DD.MM.YYYY HH:MI:SS' )
    {  $datetime_char = "$mday$dt_dlm$mon$dt_dlm$year $hour$tm_dlm$min$tm_dlm$sec";
    }
    elsif ( $format_date_time eq 'DD.MM.YYYY HH:MI' )
    {  $datetime_char = "$mday$dt_dlm$mon$dt_dlm$year $hour$tm_dlm$min";
    }
    elsif ( $format_date_time eq 'HH:MI:SS DD.MI.YYYY' )
    {  $datetime_char = "$hour$tm_dlm$min$tm_dlm$sec $mday$dt_dlm$mon$dt_dlm$year";
    }
    elsif ( $format_date_time eq 'YYYY.MM.DD HH:MI:SS' ) 
    {  $datetime_char = "$year$dt_dlm$mon$dt_dlm$mday $hour$tm_dlm$min$tm_dlm$sec";
    }
    elsif ( $format_date_time eq 'YYYY-MM-DD HH:MI:SS' ) 
    {  $datetime_char = "$year$dt_dlm$mon$dt_dlm$mday $hour$tm_dlm$min$tm_dlm$sec";
    }
    elsif ( $format_date_time eq 'YYYYMMDD_HHMISS' ) 
    {  $datetime_char = "$year$mon$mday".'_'."$hour$min$sec";
    }
    elsif ( $format_date_time eq 'HH:MI:SS' )
    {  $datetime_char = "$hour$tm_dlm$min$tm_dlm$sec";
    }
    else  # 'YYYYMMDDHHMISS'
    {   $datetime_char = "$year$mon$mday$hour$min$sec";
    }
    
    return $datetime_char;
}

1;
