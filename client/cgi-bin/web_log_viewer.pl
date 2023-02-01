#!C:/Users/ashefer/AllFilesRepos/WorkFiles/Perl/bin/perl

use strict;
use warnings;
# use CGI::Carp qw(fatalsToBrowser);
use lib "./lib";
use utf8;

use DBI;
use DBD::mysql;
use JSON;
use URI::Escape;
use File::Basename;

# we use CGI since this will be executed in a browser
use CGI qw(:standard);

sub getConfig($);
sub getDBConnection;
sub getDataByEmail($$);
sub getEmailList($$);
sub getRelativePath;
sub initForm($);

my $html    = new CGI;

my $db_con;
my $data;
my $path         = getRelativePath();
my $pathToCfg    = "$path".'/server/conf/config.txt';
my $pttrn_mail   = '((?:[\w._-]+)@[\w._-]+\..+)';
my $pttrn_file   = '^(?:.*[\\|\/])?(.*)';
my ($scrpt_name) = $0 =~ m/$pttrn_file/;

my $params = getConfig($pathToCfg);
unless (keys %{$params}) {
	print "\nThe confinguration  wasn't read. '$pathToCfg'\n";
}

# invoke the ConnectToMySQL sub-routine to make the database connection
$db_con = getDBConnection($params);

if ($html->request_method eq 'POST'){
    
    if( my $str_uri = $html->param('POSTDATA') ){  # "18%2FGetEmailList%2F3%2Fall" | "33%2FGetDataByEmail%2F15%2Ffvwgsenxc%40ya.ru"
        # print $str_uri;
        my $str = uri_unescape($str_uri);        # "18/GetEmailList/3/all" | "33/GetDataByEmail/15/fvwgsenxc@ya.ru" 
        my @str = split '/', $str;
        
        if (4 == scalar @str){
            if ($str[0] == length(join '',(split '/',$str))){

                if($str[1] eq 'GetDataByEmail'){
                    my ($email) = $str[3] =~ m/$pttrn_mail/;
                    if($email){
                        $data = getDataByEmail("address = '$email'", $params);
                    }
                    else {
                        $email eq 'all' ? $email = '' : ();
                        $data = "Error: the given email address cannot be used as a search value ($str[3]).";
                    }
                }
                elsif( $str[1] eq 'GetEmailList' ){
                    my $val         = $str[3];
                    my $whereClause = "where address != ''";
                    
                    if($val && ($val ne 'all') ){
                        my $likeVal = '';
                        
                        $val =~ s/@/\@/g;

                        if ($val =~ m/%|\*/){ 
                            $likeVal = "'$val'";
                            $likeVal =~ s/\*/%/g;
                        }
                        else{$likeVal = "'%$val%'"; }
                        
                        $whereClause .= " and address like $likeVal";
                    }
                    $data = getEmailList($whereClause, $params);
                }
            }
        }
    }
}
elsif ($html->request_method eq 'GET'){
    if (my $v = $html->param('check')){
        if ($v eq 'relPath'){
            my $checkConnect = testConnToAnotherScript('perl ../pl/parseLog.pl check');
            if ($checkConnect){ 
                print header('text/html; charset=utf-8');
                print "Check connection, result: ".$checkConnect;
            }
            exit 1;
        } 
    }
}

# -----Test only------------
# my $email = ""; #"where address like '%\@ya.ru%'";
# if ($email){
    # $data = getEmailList($email, $params);
# }
# else{ # tpxmuwr
    # $data = getDataByEmail("address = 'tpxmuwr\@somehost.ru'", $params);
# }
# ------------------------

if ($data){
    if(!($data =~ m/Error/i)){
        my $json = encode_json($data);
        print header('application/json');
        print $json;
    }
    else {
        print header('text/html; charset=utf-8');
        # my $in_post_data = $html->param('POSTDATA');
        print $data;
        # ."\n$in_post_data\n"
        # .uri_unescape($in_post_data)
        # ."\n".length(join '',(split '/',uri_unescape($in_post_data)))
        # ."\n".(split '/',uri_unescape($in_post_data))[3];        
    }
}
else {
    my $form = initForm($params);
    print $form;
}

# Disconnect from the database.
$db_con->disconnect();

# exit the script
exit 1;

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
# get data by given email
############################################
sub getDataByEmail($$){
my $email = shift;
my $prms  = shift;

my $maxRow = $prms->{"max_row"} || 100;
    
my $statement_data_email =<<STATEMENT_DATA_EMAIL
select created, str
from (
	select m.created, m.str, m.int_id, m.sort_sign
	from message m inner join log l on (m.int_id = l.int_id)
	where l.<SUB_EMAIL>
	group by m.created, m.str, m.int_id, m.sort_sign

	union all
	select le.created, le.str, le.int_id, le.sort_sign
	from log le
	where le.int_id IN (
			select la.int_id from log la 
            where la.<SUB_EMAIL>
            group by la.int_id
        )
	group by le.created, le.str, le.int_id, le.sort_sign
) as t
order by created asc, int_id asc, sort_sign asc
limit $maxRow
STATEMENT_DATA_EMAIL
;
if ($email){
    $statement_data_email =~ s/<SUB_EMAIL>/$email/g;
    my ($err, $rslt) = getSetDataSQL($db_con, $statement_data_email, 'select');
    
    if ( $err ){ return "Error: ".$err; }
    
    if ($prms->{"max_row_greedy"} =~ m/on/i){
        my $chkHr = checkHierarchy($db_con, $rslt, $email);
        if ('HASH' eq ref($chkHr)){ $rslt = $chkHr; }
    }

    return $rslt;
}

return 'Error: email-address is missed!';
}

