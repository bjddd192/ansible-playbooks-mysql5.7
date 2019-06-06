#!/bin/bash

# 心得：还原合并过程中 xtrabackup 有严格的验证，颠倒顺序或者重复执行合并操作都会报错，
#      因此可以保证还原合并过程中不会出现数据异常，可以放心进行此合并备份的过程。

source /etc/profile 
source ~/.bashrc 

LANG="zh_CN.UTF-8"
export LANG

# 备份目录
backup_dir=""
#全备文件名
full_backup_name=""
#增备文件名
increment_backup_name=""
# 锁定文件目录
lock_file="/tmp/.mysql.restore.lock"

# 显示错误并退出
# SHELL中的 exit 1 和 exit 1 有什么区别？
# exit 1 可以告知你的程序的使用者：你的程序是正常结束的。
# 如果 exit 非 0 值，那么你的程序的使用者通常会认为你的程序产生了一个错误。
# 在 shell 中调用完你的程序之后，用 echo $? 命令就可以看到你的程序的 exit 值。
# 在 shell 脚本中，通常会根据上一个命令的 $? 值来进行一些流程控制。
function error()  
{  
	echo -e "\033[31m发现异常：$1\033[0m" 1>&2
	exit 1
}

#输出帮助信息
function usage()
{
	echo "**************************************************"
    echo "功能：用于批量还原增量备份到指定到全量备份中，加快还原到效率，提升可靠性。"
	echo "用法："
	echo "    -d  备份目录"
	echo "    -f  最后一次全量备份的文件夹名称"
	echo "    -i  最后一次增量备份的文件夹名称"
	echo "执行示例："
	echo "    ./mysql_restore.sh -d /tmp/test -f 2018-05-06_00-10-01 -i 2018-05-09_00-10-01"
	echo "**************************************************"
}

#获取外部传入参数
while [ $# -ne 0 ]	#$#获取参数总个数
do
	case $1 in	#$1接收第一个参数
		-d)
			shift   #轮换到下一个参数
			backup_dir=$1
			;;
		-f)
			shift
			full_backup_name=$1
			;;
		-i)
			shift
			increment_backup_name=$1
			;;
		-h)
			usage
			exit 0	#退出shell
			;;
	esac
	shift
done

#参数检查，判断是否有传入全备文件夹名
if [ "$full_backup_name" = "" ]; then
	error '必须指定全备文件夹名!'
fi

#参数检查，判断是否有传入增备文件夹名
if [ "$increment_backup_name" = "" ]; then
	error '必须指定增备文件夹名!'
fi

#参数检查，判断是否有传入备份目录
if [ "$backup_dir" = "" ]; then
	error '必须指定备份目录!'
fi

#备份日志目录
backup_log_path="$backup_dir/log"
#全量备份日志文件
backup_full_log_path="$backup_log_path/full.log"
#增量备份日志文件
backup_increment_log_path="$backup_log_path/increment.log"
#全量备份目录
full_backup_path="$backup_dir/$full_backup_name"
#指定的全量备份所在的行号
line_full_backup_name=0
#指定的增量备份所在的行号
line_increment_backup_name=-1
#还原执行日志文件
restore_log_path="$backup_log_path/restore.log"

#判断备份目录是否存在，不存在则提示错误
if [ ! -d $backup_dir ]; then
	error "备份目录：$backup_dir 不存在!"
fi

if [ ! -d $full_backup_path ]; then
	error "全量备份目录：$full_backup_path 不存在!"
fi

#判断日志文件是否存在，不存在则提示错误
if [ ! -f $backup_full_log_path ]; then
	error "全量备份日志文件：$backup_full_log_path 不存在!"
fi

if [ ! -f $backup_increment_log_path ]; then
	error "增量备份日志文件：$backup_increment_log_path 不存在!"
fi

echo "备份目录：$backup_dir"
echo "待还原的全量备份目录：$full_backup_path"

line_full_backup_name=`cat -n $backup_increment_log_path | grep $full_backup_name | awk 'NR==1{print $1}'` 
line_increment_backup_name=`cat -n $backup_increment_log_path | grep $increment_backup_name | awk 'NR==1{print $1}'`

if [ $line_full_backup_name -gt $line_increment_backup_name ]||[ $line_full_backup_name -eq 0 ]; then
	error '未找到给定的备份区间，请检查传入参数!'
fi

read -p '备份区间正确，是否开始还原(y/n)' isok
if [ "$isok" = "y" ];then
	#防止同时执行两个备份命令，发生冲突
	#判断文件是否存在
	if [ -f $lock_file ]; then
		echo 'MySQL备份已被锁定在：'$lock_file
		exit 1
	fi

	#加锁
	echo '1' > $lock_file
    
	echo '还原开始时间：'`date +"%Y-%m-%d %H:%M:%S"`
	
	#全量备份应用日志
    if [ ! -f "$full_backup_path/merged" ]; then
        innobackupex --apply-log --redo-only $full_backup_path >& $restore_log_path
        
    	if [ $? -gt 0 ]; then
    		rm -f $lock_file
    		error "全备合并发生了异常，请检查日志!"
    	fi
        
		echo > "$full_backup_path/merged"
    fi
	
	for ((i=$line_full_backup_name+1;i<=$line_increment_backup_name;i++));do
        
    	#增量备份目录
    	increment_backup_name=`awk "NR==$i" $backup_increment_log_path` 
    	incremental_backup_path="$backup_dir/$increment_backup_name"

        if [ -d $incremental_backup_path ] && [ ! -f "$incremental_backup_path/merged" ]; then
        	#增量备份合并至全量备份
        	innobackupex --apply-log --redo-only \
        		--incremental-dir=$incremental_backup_path \
        		$full_backup_path >& $restore_log_path
            
			# 检测 lsn
			full_backup_last_lsn=`cat $full_backup_path/xtrabackup_checkpoints | grep last_lsn | awk '{print $3}'`
			incremental_backup_last_lsn=`cat $incremental_backup_path/xtrabackup_checkpoints | grep last_lsn | awk '{print $3}'`
			   
            if [ $? -gt 0 ]; then
                rm -f $lock_file
        		error "增备合并发生了异常，请检查日志!"
        	fi
            
            echo > "$incremental_backup_path/merged"
    		echo > "$full_backup_path/merged"
        fi
	done
	
	echo '还原结束时间：'`date +"%Y-%m-%d %H:%M:%S"`
	rm -f $lock_file
else
	exit 0
fi
