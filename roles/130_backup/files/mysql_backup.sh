#!/bin/bash

# mysql版本：5.6.19
# 备份工具：percona-xtrabackup-2.2.10
# 实现：执行mysql的全量备份或者增量备份  

source /etc/profile 
source ~/.bashrc 

export LANG=zh_CN.UTF-8

# 使用配置文件并获取配置参数
source mysql_backup.ini

# 锁定文件目录
lock_file="/tmp/.mysql$port.backup.lock"
# 时间戳
timestamp=""
# 是否全量备份
full=0

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

# 获取当前时间
function get_now()  
{  
	timestamp=`date -d today +"%y-%m-%d %H:%M:%S"`
}

#输出帮助信息
function usage()
{
	echo "**************************************************"
	echo "功能：执行mysql的全量备份或者增量备份"
	echo "用法："
	echo "    -F  是否全量备份（1=全量备份 0=增量备份）"
	echo "    -h  脚本使用帮助"
	echo "示例："
	echo "    ./mysql_backup.sh -F 1"
	echo "**************************************************"
}

#获取外部传入参数
while [ $# -ne 0 ]      #$#获取参数总个数
do
	case $1 in      #$1接收第一个参数
		-F)
			shift   #轮换到下一个参数
			full=$1
			;;
		-h)
			usage
			exit 1  #退出shell
			;;
	esac
	shift
done

# 参数检查，判断是否有传入端口号
if [ $port -eq 0 ]; then
	error "必须指定数据库端口号!"
fi

# 参数检查，判断是否有传入备份目录
if [ ! -d $backup_dir ]; then
	error "备份目录：$backup_dir 不存在!"
fi

# 参数检查，判断是否有传入配置文件
if [ ! -f $def_cnf ]; then
	error "配置文件：$def_cnf 不存在!"
fi

# 检查 xtrabackup 是否安装
xtrabackup --version

if [ $? -gt 0 ]; then
	error "备份工具 xtrabackup 尚未安装!"
fi

# 检查数据库
mysql --host=$host --user=$user --password=$password --port=$port -N -e "exit"

if [ $? -gt 0 ]; then
	error "数据库连接错误!"
fi

#防止同时执行两个备份命令，发生冲突
#判断文件是否存在
if [ -f $lock_file ]; then
        echo 'MySQL备份已被锁定在：'$lock_file
        exit 1
fi

#加锁
echo '1' > $lock_file

# 设置脚本报错则退出
# 主要作用是，当脚本执行出现意料之外的情况时，立即退出，避免错误被忽略，导致最终结果不正确。
# 这里不设置自动退出，由程序自己判断处理
# set -e 

#备份日志目录
backup_log_path="$backup_dir/log"

#全量备份日志文件
backup_full_log_path="$backup_log_path/full.log"

#增量备份日志文件
backup_increment_log_path="$backup_log_path/increment.log"

#上次备份成功的备份目录名称
last_backup_name=""

#上次全量备份的目录名称
last_full_backup_name=""

#备份成功的备份目录名称
backup_name=""

#备份成功的LSN
lsn=""

# 判断日志目录是否存在，不存在则创建
if [ ! -d $backup_log_path ]; then 
    mkdir -p $backup_log_path
fi

if [ $full -eq 1 ]; then
	echo '全量备份开始时间：'`date +"%Y-%m-%d %H:%M:%S"`

	#全量备份
	innobackupex --host=$host --user=$user --password=$password --port=$port $backup_dir
	
	if [ $? -gt 0 ]; then
		rm -f $lock_file
		error "全量备份失败，请检查!"
	fi

	#获取最新的全量备份路径保存到日志文件(按修改时间降序排列文件，并取出第二行结果)
	backup_name=`ls -lnt $backup_dir | awk 'NR==2 {print $9}'`

	#写入备份日志文件
	echo $backup_name >> $backup_full_log_path
	echo $backup_name >> $backup_increment_log_path
	if [ -d $backup_dir'/'$backup_name ];then
		echo '全量备份完成时间：'`date +"%Y-%m-%d %H:%M:%S"`
	fi
	#记录备份时最近一次的全备目录
	echo $backup_name >> "$backup_dir/$backup_name/full.data"
else
	echo '增量备份开始时间：'`date +"%Y-%m-%d %H:%M:%S"`

	#取最近一次的全量备份
	if [ -f $backup_full_log_path ]; then
		last_full_backup_name=`awk 'NF{a=$0}END{print a}' $backup_full_log_path`
	fi 

	#未取到最后一次全量备份则抛错
	if [ "$last_full_backup_name" = "" ]; then
		rm -f $lock_file
		error '未找到可用的全量备份，增量备份失败!'
	fi

	#取上一次的增量备份，将上次的增量做为incremental-basedir目录
	if [ -f $backup_increment_log_path ]; then
		last_backup_name=`awk 'NF{a=$0}END{print a}' $backup_increment_log_path`
	fi 

	#增量备份
	innobackupex --host=$host --user=$user --password=$password --port=$port \
		--incremental --incremental-basedir="$backup_dir/$last_backup_name" \
		$backup_dir
		
	if [ $? -gt 0 ]; then
		rm -f $lock_file
		error "增量备份失败，请检查!"
	fi

	#获取最新的增量备份路径保存到日志文件(按修改时间降序排列文件，并取出第二行结果)
	backup_name=`ls -lnt $backup_dir | awk 'NR==2 {print $9}'`

	#写入备份日志文件
	echo $backup_name >> $backup_increment_log_path
	if [ -d $backup_dir'/'$backup_name ];then
		echo '增量备份完成时间：'`date +"%Y-%m-%d %H:%M:%S"`
	fi
	
	#记录备份时最近一次的全备目录
	echo $last_full_backup_name >> "$backup_dir/$backup_name/full.data"
fi

#删除锁定文件
rm -f $lock_file

#备份数据库配置文件
cp $def_cnf "$backup_dir/$backup_name/"

#写入全备文件用于定时还原脚本

echo "备份存放路径：$backup_dir/$backup_name"
