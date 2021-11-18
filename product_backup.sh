#!/bin/bash
process_count_check(){
	P_COUNT=`ps -ef|grep $0|grep -v grep|wc -l|awk '{print $1}'`
	if [ $P_COUNT -ge 4 ]; then
			echo `date +"%Y%m%d %H:%M:%S"` [ERROR] $0 already running $P_COUNT
			exit
	fi
}

process_count_check

read_config(){

	configuration_file=$1
	cat $configuration_file |grep = > /tmp/backup_script_source.tmp
	source /tmp/backup_script_source.tmp
}


check_size_dir_disk (){
        current_mount=`findmnt -T .|awk 'NR==2{print $1}'`
        available_space=`df |grep -w "$current_mount" |awk '{print $4}'`
        dir=`echo $1|awk -F '^' '{print $1}'`
        exclude_filesr=`echo $1|awk -F '^' '{print $2}'`
        max=$2

                if [ -d $dir ]
                then
                        if [ -z $exclude_files ]
                        then
                                dir_size=$(du -c $dir|awk ' END{print $1}')
                        else
                                dir_size=$(du -c $dir `echo $exclude_files|tr ',' '\n' |xargs -i echo "--exclude={}"|xargs echo` |awk ' END{print $1}')
                        fi
                else
                        echo `date +"%Y%m%d %H:%M:%S"` [ERROR] $dir Not exist/Not a Directory
                        exit 1
                fi
                if [ $available_space -lt $margin ]
                then
                        echo "`date +"%Y%m%d %H:%M:%S"` [ERROR] Space available in the current volum is less than expected DIR size x margin:$margin  avaliable: $available_space"
			exit
                fi


}



present_working_mount_disk_check(){
	current_mount=`findmnt -T .|awk 'NR==2{print $1}'`
	available_space=`df |grep -w "$current_mount" |awk '{print $4}'`
	disk_usage_percentage=`df |grep -w "$current_mount" |awk '{print $5}'|tr -d '%'`
	mode=$1
	threshold=$2
	case $mode in
				"p")
					if [ $disk_usage_percentage -gt $threshold ]
					then
						echo `date +"%Y%m%d %H:%M:%S"` [ERROR] "$current_mount" Disk Usage is ${disk_usage_percentage}%, inorder to start the scrip disk usage shouldnt be more than ${threshold}%
						exit 2
					fi
					;;
				"s")
					if [ $available_space -lt $threshold ]
					then
						echo `date +"%Y%m%d %H:%M:%S"` [ERROR] In "$current_mount" avaliable space is ${available_space}B inorder to start the script min ${threshold}B should be avaliable
						exit 2
					fi
					;;
				"c")
					echo "$current_mount ${available_space}K ${disk_usage_percentage}%"
	esac
}


compress_dir (){
        tar_name=$1
	dir=$2
        exclude_files=$3
        parent_dir=`echo "$dir"|awk -F',' '{print $1"/../"}'`
        child_dir=`echo "$dir"|awk -F',' '{print $1}'|tr '/' ' '|awk '{print $NF}'`
        tar_name_tmp=`echo "$dir"|awk -F',' '{print $2}'`
		if [ -d $dir ]
		then
			echo `date +"%Y%m%d %H:%M:%S"` [INFO] started compressing $dir
			if [ -z $exclude_files ]
			then
					tar -zcf $tar_name -C $parent_dir $child_dir
					echo `date +"%Y%m%d %H:%M:%S"` [INFO] finished compressing $parent_dir/$child_dir
			else
					tar -zcf $tar_name `echo $exclude_files|tr ',' '\n' |xargs -i echo "--exclude={}"|xargs echo` -C $parent_dir $child_dir
					echo `date +"%Y%m%d %H:%M:%S"` [INFO] finished compressing $parent_dir/$child_dir excluding dirs $exclude_files
			fi
		else
			echo `date +"%Y%m%d %H:%M:%S"` [ERROR] $dir Not exist/Not a Directory
			exit 1
		fi

}

