#!/bin/bash

echo `date +"%Y%m%d %H:%M:%S"` [INFO] Backup Script stared

configuration_file=/opt/akshay/etc/config/product_backup.cfg
temp_dir=`grep -w temp_dir $configuration_file|grep -v '#'|awk -F '=' '{print $NF}'`
dwh_flag=`grep -w dwh $configuration_file|grep -v '#'|awk -F '=' '{print $NF}'`
transfer_type=`grep -w transfer_type $configuration_file|grep -v '#'|awk -F '=' '{print $NF}'`
dwh_hostip=`grep -w dwh_hostip $configuration_file|grep -v '#'|awk -F '=' '{print $NF}'`
dwh_user=`grep -w dwh_user $configuration_file|grep -v '#'|awk -F '=' '{print $NF}'`
dwh_password=`grep -w dwh_password $configuration_file|grep -v '#'|awk -F '=' '{print $NF}'`
dwh_dest_path=`grep -w dwh_dest_path $configuration_file|grep -v '#'|awk -F '=' '{print $NF}'`
delete_after_scp=`grep -w delete_after_scp $configuration_file|grep -v '#'|awk -F '=' '{print $NF}'`
naming=`grep -w naming $configuration_file|grep -v '#'|awk -F '=' '{print $NF}'`
disk_usage_check=`grep -w disk_usage_check $configuration_file|grep -v '#'|awk -F '=' '{print $NF}'`
disk_usage_threshold=`grep -w disk_usage_threshold $configuration_file|grep -v '#'|awk -F '=' '{print $NF}'`
disk_usage_check_loop=`grep -w disk_usage_check_loop $configuration_file|grep -v '#'|awk -F '=' '{print $NF}'`
disk_usage_check_loop_threshold=`grep -w disk_usage_check_loop_threshold $configuration_file|grep -v '#'|awk -F '=' '{print $NF}'`


>/tmp/backup_script.tmp
>/tmp/backup_script_scp_list.tmp
cd $temp_dir
current_mount=`findmnt -T .|awk 'NR==2{print $1}'`
available_space=`df |grep -w $current_mount |awk '{print $4}'`
disk_usage_percentage=`df |grep -w "$current_mount" |awk '{print $5}'|tr -d '%'`

if [ $disk_usage_threshold -gt $available_space  ]
then
	echo `date +"%Y%m%d %H:%M:%S"` [ERROR] No Space in the current mount exiting the script
	exit 2
else
	echo `date +"%Y%m%d %H:%M:%S"` [INFO] Space Check is fine 
fi
P_COUNT=`ps -ef|grep $0|grep -v grep|wc -l|awk '{print $1}'`
if [ $P_COUNT -ge 4 ]; then
        echo "`date` $0 already running ($P_COUNT)"
        exit
fi

cat $configuration_file|grep -v '#' |grep -v  '='|grep -v "^$"|while read line
do
	date_cron=`date +'%M %H %d %m %u'`
	config_cron=`echo "$line"|cut -d':' -f1`
	cron_flag=0
	for i in {1..5}
	do
		date_cron_ap="`echo "$date_cron" |cut -d' ' -f${i}`"
		config_cron_ap="`echo "$config_cron" |cut -d' ' -f${i}`"
		echo "$config_cron_ap"|grep ',' >> /dev/null
		if [ $? -eq 0  ]
		then 
			mode=','
		fi

		echo "$config_cron_ap"|grep '-' >> /dev/null
                if [ $? -eq 0  ]
                then
                        mode='-'
                fi

		echo "$config_cron_ap"|grep '*' >> /dev/null
                if [ $? -eq 0  ]
                then
                        mode='*'
                fi

		case $mode in 
			"*")
				cron_flag=`expr $cron_flag + 1 `
				;;
			"-")
				upper_limit=`echo $config_cron_ap|awk -F '-' '{print $NF}'`
				lower_limit=`echo $config_cron_ap|awk -F '-' '{print $1}'`
				if [ \( $date_cron_ap -ge $lower_limit \) -a \(  $date_cron_ap -le $upper_limit  \) ]
				then
					cron_flag=`expr $cron_flag + 1 `
				fi
				;;
			",")
				echo $config_cron_ap|grep $date_cron_ap >> /dev/null
				if [ $? -eq 0 ]
				then
					cron_flag=`expr $cron_flag + 1 `
				fi
		esac

	done
	if [ $cron_flag -eq 5  ]
	then
		echo "$line" >> /tmp/backup_script.tmp
		echo `date +"%Y%m%d %H:%M:%S"` [INFO] adding "$line" to exicution queue
	fi

