#!C:/Users/ashefer/AllFilesRepos/WorkFiles/Perl/bin/perl

use strict;
use warnings;
use CGI::Carp qw(fatalsToBrowser);
use lib "./lib";
use utf8;

use DBI;
use DBD::mysql;
use JSON;
use URI::Escape;

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
my $path       = getRelativePath();
my $pathToCfg  = ".$path".'conf/config.txt';
my $pttrn_mail = '((?:[\w._-]+)@[\w._-]+\..+)';
my $pttrn_file = '^(?:.*[\\|\/])?(.*)';
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
                    my $email = $str[3];
                    if($email =~ m/$pttrn_mail/){
                        $data = getDataByEmail("address = '$email'", $params);
                    }
                    else {
                        $email eq 'all' ? $email = '' : ();
                        $data = "Error: the given email address cannot be used as a search value ($email).";
                    }
                }
                elsif( $str[1] eq 'GetEmailList' ){
                    my $val         = $str[3];
                    my $whereClause = "where address != ''";
                    
                    if($val && ($val ne 'all') ){
                        my $likeVal = '';
                        
                        $val =~ s/@/\@/g;

                        if ($val =~ m/%|\*/){ $likeVal = $val; }
                        else{$likeVal = "'%$val%'"; }
                        
                        $whereClause .= " and address like $likeVal";
                    }
                    $data = getEmailList($whereClause, $params);
                }
            }
        }
    }
}

# -----Test only------------
# my $email = ""; #"where address like '%\@ya.ru%'";
# if ($email){
    # $data = getEmailList($email, $params);
# }
# else{ # tpxmuwr
    # $data = getDataByEmail("address like 'tpxmuwr\@somehost.ru'", $params);
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
    
    my $chkHr = checkHierarchy($db_con, $rslt, $email);
    if ('HASH' eq ref($chkHr)){ $rslt = $chkHr; }
    
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
        my @values = split ' ', $line->[1];
        unless($id){ $id = $values[0]; }
        
        unless('<=' eq $values[1]){ # ? head record
            --$org_rows;
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
# get a list of email by given patter
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

my $js_context   = core_js();

my $content =<<CONTENT
<html>
  <head>
    <meta http-equiv="content-type" content="text/html; charset=utf-8">
    <script type="text/javascript">
        $js_context
    </script>
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
    <style type="text/css">
        html{
        font-family:sans-serif;
        -ms-text-size-adjust:100%;
        -webkit-text-size-adjust:100%
        }
        .FormContainer{
            height: 600px;
            overflow-x:hidden;
            margin-top: 0px;
            margin-bottom: 20px;
            border-bottom: 1px solid #eee;
            background: #e3e3e3;
            padding-left: 5px;
        }
        .title{
            position: relative;
            left: 10%;
        }
        .email {text-align: left;}
        .btn-email,
        .btn-clear,
        .fld-email {
            display: inline-block;
            margin-right: -0.15em;
        }
        .initTable{
            margin-top: 3px;
            width: 95%;
            background: #f1f1ce;
        }
        .MenuTableContainer{
            overflow-x: hidden;
            overflow-y: auto;
        }
        .MenuTable{
            background: #bcc8bf;
        }
        .MenuTable tbody tr:nth-child(even){
            background: #f3f3f3;
        }
        .MenuTableTD{
            padding: 2px;
        }
        .scroll-table-body {
            height: 300px;
            overflow-x:auto;
            margin-top: 0px;
            margin-bottom: 10px;
            border-bottom: 1px solid #eee;
        }
        .scroll-table table {
            width:100%;
            table-layout: fixed;
            border: none;
        }
        .scroll-table thead th {
            font-weight: bold;
            text-align: left;
            border: none;
            padding: 5px 5px;
            background: #f9a34b;
            font-size: 14px;
        }
        .scroll-table tbody td {
            text-align: left;
            border-left: 1px solid #ddd;
            border-right: 1px solid #ddd;
            padding: 5px 5px;
            font-size: 14px;
            vertical-align: top;
        }
        .scroll-table tbody tr:nth-child(even){
            background: #f3f3f3;
        }
        .scroll-table thead tr:first-child > th:first-child,
            tbody tr:first-child > td:first-child {
            width: 15%;
        }

        /* style for scroll */
        ::-webkit-scrollbar {
            width: 6px;
        } 
        ::-webkit-scrollbar-track {
            box-shadow: inset 0 0 6px rgba(0,0,0,0.3); 
        } 
        ::-webkit-scrollbar-thumb {
            box-shadow: inset 0 0 6px rgba(0,0,0,0.3); 
        }
    </style>
  </body>
</html>
CONTENT
;
}