transfer_file(){
	OPTIND=0
	OPTARG=0
        while getopts "t:f:h:u:p:d:r:" arg ;do
                case $arg in
                t)
                        transfer_type=$OPTARG
                        ;;
                f)
                        file=$OPTARG
                        ;;
                h)
                        host=$OPTARG
                        ;;
                u)
                        username=$OPTARG
                        ;;
                p)
                        password=$OPTARG
                        ;;
                d)
                        destination=$OPTARG
                        ;;
                r)
                        rm_flag=$OPTARG
                        ;;
                esac
        done
  if [[ -z $transfer_type || -z $file || -z $host || -z $username || -z $destination ]]
        then
                echo `date +"%Y%m%d %H:%M:%S"` [ERROR] Please Provide Nessessory Params
        else
                case $transfer_type in
                                "scp") scp -q $file $username@$host:$destination
						rc=$?
                                                if [ $rc -eq 0 ]
                                                then
                                                        echo `date +"%Y%m%d %H:%M:%S"` [SUCCESS] Sucessfully SCPed $file to $username@$host
                                                        if [ $rm_flag = y ]
                                                        then
                                                                echo `date +"%Y%m%d %H:%M:%S"` [INFO] Removing $file
                                                                rm $file
                                                        fi
                                                else
                                                        echo `date +"%Y%m%d %H:%M:%S"` [ERROR] Failed to scp $file to $username@$host with error code $rc
                                                        exit 1
                                                fi
                                        ;;
                esac
        fi

}





#################################################################################


>/tmp/backup_script_scp_list.tmp

configuration_file=/opt/akshay/etc/config/product_backup.cfg
read_config $configuration_file

cd $temp_dir
if [ $? -ne 0 ]
then
        echo `date +"%Y%m%d %H:%M:%S"` [ERROR] wrong temp dir
        exit 2
fi
if [ $disk_usage_check = y ]
then
	if [ $disk_usage_check_mode -eq 1 ]
	then
		present_working_mount_disk_check p $disk_usage_check_percentage
	fi
	if [ $disk_usage_check_mode -eq 2  ]
        then
                present_working_mount_disk_check s $min_available_space
        fi

fi


cat $configuration_file|grep -v '#'|grep -v '=' |grep -v -e '^$' |while read line
do
	cron_flag=0
	date_cron=`date +'%M %H %d %m %u'`
	config_cron=`echo "$line" |cut -d':' -f1`
	dir_ap=`echo "$line" |cut -d':' -f2|cut -d, -f1`
	exclude_dirs=`echo "$line" |cut -d':' -f3`
	tar_name_temp=`echo "$line" |cut -d':' -f2|cut -d, -f2`
	tar_name_ap=${tar_name_temp}_`${naming}`.tar.gz

	for i in {1..5} #cron correct aakanam
	do
		date_cron_ap="`echo "$date_cron" |cut -d' ' -f${i}`"
		config_cron_ap="`echo "$config_cron" |cut -d' ' -f${i}`"
		re='^[0-9]+$';if  [[ $config_cron_ap =~ $re ]] ;
		then
			mode='n'
		else
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
		fi
		case $mode in 
			'n')
				if [ $date_cron_ap -eq $config_cron_ap ]
				then
					cron_flag=`expr $cron_flag + 1 `
				fi
				;;
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

		#echo "$date_cron_ap : $config_cron_ap : $cron_flag : $mode"
	done
	if [ $cron_flag -eq 5  ]
	then
		echo $tar_name_ap $dir_ap $exclude_dirs  >> /tmp/backup_script_scp_list.tmp
		echo `date +"%Y%m%d %H:%M:%S"` [INFO] adding "$line" to exicution queue
	fi
done

if [ `cat /tmp/backup_script_scp_list.tmp|wc -l` -eq 0 ]
then
        #echo `date +"%Y%m%d %H:%M:%S"` [INFO] No files in queue Exiting script
        exit
fi


cat /tmp/backup_script_scp_list.tmp|while read line
do
 	
	if [ $folder_size_check = y  ]
	then
		check_size_dir_disk `echo $line|cut -d' ' -f2-|tr ' ' '^'` $margin
	fi

	compress_dir `echo $line`
		if [ $dwh_flag = y ] 
		then
			if [ $delete_after_scp = y ] 
			then
				transfer_file -t $transfer_type -f "$temp_dir/$tar_name" -h "$dwh_hostip" -u "$dwh_user" -d "$dwh_dest_path" -r "y"
			else
				transfer_file -t $transfer_type -f "$temp_dir/$tar_name" -h "$dwh_hostip" -u "$dwh_user" -d "$dwh_dest_path" -r "n"
			fi
		fi
done
