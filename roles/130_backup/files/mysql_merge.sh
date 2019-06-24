#!/bin/bash 

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
    echo "功能：将一个增量备份刷新到全量备份中。"
	echo "用法："
	echo "    -d  备份目录"
	echo "    -f  待合并的全量备份的文件夹名称"
	echo "    -i  待合并的增量备份的文件夹名称"
	echo "执行示例："
	echo "    ./mysql_merge.sh -d /tmp/mysql_3306_backup -f 2018-05-06_00-10-01 -i 2018-05-09_00-10-01"
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

echo "备份合并：$increment_backup_name to $full_backup_name"
echo '合并开始时间：'`date +"%Y-%m-%d %H:%M:%S"`

incremental_backup_path="$backup_dir/$increment_backup_name"

if [[ "$full_backup_name" == "$increment_backup_name" ]]; then
	#全量备份应用日志
	innobackupex --apply-log --redo-only $full_backup_path
    
	#写入合并成功标志
	echo > "$full_backup_path/merged"
else 
	if [[ "$full_backup_name" < "$increment_backup_name" ]]; then
		innobackupex --apply-log --redo-only \
			--incremental-dir=$incremental_backup_path \
			$full_backup_path
        
		# 检测 lsn
		full_backup_last_lsn=`cat $full_backup_path/xtrabackup_checkpoints | grep last_lsn | awk '{print $3}'`
		incremental_backup_last_lsn=`cat $incremental_backup_path/xtrabackup_checkpoints | grep last_lsn | awk '{print $3}'`
		
		if [[ "$full_backup_last_lsn" == "$incremental_backup_last_lsn" ]]; then
			#写入合并成功标志
			echo > "$incremental_backup_path/merged"
			echo > "$full_backup_path/merged"

	        #取上一次的增量备份
	        if [ -f $backup_increment_log_path ]; then
	            last_backup_name=`awk 'NF{a=$0}END{print a}' $backup_increment_log_path`
	            if [ "$last_backup_name" != "$increment_backup_name" ]; then 
	                #将已合并过的增备移动到备份目录下
	                mkdir -p "$backup_dir/bak"
	                mv $incremental_backup_path "$backup_dir/bak/$increment_backup_name"
	            fi
	        fi 
		else
			error "增量备份合并失败"
		fi
	else
		error "增备[$increment_backup_name]日期大于全备[$full_backup_name]，不能进行合并"
	fi
fi

echo '合并结束时间：'`date +"%Y-%m-%d %H:%M:%S"`