############################################
# if cutting the data set to 100 entries,
#   then "tails" may appear which are not included in the data set.
# Hence it is necessary to check the integrity of the structure.
############################################
sub checkHierarchy($$$){
    my $db    = shift;
    my $data  = shift;
    my $email = shift;

    my $stop     = 1;
    my $id       = '';
    my $org_rows = $data->{numrows};
    unless ($org_rows){ return; }
    
    while( $stop && $org_rows){
        my $line   = pop @{$data->{affected_rows}};
        --$org_rows;
        my @values = split ' ', $line->[1];
        unless($id){ $id = $values[0]; }
        
        unless('<=' eq $values[1]){ # ? head record
            next;
        }
        else {$stop = 0;}
    }

my $stmt_tails_data =<<STMT_TAILS_DATA
select created, str
from (
	select m.created, m.str, m.int_id, m.sort_sign
	from message m inner join log l on (m.int_id = l.int_id)
	where l.<SUB_EMAIL>
      and l.int_id = '$id'
	group by m.created, m.str, m.int_id, m.sort_sign

	union all
	select le.created, le.str, le.int_id, le.sort_sign
	from log le
	where le.int_id IN (
			select la.int_id from log la 
            where la.<SUB_EMAIL>
              and la.int_id = '$id'
            group by la.int_id
        )
	group by le.created, le.str, le.int_id, le.sort_sign
) as t
order by created asc, int_id asc, sort_sign asc
STMT_TAILS_DATA
;
    $stmt_tails_data =~ s/<SUB_EMAIL>/$email/g;  
    
    if($org_rows < $data->{numrows}){
        my ($err, $rslt) = getSetDataSQL($db, $stmt_tails_data, 'select');
        if($err){ return $err; }
        
        push @{$data->{affected_rows}}, @{$rslt->{affected_rows}};
        $data->{numrows} = ($org_rows + $rslt->{numrows});
    }
    return $data;    
}

############################################
# get a list of email by given pattern
############################################
sub getEmailList($$){
my $where = shift;
my $prms  = shift;

my $maxRow = $prms->{"max_row"} || 100;
    
my $statement_email_list =<<STATEMENT_EMAIL_LIST
select address from log
<WHERE_CLAUSE>
group by address
order by address asc
STATEMENT_EMAIL_LIST
;
# address like '%@ya.ru'
$statement_email_list =~ s/<WHERE_CLAUSE>/$where/;
my ($err, $rslt) = getSetDataSQL($db_con, $statement_email_list, 'select');
if ( $err ){
    return "Error: ".$err."\n\n".$statement_email_list."\n\n".$where;
}
$rslt->{"query"} = $statement_email_list;
return $rslt;
}

############################################
# run a query that can be select or non-select
#
# $dbh         - conn to db; 
# $sql         - select/non-select;
# $typeOfQuery - 'select'/'non-select'
#
# retrun ref to {numrows} and {affected_rows}
############################################
sub getSetDataSQL($$$){
    my ($dbh, $sql, $typeOfQuery) = @_;
       
    my $sth            = $dbh->prepare($sql);
    my $ref->{numrows} = $sth->execute();    # get number of rows
    
    if (!$dbh->errstr){
        $ref->{numrows} = 0 if $ref->{numrows} eq '0E0';
        
        if ($typeOfQuery eq 'select'){
            $ref->{affected_rows} = $sth->fetchall_arrayref();     # get all rows and cols
            my ($slctdFileds)     = $sql =~ m/^select[\s]+(.+?)[\s]+from/i;
            $slctdFileds          =~ s/[\s]+//g;
            $ref->{fieldNames}    = [split ",", $slctdFileds];
        }
    }
    
    return ($dbh->errstr, $ref);
}

############################################
# generating a html page
############################################
sub initForm($){
    my $param = shift;
    print $html->header("Content-Type: text/html; charset=utf-8");

my $content =<<CONTENT
<html>
  <head>
    <meta http-equiv="content-type" content="text/html; charset=utf-8">
    <script type="text/javascript" src="/gspb/client/js/core.js"></script>
    <link type="text/css" rel="stylesheet" href="/gspb/client/css/core.css"></link>
  </head>
  <body>
  <div class="FormContainer">
        <div class="title">
            <h1>Web Log Viewer</h1>
        </div>
        <div class="email">
            <div class="fld-email">
                <p>Enter an email address for which you want to see the data:<br>
                    <input type="text" size="60" name="flter_by_email" id="fld_email">
                </p>
            </div>
            <div class="btn-email">
                <button type="button" class="btn menuEmail" id="btn_menu_fld_email">emails</button>
            </div>
            <div class="btn-clear">
                <button type="button" class="btn menuEmail clear" id="btn_clear_fld">clear</button>
            </div>
        </div>
        <div class="data">
            <div class="btn_data">
                <button type="button" class="btn dataEmail" id="btn_data_fld_email">get data</button>
                <div class="initTable">
                    <table></table>
                </div>
            </div>
        </div>
    </div>
  </body>
</html>
CONTENT
;
}

sub getRelativePath{
    my $path = '';

    if ( $ENV{"CONTEXT_PREFIX"} eq '/gpb/'){
        $path = '../../';
        # ($path) = $ENV{"REQUEST_URI"} =~ s/$ENV{"CONTEXT_PREFIX"}//;
        # ($path) = $path =~ s/\/$0//;
    }
    return $path;
}

sub testConnToAnotherScript($){
    my $cmd = shift;
    run_command($cmd);
    
    return $_; 
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