#!/bin/bash

source /etc/profile 
source ~/.bashrc 

LANG="zh_CN.UTF-8"
export LANG

# 是否全量备份
full=0
# 备份文本
backup_txt="增备"

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
	echo "功能：执行备份过程（包括数据库全量或增量备份，定期将增备合并到全备，目的--减少全备的个数，同时可以处理一些需定时执行的自定义数据库脚本）"
	echo "用法："
	echo "    -F  是否全量备份（1=全量备份 0=增量备份）"
	echo "    -h  脚本使用帮助"
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

if [ $full -eq 1 ]; then
    backup_txt="全备"
fi

# 使用配置文件并获取配置参数
source mysql_backup.ini

echo "显示参数："
echo "user："$user
echo "password："$password
echo "port："$port
echo "def_cnf："$def_cnf
echo "backup_dir："$backup_dir
echo "tags："$tags
echo "log_path："$log_path
echo "addressee_successed："$addressee_successed
echo "addressee_failed："$addressee_failed
echo "sender："$sender
echo "keep_days_backup："$keep_days_backup
echo "keep_days_log："$keep_days_log

# 备份保留最小日期
date_keep_backup=`date -d "-$keep_days_backup day" +%Y-%m-%d`

echo "---------- 数据库备份作业开始 ----------" > $log_path

# 调用备份脚本
if [ "$password" = "" ]; then
	./mysql_backup.sh -u $user -p $port -f $def_cnf -d $backup_dir -F $full >> $log_path
else
	./mysql_backup.sh -u $user -P $password -p $port -f $def_cnf -d $backup_dir -F $full >> $log_path
fi

declare -i success=` cat $log_path | grep 备份存放路径 | wc -l `

if [ $success -eq 1 ]; then
	subject="$tags$backup_txt备份成功"`date +"(%Y-%m-%d)"`
	addressee=$addressee_successed
else
	subject="$tags$backup_txt备份失败"`date +"(%Y-%m-%d)"`
	addressee=$addressee_failed
fi

echo "---------- 数据库备份作业结束 ----------" >> $log_path
echo "" >> $log_path
echo "---------- 数据库合并作业开始 ----------" >> $log_path

# 合并保留天数之外的备份
for backup_name in `ls $backup_dir | grep 20*`
do
	# 备份文件路径
	backup_path="$backup_dir/$backup_name"
	# 取备份名字的长度
	backup_name_length=`echo "$backup_name" |wc -L`
	# 取备份的日期
	date_backup_name=`echo ${backup_name:0:10}`
	# 备份检查点校验文件
	backup_checkpoints_path="$backup_path/xtrabackup_checkpoints"
	# 获取全备名称
	full_backup_name=`cat $backup_path/full.data`
	
	# 将小于等于最小日期的备份合并到全备
	if [ -d $backup_path ] && [ $backup_name_length -eq 19 ] && [ -f $backup_checkpoints_path ] && [ ! -f "$backup_path/merged" ]; then
		if [[ "$date_keep_backup" == "$date_backup_name" ]]; then
			echo "开始合并[$backup_name]到[$full_backup_name]" >> $log_path
			echo '合并开始时间：'`date +"%Y-%m-%d %H:%M:%S"` >> $log_path
			./mysql_merge.sh -d $backup_dir -f $full_backup_name -i $backup_name
			if [ $? -gt 0 ]; then
				echo "合并失败" >> $log_path
				subject="$subject(合并异常)"
			else
				echo "合并成功" >> $log_path
			fi
			echo '合并结束时间：'`date +"%Y-%m-%d %H:%M:%S"` >> $log_path
		fi
		if [[ "$date_keep_backup" > "$date_backup_name" ]]; then
			echo "开始合并[$backup_name]到[$full_backup_name]" >> $log_path
			echo '合并开始时间：'`date +"%Y-%m-%d %H:%M:%S"` >> $log_path
			./mysql_merge.sh -d $backup_dir -f $full_backup_name -i $backup_name
			if [ $? -gt 0 ]; then
				echo "合并失败" >> $log_path
				subject="$subject(合并异常)"
			else
				echo "合并成功" >> $log_path
			fi
			echo '合并结束时间：'`date +"%Y-%m-%d %H:%M:%S"` >> $log_path
		fi
	fi
done

echo "---------- 数据库合并作业结束 ----------" >> $log_path

# 执行备份过程中可处理的扩展内容
./mysql_backup_extra.sh

# 输出磁盘使用情况
echo "" >> $log_path
echo "服务器磁盘使用情况如下：" >> $log_path
df -lhP | grep -v "/var/lib" >> $log_path

# 发送邮件(循环多次，减少邮件发送失败的可能)
declare -i s=1

rm -rf ~/dead.letter

while (($s!=0))
do
        mailx -s $subject -c "$addressee" $sender < $log_path

        sleep 30

        if [ -f ~/dead.letter ]
        then
                echo "邮件发送失败"$s"次"
                s=$s+1
        else
                echo "邮件发送成功"
                s=0
        fi

        if [ $s -gt 30 ]
        then
                echo "失败30次，停止发送"
                s=0
        fi
done

echo "程序结束"