done

if [ `cat /tmp/backup_script.tmp|wc -l` -eq 0 ]
then
	echo `date +"%Y%m%d %H:%M:%S"` [INFO] No files in queue Exiting script
	exit 
fi

cd $temp_dir
cat /tmp/backup_script.tmp|while read line
do

	tar_cfg=`echo "$line"|awk -F':' '{print $2}'`
	parent_dir=`echo "$tar_cfg"|awk -F',' '{print $1"/../"}'`
	child_dir=`echo "$tar_cfg"|awk -F',' '{print $1}'|tr '/' ' '|awk '{print $NF}'`
	exclude_files=`echo "$line" | awk -F':' '{print $3}' `
	tar_name_tmp=`echo "$tar_cfg"|awk -F',' '{print $2}'`
	tar_name=${tar_name_tmp}_`$naming`.tar.gz
	if [ $disk_usage_check_loop = 'y'  ]
	then
		if [ $disk_usage_check_loop_threshold -lt  $disk_usage_percentage ]
		then
			echo `date +"%Y%m%d %H:%M:%S"` [ERROR] Disk Space Exceed the threshould current percentage:$disk_usage_percentage configured:$disk_usage_check_loop_threshold
			exit 

		fi
	fi

	if [ -z $exclude_files ]
	then
		echo `date +"%Y%m%d %H:%M:%S"` [INFO] started compressing $parent_dir/$child_dir
		tar -zcf $tar_name -C $parent_dir $child_dir
		echo `date +"%Y%m%d %H:%M:%S"` [INFO] finished compressing $parent_dir/$child_dir
	else
		echo `date +"%Y%m%d %H:%M:%S"` [INFO] started compressing $parent_dir/$child_dir excluding dirs $exclude_files
		tar -zcf $tar_name `echo $exclude_files|tr ',' '\n' |xargs -i echo "--exclude={}"|xargs echo` -C $parent_dir $child_dir
		echo `date +"%Y%m%d %H:%M:%S"` [INFO] finished compressing $parent_dir/$child_dir excluding dirs $exclude_files
	fi
	echo ${temp_dir}/$tar_name >> /tmp/backup_script_scp_list.tmp
done

if [ $dwh_flag = y ]
then
	echo `date +"%Y%m%d %H:%M:%S"` [INFO] DWH ENABLED
	case $transfer_type in 
		"ftp")
			echo `date +"%Y%m%d %H:%M:%S"` [INFO] Transfer type  FTP
			cat /tmp/backup_script_scp_list.tmp|while read file
			do
				exitStat=$(curl -v --ftp-method singlecwd  -T $file ftp://$dwh_user:$dwh_password@$dwh_hostip"/$dwh_dest_path/$file")
				if [ $? -eq 0 ]
				then
					echo `date +"%Y%m%d %H:%M:%S"` [INFO] Succesfully FTPED $file to DWH server $dwh_user@$dwh_hostip
				else
					echo `date +"%Y%m%d %H:%M:%S"` [ERROR]  Failed FTP $file to DWH server $dwh_user@$dwh_hostip 
				fi
			done
			;;
		"scp")
			echo `date +"%Y%m%d %H:%M:%S"` [INFO] Transfer type  SCP
			cat /tmp/backup_script_scp_list.tmp|while read file
                        do
				scp $file $dwh_user@$dwh_hostip:$dwh_dest_path >> /dev/null
				if [ $? -eq 0 ]
                                then
					echo `date +"%Y%m%d %H:%M:%S"` [INFO] Succesfully SCPED $file to DWH server $dwh_user@$dwh_hostip:$dwh_dest_path
				else
					echo `date +"%Y%m%d %H:%M:%S"` [ERROR]  Failed SCP $file to DWH server $dwh_user@$dwh_hostip
				fi
			done
	esac
else
	echo `date +"%Y%m%d %H:%M:%S"` [INFO] DWH DISABLED

fi

if [ $delete_after_scp = y ]
then
	if [ `cat /tmp/backup_script_scp_list.tmp|wc -l` -eq 0  ]
	then
		echo `date +"%Y%m%d %H:%M:%S"` [ERROR] no files to delete
		exit
	fi

	echo `date +"%Y%m%d %H:%M:%S"` [INFO] delete_after_scp enabled removing the scped tar files 
	cat /tmp/backup_script_scp_list.tmp|xargs rm 
else
	echo `date +"%Y%m%d %H:%M:%S"` [INFO] delete_after_scp disabled keeping the scped tar files	
fi
echo `date +"%Y%m%d %H:%M:%S"` [INFO] Backup Script Finished
