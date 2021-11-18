# Product Backup
this script will help us to backup the configured directories.
## how to use
configure the script in crontab such a way that the script will run every miniute
make sure that the script runs in bash

configure the below in cron
` * * * * * ./product_backup.cfg `

### supported operations in the script's cron config 
*   \*  : any value
*    ,   :  value list sperate
*    \-  : rage of values 
 

 FTP is diasabled currently