sub getRelativePath{
    my $path = '';
    if ($ENV{"CONTEXT_PREFIX"}){
        
        ($path) = $ENV{"REQUEST_URI"} =~ s/$ENV{"CONTEXT_PREFIX"}//;
        ($path) = $path =~ s/\/$0//;
    }
    return '/'.$path;
}

###############################################
# apache couldn't load a .js file
# hence all javascript functions are placed there
###############################################
sub core_js{
    
my $js =<<JS

var Workflow = {
    'data':  "GetDataByEmail",
    'menu':  "GetEmailList",
    'clear': "ClearFldEmail"
};
var AbsContextPath;

var RelContextPath = "$scrpt_name";
SetContextPath();
var nextZIndex = 100001;

function GET_XML_HTTP() {
    var _fo;
    try {
        _fo = new XMLHttpRequest();
    } catch (e) {
        try {
            _fo = new ActiveXObject("Msxml2.XMLHTTP");
        } catch (e) {
            try {
                _fo = new ActiveXObject("Microsoft.XMLHTTP");
            } catch (e) {
                ;
            }
        }
    }
    return _fo;
}

// function checkHostAvailability() {
    // var fetcher = GET_XML_HTTP();
    // fetcher.open("GET", AbsContextPath, false);
    // fetcher.setRequestHeader("Content-type", "text/plain; charset=UTF-8");
    // try {
        // fetcher.send();
    // } catch (e) {}
    // if (fetcher.readyState == 4 && fetcher.status == 200 && fetcher.responseText) {
        // return true;
    // }
    // return false;
// }

// var rval = checkHostAvailability();



function GetDocumentLocation() {
    var loc = document.location;
    var abs = loc.protocol + "//" + loc.hostname;
    if (document.location.href.indexOf(abs) == -1) {
        abs = loc.protocol + "//[" + loc.hostname + "]";
    }
    if (loc.port)
        abs += ":" + loc.port;
    var path = loc.pathname;
    var len = path.length;
    if (path.charAt(len - 1) != "/") {
        len = path.lastIndexOf("/");
        path = path.substring(0, len + 1);
    }
    return abs + path;
}
function SetContextPath() {
    if (typeof (AbsContextPath) == "undefined" || AbsContextPath == null) {
        AbsDocumentPath = GetDocumentLocation();
        AbsContextPath = AbsDocumentPath + RelContextPath;
        var req = AbsContextPath.split("/");
        var res = [];
        for (var i = 0; i < req.length; ++i) {
            if (req[i] == "..") {
                ;res.pop();
            } else
                res.push(req[i]);
        }
        AbsContextPath = res.join("/");
    } else {
        AbsDocumentPath = "";
    }
    ;
}

function MarshallArgs(args) {
    var buff = [];
    buff.push("/");
    buff.push(args[0]);
    buff.push("/");
    var typeencoders = {
        "string": function(b, o) {
            b.push(o.length);
            b.push("/");
            b.push(o);
        },
        "boolean": function(b, o) {
            b.push("1");
            b.push("/");
            b.push(o ? "1" : "0");
        },
        "number": function(b, o) {
            var ns = "" + o;
            b.push("" + ns.length);
            b.push("/");
            b.push(ns);
        }
    };
    for (var i = 1; i < args.length; ++i) {
        var ai = args[i];
        if (ai instanceof Array) {
            var l = ai.length;
            var abuff = [];
            abuff.push(l);
            abuff.push("/");
            if (l > 0) {
                var encoder = typeencoders[typeof ai[0]];
                ;for (var j = 0; j < l; ++j)
                    encoder(abuff, ai[j]);
            }
            var buffstr = abuff.join("");
            typeencoders["string"](buff, buffstr);
        } else
            typeencoders[typeof ai](buff, ai);
    }
    var finalbuff = buff.join("");
    finalbuff = (finalbuff.length - 1) + finalbuff;
    return finalbuff;
}

function trampoline(){
    var evnt;
    var arr  = new Array();
    var mail = '';
    
    if(event.currentTarget){
        if ( event.currentTarget.tagName == 'TD'
          || event.currentTarget.tagName == 'TR'
          || event.currentTarget.tagName == 'BUTTON'
        ){
            evnt = event.currentTarget;
        }
        else if(event.relatedTarget){ // && event.relatedTarget.tagName == 'TD'){
            evnt = event.relatedTarget;
        }
    }
    
    if (evnt && (evnt.tagName == 'TD' || evnt.tagName == 'TR' || evnt.tagName == 'BUTTON') ){
        if(evnt.id){
            arr = (evnt.id).split('_');
            
            if (arr[0] == 'btn') {
                var fld_id = (arr.slice(2)).join('_');
                if(fld_id){
                    if(document.getElementById(fld_id)){
                        mail = document.getElementById(fld_id).value; }
                    if (mail == ''){ mail = 'all'; }
                    var args = [];
                    args.push(Workflow[arr[1]]);
                    args.push(mail);
                    evnt.args = args;
                }
            }
            if (args[0] == 'GetEmailList' || args[0] == 'GetDataByEmail'){
                rmvMenuOuter();
                NDXRequest(evnt);
            }
            else if(args[0] == 'ClearFldEmail'){
                document.getElementsByName("flter_by_email")[0].value = '';
                if ('on' == window.mMenuOuter){
                    rmvMenuOuter(document.getElementsByClassName('MenuTableContainer')[0].parentElement);
                }
            }
        }
        else if(evnt.tagName == 'TD' && 'MenuTableTD' == evnt.className){
            document.getElementsByName("flter_by_email")[0].value = evnt.innerText;
            rmvMenuOuter(evnt.parentElement.parentElement.parentElement.parentElement);
            
            document.getElementById('btn_data_fld_email').click();
        }
    }
    if(window.mMenuOuter == 'on' && 'MenuTableBody' == event.currentTarget.className){
        rmvMenuOuter();
    }
}
function rmvMenuOuter(elm){
    if(elm && elm.className == 'MenuOuter'){
        elm.remove();
        window.mMenuOuter = '';
    }
    else if (window.mMenuOuter == 'on'){
        if ('MenuOuter' == document.getElementsByClassName("MenuTableContainer")[0].parentElement.classname){
            document.getElementsByClassName("MenuTableContainer")[0].parentElement.remove();
            window.mMenuOuter = '';
        }
    }
}

function NDXRequest(obj) {
    if(obj.args.length) {
        NDXRequestRun(obj);
    }
}
function NDXRequestRun(obj){
    var args = obj.args;
    var finalbuff = MarshallArgs(args);
    var finalbuffuri = encodeURIComponent(finalbuff);
    
    var xhr = GET_XML_HTTP();
    xhr.open('POST', AbsContextPath, false);
    xhr.setRequestHeader("Content-type", "text/html; charset=utf-8");  // application/x-www-form-urlencoded;charset=UTF-8
    xhr.send(finalbuffuri);
    
    if(xhr.status != 200){ alert( xhr.status + ': ' + xhr.statusText );
    } else {
        if(-1 < xhr.responseText.indexOf('Error')){
            alert(xhr.responseText);
        }
        else {
            callToDoAfterResponse(args, JSON.parse(xhr.responseText), obj);
        }
    }
 }

function callToDoAfterResponse(args, rspns, obj){
    var cmd = args[0];
    if (     cmd == 'GetEmailList'  ){ parseGetEmailList(rspns, obj); }
    else if (cmd == 'GetDataByEmail'){ parseGetDataByEmail(rspns); }
}

function parseGetEmailList(data, obj){
    var menu = document.createElement("DIV");
    menu.classname      = 'MenuOuter';
    menu.style.zIndex   = ++nextZIndex;
    menu.style.left     = "-2000px";
    menu.style.position = "relative";
    var mh = 250;
    if( (Number(data.numrows) * 23) < mh ){
        mh = (Number(data.numrows) * 23);
    }
    menu.style.height = mh +"px";
    menu.style.width    = "150px";
    
    menu.style.left = obj.parentElement.previousElementSibling.offsetWidth + (obj.parentElement.offsetWidth / 2);
    menu.style.top = -(obj.parentElement.parentElement.parentElement.clientHeight - (obj.parentElement.offsetTop + obj.parentElement.parentElement.parentElement.offsetTop));
    
    var ctx_tbl = '<DIV class="MenuTableContainer scroller" style="height:'+ menu.style.height +';"><TABLE class=MenuTable cellpadding=0 cellspacing=0><TBODY class=MenuTableBody tabindex="1">';
    var trstyle = "<tr class=MenuTableRow>";
    
    var ctxWidth = 150;
    if ( data.affected_rows.length ){
       for (let i = 0; i < data.affected_rows.length; i++) {
            ctx_tbl += trstyle
                        +'<td class="MenuTableTD" tabindex="'
                        + (i+1) +'">'
                        + data.affected_rows[i][0] 
                        +"</td></tr>";
            
            if( ctxWidth < data.affected_rows[i][0].length * 9){
                ctxWidth = data.affected_rows[i][0].length * 9;
            }
        }
    }
    menu.style.width = ctxWidth +"px";
    ctx_tbl += '</tbody></table></div>';
    menu.innerHTML = ctx_tbl;
    document.body.appendChild(menu);

    var tablediv = menu.childNodes[0];
    var table    = tablediv.firstChild;
    var tbody    = tablediv.firstChild.firstChild;
    // var tcell    = tablediv.firstChild.firstChild.firstChild;
    addEventHandler(tbody, 'click', trampoline);
    tbody.focus();
    addEventHandler(tbody, 'blur', trampoline);
    
    var w = table.offsetWidth
      , h = tablediv.parentElement.style.height; // table.offsetHeight
    h = h.substr(0, h.length-2);
    h = Number(h);
    table.style.width = w + "px";
    
    w += 2;
    h += 2;
    menu.style.width = w + "px";
    var row = tbody.firstChild;
    if (row == null) {return;}
    

    window.mMenuOuter = 'on';
    
}

function addEventHandler(node, type, f) {
   if (node.addEventListener) {
      node.addEventListener(type, f, false);
   } 
   else if (node.attachEvent) {
      node.attachEvent("on" + type, f);
   } 
   else {
      node["on" + type] = f;
   }
}
document.addEventListener("DOMContentLoaded", function() {
    try {
        addEventHandler(document.getElementById('btn_menu_fld_email'), 'click', trampoline);
        addEventHandler(document.getElementById('btn_data_fld_email'), 'click', trampoline);
        addEventHandler(document.getElementById('btn_clear_fld'), 'click', trampoline);
    } catch(e){;}
});

function parseGetDataByEmail(data){
    var n = document.getElementsByClassName("initTable")[0];
    if (n.firstElementChild){ n.firstElementChild.remove(); }
    
    var tbl = document.createElement("DIV");
    // tbl.classname = 'scroll-table';
    tbl.classList.add('scroll-table');
    var ctx_tbl = '<table><thead><tr>';
    
    for (let i = 0; i < data.fieldNames.length; i++) {
        ctx_tbl += '<th>'+ data.fieldNames[i] +'</th>';
    }
    ctx_tbl += '</tr></thead></table>';
    
    ctx_tbl += '<div class="scroll-table-body"><table><tbody>';
    for (let i = 0; i < data.affected_rows.length; i++) {
        ctx_tbl += '<tr class="tbl data row">';
        for (let j = 0; j < data.affected_rows[i].length; j++){
            ctx_tbl += '<td class="tbl data cell">'+ data.affected_rows[i][j] +'</td>';
        }
        ctx_tbl += '</tr>';
    }
    ctx_tbl += '</tbody></table></div>';
    
    tbl.innerHTML = ctx_tbl;
    n.appendChild(tbl); 
}


JS
;
return $js;
}
