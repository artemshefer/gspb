var Workflow = {
    'data':  "GetDataByEmail",
    'menu':  "GetEmailList",
    'clear': "ClearFldEmail"
};
var AbsContextPath;

var RelContextPath = "web_log_viewer.pl"; // "$scrpt_name";
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
    
    var tbl = document.createElement("DIV"); // class="btn_data"
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