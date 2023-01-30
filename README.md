# gspb
Configure the file '/gspb/server/conf/config.txt' based on your environment.

'/gspb/server/pl/parseLog.pl' is currently working with MySQL.

/gspb/
------
     |-- client/
     |    |-- cgi-bin/
     |    |    |-- web_log_viewer.pl
     |    |
     |    |-- css/
     |    |    |-- core.css
     |    |
     |    |-- js/
     |    |    |-- core.js
     |    |
     |-- server/
     |    |-- conf/
     |    |    |-- config.txt
     |    |
     |    |-- input/
     |    |    |-- 'there are stored incoming files'
     |    |    |-- backup/
     |    |    |    |-- 'your parsed already files'
     |    |
     |    |-- pl/
     |    |    |-- parseLog.pl
     |    |
     |-- README.md


Access to the web page via the path ../cgi-bin/web_log_viewer.pl. 
  Example: https://localhost/gpb/web_log_viewer.pl

=====================================================================================

Version 1.0.0, 28.12.2022
    Intial release works with the standart 'cgi-bin' folder.

Version 1.0.1, 30.01.2023
    The Structure was changed (see the picture above). Hence we should use the defualt 'htdocs' or an another folder which you have configured in 'httpd.conf'.
    
    'httpd.conf' - how to configure it (example).
    1. Section 'LoadModule' switch on:
        - LoadModule rewrite_module modules/mod_rewrite.so
        - LoadModule ssl_module modules/mod_ssl.so
        - LoadModule socache_shmcb_module modules/mod_socache_shmcb.so

    2. Put a new line before '<IfModule alias_module>':
        - Define "GPB" "${SRVROOT}/htdocs/gspb"
    3. In section '<IfModule alias_module>' put a new ServerAlias:
        - ScriptAlias "/gpb/" "${GPB}/client/cgi-bin/"
        
    4. Configure sub-folders of the folder structure above:
            <Directory "${GPB}/client">
                AllowOverride  None
                Options        FollowSymLinks
                Require        all granted
            </Directory>

            <Directory "${GPB}/client/cgi-bin">
                # AllowOverride None
                Options    +ExecCGI
                AddHandler  cgi-script .cgi .pl
                Require     method GET POST
                
                RewriteEngine  On
                RewriteCond    %{HTTPS} off
                RewriteRule    ^ https://%{HTTP_HOST}%{REQUEST_URI}
            </Directory>

            <Directory "${GPB}/server/pl">
                AllowOverride  None
                Options       +ExecCGI +FollowSymLinks
                AddHandler     cgi-script .cgi .pl
                Require        all denied
            </Directory>
        
    5. In section '<IfModule mime_module>' put a new line:
        - AddType application/javascript .js
        
    6. SSL how to get your own certificate.
    
        6.1 Ensure you have write permissions to your Apache conf folder.
        6.2 Open a command prompt in 'Apache2\conf' folder
            Type
            ..\bin\openssl req -config openssl.cnf -new -out YOUR_SERVER_NAME.csr -keyout YOUR_SERVER_NAME.pem
            Expl. 'YOUR_SERVER_NAME' - google etc.
            
                You can leave all questions blank except:

                PEM Passphrase:  a temporary password such as "password"
                Common Name:     the hostname of your server

            When that completes, type
            ..\bin\openssl rsa -in YOUR_SERVER_NAME.pem -out YOUR_SERVER_NAME.key

            Generate your self-signed certificate by typing:
            ..\bin\openssl x509 -in YOUR_SERVER_NAME.csr -out YOUR_SERVER_NAME.cert -req -signkey YOUR_SERVER_NAME.key -days 365

            Open Apache's conf\httpd.conf file and ensure SSL module is enabled - there should be no hash at the start of this line:
                LoadModule ssl_module modules/mod_ssl.so

            In Apache2.2 following line is uncommented in apache/conf/httpd.conf by default.
                LoadModule socache_shmcb_module modules/mod_socache_shmcb.so

            From Apache 2.4 above line is commented so remove the # sign before it.

            Some Apache installations place the SSL config in a separate file. If so, ensure that the SSL conf file is being included. In my case I had to uncomment this line:
                Include 'conf/extra/httpd-ssl.conf'

            In the SSL config 'httpd-ssl.conf' I had to update the following lines:
            Update
                SSLSessionCache "shmcb:C:\Program Files (x86)\Zend\Apache2/logs/ssl_scache(512000)"
            to
                SSLSessionCache "shmcb:C:/Progra\~2/Zend/Apache2/logs/ssl_scache(512000)"
            (The brackets in the path confuse the module, so we need to escape them)
            
            DocumentRoot - set this to the folder for your web files
            ServerName - the server's hostname
            SSLCertificateFile "conf/YOUR_SERVER_NAME.cert"
            SSLCertificateKeyFile "conf/YOUR_SERVER_NAME.key"
         
            Restart Apache.
                httpd -k restart

        Try loading https://localhost/ in your browser.
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        
        